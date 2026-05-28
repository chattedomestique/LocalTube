import Foundation
import Observation

// MARK: - LibraryStore
//
// Owns the in-memory channel and video catalog plus all CRUD that persists
// through DatabaseService. Extracted from AppState so the domain logic can
// be exercised in isolation (tests, future swap of persistence backend) and
// so AppState can shed responsibility for "everything."
//
// AppState retains forwarding helpers for back-compat — existing call sites
// like `appState.channels` and `appState.addChannel(_:)` continue to work
// while new code can call `appState.library.X` directly.

@Observable
@MainActor
final class LibraryStore {
    var channels: [Channel] = []
    var videos: [UUID: [Video]] = [:]

    // Profiles — each profile carries a subset of channels it can see in
    // viewer mode. Empty `profiles` falls back to "all channels visible."
    var profiles: [Profile] = []
    var profileChannels: [UUID: Set<UUID>] = [:]  // profileId → channelIds
    /// Per-profile favorited video IDs. Two profiles assigned the same
    /// channel maintain independent favorite lists.
    var profileFavorites: [UUID: Set<UUID>] = [:]  // profileId → videoIds
    /// Per-profile hidden channels. Distinct from un-assignment: the
    /// channel stays in profile_channels but is filtered out of the
    /// viewer-mode library. Easy to unhide from the edit layer.
    var profileHiddenChannels: [UUID: Set<UUID>] = [:]  // profileId → channelIds

    // Playlists — profile-scoped ordered video lists. `playlists` holds
    // metadata; `playlistVideos` holds the ordered membership keyed by
    // playlist id. Each profile's active playlist id lives on the
    // Profile record (activePlaylistId).
    var playlists: [Playlist] = []
    var playlistVideos: [UUID: [UUID]] = [:]  // playlistId → ordered videoIds
    var activeProfileId: UUID? {
        didSet {
            if let id = activeProfileId {
                UserDefaults.standard.set(id.uuidString, forKey: Self.activeProfileKey)
            } else {
                UserDefaults.standard.removeObject(forKey: Self.activeProfileKey)
            }
        }
    }
    private static let activeProfileKey = "lt.activeProfileId"

    var undoManager: UndoManager?

    // MARK: - Lookup

    func videoById(_ id: UUID) -> Video? {
        for (_, vids) in videos {
            if let v = vids.first(where: { $0.id == id }) { return v }
        }
        return nil
    }

    func channelById(_ id: UUID) -> Channel? {
        channels.first { $0.id == id }
    }

    func videosForChannel(_ channelId: UUID) -> [Video] {
        videos[channelId] ?? []
    }

    func firstThumbnail(for channel: Channel) -> String? {
        videos[channel.id]?.first(where: { !$0.thumbnailPath.isEmpty })?.thumbnailPath
    }

    // MARK: - Load

    func load() async {
        do {
            try await DatabaseService.shared.open()
            let loaded = try await DatabaseService.shared.fetchAllChannels()
            channels = loaded
            for channel in channels {
                var vids = try await DatabaseService.shared.fetchVideos(forChannelId: channel.id)
                vids = await healInterruptedDownloads(vids)
                videos[channel.id] = vids
            }
            // Profiles + assignments + favorites
            profiles = try await DatabaseService.shared.fetchAllProfiles()
            profileChannels = try await DatabaseService.shared.fetchAllProfileChannels()
            profileFavorites = try await DatabaseService.shared.fetchAllProfileFavorites()
            profileHiddenChannels = try await DatabaseService.shared.fetchAllProfileHiddenChannels()
            playlists = try await DatabaseService.shared.fetchAllPlaylists()
            playlistVideos = try await DatabaseService.shared.fetchAllPlaylistVideos()
            await ensureUpNextPlaylists()
            // Restore the persisted active profile if it still exists. If the
            // stored id refers to a deleted profile, fall back to nil so the
            // user picks again.
            if let stored = UserDefaults.standard.string(forKey: Self.activeProfileKey),
               let storedId = UUID(uuidString: stored),
               profiles.contains(where: { $0.id == storedId }) {
                activeProfileId = storedId
            } else {
                activeProfileId = nil
            }
        } catch {
            AppLogger.error("LibraryStore.load failed: \(error.localizedDescription)")
        }
    }

    // MARK: - Profile CRUD

    func addProfile(_ profile: Profile) {
        profiles.append(profile)
        profiles.sort { $0.sortOrder < $1.sortOrder }
        profileChannels[profile.id] = []
        // Every profile gets an "Up Next" system playlist as its active
        // queue from day one.
        let upNext = Playlist(profileId: profile.id, name: "Up Next", sortOrder: 0, isSystem: true)
        playlists.append(upNext)
        playlistVideos[upNext.id] = []
        if let idx = profiles.firstIndex(where: { $0.id == profile.id }) {
            profiles[idx].activePlaylistId = upNext.id
        }
        Task {
            await persist("insertProfile") {
                try await DatabaseService.shared.insertProfile(profile)
                try await DatabaseService.shared.insertPlaylist(upNext)
                try await DatabaseService.shared.setActivePlaylist(profileId: profile.id, playlistId: upNext.id)
            }
        }
    }

    // MARK: - Playlists

    /// Guarantees every profile has an "Up Next" system playlist set as
    /// active. Runs on load (covers profiles created before migration 9)
    /// and is idempotent.
    private func ensureUpNextPlaylists() async {
        for profile in profiles {
            let hasSystem = playlists.contains { $0.profileId == profile.id && $0.isSystem }
            if hasSystem {
                // Make sure something is active.
                if profile.activePlaylistId == nil,
                   let sys = playlists.first(where: { $0.profileId == profile.id && $0.isSystem }) {
                    if let idx = profiles.firstIndex(where: { $0.id == profile.id }) {
                        profiles[idx].activePlaylistId = sys.id
                    }
                    await persist("seed active playlist") {
                        try await DatabaseService.shared.setActivePlaylist(profileId: profile.id, playlistId: sys.id)
                    }
                }
                continue
            }
            let upNext = Playlist(profileId: profile.id, name: "Up Next", sortOrder: 0, isSystem: true)
            playlists.append(upNext)
            playlistVideos[upNext.id] = []
            if let idx = profiles.firstIndex(where: { $0.id == profile.id }) {
                profiles[idx].activePlaylistId = upNext.id
            }
            await persist("create Up Next") {
                try await DatabaseService.shared.insertPlaylist(upNext)
                try await DatabaseService.shared.setActivePlaylist(profileId: profile.id, playlistId: upNext.id)
            }
        }
    }

    func createPlaylist(profileId: UUID, name: String) -> Playlist {
        let count = playlists.filter { $0.profileId == profileId }.count
        let playlist = Playlist(profileId: profileId, name: name, sortOrder: count)
        playlists.append(playlist)
        playlistVideos[playlist.id] = []
        Task {
            await persist("createPlaylist") {
                try await DatabaseService.shared.insertPlaylist(playlist)
            }
        }
        return playlist
    }

    func renamePlaylist(id: UUID, name: String) {
        guard let idx = playlists.firstIndex(where: { $0.id == id }), !playlists[idx].isSystem else { return }
        playlists[idx].name = name
        let snapshot = playlists[idx]
        Task {
            await persist("renamePlaylist") {
                try await DatabaseService.shared.updatePlaylist(snapshot)
            }
        }
    }

    func deletePlaylist(id: UUID) {
        guard let pl = playlists.first(where: { $0.id == id }), !pl.isSystem else { return }
        playlists.removeAll { $0.id == id }
        playlistVideos.removeValue(forKey: id)
        // If it was the active playlist, fall back to the profile's Up Next.
        if let pIdx = profiles.firstIndex(where: { $0.activePlaylistId == id }) {
            let sys = playlists.first { $0.profileId == pl.profileId && $0.isSystem }
            profiles[pIdx].activePlaylistId = sys?.id
            let profileId = profiles[pIdx].id
            let fallback = sys?.id
            Task {
                await persist("reset active after delete") {
                    try await DatabaseService.shared.setActivePlaylist(profileId: profileId, playlistId: fallback)
                }
            }
        }
        Task {
            await persist("deletePlaylist") {
                try await DatabaseService.shared.deletePlaylist(id: id)
            }
        }
    }

    func setActivePlaylist(profileId: UUID, playlistId: UUID?) {
        guard let idx = profiles.firstIndex(where: { $0.id == profileId }) else { return }
        profiles[idx].activePlaylistId = playlistId
        Task {
            await persist("setActivePlaylist") {
                try await DatabaseService.shared.setActivePlaylist(profileId: profileId, playlistId: playlistId)
            }
        }
    }

    func setAutoPlaybackMode(profileId: UUID, mode: String) {
        guard let idx = profiles.firstIndex(where: { $0.id == profileId }) else { return }
        profiles[idx].autoPlaybackMode = mode
        Task {
            await persist("setAutoPlaybackMode") {
                try await DatabaseService.shared.setAutoPlaybackMode(profileId: profileId, mode: mode)
            }
        }
    }

    func addToPlaylist(playlistId: UUID, videoId: UUID) {
        var list = playlistVideos[playlistId] ?? []
        guard !list.contains(videoId) else { return }   // dedupe
        let position = list.count
        list.append(videoId)
        playlistVideos[playlistId] = list
        Task {
            await persist("addToPlaylist") {
                try await DatabaseService.shared.addVideoToPlaylist(
                    playlistId: playlistId, videoId: videoId, sortOrder: position
                )
            }
        }
    }

    func removeFromPlaylist(playlistId: UUID, videoId: UUID) {
        playlistVideos[playlistId]?.removeAll { $0 == videoId }
        Task {
            await persist("removeFromPlaylist") {
                try await DatabaseService.shared.removeVideoFromPlaylist(
                    playlistId: playlistId, videoId: videoId
                )
            }
        }
    }

    func reorderPlaylist(playlistId: UUID, videoIds: [UUID]) {
        playlistVideos[playlistId] = videoIds
        Task {
            await persist("reorderPlaylist") {
                try await DatabaseService.shared.setPlaylistVideos(playlistId: playlistId, videoIds: videoIds)
            }
        }
    }

    func clearPlaylist(playlistId: UUID) {
        playlistVideos[playlistId] = []
        Task {
            await persist("clearPlaylist") {
                try await DatabaseService.shared.setPlaylistVideos(playlistId: playlistId, videoIds: [])
            }
        }
    }

    func updateProfile(_ profile: Profile) {
        if let idx = profiles.firstIndex(where: { $0.id == profile.id }) {
            profiles[idx] = profile
            Task {
                await persist("updateProfile") {
                    try await DatabaseService.shared.updateProfile(profile)
                }
            }
        }
    }

    func removeProfile(id: UUID) {
        profiles.removeAll { $0.id == id }
        profileChannels.removeValue(forKey: id)
        if activeProfileId == id { activeProfileId = nil }
        Task {
            await persist("deleteProfile") {
                try await DatabaseService.shared.deleteProfile(id: id)
            }
        }
    }

    func setProfileChannels(profileId: UUID, channelIds: [UUID]) {
        profileChannels[profileId] = Set(channelIds)
        let ids = channelIds
        Task {
            await persist("setProfileChannels") {
                try await DatabaseService.shared.setProfileChannels(
                    profileId: profileId, channelIds: ids
                )
            }
        }
    }

    /// Channels visible to the active profile in viewer mode. If there's no
    /// active profile (or no profiles at all), every channel is visible.
    func visibleChannels(for profileId: UUID?) -> [Channel] {
        guard let pid = profileId, let assigned = profileChannels[pid] else {
            return channels
        }
        return channels.filter { assigned.contains($0.id) }
    }

    // MARK: - Favorites

    func setChannelHidden(profileId: UUID, channelId: UUID, hidden: Bool) {
        var current = profileHiddenChannels[profileId] ?? []
        if hidden { current.insert(channelId) } else { current.remove(channelId) }
        profileHiddenChannels[profileId] = current
        Task {
            await persist("setChannelHidden") {
                if hidden {
                    try await DatabaseService.shared.hideChannel(profileId: profileId, channelId: channelId)
                } else {
                    try await DatabaseService.shared.unhideChannel(profileId: profileId, channelId: channelId)
                }
            }
        }
    }

    func setFavorite(profileId: UUID, videoId: UUID, isFavorite: Bool) {
        var current = profileFavorites[profileId] ?? []
        if isFavorite { current.insert(videoId) } else { current.remove(videoId) }
        profileFavorites[profileId] = current
        Task {
            await persist("setFavorite") {
                if isFavorite {
                    try await DatabaseService.shared.addFavorite(profileId: profileId, videoId: videoId)
                } else {
                    try await DatabaseService.shared.removeFavorite(profileId: profileId, videoId: videoId)
                }
            }
        }
    }

    private func healInterruptedDownloads(_ vids: [Video]) async -> [Video] {
        var healed = vids
        for i in healed.indices where healed[i].downloadState == .downloading {
            healed[i].downloadState    = .error
            healed[i].downloadError    = "Download was interrupted — please tap Retry."
            healed[i].downloadProgress = 0
            AppLogger.info("Healed interrupted download for video \(healed[i].id)")
            let snapshot = healed[i]
            await persist("heal interrupted") {
                try await DatabaseService.shared.updateVideo(snapshot)
            }
        }
        return healed
    }

    // MARK: - Channel CRUD

    func addChannel(_ channel: Channel) {
        channels.append(channel)
        channels.sort { $0.sortOrder < $1.sortOrder }
        videos[channel.id] = []

        undoManager?.registerUndo(withTarget: self) { [channelId = channel.id] target in
            Task { @MainActor in
                target.removeChannel(id: channelId, registerRedo: true)
            }
        }
        undoManager?.setActionName("Add Channel")

        Task {
            await persist("insertChannel") {
                try await DatabaseService.shared.insertChannel(channel)
            }
        }
    }

    func removeChannel(id: UUID, registerRedo: Bool = false) {
        guard let channel = channelById(id) else { return }
        let channelVideos = videos[id] ?? []

        channels.removeAll { $0.id == id }
        videos.removeValue(forKey: id)

        if registerRedo {
            undoManager?.registerUndo(withTarget: self) { [ch = channel, vids = channelVideos] target in
                Task { @MainActor in
                    target.addChannel(ch)
                    for v in vids { target.videos[ch.id]?.append(v) }
                }
            }
        } else {
            undoManager?.registerUndo(withTarget: self) { [ch = channel, vids = channelVideos] target in
                Task { @MainActor in
                    target.channels.append(ch)
                    target.videos[ch.id] = vids
                    await target.persist("undo deleteChannel") {
                        try await DatabaseService.shared.insertChannel(ch)
                    }
                }
            }
            undoManager?.setActionName("Delete Channel")
        }

        Task {
            await persist("deleteChannel") {
                try await DatabaseService.shared.deleteChannel(id: id)
            }
        }
    }

    func updateChannel(_ channel: Channel) {
        if let idx = channels.firstIndex(where: { $0.id == channel.id }) {
            let old = channels[idx]
            channels[idx] = channel

            undoManager?.registerUndo(withTarget: self) { target in
                Task { @MainActor in target.updateChannel(old) }
            }
            undoManager?.setActionName("Rename Channel")

            Task {
                await persist("updateChannel") {
                    try await DatabaseService.shared.updateChannel(channel)
                }
            }
        }
    }

    func moveChannels(from source: IndexSet, to destination: Int) {
        channels.move(fromOffsets: source, toOffset: destination)
        for (i, var ch) in channels.enumerated() {
            ch.sortOrder = i
            channels[i] = ch
        }
        let reordered = channels
        Task {
            do {
                try await DatabaseService.shared.updateChannelsBatched(reordered)
            } catch {
                AppLogger.error("moveChannels persist failed: \(error.localizedDescription)")
            }
        }
    }

    // MARK: - Video CRUD

    func addVideo(_ video: Video) {
        var arr = videos[video.channelId] ?? []
        arr.append(video)
        videos[video.channelId] = arr

        undoManager?.registerUndo(withTarget: self) { [vid = video] target in
            Task { @MainActor in target.removeVideo(id: vid.id) }
        }
        undoManager?.setActionName("Add Video")

        Task {
            await persist("insertVideo") {
                try await DatabaseService.shared.insertVideo(video)
            }
        }
    }

    func removeVideo(id: UUID) {
        guard let video = videoById(id) else { return }
        videos[video.channelId]?.removeAll { $0.id == id }

        undoManager?.registerUndo(withTarget: self) { [v = video] target in
            Task { @MainActor in target.addVideo(v) }
        }
        undoManager?.setActionName("Remove Video")

        Task {
            await persist("deleteVideo") {
                try await DatabaseService.shared.deleteVideo(id: id)
            }
        }
    }

    func updateVideo(_ video: Video) {
        guard let idx = videos[video.channelId]?.firstIndex(where: { $0.id == video.id }) else { return }
        videos[video.channelId]?[idx] = video
    }

    func moveVideos(in channelId: UUID, from source: IndexSet, to destination: Int) {
        guard var arr = videos[channelId] else { return }
        arr.move(fromOffsets: source, toOffset: destination)
        for (i, var v) in arr.enumerated() {
            v.sortOrder = i
            arr[i] = v
        }
        videos[channelId] = arr
        let updated = arr
        Task {
            do {
                try await DatabaseService.shared.updateVideosBatched(updated)
            } catch {
                AppLogger.error("moveVideos persist failed: \(error.localizedDescription)")
            }
        }
    }

    func updateResumePosition(videoId: UUID, seconds: Double) {
        if var video = videoById(videoId) {
            video.resumePositionSeconds = seconds
            updateVideo(video)
        }
        Task {
            await persist("updateResumePosition") {
                try await DatabaseService.shared.updateResumePosition(videoId: videoId, seconds: seconds)
            }
        }
    }

    // MARK: - Persistence Helper

    func persist(
        _ context: String,
        _ op: @Sendable @escaping () async throws -> Void
    ) async {
        do { try await op() }
        catch { AppLogger.error("Persist [\(context)] failed: \(error.localizedDescription)") }
    }
}
