import Foundation
import Observation

// MARK: - App Mode

enum AppMode: Equatable {
    case viewer
    case editor
}

enum PendingPinAction: Sendable {
    /// PIN unlocks the global Admin shell.
    case admin
    /// PIN unlocks the inline edit layer (sets `isEditing = true`).
    case edit
}

/// What happens when a channel-initiated video ends. Per profile;
/// stored on `profiles.auto_playback_mode`. Queue playback ignores this
/// (it always advances to the next queued item).
enum PlaybackMode: String, CaseIterable, Sendable {
    case exit          // return to channel view (default)
    case sequential    // play the next video in the channel
    case repeatOne     // replay the same video
    case random        // play a random video from the channel

    var next: PlaybackMode {
        let all = PlaybackMode.allCases
        let idx = all.firstIndex(of: self) ?? 0
        return all[(idx + 1) % all.count]
    }
}

/// Where the current playback originated, which drives end-of-video
/// behaviour. Channel → apply PlaybackMode. Queue → advance the queue.
enum PlaybackSource: Sendable, Equatable {
    case channel(UUID)
    case queue(UUID)   // playlist id
}

// MARK: - Navigation Destination

enum ViewerDestination: Hashable {
    case channel(UUID)
    case player(UUID)
}

// MARK: - App State
//
// Root state container injected via `.environment(appState)`. Holds:
//   • Library data + CRUD (delegated to `library: LibraryStore`)
//   • UI navigation state (viewerPath, currentVideoId, editor selection)
//   • Mode + onboarding gates (viewer/editor, PIN, dependency checks)
//   • Service references with lifecycle (downloadService, dependencyService)
//
// LibraryStore was split out so the domain CRUD is testable in isolation.
// Forwarding helpers below preserve compatibility with existing call sites
// that go through `appState.channels`, `appState.addVideo(_:)`, etc.

@Observable
@MainActor
final class AppState {
    // MARK: - Library

    let library = LibraryStore()

    // MARK: - Navigation

    var viewerPath: [ViewerDestination] = []
    var currentVideoId: UUID?

    // MARK: - Mode

    var appMode: AppMode = .viewer
    // editorRemainingSeconds remains as a computed always-zero so any
    // stale bridge payload reader still sees a sane value during the
    // migration. The auto-lock timer was removed in the editing-model
    // redesign — parents now have to explicitly Exit Admin / Exit Edit.
    var editorRemainingSeconds: Int { 0 }

    /// Inline edit layer flag (separate from `.editor` admin mode).
    /// When true, the active profile's Library/Channel page renders edit
    /// affordances (drag handles, remove buttons) and blocks navigation
    /// into deeper layers. Mutually exclusive with `.editor` admin mode —
    /// entering one clears the other.
    var isEditing: Bool = false

    /// Tracks what to do after a successful PIN entry — admin (the
    /// global editor) vs. edit (the inline edit layer). Defaults to
    /// `.admin` for back-compat with the existing picker flow.
    var pendingPinAction: PendingPinAction = .admin

    // MARK: - Onboarding / Gates

    var isOnboarding: Bool = false
    var needsPINSetup: Bool = false
    var showPINEntry: Bool = false

    /// False when a download folder is configured but currently
    /// unreachable (external drive unplugged, share offline). The UI shows
    /// a "library unavailable" screen with Retry / Locate instead of
    /// onboarding, and downloads pause until it comes back.
    var libraryFolderAvailable: Bool = true

    // MARK: - Downloads

    var downloadQueue: [DownloadQueueItem] = []

    // MARK: - Settings

    var settings: AppSettings = AppSettings()

    // MARK: - Dependencies

    var dependencyStatus = DependencyStatus()

    // MARK: - Editor State

    var editorSelectedChannelId: UUID?

    // MARK: - Undo

    var undoManager: UndoManager? {
        didSet { library.undoManager = undoManager }
    }

    // MARK: - Sync State

    /// Channel IDs currently being synced; observed by the bridge to show/hide indicators.
    var syncingChannelIds: Set<UUID> = []

    // MARK: - Services (held here for lifecycle)

    let dependencyService = DependencyService()
    var downloadService = DownloadService()
    let maintenance = LibraryMaintenanceService()

    // MARK: - External hooks (set by WebWindowController)

    /// Called every second while editor mode is active with remaining lock seconds.
    var onEditorTimerTick: (@MainActor (Int) -> Void)?

    // MARK: - App info

    /// "1.0.34 (35)" — from the bundle's Info.plist. Shown in Settings → About.
    static let appVersion: String = {
        let info = Bundle.main.infoDictionary ?? [:]
        let short = info["CFBundleShortVersionString"] as? String ?? "dev"
        let build = info["CFBundleVersion"] as? String ?? "0"
        return "\(short) (\(build))"
    }()

    // MARK: - Init

    init() {}

    // MARK: - Library Loading

    func setup() {
        downloadService.appState = self
        maintenance.appState = self
        library.undoManager = undoManager
    }

    func loadLibrary() async {
        await library.load()
    }

    /// Library database error from launch, if any (nil = healthy).
    var libraryLoadError: String? { library.loadError }

    /// Re-checks whether the configured download folder is reachable and
    /// updates `libraryFolderAvailable`. Returns the new value.
    @discardableResult
    func refreshLibraryFolderAvailability() -> Bool {
        let available: Bool
        if settings.downloadFolderPath == nil {
            available = true   // nothing configured yet → onboarding, not "unavailable"
        } else {
            available = SettingsService.isDownloadFolderAvailable(settings)
        }
        if available != libraryFolderAvailable {
            AppLogger.info("Library folder availability changed: \(available)")
        }
        libraryFolderAvailable = available
        return available
    }

    // MARK: - Library Forwarders
    //
    // Keep existing call sites (views, bridge handlers, services) working by
    // proxying the channel/video accessors. New code can call `library.X`
    // directly; these forwarders are not deprecated yet because they read
    // cleanly enough at call sites.

    var channels: [Channel] {
        get { library.channels }
        set { library.channels = newValue }
    }

    var videos: [UUID: [Video]] {
        get { library.videos }
        set { library.videos = newValue }
    }

    func videoById(_ id: UUID) -> Video?        { library.videoById(id) }
    func channelById(_ id: UUID) -> Channel?    { library.channelById(id) }
    func videosForChannel(_ id: UUID) -> [Video] { library.videosForChannel(id) }
    func firstThumbnail(for ch: Channel) -> String? { library.firstThumbnail(for: ch) }

    // Profile forwarders
    var profiles: [Profile] {
        get { library.profiles }
        set { library.profiles = newValue }
    }
    var profileChannels: [UUID: Set<UUID>] {
        get { library.profileChannels }
        set { library.profileChannels = newValue }
    }
    var activeProfileId: UUID? {
        get { library.activeProfileId }
        set { library.activeProfileId = newValue }
    }
    func addProfile(_ p: Profile)            { library.addProfile(p) }
    func updateProfile(_ p: Profile)         { library.updateProfile(p) }
    func removeProfile(id: UUID)             { library.removeProfile(id: id) }
    func setProfileChannels(profileId: UUID, channelIds: [UUID]) {
        library.setProfileChannels(profileId: profileId, channelIds: channelIds)
    }

    // Favorites forwarders
    var profileFavorites: [UUID: Set<UUID>] {
        get { library.profileFavorites }
        set { library.profileFavorites = newValue }
    }
    func setFavorite(profileId: UUID, videoId: UUID, isFavorite: Bool) {
        library.setFavorite(profileId: profileId, videoId: videoId, isFavorite: isFavorite)
    }

    // Hidden-channel forwarders
    var profileHiddenChannels: [UUID: Set<UUID>] {
        get { library.profileHiddenChannels }
        set { library.profileHiddenChannels = newValue }
    }
    func setChannelHidden(profileId: UUID, channelId: UUID, hidden: Bool) {
        library.setChannelHidden(profileId: profileId, channelId: channelId, hidden: hidden)
    }

    // Playlist forwarders
    var playlists: [Playlist] {
        get { library.playlists }
        set { library.playlists = newValue }
    }
    var playlistVideos: [UUID: [UUID]] {
        get { library.playlistVideos }
        set { library.playlistVideos = newValue }
    }
    @discardableResult
    func createPlaylist(profileId: UUID, name: String) -> Playlist {
        library.createPlaylist(profileId: profileId, name: name)
    }
    func renamePlaylist(id: UUID, name: String)        { library.renamePlaylist(id: id, name: name) }
    func deletePlaylist(id: UUID)                      { library.deletePlaylist(id: id) }
    func setActivePlaylist(profileId: UUID, playlistId: UUID?) {
        library.setActivePlaylist(profileId: profileId, playlistId: playlistId)
    }
    func addToPlaylist(playlistId: UUID, videoId: UUID)      { library.addToPlaylist(playlistId: playlistId, videoId: videoId) }
    func removeFromPlaylist(playlistId: UUID, videoId: UUID) { library.removeFromPlaylist(playlistId: playlistId, videoId: videoId) }
    func reorderPlaylist(playlistId: UUID, videoIds: [UUID]) { library.reorderPlaylist(playlistId: playlistId, videoIds: videoIds) }
    func clearPlaylist(playlistId: UUID)                    { library.clearPlaylist(playlistId: playlistId) }

    /// The active profile's channel-playback mode (defaults to .exit).
    var activeProfileAutoPlaybackMode: PlaybackMode {
        guard let pid = activeProfileId,
              let p = profiles.first(where: { $0.id == pid }),
              let raw = p.autoPlaybackMode,
              let mode = PlaybackMode(rawValue: raw) else { return .exit }
        return mode
    }
    func setAutoPlaybackMode(profileId: UUID, mode: PlaybackMode) {
        library.setAutoPlaybackMode(profileId: profileId, mode: mode.rawValue)
    }

    func addChannel(_ channel: Channel)         { library.addChannel(channel) }

    /// Removes a channel from the library and deletes its folder
    /// (videos, thumbnails, banner) from disk. Any in-flight downloads for
    /// the channel are cancelled first so nothing keeps writing into the
    /// folder being removed.
    func removeChannel(id: UUID, registerRedo: Bool = false) {
        guard let channel = channelById(id) else { return }
        let channelVideoIds = Set(videosForChannel(id).map { $0.id })
        downloadService.cancelDownloads(forVideoIds: channelVideoIds)

        let others = channels.filter { $0.id != id }
        let root = settings.downloadFolderPath

        library.removeChannel(id: id, registerRedo: registerRedo)
        if editorSelectedChannelId == id { editorSelectedChannelId = nil }

        if let root, !root.isEmpty, SettingsService.isDirectory(atPath: root) {
            Task {
                _ = await LibraryMaintenanceService.deleteFolder(for: channel, rootFolder: root, otherChannels: others)
            }
        }
    }
    func updateChannel(_ channel: Channel)      { library.updateChannel(channel) }
    func moveChannels(from source: IndexSet, to destination: Int) {
        library.moveChannels(from: source, to: destination)
    }

    func addVideo(_ video: Video)               { library.addVideo(video) }

    /// Removes a video from the library and deletes its file, thumbnail
    /// and any partial download from disk.
    func removeVideo(id: UUID) {
        guard let video = videoById(id) else { return }
        downloadService.cancelDownloads(forVideoIds: [id])
        let channel = channelById(video.channelId)
        let root = settings.downloadFolderPath
        library.removeVideo(id: id)
        Task {
            await LibraryMaintenanceService.deleteFiles(for: video, channel: channel, rootFolder: root)
        }
    }
    func updateVideo(_ video: Video)            { library.updateVideo(video) }
    func updateVideoAndPersist(_ video: Video, context: String) {
        library.updateVideoAndPersist(video, context: context)
    }
    func moveVideos(in channelId: UUID, from source: IndexSet, to destination: Int) {
        library.moveVideos(in: channelId, from: source, to: destination)
    }
    func updateResumePosition(videoId: UUID, seconds: Double) {
        library.updateResumePosition(videoId: videoId, seconds: seconds)
    }

    /// Marks a "ready" video whose file has disappeared as queued again and
    /// puts it back in the download queue. Returns the updated video.
    @discardableResult
    func markVideoMissing(_ video: Video) async -> Video? {
        guard var v = videoById(video.id), let channel = channelById(v.channelId) else { return nil }
        AppLogger.info("Video file missing, re-queueing: \(v.title)")
        v.downloadState = .queued
        v.downloadProgress = 0
        v.downloadError = nil
        updateVideoAndPersist(v, context: "mark missing")
        await downloadService.enqueue(video: v, channel: channel)
        return videoById(v.id)
    }

    // Used by DownloadService / LocalTubeBridge for fire-and-forget DB writes
    // with consistent logging instead of `try?` swallowing.
    func persist(
        _ context: String,
        _ op: @Sendable @escaping () async throws -> Void
    ) async {
        await library.persist(context, op)
    }

    // MARK: - Admin Mode (formerly "Editor Mode")
    //
    // Internal names (requestEditorMode, enterEditorMode, exitEditorMode,
    // AppMode.editor) are kept to limit churn — they're not user-visible.
    // The user-facing label is "Admin" throughout the UI.
    //
    // The auto-lock timer was removed. Admin mode now stays open until
    // the parent explicitly clicks "Exit Admin". This matches the new
    // editing-model design (EDITING_MODEL.md) where editing is a
    // deliberate context the parent enters and leaves on purpose.

    func requestEditorMode() {
        showPINEntry = true
    }

    func enterEditorMode() {
        appMode = .editor
        isEditing = false   // mutual exclusion
        showPINEntry = false
        pendingPinAction = .admin
        AppLogger.info("Admin mode entered")
    }

    func exitEditorMode() {
        appMode = .viewer
        isEditing = false
        showPINEntry = false
        AppLogger.info("Admin mode exited")
    }

    /// Enter the inline edit layer (per-profile, page-contextual). Always
    /// keeps `appMode = .viewer` — edit layer overlays the viewer; it
    /// doesn't replace it with the Admin shell.
    func enterEditMode() {
        appMode = .viewer
        isEditing = true
        showPINEntry = false
        pendingPinAction = .admin
        AppLogger.info("Edit layer entered")
    }

    func endEditMode() {
        isEditing = false
        AppLogger.info("Edit layer exited")
    }

    // MARK: - Channel Sync

    /// Fetches the latest video list for a YouTube source channel and adds any
    /// new videos to the library. Also re-queues videos whose file has gone
    /// missing or whose last download failed, and fetches the channel banner
    /// on first sync. Errors are caught and stored on Channel.lastSyncError
    /// so the UI can surface them — they no longer silently disappear into
    /// the log.
    func syncChannel(_ channel: Channel) async {
        guard let ytId = channel.youtubeChannelId, !ytId.isEmpty else { return }
        guard !syncingChannelIds.contains(channel.id) else {
            AppLogger.info("syncChannel: \(channel.displayName) already syncing — ignoring")
            return
        }

        syncingChannelIds.insert(channel.id)
        NotificationCenter.default.post(name: .channelSyncStateChanged, object: nil)

        defer {
            syncingChannelIds.remove(channel.id)
            NotificationCenter.default.post(name: .channelSyncStateChanged, object: nil)
        }

        // Fetch video list from YouTube — store the failure reason on the
        // channel so the UI shows a banner instead of silently doing nothing.
        let entries: [ChannelSyncEntry]
        do {
            entries = try await ChannelSyncService.fetchVideoList(youtubeChannelId: ytId)
        } catch {
            let msg = error.localizedDescription
            AppLogger.error("ChannelSyncService: \(msg)")
            if var ch = channels.first(where: { $0.id == channel.id }) {
                ch.lastSyncError = msg
                updateChannel(ch)
                await persist("syncChannel error") {
                    try await DatabaseService.shared.updateChannelSyncState(
                        id: ch.id, lastSyncedAt: ch.lastSyncedAt, lastSyncError: msg
                    )
                }
            }
            return
        }

        // The channel may have been deleted while yt-dlp was running.
        guard channelById(channel.id) != nil else { return }

        // Success — clear any prior error and stamp lastSyncedAt.
        if var ch = channels.first(where: { $0.id == channel.id }) {
            let now = Date()
            ch.lastSyncedAt = now
            ch.lastSyncError = nil
            updateChannel(ch)
            await persist("syncChannel success") {
                try await DatabaseService.shared.updateChannelSyncState(
                    id: ch.id, lastSyncedAt: now, lastSyncError: nil
                )
            }
        }

        // ── New uploads ─────────────────────────────────────────────────
        let existingSet = Set(videosForChannel(channel.id).map { $0.youtubeVideoId })
        var nextSortOrder = (videos[channel.id]?.map { $0.sortOrder }.max() ?? -1) + 1
        var added = 0
        for entry in entries {
            guard !existingSet.contains(entry.videoId) else { continue }
            let video = Video(
                channelId: channel.id,
                youtubeVideoId: entry.videoId,
                title: entry.title,
                durationSeconds: entry.durationSeconds ?? 0,
                downloadState: .queued,
                sortOrder: nextSortOrder
            )
            nextSortOrder += 1
            added += 1
            addVideo(video)
            await downloadService.enqueue(video: video, channel: channel)
        }

        // ── Missing files + failed downloads ────────────────────────────
        // (a) A ready video whose file is gone from disk goes back in the
        //     queue. (b) A video whose last download errored gets another
        //     attempt — transient network failures shouldn't need a
        //     per-video Retry click.
        let requeued = await requeueMissingAndFailed(in: channel)
        if added > 0 || requeued > 0 {
            AppLogger.info("Sync \(channel.displayName): \(added) new, \(requeued) re-queued (missing/failed)")
        }

        // Fetch banner if not already present
        if channel.bannerPath.isEmpty, let rootFolder = settings.downloadFolderPath, !rootFolder.isEmpty {
            if let bannerPath = await ChannelBannerService.fetchAndDownload(
                youtubeChannelId: ytId,
                sanitizedFolderName: channel.sanitizedFolderName,
                rootFolder: rootFolder
            ) {
                if let idx = channels.firstIndex(where: { $0.id == channel.id }) {
                    channels[idx].bannerPath = bannerPath
                }
                await persist("updateChannelBanner") {
                    try await DatabaseService.shared.updateChannelBanner(id: channel.id, bannerPath: bannerPath)
                }
                NotificationCenter.default.post(name: .channelBannerUpdated, object: nil)
            }
        }
    }

    /// Re-queues a channel's videos whose file is missing on disk or whose
    /// last download failed. Returns how many were re-queued.
    @discardableResult
    func requeueMissingAndFailed(in channel: Channel) async -> Int {
        guard libraryFolderAvailable,
              let root = settings.downloadFolderPath,
              SettingsService.isDirectory(atPath: root) else { return 0 }
        let knownRoots = settings.knownLibraryRoots
        let current = videosForChannel(channel.id)
        let readyPaths = current
            .filter { $0.downloadState == .ready }
            .map { ($0.id, $0.localFilePath) }

        let missingIds: [UUID] = await Task.detached(priority: .utility) {
            readyPaths
                .filter { !LibraryMaintenanceService.fileExists(forStored: $0.1, currentRoot: root, knownRoots: knownRoots) }
                .map { $0.0 }
        }.value

        var count = 0
        for id in missingIds {
            guard let v = videoById(id) else { continue }
            if await markVideoMissing(v) != nil { count += 1 }
        }
        for video in videosForChannel(channel.id) where video.downloadState == .error {
            await downloadService.retryDownload(video: video, channel: channel)
            count += 1
        }
        return count
    }

    /// Auto-checks source channels for newly uploaded videos. Syncs only
    /// channels whose last successful sync is older than `maxAge` (or that
    /// have never synced), one at a time so we never spawn a burst of yt-dlp
    /// processes. Each `syncChannel` adds just the new videos, enqueues their
    /// downloads, and posts `.channelSyncStateChanged` so the UI keeps up.
    /// Driven on launch and on a daily timer (see AppDelegate).
    func autoSyncStaleChannels(maxAge: TimeInterval) async {
        guard libraryFolderAvailable else {
            AppLogger.info("Auto-sync skipped: library folder unavailable")
            return
        }
        let now = Date()
        let due = channels.filter { ch in
            guard ch.type == .source, ch.youtubeChannelId?.isEmpty == false else { return false }
            guard let last = ch.lastSyncedAt else { return true }   // never synced → due
            return now.timeIntervalSince(last) >= maxAge
        }
        guard !due.isEmpty else {
            AppLogger.info("Auto-sync: no source channels due for refresh")
            return
        }
        AppLogger.info("Auto-sync: refreshing \(due.count) source channel(s) for new uploads")
        for channel in due {
            await syncChannel(channel)
        }
    }

    // MARK: - Download

    var activeDownload: DownloadQueueItem? {
        downloadQueue.first { $0.state == .active }
    }

    var pendingDownloadCount: Int {
        downloadQueue.filter { $0.state == .waiting || $0.state == .active }.count
    }
}

// MARK: - Notification Names

extension Notification.Name {
    static let channelBannerUpdated    = Notification.Name("LocalTube.channelBannerUpdated")
    static let channelSyncStateChanged = Notification.Name("LocalTube.channelSyncStateChanged")
    /// Posted when `libraryFolderAvailable` or the library load error changes.
    static let libraryStatusChanged    = Notification.Name("LocalTube.libraryStatusChanged")
}
