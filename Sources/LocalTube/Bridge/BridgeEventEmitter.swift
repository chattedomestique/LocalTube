import WebKit
import Foundation

// MARK: - Bridge Event Emitter (Swift → JS)
//
// Calls window.LocalTubeBridge.dispatch(event, payload) in the WKWebView.
// All calls must happen on the main thread (WKWebView requirement).
// Mirror any new event in WebUI/src/types.ts (BridgeEvent).

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
        guard JSONSerialization.isValidJSONObject(envelope),
              let jsonData = try? JSONSerialization.data(withJSONObject: envelope) else {
            AppLogger.error("BridgeEventEmitter [\(event)]: payload is not valid JSON")
            return
        }
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

    /// `lockoutSeconds` > 0 means further attempts are refused for that
    /// long (rate limiting after repeated failures).
    func emitPINValidated(valid: Bool, lockoutSeconds: Int = 0) {
        emit("pinValidated", payload: ["valid": valid, "lockoutSeconds": max(0, lockoutSeconds)])
    }

    /// Transient, non-state message for the UI to show briefly.
    /// kind: "info" | "success" | "warning" | "error"
    func emitToast(_ message: String, kind: String = "info") {
        emit("toast", payload: ["message": message, "kind": kind])
    }

    // emitEditorTimerTick removed with the auto-lock timer.

    // MARK: - Library management emitters

    /// Reply to `chooseLibraryFolder`. `analysis == nil` means the user
    /// cancelled the picker.
    func emitLibraryFolderPicked(analysis: LibraryFolderAnalysis?) {
        if let analysis {
            emit("libraryFolderPicked", payload: ["cancelled": false, "analysis": analysis.bridgePayload()])
        } else {
            emit("libraryFolderPicked", payload: ["cancelled": true])
        }
    }

    func emitLibraryRelocationProgress(done: Int, total: Int, channel: String) {
        emit("libraryRelocationProgress", payload: ["done": done, "total": total, "channel": channel])
    }

    func emitLibraryRelocated(result: LibraryRelocationResult) {
        emit("libraryRelocated", payload: result.bridgePayload())
    }

    func emitLibraryScanStarted() {
        emit("libraryScanStarted")
    }

    func emitLibraryScanCompleted(result: LibraryScanResult) {
        emit("libraryScanCompleted", payload: result.bridgePayload())
    }

    // MARK: - Targeted diff emitters
    //
    // These let handlers push only the changed slice instead of the full
    // bridgePayload (~1.5 MB for a 300-video library). The React reducer
    // applies these as O(1) patches against its existing store.

    func emitChannelUpserted(_ channel: Channel) {
        emit("channelUpserted", payload: ["channel": channel.bridgePayload()])
    }

    func emitChannelRemoved(id: UUID) {
        emit("channelRemoved", payload: ["channelId": id.uuidString])
    }

    func emitVideosUpserted(channelId: UUID, videos: [Video]) {
        emit("videosUpserted", payload: [
            "channelId": channelId.uuidString,
            "videos": videos.map { $0.bridgePayload() },
        ])
    }

    func emitVideoRemoved(id: UUID) {
        emit("videoRemoved", payload: ["videoId": id.uuidString])
    }

    func emitSettingsUpdated(_ settings: AppSettings) {
        emit("settingsUpdated", payload: ["settings": settings.bridgePayload()])
    }

    func emitAppModeChanged(mode: AppMode) {
        emit("appModeChanged", payload: [
            "appMode": mode == .editor ? "editor" : "viewer",
        ])
    }

    // MARK: - Profile diff emitters

    func emitProfileUpserted(_ profile: Profile) {
        emit("profileUpserted", payload: ["profile": profile.bridgePayload()])
    }

    func emitProfileRemoved(id: UUID) {
        emit("profileRemoved", payload: ["profileId": id.uuidString])
    }

    func emitProfileChannelsUpdated(profileId: UUID, channelIds: [UUID]) {
        emit("profileChannelsUpdated", payload: [
            "profileId": profileId.uuidString,
            "channelIds": channelIds.map { $0.uuidString },
        ])
    }

    func emitActiveProfileChanged(activeProfileId: UUID?) {
        emit("activeProfileChanged", payload: [
            "activeProfileId": activeProfileId?.uuidString as Any,
        ])
    }

    func emitIsEditingChanged(_ isEditing: Bool) {
        emit("isEditingChanged", payload: ["isEditing": isEditing])
    }

    func emitFavoriteChanged(profileId: UUID, videoId: UUID, isFavorite: Bool) {
        emit("favoriteChanged", payload: [
            "profileId":  profileId.uuidString,
            "videoId":    videoId.uuidString,
            "isFavorite": isFavorite,
        ])
    }

    func emitChannelHiddenChanged(profileId: UUID, channelId: UUID, hidden: Bool) {
        emit("channelHiddenChanged", payload: [
            "profileId": profileId.uuidString,
            "channelId": channelId.uuidString,
            "hidden":    hidden,
        ])
    }

    // MARK: - Playlist diff emitters

    func emitPlaylistUpserted(_ playlist: Playlist) {
        emit("playlistUpserted", payload: ["playlist": playlist.bridgePayload()])
    }

    func emitPlaylistRemoved(id: UUID) {
        emit("playlistRemoved", payload: ["playlistId": id.uuidString])
    }

    func emitPlaylistVideosUpdated(playlistId: UUID, videoIds: [UUID]) {
        emit("playlistVideosUpdated", payload: [
            "playlistId": playlistId.uuidString,
            "videoIds":   videoIds.map { $0.uuidString },
        ])
    }

    func emitActivePlaylistChanged(profileId: UUID, activePlaylistId: UUID?) {
        emit("activePlaylistChanged", payload: [
            "profileId":        profileId.uuidString,
            "activePlaylistId": activePlaylistId?.uuidString as Any,
        ])
    }

    // MARK: - Playback diff emitters

    /// The video currently playing in the floating player, or nil when the
    /// player closes. Drives the now-playing highlight in the queue tray.
    func emitNowPlayingChanged(videoId: UUID?) {
        emit("nowPlayingChanged", payload: [
            "videoId": videoId?.uuidString as Any,
        ])
    }

    /// The active profile's channel-playback mode changed (from the player
    /// overlay's autoplay button). Mirrors `setAutoPlaybackMode` so any
    /// open React surface stays in sync.
    func emitAutoPlaybackModeChanged(profileId: UUID, mode: String) {
        emit("autoPlaybackModeChanged", payload: [
            "profileId": profileId.uuidString,
            "mode":      mode,
        ])
    }
}

extension Playlist {
    func bridgePayload() -> [String: Any] {
        [
            "id":        id.uuidString,
            "profileId": profileId.uuidString,
            "name":      name,
            "sortOrder": sortOrder,
            "isSystem":  isSystem,
            "createdAt": sharedISO8601Formatter.string(from: createdAt),
        ]
    }
}

// MARK: - Shared Formatter
// M10 fix: Cache ISO8601DateFormatter to avoid re-creating on every bridgePayload call.
private let sharedISO8601Formatter: ISO8601DateFormatter = {
    let f = ISO8601DateFormatter()
    return f
}()

// MARK: - Thumbnail URL helper
//
// Builds a `localtube-thumb://` URL from an absolute file path. The path
// is percent-encoded so folders containing '#', '?', '%' or spaces don't
// break the URL (a root folder named "Kids #1" used to truncate every
// thumbnail path at the '#'). ThumbnailURLSchemeHandler decodes it back
// via `URL.path`.

private func thumbURL(forPath path: String, version: Int? = nil) -> String {
    guard !path.isEmpty else { return "" }
    let encoded = path.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? path
    if let version {
        return "localtube-thumb://\(encoded)?v=\(version)"
    }
    return "localtube-thumb://\(encoded)"
}

// MARK: - AppState → Bridge Payload

extension AppState {
    func bridgePayload() -> [String: Any] {
        var payload: [String: Any] = [
            "channels":  channels.map { $0.bridgePayload() },
            "appMode":   appMode == .editor ? "editor" : "viewer",
            "isEditing": isEditing,
            "isOnboarding": isOnboarding,
            "needsPINSetup": needsPINSetup,
            "showPINEntry":  showPINEntry,
            "editorRemainingSeconds": editorRemainingSeconds,
            "settings": settings.bridgePayload(),
            "dependencyStatus": [
                "ytDlp":  dependencyStatus.ytDlp,
                "ffmpeg": dependencyStatus.ffmpeg,
            ],
            "libraryFolderAvailable": libraryFolderAvailable,
            "isScanning": maintenance.isScanning,
            "isRelocating": maintenance.isRelocating,
            "appVersion": AppState.appVersion,
        ]
        if let err = libraryLoadError { payload["libraryLoadError"] = err }
        if let scan = maintenance.lastScanResult { payload["lastScan"] = scan.bridgePayload() }

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
        payload["pendingDownloadCount"] = pendingDownloadCount

        // Channels currently being synced
        payload["syncingChannelIds"] = syncingChannelIds.map { $0.uuidString }

        // Profiles
        payload["profiles"] = profiles.map { $0.bridgePayload() }
        var pcMap: [String: [String]] = [:]
        for (pid, cids) in profileChannels {
            pcMap[pid.uuidString] = cids.map { $0.uuidString }
        }
        payload["profileChannels"] = pcMap
        payload["activeProfileId"] = activeProfileId?.uuidString as Any

        var favMap: [String: [String]] = [:]
        for (pid, vids) in profileFavorites {
            favMap[pid.uuidString] = vids.map { $0.uuidString }
        }
        payload["profileFavorites"] = favMap

        var hiddenMap: [String: [String]] = [:]
        for (pid, cids) in profileHiddenChannels {
            hiddenMap[pid.uuidString] = cids.map { $0.uuidString }
        }
        payload["profileHiddenChannels"] = hiddenMap

        payload["playlists"] = playlists.map { $0.bridgePayload() }
        var plvMap: [String: [String]] = [:]
        for (plid, vids) in playlistVideos {
            plvMap[plid.uuidString] = vids.map { $0.uuidString }
        }
        payload["playlistVideos"] = plvMap

        return payload
    }
}

extension Profile {
    func bridgePayload() -> [String: Any] {
        var p: [String: Any] = [
            "id":        id.uuidString,
            "name":      name,
            "sortOrder": sortOrder,
            "createdAt": sharedISO8601Formatter.string(from: createdAt),
        ]
        if let emoji = emoji { p["emoji"] = emoji }
        if let icon  = icon  { p["icon"]  = icon  }
        if let color = color { p["color"] = color }
        if let apid  = activePlaylistId { p["activePlaylistId"] = apid.uuidString }
        if let apm   = autoPlaybackMode { p["autoPlaybackMode"] = apm }
        return p
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
            "bannerPath":  thumbURL(forPath: bannerPath),
        ]
        if let emoji = emoji              { p["emoji"]            = emoji }
        if let ytId  = youtubeChannelId   { p["youtubeChannelId"] = ytId  }
        if let t = lastSyncedAt           { p["lastSyncedAt"]     = sharedISO8601Formatter.string(from: t) }
        if let err = lastSyncError        { p["lastSyncError"]    = err }
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
            "thumbnailPath":         thumbURL(forPath: thumbnailPath, version: thumbnailVersion),
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
            "downloadQuality":       downloadQuality.rawValue,
        ]
        if let fp = downloadFolderPath { p["downloadFolderPath"] = fp }
        return p
    }
}
