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

    func userContentController(
        _ userContentController: WKUserContentController,
        didReceive message: WKScriptMessage
    ) {
        guard let body = message.body as? [String: Any],
              let typeStr = body["type"] as? String else {
            AppLogger.error("Bridge: malformed message body: \(message.body)")
            return
        }

        let payloadDict = body["payload"] as? [String: Any] ?? [:]

        AppLogger.info("Bridge ← JS: \(typeStr)")

        switch typeStr {
        case "getState":        handleGetState()
        case "playVideo":       handlePlayVideo(payloadDict)
        case "stopPlayer":      handleStopPlayer()
        case "openFolderPicker": handleOpenFolderPicker()
        case "validatePIN":     handleValidatePIN(payloadDict)
        case "setPIN":          handleSetPIN(payloadDict)
        case "requestEditorMode": handleRequestEditorMode()
        case "exitEditorMode":  handleExitEditorMode()
        case "addChannel":      handleAddChannel(payloadDict)
        case "deleteChannel":   handleDeleteChannel(payloadDict)
        case "updateChannel":   handleUpdateChannel(payloadDict)
        case "addVideoURLs":    handleAddVideoURLs(payloadDict)
        case "deleteVideo":     handleDeleteVideo(payloadDict)
        case "retryDownload":   handleRetryDownload(payloadDict)
        case "saveSettings":    handleSaveSettings(payloadDict)
        case "checkDependencies": handleCheckDependencies()
        default:
            AppLogger.error("Bridge: unknown message type: \(typeStr)")
        }
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
        playerOverlayController?.show(video: video, appState: appState)
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

    private func handleValidatePIN(_ payload: [String: Any]) {
        guard let pin = payload["pin"] as? String else { return }
        let valid = PINService.verify(pin)
        if valid { appState?.enterEditorMode() }
        emitter.emitPINValidated(valid: valid)
        if let appState { emitter.emitStateUpdate(appState) }
    }

    private func handleSetPIN(_ payload: [String: Any]) {
        guard let pin = payload["pin"] as? String else { return }
        let recovery = PINService.generateRecoveryPhrase()
        try? PINService.savePin(pin, recoveryPhrase: recovery)
        if let appState {
            appState.needsPINSetup = false
            emitter.emitStateUpdate(appState)
        }
    }

    private func handleRequestEditorMode() {
        guard let appState else { return }
        appState.requestEditorMode()
        emitter.emitStateUpdate(appState)
    }

    private func handleExitEditorMode() {
        guard let appState else { return }
        appState.exitEditorMode()
        emitter.emitStateUpdate(appState)
    }

    // MARK: - Channel CRUD

    private func handleAddChannel(_ payload: [String: Any]) {
        guard let appState,
              let displayName = payload["displayName"] as? String,
              let typeStr     = payload["type"] as? String,
              let channelType = ChannelType(rawValue: typeStr) else { return }

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
        emitter.emitStateUpdate(appState)
    }

    private func handleDeleteChannel(_ payload: [String: Any]) {
        guard let appState,
              let channelIdStr = payload["channelId"] as? String,
              let channelId    = UUID(uuidString: channelIdStr) else { return }
        appState.removeChannel(id: channelId)
        emitter.emitStateUpdate(appState)
    }

    private func handleUpdateChannel(_ payload: [String: Any]) {
        guard let appState,
              let idStr       = payload["id"] as? String,
              let channelId   = UUID(uuidString: idStr),
              var channel     = appState.channelById(channelId) else { return }

        if let name = payload["displayName"] as? String { channel.displayName = name }
        if let emoji = payload["emoji"] as? String { channel.emoji = emoji }
        if let ytId  = payload["youtubeChannelId"] as? String { channel.youtubeChannelId = ytId }

        appState.updateChannel(channel)
        emitter.emitStateUpdate(appState)
    }

    // MARK: - Video Management

    private func handleAddVideoURLs(_ payload: [String: Any]) {
        guard let appState,
              let channelIdStr = payload["channelId"] as? String,
              let channelId    = UUID(uuidString: channelIdStr),
              let channel      = appState.channelById(channelId),
              let urls         = payload["urls"] as? [String] else { return }

        for url in urls {
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
            Task { await appState.downloadService.enqueue(video: video, channel: channel) }
        }
        emitter.emitStateUpdate(appState)
    }

    private func handleDeleteVideo(_ payload: [String: Any]) {
        guard let appState,
              let videoIdStr = payload["videoId"] as? String,
              let videoId    = UUID(uuidString: videoIdStr) else { return }
        appState.removeVideo(id: videoId)
        emitter.emitStateUpdate(appState)
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
        emitter.emitStateUpdate(appState)
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
}
