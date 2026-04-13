import Foundation
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

    // MARK: - Sync State

    /// Channel IDs currently being synced; observed by the bridge to show/hide indicators.
    var syncingChannelIds: Set<UUID> = []

    // MARK: - Services (held here for lifecycle)

    let dependencyService = DependencyService()
    var downloadService = DownloadService()

    // MARK: - External hooks (set by WebWindowController)

    /// Called every second while editor mode is active with remaining lock seconds.
    var onEditorTimerTick: (@MainActor (Int) -> Void)?

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
            // Eager-load all videos, healing any state left over from a previous
            // session that was killed or rebuilt mid-download.
            for channel in channels {
                var vids = try await DatabaseService.shared.fetchVideos(forChannelId: channel.id)
                vids = await healInterruptedDownloads(vids)
                videos[channel.id] = vids
            }
        } catch {
            AppLogger.error("Failed to load library: \(error.localizedDescription)")
        }
    }

    /// Resets any video that was mid-download when the previous process died.
    /// Without this, those videos show a frozen progress bar with no way to recover
    /// other than deleting and re-adding the video.
    private func healInterruptedDownloads(_ vids: [Video]) async -> [Video] {
        var healed = vids
        for i in healed.indices where healed[i].downloadState == .downloading {
            healed[i].downloadState    = .error
            healed[i].downloadError    = "Download was interrupted — please tap Retry."
            healed[i].downloadProgress = 0
            AppLogger.info("Healed interrupted download for video \(healed[i].id)")
            try? await DatabaseService.shared.updateVideo(healed[i])
        }
        return healed
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
        showPINEntry = false
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
                self.onEditorTimerTick?(self.editorRemainingSeconds)
                if self.editorRemainingSeconds <= 0 {
                    AppLogger.info("Editor Mode auto-locked due to inactivity")
                    self.exitEditorMode()
                }
            }
        }
    }

    // MARK: - Channel Sync

    /// Fetches the latest video list for a YouTube source channel and adds any
    /// new videos to the library. Also fetches the channel banner on first sync.
    func syncChannel(_ channel: Channel) async {
        guard let ytId = channel.youtubeChannelId, !ytId.isEmpty else { return }

        syncingChannelIds.insert(channel.id)
        NotificationCenter.default.post(name: .channelSyncStateChanged, object: nil)

        defer {
            syncingChannelIds.remove(channel.id)
            NotificationCenter.default.post(name: .channelSyncStateChanged, object: nil)
        }

        // Fetch video list from YouTube
        let entries = await ChannelSyncService.fetchVideoList(youtubeChannelId: ytId)
        let existing = videosForChannel(channel.id).map { $0.youtubeVideoId }
        let existingSet = Set(existing)

        for (i, entry) in entries.enumerated() {
            guard !existingSet.contains(entry.videoId) else { continue }
            let video = Video(
                channelId: channel.id,
                youtubeVideoId: entry.videoId,
                title: entry.title,
                durationSeconds: entry.durationSeconds ?? 0,
                downloadState: .queued,
                sortOrder: (videos[channel.id]?.count ?? 0) + i
            )
            addVideo(video)
            Task { await downloadService.enqueue(video: video, channel: channel) }
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
                try? await DatabaseService.shared.updateChannelBanner(id: channel.id, bannerPath: bannerPath)
                NotificationCenter.default.post(name: .channelBannerUpdated, object: nil)
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

// MARK: - Notification Names

extension Notification.Name {
    static let channelBannerUpdated    = Notification.Name("LocalTube.channelBannerUpdated")
    static let channelSyncStateChanged = Notification.Name("LocalTube.channelSyncStateChanged")
}
