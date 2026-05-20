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
        } catch {
            AppLogger.error("LibraryStore.load failed: \(error.localizedDescription)")
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
