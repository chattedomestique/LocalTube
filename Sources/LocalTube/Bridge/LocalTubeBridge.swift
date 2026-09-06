import WebKit
import AppKit
import Foundation

// MARK: - LocalTube JS Bridge
//
// Handles all messages arriving from the WKWebView via
//   window.webkit.messageHandlers.LocalTubeBridge.postMessage({ type, payload })
//
// Each message is decoded into a BridgeMessage and dispatched to the appropriate handler.

@MainActor
final class LocalTubeBridge: NSObject, WKScriptMessageHandler {

    // MARK: - Dependencies

    weak var appState: AppState?
    weak var playerOverlayController: PlayerOverlayController?
    let emitter = BridgeEventEmitter()

    // MARK: - WKScriptMessageHandler

    // M7 fix: Dispatch using BridgeMessageType enum instead of raw strings.
    // This ensures a single source of truth for valid message types.
    func userContentController(
        _ userContentController: WKUserContentController,
        didReceive message: WKScriptMessage
    ) {
        guard let body = message.body as? [String: Any],
              let typeStr = body["type"] as? String else {
            AppLogger.error("Bridge: malformed message body: \(message.body)")
            return
        }

        guard let messageType = BridgeMessageType(rawValue: typeStr) else {
            AppLogger.error("Bridge: unknown message type: \(typeStr)")
            return
        }

        let payloadDict = body["payload"] as? [String: Any] ?? [:]

        // Never log PIN payloads.
        if messageType != .validatePIN && messageType != .setPIN {
            AppLogger.info("Bridge ← JS: \(typeStr)")
        } else {
            AppLogger.info("Bridge ← JS: \(typeStr) (payload redacted)")
        }

        switch messageType {
        case .getState:          handleGetState()
        case .playVideo:         handlePlayVideo(payloadDict)
        case .stopPlayer:        handleStopPlayer()
        case .openFolderPicker:  handleOpenFolderPicker()
        case .validatePIN:       handleValidatePIN(payloadDict)
        case .setPIN:            handleSetPIN(payloadDict)
        case .requestEditorMode: handleRequestEditorMode()
        case .exitEditorMode:    handleExitEditorMode()
        case .addChannel:        handleAddChannel(payloadDict)
        case .deleteChannel:     handleDeleteChannel(payloadDict)
        case .updateChannel:     handleUpdateChannel(payloadDict)
        case .addVideoURLs:      handleAddVideoURLs(payloadDict)
        case .deleteVideo:       handleDeleteVideo(payloadDict)
        case .retryDownload:     handleRetryDownload(payloadDict)
        case .saveSettings:      handleSaveSettings(payloadDict)
        case .checkDependencies: handleCheckDependencies()
        case .syncChannel:         handleSyncChannel(payloadDict)
        case .uploadChannelBanner: handleUploadChannelBanner(payloadDict)
        case .setActiveProfile:    handleSetActiveProfile(payloadDict)
        case .addProfile:          handleAddProfile(payloadDict)
        case .updateProfile:       handleUpdateProfile(payloadDict)
        case .deleteProfile:       handleDeleteProfile(payloadDict)
        case .setProfileChannels:  handleSetProfileChannels(payloadDict)
        case .dismissPINEntry:     handleDismissPINEntry()
        case .toggleFavorite:      handleToggleFavorite(payloadDict)
        case .requestEditMode:     handleRequestEditMode()
        case .endEditMode:         handleEndEditMode()
        case .toggleChannelHidden: handleToggleChannelHidden(payloadDict)
        case .createPlaylist:      handleCreatePlaylist(payloadDict)
        case .renamePlaylist:      handleRenamePlaylist(payloadDict)
        case .deletePlaylist:      handleDeletePlaylist(payloadDict)
        case .setActivePlaylist:   handleSetActivePlaylist2(payloadDict)
        case .addToPlaylist:       handleAddToPlaylist(payloadDict)
        case .removeFromPlaylist:  handleRemoveFromPlaylist(payloadDict)
        case .reorderPlaylist:     handleReorderPlaylist(payloadDict)
        case .clearPlaylist:       handleClearPlaylist(payloadDict)
        case .setAutoPlaybackMode: handleSetAutoPlaybackMode(payloadDict)
        case .chooseLibraryFolder: handleChooseLibraryFolder()
        case .relocateLibrary:     handleRelocateLibrary(payloadDict)
        case .verifyLibrary:       handleVerifyLibrary()
        case .revealLibraryFolder: handleRevealLibraryFolder()
        case .recheckLibraryFolder: handleRecheckLibraryFolder()
        case .retryFailedDownloads: handleRetryFailedDownloads(payloadDict)
        }
    }

    // MARK: - Library management

    /// Settings → Change… Picks a folder and returns an analysis so the UI
    /// can offer Move / Adopt / Switch. Never changes settings by itself.
    private func handleChooseLibraryFolder() {
        guard let appState else { return }
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.canCreateDirectories = true
        panel.allowsMultipleSelection = false
        panel.prompt = "Choose Library Folder"
        panel.message = "Select the folder where LocalTube should keep downloaded videos."
        if let current = appState.settings.downloadFolderPath, SettingsService.isDirectory(atPath: current) {
            panel.directoryURL = URL(fileURLWithPath: current).deletingLastPathComponent()
        }
        panel.begin { [weak self] response in
            Task { @MainActor [weak self] in
                guard let self, let appState = self.appState else { return }
                guard response == .OK, let url = panel.url else {
                    self.emitter.emitLibraryFolderPicked(analysis: nil)
                    return
                }
                let analysis = await appState.maintenance.analyzeFolder(url.path)
                self.emitter.emitLibraryFolderPicked(analysis: analysis)
            }
        }
    }

    private func handleRelocateLibrary(_ payload: [String: Any]) {
        guard let appState,
              let path = payload["path"] as? String, !path.isEmpty,
              let modeRaw = payload["mode"] as? String,
              let mode = LibraryRelocationMode(rawValue: modeRaw) else {
            AppLogger.error("Bridge: relocateLibrary rejected — invalid payload")
            emitter.emitLibraryRelocated(result: LibraryRelocationResult(
                mode: .switchOnly, newRoot: "", message: "Invalid relocation request."))
            return
        }
        Task { [weak self] in
            guard let self, let appState = self.appState else { return }
            let result = await appState.maintenance.relocate(to: path, mode: mode)
            self.emitter.emitLibraryRelocated(result: result)
            self.emitter.emitStateUpdate(appState)
        }
        _ = appState
    }

    private func handleVerifyLibrary() {
        guard let appState else { return }
        emitter.emitLibraryScanStarted()
        Task { [weak self] in
            guard let self, let appState = self.appState else { return }
            let result = await appState.maintenance.verify(requeueMissing: true)
            self.emitter.emitLibraryScanCompleted(result: result)
            self.emitter.emitStateUpdate(appState)
        }
        _ = appState
    }

    private func handleRevealLibraryFolder() {
        guard let appState,
              let path = appState.settings.downloadFolderPath, !path.isEmpty else { return }
        if SettingsService.isDirectory(atPath: path) {
            NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: path)])
        } else {
            AppLogger.error("revealLibraryFolder: folder not reachable: \(path)")
        }
    }

    private func handleRecheckLibraryFolder() {
        guard let appState else { return }
        let available = appState.refreshLibraryFolderAvailability()
        if available {
            Task { [weak self] in
                guard let self, let appState = self.appState else { return }
                await appState.downloadService.resumePendingDownloads()
                self.emitter.emitStateUpdate(appState)
                let result = await appState.maintenance.verify(requeueMissing: true)
                self.emitter.emitLibraryScanCompleted(result: result)
                self.emitter.emitStateUpdate(appState)
            }
        } else {
            emitter.emitStateUpdate(appState)
        }
    }

    private func handleRetryFailedDownloads(_ payload: [String: Any]) {
        guard let appState else { return }
        let channelId = (payload["channelId"] as? String).flatMap(UUID.init(uuidString:))
        Task { [weak self] in
            guard let self, let appState = self.appState else { return }
            let n = await appState.downloadService.retryFailedDownloads(channelId: channelId)
            AppLogger.info("retryFailedDownloads: re-queued \(n) video(s)")
            self.emitter.emitStateUpdate(appState)
        }
        _ = appState
    }

    // MARK: - Playback

    private func handleSetAutoPlaybackMode(_ payload: [String: Any]) {
        guard let appState,
              let pidStr = payload["profileId"] as? String,
              let pid = UUID(uuidString: pidStr),
              let modeStr = payload["mode"] as? String,
              let mode = PlaybackMode(rawValue: modeStr) else { return }
        appState.setAutoPlaybackMode(profileId: pid, mode: mode)
        emitter.emitAutoPlaybackModeChanged(profileId: pid, mode: mode.rawValue)
    }

    // MARK: - Playlists

    private func handleCreatePlaylist(_ payload: [String: Any]) {
        guard let appState,
              let pidStr = payload["profileId"] as? String,
              let pid = UUID(uuidString: pidStr),
              let name = payload["name"] as? String,
              !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              name.count <= 60 else { return }
        let playlist = appState.createPlaylist(profileId: pid, name: name)
        emitter.emitPlaylistUpserted(playlist)
    }

    private func handleRenamePlaylist(_ payload: [String: Any]) {
        guard let appState,
              let idStr = payload["playlistId"] as? String,
              let id = UUID(uuidString: idStr),
              let name = payload["name"] as? String,
              !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              name.count <= 60 else { return }
        appState.renamePlaylist(id: id, name: name)
        if let pl = appState.playlists.first(where: { $0.id == id }) {
            emitter.emitPlaylistUpserted(pl)
        }
    }

    private func handleDeletePlaylist(_ payload: [String: Any]) {
        guard let appState,
              let idStr = payload["playlistId"] as? String,
              let id = UUID(uuidString: idStr),
              let pl = appState.playlists.first(where: { $0.id == id }) else { return }
        let profileId = pl.profileId
        appState.deletePlaylist(id: id)
        emitter.emitPlaylistRemoved(id: id)
        // Active may have fallen back to Up Next.
        if let p = appState.profiles.first(where: { $0.id == profileId }) {
            emitter.emitActivePlaylistChanged(profileId: profileId, activePlaylistId: p.activePlaylistId)
        }
    }

    private func handleSetActivePlaylist2(_ payload: [String: Any]) {
        guard let appState,
              let pidStr = payload["profileId"] as? String,
              let pid = UUID(uuidString: pidStr) else { return }
        let playlistId = (payload["playlistId"] as? String).flatMap(UUID.init(uuidString:))
        appState.setActivePlaylist(profileId: pid, playlistId: playlistId)
        emitter.emitActivePlaylistChanged(profileId: pid, activePlaylistId: playlistId)
    }

    private func handleAddToPlaylist(_ payload: [String: Any]) {
        guard let appState,
              let plidStr = payload["playlistId"] as? String,
              let plid = UUID(uuidString: plidStr),
              let vidStr = payload["videoId"] as? String,
              let vid = UUID(uuidString: vidStr) else { return }
        appState.addToPlaylist(playlistId: plid, videoId: vid)
        emitter.emitPlaylistVideosUpdated(playlistId: plid, videoIds: appState.playlistVideos[plid] ?? [])
    }

    private func handleRemoveFromPlaylist(_ payload: [String: Any]) {
        guard let appState,
              let plidStr = payload["playlistId"] as? String,
              let plid = UUID(uuidString: plidStr),
              let vidStr = payload["videoId"] as? String,
              let vid = UUID(uuidString: vidStr) else { return }
        appState.removeFromPlaylist(playlistId: plid, videoId: vid)
        emitter.emitPlaylistVideosUpdated(playlistId: plid, videoIds: appState.playlistVideos[plid] ?? [])
    }

    private func handleReorderPlaylist(_ payload: [String: Any]) {
        guard let appState,
              let plidStr = payload["playlistId"] as? String,
              let plid = UUID(uuidString: plidStr),
              let rawIds = payload["videoIds"] as? [String] else { return }
        let ids = rawIds.compactMap(UUID.init(uuidString:))
        appState.reorderPlaylist(playlistId: plid, videoIds: ids)
        emitter.emitPlaylistVideosUpdated(playlistId: plid, videoIds: appState.playlistVideos[plid] ?? [])
    }

    private func handleClearPlaylist(_ payload: [String: Any]) {
        guard let appState,
              let plidStr = payload["playlistId"] as? String,
              let plid = UUID(uuidString: plidStr) else { return }
        appState.clearPlaylist(playlistId: plid)
        emitter.emitPlaylistVideosUpdated(playlistId: plid, videoIds: [])
    }

    private func handleToggleChannelHidden(_ payload: [String: Any]) {
        guard let appState,
              let pidStr = payload["profileId"] as? String,
              let pid = UUID(uuidString: pidStr),
              let cidStr = payload["channelId"] as? String,
              let cid = UUID(uuidString: cidStr),
              let hidden = payload["hidden"] as? Bool else { return }
        appState.setChannelHidden(profileId: pid, channelId: cid, hidden: hidden)
        emitter.emitChannelHiddenChanged(profileId: pid, channelId: cid, hidden: hidden)
    }

    private func handleToggleFavorite(_ payload: [String: Any]) {
        guard let appState,
              let pidStr = payload["profileId"] as? String,
              let pid = UUID(uuidString: pidStr),
              let vidStr = payload["videoId"] as? String,
              let vid = UUID(uuidString: vidStr),
              let isFavorite = payload["isFavorite"] as? Bool else { return }
        appState.setFavorite(profileId: pid, videoId: vid, isFavorite: isFavorite)
        emitter.emitFavoriteChanged(profileId: pid, videoId: vid, isFavorite: isFavorite)
    }

    // MARK: - PIN entry dismissal
    //
    // Closes the PIN modal without mutating appMode. The bridge only emits
    // appModeChanged on exit; that event doesn't carry showPINEntry, so a
    // raw exitEditorMode call leaves React with the modal still open.
    // This dedicated handler emits a full state update so React sees the
    // showPINEntry: false transition.

    private func handleDismissPINEntry() {
        guard let appState else { return }
        appState.showPINEntry = false
        emitter.emitStateUpdate(appState)
    }

    // MARK: - State

    private func handleGetState() {
        guard let appState else { return }
        emitter.emitStateUpdate(appState)
    }

    // MARK: - Player

    private func handlePlayVideo(_ payload: [String: Any]) {
        guard let videoIdStr = payload["videoId"] as? String,
              let videoId    = UUID(uuidString: videoIdStr),
              let appState,
              let video      = appState.videoById(videoId) else { return }

        // A "ready" video whose file vanished (drive swapped, deleted in
        // Finder) would otherwise open a black player. Put it back in the
        // download queue and tell the UI.
        if video.isPlayable, !FileManager.default.fileExists(atPath: video.localFilePath) {
            AppLogger.error("playVideo: file missing for \(video.title) at \(video.localFilePath)")
            Task { [weak self] in
                guard let self, let appState = self.appState else { return }
                if let updated = await appState.markVideoMissing(video) {
                    self.emitter.emitVideosUpserted(channelId: updated.channelId, videos: [updated])
                }
                self.emitter.emitToast(
                    "\"\(video.title)\" is missing from the library folder and has been re-queued for download.",
                    kind: "warning"
                )
            }
            return
        }

        // Resolve the playback source. `source` is "queue" or "channel" and
        // `contextId` is the playlist/channel UUID. Falls back to the
        // video's own channel so older call sites keep working.
        let source: PlaybackSource = {
            let sourceStr = payload["source"] as? String
            let contextId = (payload["contextId"] as? String).flatMap(UUID.init(uuidString:))
            switch sourceStr {
            case "queue":   if let id = contextId { return .queue(id) }
            case "channel": if let id = contextId { return .channel(id) }
            default: break
            }
            return .channel(video.channelId)
        }()

        playerOverlayController?.show(video: video, appState: appState, source: source)
    }

    private func handleStopPlayer() {
        playerOverlayController?.hide()
    }

    // MARK: - Folder Picker (onboarding)

    /// First-run folder choice. Sets the download folder directly and ends
    /// onboarding. (Settings uses `chooseLibraryFolder` instead, which
    /// goes through the relocation flow so existing videos aren't
    /// orphaned.) Previously `isOnboarding` never flipped to false here,
    /// so a fresh install stayed on the welcome screen until relaunch.
    private func handleOpenFolderPicker() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.canCreateDirectories = true
        panel.allowsMultipleSelection = false
        panel.prompt = "Choose Download Folder"
        panel.message = "Select the folder where LocalTube will save downloaded videos."
        panel.begin { [weak self] response in
            guard response == .OK, let url = panel.url else { return }
            Task { @MainActor [weak self] in
                guard let self, let appState = self.appState else { return }
                let path = LibraryPaths.normalize(url.path)
                let hadLibrary = !appState.library.allVideos.isEmpty
                if hadLibrary, let current = appState.settings.downloadFolderPath,
                   LibraryPaths.normalize(current) != path {
                    // Not onboarding — an existing library is being moved.
                    // Route through the relocation flow instead of silently
                    // re-pointing new downloads and orphaning the old files.
                    let analysis = await appState.maintenance.analyzeFolder(path)
                    self.emitter.emitLibraryFolderPicked(analysis: analysis)
                    return
                }
                appState.settings.downloadFolderPath = path
                appState.settings.rememberLibraryRoot(path)
                SettingsService.save(appState.settings)
                appState.isOnboarding = false
                appState.refreshLibraryFolderAvailability()
                self.emitter.emitFolderSelected(path: path)
                self.emitter.emitStateUpdate(appState)
                await appState.downloadService.resumePendingDownloads()
            }
        }
    }

    // MARK: - PIN

    // M11 fix: Validate PIN length and character set at the handler boundary.
    private func handleValidatePIN(_ payload: [String: Any]) {
        guard let pin = payload["pin"] as? String,
              pin.count >= 4, pin.count <= 8,
              pin.allSatisfy({ $0.isNumber }) else {
            AppLogger.error("Bridge: validatePIN rejected — invalid PIN format")
            emitter.emitPINValidated(valid: false, lockoutSeconds: Int(PINService.lockoutRemaining.rounded(.up)))
            return
        }
        if PINService.isLockedOut {
            emitter.emitPINValidated(valid: false, lockoutSeconds: Int(PINService.lockoutRemaining.rounded(.up)))
            return
        }
        let valid = PINService.verify(pin)
        if valid, let appState {
            // Dispatch on the pending intent so the same PIN modal can
            // unlock either Admin shell or the inline edit layer.
            switch appState.pendingPinAction {
            case .admin: appState.enterEditorMode()
            case .edit:  appState.enterEditMode()
            }
        }
        emitter.emitPINValidated(valid: valid, lockoutSeconds: Int(PINService.lockoutRemaining.rounded(.up)))
        if let appState { emitter.emitStateUpdate(appState) }
    }

    // M11 fix: Validate PIN format before saving.
    private func handleSetPIN(_ payload: [String: Any]) {
        guard let pin = payload["pin"] as? String,
              pin.count >= 4, pin.count <= 8,
              pin.allSatisfy({ $0.isNumber }) else {
            AppLogger.error("Bridge: setPIN rejected — invalid PIN format")
            return
        }
        let recovery = PINService.generateRecoveryPhrase()
        do {
            try PINService.savePin(pin, recoveryPhrase: recovery)
        } catch {
            AppLogger.error("Bridge: setPIN savePin failed: \(error.localizedDescription)")
            return
        }
        if let appState {
            appState.needsPINSetup = false
            emitter.emitStateUpdate(appState)
        }
    }

    private func handleRequestEditorMode() {
        guard let appState else { return }
        // Session continuation: if the parent is already in the edit
        // layer (PIN'd in), promote straight to Admin without re-PIN.
        if appState.isEditing {
            appState.enterEditorMode()
            emitter.emitIsEditingChanged(false)
            emitter.emitAppModeChanged(mode: .editor)
            return
        }
        appState.pendingPinAction = .admin
        appState.requestEditorMode()
        emitter.emitStateUpdate(appState)
    }

    // Inline edit layer entry. Same PIN-session continuation: if the
    // parent is already in Admin, drop them into edit layer (which
    // implies viewer mode) without re-PIN.
    private func handleRequestEditMode() {
        guard let appState else { return }
        if appState.appMode == .editor {
            appState.enterEditMode()
            emitter.emitAppModeChanged(mode: .viewer)
            emitter.emitIsEditingChanged(true)
            return
        }
        appState.pendingPinAction = .edit
        appState.showPINEntry = true
        emitter.emitStateUpdate(appState)
    }

    private func handleEndEditMode() {
        guard let appState else { return }
        appState.endEditMode()
        emitter.emitIsEditingChanged(false)
    }

    private func handleExitEditorMode() {
        guard let appState else { return }
        appState.exitEditorMode()
        emitter.emitAppModeChanged(mode: appState.appMode)
    }

    // MARK: - Channel CRUD

    // M11 fix: Validate displayName length.
    private func handleAddChannel(_ payload: [String: Any]) {
        guard let appState,
              let displayName = payload["displayName"] as? String,
              !displayName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              displayName.count <= 100,
              let typeStr     = payload["type"] as? String,
              let channelType = ChannelType(rawValue: typeStr) else {
            AppLogger.error("Bridge: addChannel rejected — invalid payload")
            return
        }

        let emoji     = payload["emoji"]            as? String
        let ytId      = (payload["youtubeChannelId"] as? String)?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        // Folder name: slug of the display name, made unique across the
        // library so two channels never share (and never delete) each
        // other's files.
        let folderName = appState.library.uniqueFolderName(base: displayName.trimmingCharacters(in: .whitespacesAndNewlines).slugified())

        let channel = Channel(
            displayName: displayName.trimmingCharacters(in: .whitespacesAndNewlines),
            emoji: emoji,
            type: channelType,
            youtubeChannelId: (ytId?.isEmpty == false) ? ytId : nil,
            folderName: folderName,
            sortOrder: (appState.channels.map { $0.sortOrder }.max() ?? -1) + 1
        )
        appState.addChannel(channel)
        emitter.emitChannelUpserted(channel)

        // A "source" channel exists to mirror a YouTube channel, so grab its
        // videos immediately instead of leaving an empty channel that needs a
        // separate, easily-missed manual Sync. syncChannel awaits the network
        // video-list fetch before inserting any rows, so the channel's own DB
        // insert (kicked off just above) always lands first — no FK race.
        // It also posts .channelSyncStateChanged, which drives the live
        // "Syncing…" indicator; we emit a full state update when it finishes.
        if channelType == .source, let ytId, !ytId.isEmpty {
            Task { [weak self] in
                guard let self, let appState = self.appState else { return }
                await appState.syncChannel(channel)
                self.emitter.emitStateUpdate(appState)
            }
        }
    }

    private func handleDeleteChannel(_ payload: [String: Any]) {
        guard let appState,
              let channelIdStr = payload["channelId"] as? String,
              let channelId    = UUID(uuidString: channelIdStr) else { return }
        appState.removeChannel(id: channelId)
        emitter.emitChannelRemoved(id: channelId)
        // Playlists / favorites may have lost members.
        emitter.emitStateUpdate(appState)
    }

    // M11 fix: Validate displayName length on update.
    private func handleUpdateChannel(_ payload: [String: Any]) {
        guard let appState,
              let idStr       = payload["id"] as? String,
              let channelId   = UUID(uuidString: idStr),
              var channel     = appState.channelById(channelId) else { return }

        if let name = payload["displayName"] as? String,
           !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
           name.count <= 100 { channel.displayName = name.trimmingCharacters(in: .whitespacesAndNewlines) }
        if let emoji = payload["emoji"] as? String { channel.emoji = emoji.isEmpty ? nil : emoji }
        if let ytId  = payload["youtubeChannelId"] as? String {
            let trimmed = ytId.trimmingCharacters(in: .whitespacesAndNewlines)
            channel.youtubeChannelId = trimmed.isEmpty ? nil : trimmed
        }

        appState.updateChannel(channel)
        emitter.emitChannelUpserted(channel)
    }

    // MARK: - Video Management

    private func handleAddVideoURLs(_ payload: [String: Any]) {
        guard let appState,
              let channelIdStr = payload["channelId"] as? String,
              let channelId    = UUID(uuidString: channelIdStr),
              let channel      = appState.channelById(channelId),
              let urls         = payload["urls"] as? [String] else { return }

        // M11 fix: Cap the number of URLs per request to prevent abuse.
        let cappedURLs = Array(urls.prefix(50))
        var addedVideos: [Video] = []
        var seen = Set<String>()
        var nextSortOrder = (appState.videosForChannel(channelId).map { $0.sortOrder }.max() ?? -1) + 1
        for url in cappedURLs {
            guard let videoId = url.trimmingCharacters(in: .whitespacesAndNewlines).youtubeVideoId,
                  !videoId.isEmpty, seen.insert(videoId).inserted else { continue }
            let alreadyAdded = appState.videosForChannel(channelId).contains { $0.youtubeVideoId == videoId }
            if alreadyAdded { continue }
            let video = Video(
                channelId: channelId,
                youtubeVideoId: videoId,
                title: "Video \(videoId)",
                downloadState: .queued,
                sortOrder: nextSortOrder
            )
            nextSortOrder += 1
            appState.addVideo(video)
            addedVideos.append(video)
        }
        if !addedVideos.isEmpty {
            emitter.emitVideosUpserted(channelId: channelId, videos: addedVideos)
            let toEnqueue = addedVideos
            Task {
                for video in toEnqueue {
                    await appState.downloadService.enqueue(video: video, channel: channel)
                }
            }
        }
    }

    private func handleDeleteVideo(_ payload: [String: Any]) {
        guard let appState,
              let videoIdStr = payload["videoId"] as? String,
              let videoId    = UUID(uuidString: videoIdStr) else { return }
        appState.removeVideo(id: videoId)
        emitter.emitVideoRemoved(id: videoId)
    }

    /// Retry goes through `retryDownload`, which clears the stale failed
    /// queue entry first. Calling `enqueue` directly (as this used to)
    /// was a no-op after a failure because the dead entry still matched
    /// the de-duplication check — the Retry button did nothing.
    private func handleRetryDownload(_ payload: [String: Any]) {
        guard let appState,
              let videoIdStr = payload["videoId"] as? String,
              let videoId    = UUID(uuidString: videoIdStr),
              let video      = appState.videoById(videoId),
              let channel    = appState.channelById(video.channelId) else { return }
        Task { [weak self] in
            guard let self, let appState = self.appState else { return }
            await appState.downloadService.retryDownload(video: video, channel: channel)
            if let updated = appState.videoById(videoId) {
                self.emitter.emitVideosUpserted(channelId: updated.channelId, videos: [updated])
            }
        }
    }

    // MARK: - Settings

    /// Applies the editable settings. The download folder is deliberately
    /// NOT accepted here — changing it must go through the relocation
    /// flow (`chooseLibraryFolder` → `relocateLibrary`) so existing files
    /// are moved or adopted rather than orphaned.
    private func handleSaveSettings(_ payload: [String: Any]) {
        guard let appState else { return }
        if let mins = payload["editorAutoLockMinutes"] as? Int, (1...120).contains(mins) {
            appState.settings.editorAutoLockMinutes = mins
        }
        if let check = payload["checkDepsOnLaunch"] as? Bool {
            appState.settings.checkDepsOnLaunch = check
        }
        if let qualityRaw = payload["downloadQuality"] as? String,
           let quality = DownloadQuality(rawValue: qualityRaw) {
            appState.settings.downloadQuality = quality
        }
        if let fp = payload["downloadFolderPath"] as? String,
           let current = appState.settings.downloadFolderPath,
           LibraryPaths.normalize(fp) != LibraryPaths.normalize(current) {
            AppLogger.error("Bridge: saveSettings ignored downloadFolderPath change — use the relocation flow")
        }
        SettingsService.save(appState.settings)
        emitter.emitSettingsUpdated(appState.settings)
    }

    // MARK: - Channel Sync

    private func handleSyncChannel(_ payload: [String: Any]) {
        guard let appState,
              let channelIdStr = payload["channelId"] as? String,
              let channelId    = UUID(uuidString: channelIdStr),
              let channel      = appState.channelById(channelId) else { return }
        Task { [weak self] in
            guard let self, let appState = self.appState else { return }
            await appState.syncChannel(channel)
            self.emitter.emitStateUpdate(appState)
        }
    }

    // MARK: - Banner Upload

    private func handleUploadChannelBanner(_ payload: [String: Any]) {
        guard let appState,
              let channelIdStr = payload["channelId"] as? String,
              let channelId    = UUID(uuidString: channelIdStr),
              let channel      = appState.channelById(channelId),
              let rootFolder   = appState.settings.downloadFolderPath,
              !rootFolder.isEmpty else { return }

        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        panel.allowedContentTypes = [.jpeg, .png, .gif, .bmp, .tiff]
        panel.prompt = "Choose Banner Image"
        panel.message = "Select an image to use as the channel banner."

        panel.begin { [weak self] response in
            guard response == .OK, let sourceURL = panel.url else { return }
            Task { @MainActor [weak self] in
                guard let self, let appState = self.appState else { return }

                let destDir  = channel.folderPath(rootFolder: rootFolder)
                let destPath = (destDir as NSString).appendingPathComponent("banner.jpg")

                do {
                    try FileManager.default.createDirectory(
                        atPath: destDir, withIntermediateDirectories: true
                    )
                    if FileManager.default.fileExists(atPath: destPath) {
                        try FileManager.default.removeItem(atPath: destPath)
                    }
                    try FileManager.default.copyItem(
                        at: sourceURL,
                        to: URL(fileURLWithPath: destPath)
                    )

                    // Update in-memory state
                    if let idx = appState.channels.firstIndex(where: { $0.id == channelId }) {
                        appState.channels[idx].bannerPath = destPath
                    }

                    // Persist to DB
                    try await DatabaseService.shared.updateChannelBanner(
                        id: channelId, bannerPath: destPath
                    )

                    self.emitter.emitStateUpdate(appState)
                    AppLogger.info("Banner uploaded for channel \(channel.displayName)")
                } catch {
                    AppLogger.error("Banner upload failed: \(error.localizedDescription)")
                    self.emitter.emitToast("Banner upload failed: \(error.localizedDescription)", kind: "error")
                }
            }
        }
    }

    // MARK: - Dependencies

    private func handleCheckDependencies() {
        guard let appState else { return }
        Task { [weak self] in
            guard let self, let appState = self.appState else { return }
            await appState.dependencyService.checkAll()
            appState.dependencyStatus = appState.dependencyService.status
            await appState.downloadService.resolveToolPaths()
            self.emitter.emitStateUpdate(appState)
        }
    }

    // MARK: - Profiles

    private func handleSetActiveProfile(_ payload: [String: Any]) {
        guard let appState else { return }
        // payload.profileId is either a UUID string or null (clear).
        if let raw = payload["profileId"] as? String, let id = UUID(uuidString: raw),
           appState.profiles.contains(where: { $0.id == id }) {
            appState.activeProfileId = id
        } else {
            appState.activeProfileId = nil
        }
        emitter.emitActiveProfileChanged(activeProfileId: appState.activeProfileId)
    }

    private func handleAddProfile(_ payload: [String: Any]) {
        guard let appState,
              let name = payload["name"] as? String,
              !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              name.count <= 60 else {
            AppLogger.error("Bridge: addProfile rejected — invalid name")
            return
        }
        let emoji = payload["emoji"] as? String
        let icon  = payload["icon"]  as? String
        let color = payload["color"] as? String
        let channelIds: [UUID] = (payload["channelIds"] as? [String])?
            .compactMap(UUID.init(uuidString:)) ?? []
        let profile = Profile(
            name: name.trimmingCharacters(in: .whitespacesAndNewlines),
            emoji: emoji,
            icon: icon,
            color: color,
            sortOrder: (appState.profiles.map { $0.sortOrder }.max() ?? -1) + 1
        )
        appState.addProfile(profile)
        if !channelIds.isEmpty {
            appState.setProfileChannels(profileId: profile.id, channelIds: channelIds)
        }
        emitter.emitProfileUpserted(profile)
        if !channelIds.isEmpty {
            emitter.emitProfileChannelsUpdated(
                profileId: profile.id,
                channelIds: Array(appState.profileChannels[profile.id] ?? [])
            )
        }
        // Profile creation also seeds an "Up Next" playlist.
        if let upNext = appState.playlists.first(where: { $0.profileId == profile.id && $0.isSystem }) {
            emitter.emitPlaylistUpserted(upNext)
            emitter.emitActivePlaylistChanged(profileId: profile.id, activePlaylistId: upNext.id)
        }
    }

    private func handleUpdateProfile(_ payload: [String: Any]) {
        guard let appState,
              let raw = payload["id"] as? String,
              let id = UUID(uuidString: raw),
              var profile = appState.profiles.first(where: { $0.id == id }) else { return }

        if let name = payload["name"] as? String,
           !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
           name.count <= 60 {
            profile.name = name.trimmingCharacters(in: .whitespacesAndNewlines)
        }
        if let emoji = payload["emoji"] as? String {
            profile.emoji = emoji.isEmpty ? nil : emoji
        }
        // Use NSNull / explicit empty string as "clear" semantics from JS:
        // present-and-empty → nil, present-and-nonempty → set, absent → unchanged.
        if let icon = payload["icon"] as? String {
            profile.icon = icon.isEmpty ? nil : icon
        }
        if let color = payload["color"] as? String {
            profile.color = color.isEmpty ? nil : color
        }
        appState.updateProfile(profile)
        emitter.emitProfileUpserted(profile)
    }

    private func handleDeleteProfile(_ payload: [String: Any]) {
        guard let appState,
              let raw = payload["profileId"] as? String,
              let id = UUID(uuidString: raw) else { return }
        let wasActive = appState.activeProfileId == id
        appState.removeProfile(id: id)
        emitter.emitProfileRemoved(id: id)
        if wasActive {
            emitter.emitActiveProfileChanged(activeProfileId: nil)
        }
        // Owned playlists went with it.
        emitter.emitStateUpdate(appState)
    }

    private func handleSetProfileChannels(_ payload: [String: Any]) {
        guard let appState,
              let raw = payload["profileId"] as? String,
              let id = UUID(uuidString: raw),
              let rawIds = payload["channelIds"] as? [String] else { return }
        let channelIds = rawIds.compactMap(UUID.init(uuidString:))
        appState.setProfileChannels(profileId: id, channelIds: channelIds)
        // Echo back the cleaned list (unknown/duplicate ids dropped) in the
        // order the UI sent so drag-reorder stays exact.
        let accepted = appState.profileChannels[id] ?? []
        var seen = Set<UUID>()
        let ordered = channelIds.filter { accepted.contains($0) && seen.insert($0).inserted }
        emitter.emitProfileChannelsUpdated(profileId: id, channelIds: ordered)
    }
}
