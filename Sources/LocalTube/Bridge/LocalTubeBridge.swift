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

        AppLogger.info("Bridge ← JS: \(typeStr)")

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
        }
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
        emitter.emitPlaylistVideosUpdated(playlistId: plid, videoIds: ids)
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

    // MARK: - Folder Picker

    private func handleOpenFolderPicker() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.prompt = "Choose Download Folder"
        panel.message = "Select the folder where LocalTube will save downloaded videos."
        panel.begin { [weak self] response in
            guard response == .OK, let url = panel.url else { return }
            Task { @MainActor [weak self] in
                guard let self, let appState = self.appState else { return }
                appState.settings.downloadFolderPath = url.path
                SettingsService.save(appState.settings)
                self.emitter.emitFolderSelected(path: url.path)
                self.emitter.emitStateUpdate(appState)
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
            emitter.emitPINValidated(valid: false)
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
        emitter.emitPINValidated(valid: valid)
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
        let ytId      = payload["youtubeChannelId"] as? String
        let folderName = displayName
            .lowercased()
            .replacingOccurrences(of: " ", with: "-")
            .filter { $0.isLetter || $0.isNumber || $0 == "-" }

        let channel = Channel(
            displayName: displayName,
            emoji: emoji,
            type: channelType,
            youtubeChannelId: ytId,
            folderName: folderName,
            sortOrder: appState.channels.count
        )
        appState.addChannel(channel)
        emitter.emitChannelUpserted(channel)
    }

    private func handleDeleteChannel(_ payload: [String: Any]) {
        guard let appState,
              let channelIdStr = payload["channelId"] as? String,
              let channelId    = UUID(uuidString: channelIdStr) else { return }
        appState.removeChannel(id: channelId)
        emitter.emitChannelRemoved(id: channelId)
    }

    // M11 fix: Validate displayName length on update.
    private func handleUpdateChannel(_ payload: [String: Any]) {
        guard let appState,
              let idStr       = payload["id"] as? String,
              let channelId   = UUID(uuidString: idStr),
              var channel     = appState.channelById(channelId) else { return }

        if let name = payload["displayName"] as? String,
           !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
           name.count <= 100 { channel.displayName = name }
        if let emoji = payload["emoji"] as? String { channel.emoji = emoji }
        if let ytId  = payload["youtubeChannelId"] as? String { channel.youtubeChannelId = ytId }

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
        for url in cappedURLs {
            guard let videoId = url.youtubeVideoId else { continue }
            let alreadyAdded = appState.videosForChannel(channelId).contains { $0.youtubeVideoId == videoId }
            if alreadyAdded { continue }
            let video = Video(
                channelId: channelId,
                youtubeVideoId: videoId,
                title: "Video \(videoId)",
                downloadState: .queued,
                sortOrder: appState.videosForChannel(channelId).count
            )
            appState.addVideo(video)
            addedVideos.append(video)
            Task { await appState.downloadService.enqueue(video: video, channel: channel) }
        }
        if !addedVideos.isEmpty {
            emitter.emitVideosUpserted(channelId: channelId, videos: addedVideos)
        }
    }

    private func handleDeleteVideo(_ payload: [String: Any]) {
        guard let appState,
              let videoIdStr = payload["videoId"] as? String,
              let videoId    = UUID(uuidString: videoIdStr) else { return }
        appState.removeVideo(id: videoId)
        emitter.emitVideoRemoved(id: videoId)
    }

    private func handleRetryDownload(_ payload: [String: Any]) {
        guard let appState,
              let videoIdStr = payload["videoId"] as? String,
              let videoId    = UUID(uuidString: videoIdStr),
              let video      = appState.videoById(videoId),
              let channel    = appState.channelById(video.channelId) else { return }
        Task { await appState.downloadService.enqueue(video: video, channel: channel) }
    }

    // MARK: - Settings

    private func handleSaveSettings(_ payload: [String: Any]) {
        guard let appState else { return }
        if let mins = payload["editorAutoLockMinutes"] as? Int {
            appState.settings.editorAutoLockMinutes = mins
        }
        if let fp = payload["downloadFolderPath"] as? String {
            appState.settings.downloadFolderPath = fp
        }
        if let check = payload["checkDepsOnLaunch"] as? Bool {
            appState.settings.checkDepsOnLaunch = check
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
        Task {
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

                let destDir  = (rootFolder as NSString).appendingPathComponent(channel.sanitizedFolderName)
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
                }
            }
        }
    }

    // MARK: - Dependencies

    private func handleCheckDependencies() {
        guard let appState else { return }
        Task {
            await appState.dependencyService.checkAll()
            appState.dependencyStatus = appState.dependencyService.status
            self.emitter.emitStateUpdate(appState)
        }
    }

    // MARK: - Profiles

    private func handleSetActiveProfile(_ payload: [String: Any]) {
        guard let appState else { return }
        // payload.profileId is either a UUID string or null (clear).
        if let raw = payload["profileId"] as? String, let id = UUID(uuidString: raw) {
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
            name: name,
            emoji: emoji,
            icon: icon,
            color: color,
            sortOrder: appState.profiles.count
        )
        appState.addProfile(profile)
        if !channelIds.isEmpty {
            appState.setProfileChannels(profileId: profile.id, channelIds: channelIds)
        }
        emitter.emitProfileUpserted(profile)
        if !channelIds.isEmpty {
            emitter.emitProfileChannelsUpdated(profileId: profile.id, channelIds: channelIds)
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
            profile.name = name
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
    }

    private func handleSetProfileChannels(_ payload: [String: Any]) {
        guard let appState,
              let raw = payload["profileId"] as? String,
              let id = UUID(uuidString: raw),
              let rawIds = payload["channelIds"] as? [String] else { return }
        let channelIds = rawIds.compactMap(UUID.init(uuidString:))
        appState.setProfileChannels(profileId: id, channelIds: channelIds)
        emitter.emitProfileChannelsUpdated(profileId: id, channelIds: channelIds)
    }
}
