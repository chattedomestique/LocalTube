import Foundation

// MARK: - Resolved Channel Info

struct ResolvedChannel: Sendable {
    let channelId: String
    let displayName: String
}

// MARK: - Channel Resolver

enum ChannelResolverService {
    private static let cap = 200

    /// Resolves a YouTube channel URL to its channel ID and display name.
    static func resolve(youtubeURL: String) async throws -> ResolvedChannel {
        let ytDlp = findYtDlp()
        let json = try await ShellRunner.run(ytDlp, args: [
            "--dump-single-json",
            "--flat-playlist",
            "--playlist-items", "1",
            "--no-warnings",
            youtubeURL
        ])
        guard let data = json.data(using: .utf8),
              let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        else {
            throw ChannelResolverError.parseError("Could not parse yt-dlp response")
        }

        let channelId = (obj["channel_id"] as? String)
            ?? (obj["id"] as? String)
            ?? ""
        let rawName = (obj["uploader"] as? String)
            ?? (obj["channel"] as? String)
            ?? (obj["title"] as? String)
            ?? "Unknown Channel"
        // Decode residual HTML entities that yt-dlp can leave in channel names
        let displayName = rawName.htmlEntityDecoded

        guard !channelId.isEmpty else {
            throw ChannelResolverError.notAChannel
        }
        return ResolvedChannel(channelId: channelId, displayName: displayName)
    }

    /// Fetches all public video URLs from a channel (up to 200).
    /// Returns (videoURLs, process) — caller can cancel the process.
    @discardableResult
    static func fetchVideoURLs(
        channelURL: String,
        onProgress: @escaping @Sendable (Int) -> Void,
        onCompletion: @escaping @Sendable (Result<[String], Error>) -> Void
    ) -> Process {
        let ytDlp = findYtDlp()
        // Use a lock-protected collector to safely accumulate URLs from the
        // streaming callback (which runs on a background thread).
        let collector = URLCollector()

        return ShellRunner.stream(ytDlp, args: [
            "--flat-playlist",
            "--print", "url",
            "--no-warnings",
            "--playlist-end", "\(cap)",
            channelURL
        ]) { line in
            let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty, trimmed.hasPrefix("http") else { return }
            let count = collector.append(trimmed)
            onProgress(count)
        } onCompletion: { exitCode in
            if exitCode == 0 {
                onCompletion(.success(collector.all))
            } else {
                onCompletion(.failure(ChannelResolverError.fetchFailed(exitCode)))
            }
        }
    }

    /// Extracts the YouTube channel ID from a video URL.
    static func extractChannelId(fromVideoURL url: String) async throws -> String {
        let ytDlp = findYtDlp()
        return try await ShellRunner.run(ytDlp, args: [
            "--print", "channel_id",
            "--no-warnings",
            "--skip-download",
            url
        ])
    }

    // MARK: - Private

    private static func findYtDlp() -> String {

        let candidates = ["/opt/homebrew/bin/yt-dlp", "/usr/local/bin/yt-dlp"]
        return candidates.first { FileManager.default.fileExists(atPath: $0) } ?? "yt-dlp"
    }
}

// MARK: - Thread-safe URL collector

/// Collects URL strings from concurrent callbacks using a lock.
private final class URLCollector: @unchecked Sendable {
    private var _urls: [String] = []
    private let lock = NSLock()

    /// Appends a URL and returns the new count.
    @discardableResult
    func append(_ url: String) -> Int {
        lock.lock(); defer { lock.unlock() }
        _urls.append(url)
        return _urls.count
    }

    var all: [String] {
        lock.lock(); defer { lock.unlock() }
        return _urls
    }
}

enum ChannelResolverError: Error, LocalizedError {
    case parseError(String)
    case notAChannel
    case fetchFailed(Int32)
    case wrongChannel

    var errorDescription: String? {
        switch self {
        case .parseError(let m): return "Parse error: \(m)"
        case .notAChannel: return "URL doesn't appear to be a YouTube channel"
        case .fetchFailed(let c): return "yt-dlp exited with code \(c)"
        case .wrongChannel: return "This video doesn't belong to the selected channel"
        }
    }
}
