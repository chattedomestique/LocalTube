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
    /// new videos to the library. Also fetches the channel banner on first sync.
    /// Errors are caught and stored on Channel.lastSyncError so the UI can
    /// surface them — they no longer silently disappear into the log.
    func syncChannel(_ channel: Channel) async {
        guard let ytId = channel.youtubeChannelId, !ytId.isEmpty else { return }

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
