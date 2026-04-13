import Foundation

// MARK: - Channel Sync Service
//
// Fetches the full video list for a YouTube source channel using yt-dlp's
// --flat-playlist --print mode, which retrieves metadata only (no downloads).
// Returns one entry per video in the channel's /videos feed.

struct ChannelSyncEntry: Sendable {
    let videoId: String
    let title: String
    let durationSeconds: Double?
}

enum ChannelSyncService {

    /// Fetches the video list for a YouTube channel.
    /// Returns an array of ChannelSyncEntry sorted oldest-first (yt-dlp default),
    /// or an empty array on any failure.
    static func fetchVideoList(youtubeChannelId: String) async -> [ChannelSyncEntry] {
        guard let ytDlp = findYtDlp() else {
            AppLogger.error("ChannelSyncService: yt-dlp not found")
            return []
        }

        let channelURL = makeChannelURL(youtubeChannelId)
        AppLogger.info("ChannelSyncService: fetching video list for \(channelURL)")

        // --flat-playlist: metadata only, no actual video downloads.
        // --print: one tab-separated line per entry.
        // Duration may be "NA" for live/premiere items — we skip those.
        let output: String
        do {
            output = try await ShellRunner.run(ytDlp, args: [
                "--flat-playlist",
                "--print", "%(id)s\t%(title)s\t%(duration)s",
                "--no-warnings",
                channelURL,
            ], timeout: 180)
        } catch {
            AppLogger.error("ChannelSyncService: yt-dlp failed — \(error.localizedDescription)")
            return []
        }

        guard !output.isEmpty else { return [] }

        return output
            .components(separatedBy: "\n")
            .compactMap { line -> ChannelSyncEntry? in
                let parts = line.components(separatedBy: "\t")
                let videoId = parts[0].trimmingCharacters(in: .whitespaces)
                guard !videoId.isEmpty, videoId != "NA" else { return nil }

                let rawTitle = parts.count >= 2 ? parts[1] : ""
                let title = rawTitle.isEmpty ? "Video \(videoId)" : rawTitle.htmlEntityDecoded

                let duration: Double?
                if parts.count >= 3, let d = Double(parts[2]) {
                    duration = d
                } else {
                    duration = nil
                }

                return ChannelSyncEntry(videoId: videoId, title: title, durationSeconds: duration)
            }
    }

    // MARK: - Private

    /// Constructs the channel URL from whatever the user supplied:
    ///   UCxxxxxx  →  /channel/UCxxxxxx/videos
    ///   @handle   →  /@handle/videos
    ///   bare name →  /@name/videos
    private static func makeChannelURL(_ youtubeChannelId: String) -> String {
        if youtubeChannelId.hasPrefix("UC") || youtubeChannelId.hasPrefix("HC") {
            return "https://www.youtube.com/channel/\(youtubeChannelId)/videos"
        } else if youtubeChannelId.hasPrefix("@") {
            return "https://www.youtube.com/\(youtubeChannelId)/videos"
        } else {
            return "https://www.youtube.com/@\(youtubeChannelId)/videos"
        }
    }

    private static func findYtDlp() -> String? {
        let candidates = ["/opt/homebrew/bin/yt-dlp", "/usr/local/bin/yt-dlp"]
        return candidates.first { FileManager.default.isExecutableFile(atPath: $0) }
    }
}
