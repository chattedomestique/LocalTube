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

        // Serialise the envelope to JSON, then convert to pure-ASCII by
        // replacing every non-ASCII UTF-8 sequence with its \uXXXX escape.
        // This is the key fix for emoji / curly-quote corruption:
        //   JSONSerialization emits raw UTF-8 bytes for non-ASCII characters.
        //   atob() in JS decodes base64 to a "binary string" where each byte
        //   becomes an individual JS char (code 0-255).  Feeding that binary
        //   string directly to JSON.parse() splits multi-byte sequences into
        //   garbage characters ("🥁" → four Latin-1 chars; """ → "â€œ").
        //   Converting to ASCII-first (all non-ASCII → \uXXXX / surrogates)
        //   makes the base64 payload pure ASCII, so atob() + JSON.parse()
        //   always round-trip correctly — no TextDecoder workaround needed.
        let envelope: [String: Any] = ["type": event, "payload": payload]
        guard let jsonData = try? JSONSerialization.data(withJSONObject: envelope) else { return }
        let asciiJSON = jsonData.asciiSafeJSONString
        let base64 = Data(asciiJSON.utf8).base64EncodedString()

        let js = """
        if (window.LocalTubeBridge) {
            try { window.LocalTubeBridge.dispatch(JSON.parse(atob('\(base64)'))); }
            catch(e) { console.error('Bridge decode error', e); }
        }
        """

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

// MARK: - Shared Formatter
// M10 fix: Cache ISO8601DateFormatter to avoid re-creating on every bridgePayload call.
private let sharedISO8601Formatter: ISO8601DateFormatter = {
    let f = ISO8601DateFormatter()
    return f
}()

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

        // Channels currently being synced
        payload["syncingChannelIds"] = syncingChannelIds.map { $0.uuidString }

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
            "createdAt":   sharedISO8601Formatter.string(from: createdAt),
            "bannerPath":  bannerPath.isEmpty ? "" : "localtube-thumb://\(bannerPath)",
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
            "downloadedAt":          sharedISO8601Formatter.string(from: downloadedAt),
            "durationSeconds":       durationSeconds,
            "resumePositionSeconds": resumePositionSeconds,
            "downloadState":         downloadState.rawValue,
            "downloadProgress":      downloadProgress,
            "sortOrder":             sortOrder,
            // Convert filesystem thumbnail path to our custom scheme URL for WKWebView.
            // Append ?v=N so WKWebView re-fetches when the file is replaced on disk.
            "thumbnailPath":         thumbnailPath.isEmpty ? "" : "localtube-thumb://\(thumbnailPath)?v=\(thumbnailVersion)",
            "thumbnailVersion":      thumbnailVersion,
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
