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

    var undoManager: UndoManager? {
        didSet { library.undoManager = undoManager }
    }

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
        library.undoManager = undoManager
    }

    func loadLibrary() async {
        await library.load()
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

    func addChannel(_ channel: Channel)         { library.addChannel(channel) }
    func removeChannel(id: UUID, registerRedo: Bool = false) {
        library.removeChannel(id: id, registerRedo: registerRedo)
        if editorSelectedChannelId == id { editorSelectedChannelId = nil }
    }
    func updateChannel(_ channel: Channel)      { library.updateChannel(channel) }
    func moveChannels(from source: IndexSet, to destination: Int) {
        library.moveChannels(from: source, to: destination)
    }

    func addVideo(_ video: Video)               { library.addVideo(video) }
    func removeVideo(id: UUID)                  { library.removeVideo(id: id) }
    func updateVideo(_ video: Video)            { library.updateVideo(video) }
    func moveVideos(in channelId: UUID, from source: IndexSet, to destination: Int) {
        library.moveVideos(in: channelId, from: source, to: destination)
    }
    func updateResumePosition(videoId: UUID, seconds: Double) {
        library.updateResumePosition(videoId: videoId, seconds: seconds)
    }

    // Used by DownloadService / LocalTubeBridge for fire-and-forget DB writes
    // with consistent logging instead of `try?` swallowing.
    func persist(
        _ context: String,
        _ op: @Sendable @escaping () async throws -> Void
    ) async {
        await library.persist(context, op)
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
                await persist("updateChannelBanner") {
                    try await DatabaseService.shared.updateChannelBanner(id: channel.id, bannerPath: bannerPath)
                }
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
