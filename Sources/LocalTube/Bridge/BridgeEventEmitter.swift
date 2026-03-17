import WebKit
import Foundation

// MARK: - Bridge Event Emitter (Swift → JS)
//
// Calls window.LocalTubeBridge.dispatch(event, payload) in the WKWebView.
// All calls must happen on the main thread (WKWebView requirement).

@MainActor
final class BridgeEventEmitter {
    weak var webView: WKWebView?

    // MARK: - Emit helpers

    func emit(_ event: String, payload: [String: Any] = [:]) {
        guard let webView else { return }

        // Serialise the full BridgeEvent as a single {type, payload} JSON object.
        // React's bridge.ts initBridge expects: dispatch(event: BridgeEvent)
        let envelope: [String: Any] = ["type": event, "payload": payload]
        guard let jsonData = try? JSONSerialization.data(withJSONObject: envelope),
              let jsonString = String(data: jsonData, encoding: .utf8) else { return }

        let js = "window.LocalTubeBridge && window.LocalTubeBridge.dispatch(\(jsonString));"

        // Must use .page world — bootstrap script and React both run in the page's
        // default content world, not the isolated .defaultClient world.
        webView.evaluateJavaScript(js, in: nil, in: .page) { result in
            if case .failure(let err) = result {
                AppLogger.error("BridgeEventEmitter [\(event)] JS error: \(err)")
            }
        }
    }

    // MARK: - Convenience typed emitters

    /// Push the full app state snapshot to JS
    func emitStateUpdate(_ appState: AppState) {
        emit("stateUpdate", payload: appState.bridgePayload())
    }

    func emitDownloadProgress(videoId: String, progress: Double) {
        emit("downloadProgress", payload: ["videoId": videoId, "progress": progress])
    }

    func emitDownloadCompleted(videoId: String) {
        emit("downloadCompleted", payload: ["videoId": videoId])
    }

    func emitDownloadError(videoId: String, error: String) {
        emit("downloadError", payload: ["videoId": videoId, "error": error])
    }

    func emitFolderSelected(path: String) {
        emit("folderSelected", payload: ["path": path])
    }

    func emitPINValidated(valid: Bool) {
        emit("pinValidated", payload: ["valid": valid])
    }

    func emitEditorTimerTick(remainingSeconds: Int) {
        emit("editorTimerTick", payload: ["remainingSeconds": remainingSeconds])
    }
}

// MARK: - AppState → Bridge Payload

extension AppState {
    func bridgePayload() -> [String: Any] {
        var payload: [String: Any] = [
            "channels":  channels.map { $0.bridgePayload() },
            "appMode":   appMode == .editor ? "editor" : "viewer",
            "isOnboarding": isOnboarding,
            "needsPINSetup": needsPINSetup,
            "showPINEntry":  showPINEntry,
            "editorRemainingSeconds": editorRemainingSeconds,
            "settings": settings.bridgePayload(),
            "dependencyStatus": [
                "ytDlp":  dependencyStatus.ytDlp,
                "ffmpeg": dependencyStatus.ffmpeg,
            ],
        ]

        // Videos keyed by channelId
        var videosMap: [String: Any] = [:]
        for (channelId, vids) in videos {
            videosMap[channelId.uuidString] = vids.map { $0.bridgePayload() }
        }
        payload["videos"] = videosMap

        // Active download
        if let active = activeDownload {
            payload["activeDownload"] = [
                "videoId":  active.videoId.uuidString,
                "progress": active.progress,
                "title":    active.videoTitle,
            ]
        }

        return payload
    }
}

extension Channel {
    func bridgePayload() -> [String: Any] {
        var p: [String: Any] = [
            "id":          id.uuidString,
            "displayName": displayName,
            "type":        type.rawValue,
            "folderName":  folderName,
            "sortOrder":   sortOrder,
            "createdAt":   ISO8601DateFormatter().string(from: createdAt),
        ]
        if let emoji = emoji              { p["emoji"]            = emoji }
        if let ytId  = youtubeChannelId   { p["youtubeChannelId"] = ytId  }
        return p
    }
}

extension Video {
    func bridgePayload() -> [String: Any] {
        var p: [String: Any] = [
            "id":                    id.uuidString,
            "channelId":             channelId.uuidString,
            "youtubeVideoId":        youtubeVideoId,
            "title":                 title,
            "localFilePath":         localFilePath,
            "downloadedAt":          ISO8601DateFormatter().string(from: downloadedAt),
            "durationSeconds":       durationSeconds,
            "resumePositionSeconds": resumePositionSeconds,
            "downloadState":         downloadState.rawValue,
            "downloadProgress":      downloadProgress,
            "sortOrder":             sortOrder,
            // Convert filesystem thumbnail path to our custom scheme URL for WKWebView
            "thumbnailPath":         thumbnailPath.isEmpty ? "" : "localtube-thumb://\(thumbnailPath)",
        ]
        if let err = downloadError { p["downloadError"] = err }
        return p
    }
}

extension AppSettings {
    func bridgePayload() -> [String: Any] {
        var p: [String: Any] = [
            "editorAutoLockMinutes": editorAutoLockMinutes,
            "checkDepsOnLaunch":     checkDepsOnLaunch,
        ]
        if let fp = downloadFolderPath { p["downloadFolderPath"] = fp }
        return p
    }
}
