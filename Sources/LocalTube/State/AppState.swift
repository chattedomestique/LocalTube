import Foundation
import SwiftUI
import Observation

// MARK: - App Mode

enum AppMode: Equatable {
    case viewer
    case editor
}

// MARK: - Navigation Destination

enum ViewerDestination: Hashable {
    case channel(UUID)
    case player(UUID)
}

// MARK: - App State

@Observable
@MainActor
final class AppState {
    // MARK: - Library

    var channels: [Channel] = []
    var videos: [UUID: [Video]] = [:]   // keyed by channelId

    // MARK: - Navigation

    var viewerPath: [ViewerDestination] = []
    var currentVideoId: UUID?

    // MARK: - Mode

    var appMode: AppMode = .viewer
    private var editorLockTimer: Timer?
    private(set) var editorRemainingSeconds: Int = 0

    // MARK: - Onboarding / Gates

    var isOnboarding: Bool = false
    var needsPINSetup: Bool = false
    var showPINEntry: Bool = false

    // MARK: - Downloads

    var downloadQueue: [DownloadQueueItem] = []

    // MARK: - Settings

    var settings: AppSettings = AppSettings()

    // MARK: - Dependencies

    var dependencyStatus = DependencyStatus()

    // MARK: - Editor State

    var editorSelectedChannelId: UUID?

    // MARK: - Undo

    var undoManager: UndoManager?

    // MARK: - Services (held here for lifecycle)

    let dependencyService = DependencyService()
    var downloadService = DownloadService()

    // MARK: - Init

    init() {}

    // MARK: - Library Loading

    func setup() {
        downloadService.appState = self
    }

    func loadLibrary() async {
        do {
            try await DatabaseService.shared.open()
            let loaded = try await DatabaseService.shared.fetchAllChannels()
            channels = loaded
            // Eager-load all videos
            for channel in channels {
                let vids = try await DatabaseService.shared.fetchVideos(forChannelId: channel.id)
                videos[channel.id] = vids
            }
        } catch {
            AppLogger.error("Failed to load library: \(error.localizedDescription)")
        }
    }

    // MARK: - Lookup Helpers

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
            try? await DatabaseService.shared.insertChannel(channel)
        }
    }

    func removeChannel(id: UUID, registerRedo: Bool = false) {
        guard let channel = channelById(id) else { return }
        let channelVideos = videos[id] ?? []

        channels.removeAll { $0.id == id }
        videos.removeValue(forKey: id)
        if editorSelectedChannelId == id { editorSelectedChannelId = nil }

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
                    try? await DatabaseService.shared.insertChannel(ch)
                }
            }
            undoManager?.setActionName("Delete Channel")
        }

        Task {
            try? await DatabaseService.shared.deleteChannel(id: id)
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

            Task { try? await DatabaseService.shared.updateChannel(channel) }
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
            for ch in reordered {
                try? await DatabaseService.shared.updateChannel(ch)
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

        Task { try? await DatabaseService.shared.insertVideo(video) }
    }

    func removeVideo(id: UUID) {
        guard let video = videoById(id) else { return }
        videos[video.channelId]?.removeAll { $0.id == id }

        undoManager?.registerUndo(withTarget: self) { [v = video] target in
            Task { @MainActor in target.addVideo(v) }
        }
        undoManager?.setActionName("Remove Video")

        Task { try? await DatabaseService.shared.deleteVideo(id: id) }
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
            for v in updated {
                try? await DatabaseService.shared.updateVideo(v)
            }
        }
    }

    func updateResumePosition(videoId: UUID, seconds: Double) {
        if var video = videoById(videoId) {
            video.resumePositionSeconds = seconds
            updateVideo(video)
        }
        Task { try? await DatabaseService.shared.updateResumePosition(videoId: videoId, seconds: seconds) }
    }

    // MARK: - Editor Mode

    func requestEditorMode() {
        showPINEntry = true
    }

    func enterEditorMode() {
        appMode = .editor
        showPINEntry = false
        resetEditorLockTimer()
        AppLogger.info("Editor Mode entered")
    }

    func exitEditorMode() {
        appMode = .viewer
        editorLockTimer?.invalidate()
        editorLockTimer = nil
        editorRemainingSeconds = 0
        AppLogger.info("Editor Mode exited")
    }

    func resetEditorLockTimer() {
        editorLockTimer?.invalidate()
        let minutes = settings.editorAutoLockMinutes
        editorRemainingSeconds = minutes * 60

        editorLockTimer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                guard let self = self else { return }
                self.editorRemainingSeconds -= 1
                if self.editorRemainingSeconds <= 0 {
                    AppLogger.info("Editor Mode auto-locked due to inactivity")
                    self.exitEditorMode()
                }
            }
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
