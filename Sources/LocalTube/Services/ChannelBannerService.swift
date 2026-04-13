import Foundation

// MARK: - Channel Banner Service
//
// Fetches a YouTube channel's banner/header art using yt-dlp and downloads
// it to disk.  Only runs for Type A (source) channels that have a YouTube
// channel ID.

enum ChannelBannerService {

    /// Fetches the channel banner URL via yt-dlp --dump-single-json and
    /// downloads it to `<rootFolder>/<sanitizedFolderName>/banner.jpg`.
    /// Returns the local file path on success, nil on any failure.
    static func fetchAndDownload(
        youtubeChannelId: String,
        sanitizedFolderName: String,
        rootFolder: String
    ) async -> String? {
        let destDir = (rootFolder as NSString).appendingPathComponent(sanitizedFolderName)
        let destPath = (destDir as NSString).appendingPathComponent("banner.jpg")

        // Already cached — skip re-download
        if FileManager.default.fileExists(atPath: destPath) {
            return destPath
        }

        guard let ytDlp = findYtDlp() else { return nil }
        let channelURL = makeChannelURL(youtubeChannelId)

        // --playlist-items 0 returns empty output; --playlist-items 1 fetches
        // just one video entry but still includes all channel-level thumbnail
        // metadata (banner, avatar, etc.) in the top-level JSON object.
        let json = try? await ShellRunner.run(ytDlp, args: [
            "--dump-single-json",
            "--flat-playlist",
            "--playlist-items", "1",
            "--no-warnings",
            channelURL
        ])
        guard let json, !json.isEmpty,
              let data = json.data(using: .utf8),
              let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        else { return nil }

        // Extract the best banner URL from the thumbnails array.
        // YouTube channel banners have very wide aspect ratios (≥ 4:1) or
        // IDs/preferences containing "banner" or "header".
        guard let bannerURL = extractBannerURL(from: obj) else { return nil }

        // Download to disk
        guard let url = URL(string: bannerURL) else { return nil }
        do {
            try FileManager.default.createDirectory(
                atPath: destDir,
                withIntermediateDirectories: true
            )
            let (tmpURL, _) = try await URLSession.shared.download(from: url)
            // Move to final destination (overwrite if present from a prior partial download)
            if FileManager.default.fileExists(atPath: destPath) {
                try FileManager.default.removeItem(atPath: destPath)
            }
            try FileManager.default.moveItem(at: tmpURL, to: URL(fileURLWithPath: destPath))
            return destPath
        } catch {
            AppLogger.error("ChannelBannerService: download failed for \(bannerURL) — \(error)")
            return nil
        }
    }

    // MARK: - Private

    private static func extractBannerURL(from obj: [String: Any]) -> String? {
        guard let thumbnails = obj["thumbnails"] as? [[String: Any]] else { return nil }

        // Score each thumbnail — prefer banner-shaped wide images.
        // Priority order:
        //   1. ID or preference key contains "banner" or "header" (highest)
        //   2. width/height ratio ≥ 4 (wide banner shape)
        //   3. Largest total resolution as tiebreaker

        var best: (url: String, score: Int, area: Int)?

        for thumb in thumbnails {
            guard let urlStr = thumb["url"] as? String, !urlStr.isEmpty else { continue }
            let id = (thumb["id"] as? String ?? "").lowercased()
            let pref = thumb["preference"] as? Int ?? 0
            let width = thumb["width"] as? Int ?? 0
            let height = thumb["height"] as? Int ?? 1
            let area = width * height

            var score = 0
            if id.contains("banner") || id.contains("header") { score += 100 }
            if pref < -1 { score += 50 } // yt-dlp uses negative preferences for non-avatar art
            let ratio = height > 0 ? Double(width) / Double(height) : 0
            if ratio >= 4.0 { score += 80 }
            else if ratio >= 2.0 { score += 30 }

            if best == nil || score > best!.score || (score == best!.score && area > best!.area) {
                best = (urlStr, score, area)
            }
        }

        // Only accept something that looks genuinely banner-shaped (score > 0)
        // to avoid accidentally using the avatar as a banner.
        guard let result = best, result.score > 0 else { return nil }
        return result.url
    }

    /// Constructs a channel URL that works for UC... IDs, @handles, and bare names.
    private static func makeChannelURL(_ youtubeChannelId: String) -> String {
        if youtubeChannelId.hasPrefix("UC") || youtubeChannelId.hasPrefix("HC") {
            return "https://www.youtube.com/channel/\(youtubeChannelId)"
        } else if youtubeChannelId.hasPrefix("@") {
            return "https://www.youtube.com/\(youtubeChannelId)"
        } else {
            return "https://www.youtube.com/@\(youtubeChannelId)"
        }
    }

    private static func findYtDlp() -> String? {
        let candidates = ["/opt/homebrew/bin/yt-dlp", "/usr/local/bin/yt-dlp"]
        return candidates.first { FileManager.default.isExecutableFile(atPath: $0) }
    }
}
