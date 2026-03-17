import Foundation
import Observation

// MARK: - Download Event

enum DownloadEvent: Sendable {
    case progress(UUID, Double)
    case completed(UUID)
    case error(UUID, String)
}

// MARK: - Download Service

@Observable
@MainActor
final class DownloadService {
    weak var appState: AppState?

    /// Optional event hook — set by WebWindowController to forward events to the JS bridge.
    var eventHandler: (@MainActor (DownloadEvent) -> Void)?

    private var isProcessing = false

    init(appState: AppState? = nil) {
        self.appState = appState
    }

    // MARK: - Queue Management

    func enqueue(video: Video, channel: Channel) async {
        guard let appState = appState else { return }

        // Don't double-enqueue
        let alreadyQueued = appState.downloadQueue.contains { $0.videoId == video.id }
        if alreadyQueued { return }

        let item = DownloadQueueItem(
            videoId: video.id,
            videoTitle: video.title,
            channelName: channel.displayName
        )
        appState.downloadQueue.append(item)

        // Update video state in AppState
        if var v = appState.videoById(video.id) {
            v.downloadState = .queued
            appState.updateVideo(v)
        }

        if !isProcessing {
            await processNext()
        }
    }

    func cancelDownload(itemId: UUID) {
        guard let appState = appState,
              let item = appState.downloadQueue.first(where: { $0.id == itemId })
        else { return }

        item.activeProcess?.terminate()
        item.state = .cancelled

        if var v = appState.videoById(item.videoId) {
            v.downloadState = .queued
            v.downloadProgress = 0
            appState.updateVideo(v)
            Task { try? await DatabaseService.shared.updateVideo(v) }
        }
    }

    func cancelAll() {
        guard let appState = appState else { return }
        for item in appState.downloadQueue where item.state == .waiting || item.state == .active {
            item.activeProcess?.terminate()
            item.state = .cancelled
        }
    }

    /// Re-queues a video that previously failed, stalled, or was cancelled.
    /// Removes any stale queue entry and resets the video state before enqueuing.
    func retryDownload(video: Video, channel: Channel) async {
        guard let appState = appState else { return }

        // Remove any stale queue entry so the dedup check in enqueue() won't block it
        appState.downloadQueue.removeAll { $0.videoId == video.id }

        // Reset the video back to queued state
        var resetVideo = video
        resetVideo.downloadState  = .queued
        resetVideo.downloadProgress = 0
        resetVideo.downloadError  = nil
        appState.updateVideo(resetVideo)
        Task { try? await DatabaseService.shared.updateVideo(resetVideo) }

        await enqueue(video: resetVideo, channel: channel)
    }

    // MARK: - Processing Loop

    private func processNext() async {
        guard let appState = appState,
              let item = appState.downloadQueue.first(where: { $0.state == .waiting })
        else {
            isProcessing = false
            return
        }

        isProcessing = true
        item.state = .active

        guard let video = appState.videoById(item.videoId),
              let channel = appState.channelById(video.channelId),
              let rootFolder = appState.settings.downloadFolderPath
        else {
            item.state = .failed(error: "Missing video or channel data")
            await processNext()
            return
        }

        do {
            let updatedVideo = try await downloadVideo(
                video: video,
                channel: channel,
                rootFolder: rootFolder,
                item: item
            )
            appState.updateVideo(updatedVideo)
            try await DatabaseService.shared.updateVideo(updatedVideo)
            item.state = .completed
            AppLogger.info("Download completed: \(video.title)")
            eventHandler?(.completed(video.id))
        } catch {
            item.state = .failed(error: error.localizedDescription)
            if var v = appState.videoById(item.videoId) {
                v.downloadState = .error
                v.downloadError = error.localizedDescription
                appState.updateVideo(v)
                try? await DatabaseService.shared.updateVideo(v)
            }
            AppLogger.error("Download failed: \(video.title) — \(error.localizedDescription)")
            eventHandler?(.error(video.id, error.localizedDescription))
        }

        await processNext()
    }

    // MARK: - Single Video Download

    private func downloadVideo(
        video: Video,
        channel: Channel,
        rootFolder: String,
        item: DownloadQueueItem
    ) async throws -> Video {
        var updatedVideo = video
        updatedVideo.downloadState = .downloading
        updatedVideo.downloadProgress = 0
        appState?.updateVideo(updatedVideo)

        // ── Fetch real title before downloading ──────────────────────────────
        // yt-dlp --skip-download --print is fast (no video bytes downloaded)
        // and replaces the "Video XXXX" placeholder immediately in the UI.
        let fetchedTitle = await fetchVideoTitle(videoId: video.youtubeVideoId)
        if !fetchedTitle.isEmpty {
            updatedVideo.title = fetchedTitle
            item.videoTitle = fetchedTitle
            appState?.updateVideo(updatedVideo)
            try? await DatabaseService.shared.updateVideo(updatedVideo)
        }

        // Ensure directories exist
        let videosDir = channel.videosPath(rootFolder: rootFolder)
        let thumbsDir = channel.thumbnailsPath(rootFolder: rootFolder)
        try FileManager.default.createDirectory(atPath: videosDir, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(atPath: thumbsDir, withIntermediateDirectories: true)

        // Output path — use the resolved title slug
        let safeTitle = updatedVideo.title.slugified()
        let fileName = "\(safeTitle)-\(video.id.uuidString.prefix(8)).mp4"
        let outputPath = (videosDir as NSString).appendingPathComponent(fileName)
        let thumbnailPath = ThumbnailService.thumbnailPath(
            for: video,
            channel: channel,
            rootFolder: rootFolder
        )

        let ytDlp = findYtDlp()
        let videoURL = "https://www.youtube.com/watch?v=\(video.youtubeVideoId)"

        try await withCheckedThrowingContinuation { (cont: CheckedContinuation<Void, Error>) in
            let process = ShellRunner.stream(ytDlp, args: [
                // Prefer H.264 + AAC — universally fast to decode on macOS.
                // AV1/VP9 are excluded here because AVPlayer needs hardware
                // acceleration for them and may stall on first-frame rendering.
                "-f", "bestvideo[vcodec^=avc1][height<=1080]+bestaudio[ext=m4a]/bestvideo[vcodec^=avc1]+bestaudio/bestvideo[ext=mp4]+bestaudio[ext=m4a]/best[ext=mp4]/best",
                "--merge-output-format", "mp4",
                "-o", outputPath,
                "--no-playlist",
                "--newline",
                videoURL
            ]) { [weak self, weak item] line in
                guard let self = self, let item = item else { return }
                let progress = self.parseProgress(from: line)
                Task { @MainActor in
                    if let p = progress {
                        item.progress = p
                        if var v = self.appState?.videoById(video.id) {
                            v.downloadProgress = p
                            self.appState?.updateVideo(v)
                        }
                        self.eventHandler?(.progress(video.id, p))
                    }
                }
            } onCompletion: { exitCode in
                if exitCode == 0 {
                    cont.resume()
                } else {
                    cont.resume(throwing: ShellError.nonZeroExit(exitCode, "yt-dlp download failed"))
                }
            }
            item.activeProcess = process
        }

        // Extract duration with ffprobe
        let duration = await extractDuration(from: outputPath)

        // Extract thumbnail
        try? await ThumbnailService.extract(videoPath: outputPath, outputPath: thumbnailPath)

        updatedVideo.localFilePath = outputPath
        updatedVideo.thumbnailPath = FileManager.default.fileExists(atPath: thumbnailPath) ? thumbnailPath : ""
        updatedVideo.durationSeconds = duration
        updatedVideo.downloadState = .ready
        updatedVideo.downloadProgress = 1.0
        updatedVideo.downloadedAt = Date()

        return updatedVideo
    }

    // MARK: - Helpers

    private nonisolated func parseProgress(from line: String) -> Double? {
        // yt-dlp format: "[download]  45.6% of ..."
        guard line.contains("[download]"), line.contains("%") else { return nil }
        let parts = line.components(separatedBy: "%")
        guard let first = parts.first else { return nil }
        let digits = first.components(separatedBy: .whitespaces).last ?? ""
        guard let pct = Double(digits) else { return nil }
        return min(pct / 100.0, 1.0)
    }

    private func extractDuration(from path: String) async -> Double {
        let ffprobe = findFfprobe()
        let output = try? await ShellRunner.run(ffprobe, args: [
            "-v", "error",
            "-show_entries", "format=duration",
            "-of", "default=noprint_wrappers=1:nokey=1",
            path
        ])
        return output.flatMap { Double($0) } ?? 0
    }

    private func findYtDlp() -> String {
        let candidates = ["/opt/homebrew/bin/yt-dlp", "/usr/local/bin/yt-dlp"]
        return candidates.first { FileManager.default.fileExists(atPath: $0) } ?? "yt-dlp"
    }

    private func findFfprobe() -> String {
        let candidates = ["/opt/homebrew/bin/ffprobe", "/usr/local/bin/ffprobe"]
        return candidates.first { FileManager.default.fileExists(atPath: $0) } ?? "ffprobe"
    }

    /// Fetches the YouTube video title without downloading any video data.
    /// Returns "" on failure so callers can fall back to the existing title.
    private func fetchVideoTitle(videoId: String) async -> String {
        let ytDlp = findYtDlp()
        let url = "https://www.youtube.com/watch?v=\(videoId)"
        let output = try? await ShellRunner.run(ytDlp, args: [
            "--skip-download",
            "--print", "%(title)s",
            "--no-playlist",
            url
        ])
        let title = output?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        // yt-dlp outputs "NA" when a field is unavailable
        return (title.isEmpty || title == "NA") ? "" : title
    }
}
