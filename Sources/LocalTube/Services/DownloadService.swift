import Foundation
import Observation

// MARK: - Download Event

enum DownloadEvent: Sendable {
    case progress(UUID, Double)
    case completed(UUID)
    case error(UUID, String)
}

// MARK: - Download Service
//
// Owns the in-session download queue and drives yt-dlp. Everything here
// is main-actor confined; the only off-main work is the yt-dlp process
// itself (ShellRunner) whose callbacks hop back via Task { @MainActor }.
//
// Persistence contract: every download-state transition that matters
// after a relaunch (queued → downloading → ready/error) is written to the
// database as it happens. `resumePendingDownloads()` re-enqueues whatever
// was still queued or mid-download when the app last quit, so a closed
// lid or a crash no longer strands half a channel in "Queued" forever.

@Observable
@MainActor
final class DownloadService {
    weak var appState: AppState?

    /// Optional event hook — set by WebWindowController to forward events to the JS bridge.
    var eventHandler: (@MainActor (DownloadEvent) -> Void)?

    private var activeDownloadCount = 0
    /// Parallel yt-dlp processes. Each one also spawns ffmpeg for the
    /// final mux, so this is effectively 2× the process count.
    private let maxConcurrent = 4
    private var lastProgressTime: [UUID: Date] = [:]
    /// Finished queue entries (completed/failed/cancelled) are kept around
    /// for the queue panel but trimmed so the array can't grow unbounded
    /// across a long-running session.
    private let maxFinishedEntries = 100
    /// Terminate a download that has produced no output for this long
    /// (a stuck network connection, a hung ffmpeg). yt-dlp resumes the
    /// `.part` file on the next retry so nothing is lost.
    private let downloadInactivityTimeout: TimeInterval = 10 * 60
    private var loggedFolderUnavailable = false

    init(appState: AppState? = nil) {
        self.appState = appState
    }

    // MARK: - Queue Management

    func enqueue(video: Video, channel: Channel) async {
        guard let appState = appState else { return }

        // Drop finished entries for this video so a retry after a failure
        // isn't blocked by the stale row; then de-duplicate against live ones.
        appState.downloadQueue.removeAll { $0.videoId == video.id && !$0.isLive }
        if appState.downloadQueue.contains(where: { $0.videoId == video.id }) { return }

        let item = DownloadQueueItem(
            videoId: video.id,
            videoTitle: video.title,
            channelName: channel.displayName
        )
        appState.downloadQueue.append(item)
        trimFinishedEntries()

        // Reflect "queued" in memory + DB so a relaunch picks it back up.
        if var v = appState.videoById(video.id), v.downloadState != .queued {
            v.downloadState = .queued
            v.downloadProgress = 0
            v.downloadError = nil
            appState.updateVideoAndPersist(v, context: "enqueue")
        }

        await processNext()
    }

    func cancelDownload(itemId: UUID) {
        guard let appState = appState,
              let item = appState.downloadQueue.first(where: { $0.id == itemId })
        else { return }
        cancel(item: item, appState: appState)
    }

    /// Cancels any live download for the given videos (used before a video
    /// or channel is deleted so the process doesn't keep writing into a
    /// folder we're about to remove).
    func cancelDownloads(forVideoIds ids: Set<UUID>) {
        guard let appState = appState else { return }
        for item in appState.downloadQueue where ids.contains(item.videoId) && item.isLive {
            if let process = item.activeProcess { ShellRunner.forceTerminate(process) }
            item.state = .cancelled
        }
    }

    func cancelAll() {
        guard let appState = appState else { return }
        for item in appState.downloadQueue where item.isLive {
            cancel(item: item, appState: appState)
        }
    }

    private func cancel(item: DownloadQueueItem, appState: AppState) {
        if let process = item.activeProcess { ShellRunner.forceTerminate(process) }
        item.state = .cancelled

        if var v = appState.videoById(item.videoId) {
            v.downloadState = .queued
            v.downloadProgress = 0
            appState.updateVideoAndPersist(v, context: "cancelDownload")
        }
    }

    /// Re-queues a video that previously failed, stalled, or was cancelled.
    /// Removes any stale queue entry and resets the video state before enqueuing.
    func retryDownload(video: Video, channel: Channel) async {
        guard let appState = appState else { return }

        // A live entry for this video means it's already being handled.
        if let live = appState.downloadQueue.first(where: { $0.videoId == video.id && $0.isLive }) {
            AppLogger.info("retryDownload: \(video.title) already \(live.state) — ignoring")
            return
        }
        appState.downloadQueue.removeAll { $0.videoId == video.id }

        var resetVideo = video
        resetVideo.downloadState  = .queued
        resetVideo.downloadProgress = 0
        resetVideo.downloadError  = nil
        appState.updateVideoAndPersist(resetVideo, context: "retry")

        await enqueue(video: resetVideo, channel: channel)
    }

    /// Retries every failed video (optionally scoped to one channel).
    /// Returns the number of videos re-queued.
    @discardableResult
    func retryFailedDownloads(channelId: UUID? = nil) async -> Int {
        guard let appState = appState else { return 0 }
        var count = 0
        for channel in appState.channels where channelId == nil || channel.id == channelId {
            for video in appState.videosForChannel(channel.id) where video.downloadState == .error {
                await retryDownload(video: video, channel: channel)
                count += 1
            }
        }
        return count
    }

    /// Re-enqueues every video the database still marks as queued or
    /// downloading. Called once after the library loads. Ordered by
    /// channel then sort order so the queue mirrors what the user sees.
    @discardableResult
    func resumePendingDownloads() async -> Int {
        guard let appState = appState else { return 0 }
        var count = 0
        for channel in appState.channels {
            let pending = appState.videosForChannel(channel.id)
                .filter { $0.downloadState == .queued || $0.downloadState == .downloading }
                .sorted { $0.sortOrder < $1.sortOrder }
            for video in pending {
                await enqueue(video: video, channel: channel)
                count += 1
            }
        }
        if count > 0 {
            AppLogger.info("Resumed \(count) pending download(s) from a previous session")
        }
        return count
    }

    // MARK: - Processing Loop

    /// Fills all available download slots up to `maxConcurrent`.
    /// Each slot runs independently — when one finishes it calls back here
    /// to immediately pull the next waiting item off the queue.
    private func processNext() async {
        guard let appState = appState else { return }

        // No library folder (unplugged drive, offline share): leave items
        // waiting rather than failing them all. `recheckLibraryFolder`
        // calls back here once the folder is reachable again.
        guard let rootFolder = appState.settings.downloadFolderPath,
              SettingsService.isDirectory(atPath: rootFolder) else {
            if !loggedFolderUnavailable {
                AppLogger.error("Downloads paused: library folder is unavailable")
                loggedFolderUnavailable = true
            }
            return
        }
        loggedFolderUnavailable = false

        while activeDownloadCount < maxConcurrent,
              let item = appState.downloadQueue.first(where: { $0.state == .waiting }) {

            guard let video = appState.videoById(item.videoId),
                  let channel = appState.channelById(video.channelId)
            else {
                // The video was deleted while it sat in the queue.
                item.state = .cancelled
                continue
            }

            item.state = .active
            activeDownloadCount += 1

            Task {
                do {
                    let updatedVideo = try await downloadVideo(
                        video: video,
                        channel: channel,
                        rootFolder: rootFolder,
                        item: item
                    )
                    // The video may have been deleted mid-download; don't
                    // resurrect it in memory or in the database.
                    if appState.videoById(video.id) != nil {
                        appState.updateVideo(updatedVideo)
                        try await DatabaseService.shared.updateVideo(updatedVideo)
                        item.state = .completed
                        AppLogger.info("Download completed: \(updatedVideo.title)")
                        eventHandler?(.completed(video.id))
                    } else {
                        item.state = .cancelled
                        AppLogger.info("Download finished for a video that was deleted meanwhile: \(video.title)")
                    }
                } catch {
                    let message = error.localizedDescription
                    if item.state == .cancelled {
                        AppLogger.info("Download cancelled: \(video.title)")
                    } else {
                        item.state = .failed(error: message)
                        if var v = appState.videoById(item.videoId) {
                            v.downloadState = .error
                            v.downloadError = message
                            v.downloadProgress = 0
                            appState.updateVideoAndPersist(v, context: "download error")
                        }
                        AppLogger.error("Download failed: \(video.title) — \(message)")
                        eventHandler?(.error(video.id, message))
                    }
                }
                lastProgressTime.removeValue(forKey: video.id)
                activeDownloadCount -= 1
                trimFinishedEntries()
                await processNext() // fill the freed slot immediately
            }
        }
    }

    private func trimFinishedEntries() {
        guard let appState = appState else { return }
        let finished = appState.downloadQueue.filter { !$0.isLive }
        guard finished.count > maxFinishedEntries else { return }
        let excess = finished.count - maxFinishedEntries
        var removed = 0
        appState.downloadQueue.removeAll { item in
            guard !item.isLive, removed < excess else { return false }
            removed += 1
            return true
        }
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
        updatedVideo.downloadError = nil
        appState?.updateVideoAndPersist(updatedVideo, context: "download start")

        // ── Fetch real title before downloading ──────────────────────────────
        // yt-dlp --skip-download --print is fast (no video bytes downloaded)
        // and replaces the "Video XXXX" placeholder immediately in the UI.
        let fetchedTitle = await fetchVideoTitle(videoId: video.youtubeVideoId)
        if !fetchedTitle.isEmpty, fetchedTitle != updatedVideo.title {
            updatedVideo.title = fetchedTitle
            item.videoTitle = fetchedTitle
            appState?.updateVideoAndPersist(updatedVideo, context: "download title")
        }

        // Ensure directories exist
        let videosDir = channel.videosPath(rootFolder: rootFolder)
        let thumbsDir = channel.thumbnailsPath(rootFolder: rootFolder)
        try FileManager.default.createDirectory(atPath: videosDir, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(atPath: thumbsDir, withIntermediateDirectories: true)

        // Output path — use the resolved title slug. Keep the path from a
        // previous attempt when it exists so yt-dlp can resume its .part.
        let outputPath: String
        if !video.localFilePath.isEmpty,
           LibraryPaths.isPath(video.localFilePath, under: videosDir) {
            outputPath = video.localFilePath
        } else {
            let safeTitle = updatedVideo.title.slugified()
            let fileName = "\(safeTitle)-\(video.id.uuidString.prefix(8)).mp4"
            outputPath = (videosDir as NSString).appendingPathComponent(fileName)
        }
        let thumbnailPath = ThumbnailService.thumbnailPath(
            for: video,
            channel: channel,
            rootFolder: rootFolder
        )

        let ytDlp = findYtDlp()
        let videoURL = "https://www.youtube.com/watch?v=\(video.youtubeVideoId)"
        let quality = appState?.settings.downloadQuality ?? .best
        let errorLines = ErrorLineCollector()
        let inactivityTimeout = downloadInactivityTimeout

        try await withCheckedThrowingContinuation { (cont: CheckedContinuation<Void, Error>) in
            let process = ShellRunner.stream(ytDlp, args: [
                "-f", quality.ytDlpFormat,
                "--merge-output-format", "mp4",
                // Ask yt-dlp to write the thumbnail alongside the video file.
                // yt-dlp saves it as <outputBase>.<ext> next to the video.
                // We move it to thumbnailPath after the download completes.
                "--write-thumbnail",
                "--convert-thumbnails", "jpg",
                "-o", outputPath,
                "--no-playlist",
                "--newline",
                "--no-warnings",
                videoURL
            ], inactivityTimeout: inactivityTimeout) { [weak self, weak item] line in
                errorLines.record(line)
                guard let self = self, let item = item else { return }
                let progress = self.parseProgress(from: line)
                Task { @MainActor in
                    guard let p = progress else { return }
                    // Throttle UI updates to 2/sec per video — yt-dlp emits
                    // many lines/sec and each update triggers a React re-render.
                    let now = Date()
                    if let last = self.lastProgressTime[video.id],
                       now.timeIntervalSince(last) < 0.5 { return }
                    self.lastProgressTime[video.id] = now
                    item.progress = p
                    if var v = self.appState?.videoById(video.id) {
                        v.downloadProgress = p
                        self.appState?.updateVideo(v)
                    }
                    self.eventHandler?(.progress(video.id, p))
                }
            } onCompletion: { exitCode in
                switch exitCode {
                case 0:
                    cont.resume()
                case ShellRunner.launchFailedExitCode:
                    cont.resume(throwing: ShellError.launchFailed(
                        "yt-dlp could not be launched (\(ytDlp)). Check Settings → Dependencies."))
                case ShellRunner.stalledExitCode:
                    cont.resume(throwing: ShellError.stalled(Int(inactivityTimeout)))
                default:
                    cont.resume(throwing: ShellError.nonZeroExit(exitCode, errorLines.summary))
                }
            }
            item.activeProcess = process
        }

        guard FileManager.default.fileExists(atPath: outputPath) else {
            throw ShellError.nonZeroExit(0, "yt-dlp reported success but no file was written")
        }

        // Extract duration with ffprobe
        let duration = await extractDuration(from: outputPath)

        // yt-dlp writes the thumbnail next to the video as <videoBase>.<ext>.
        // Move it to thumbnailPath so the UI can find it via the standard path.
        // YouTube serves WebP; --convert-thumbnails jpg converts it, but we
        // check both extensions in case ffmpeg wasn't available for conversion.
        let videoBase = (outputPath as NSString).deletingPathExtension
        let ytThumbCandidates = [videoBase + ".jpg", videoBase + ".webp", videoBase + ".png"]
        for src in ytThumbCandidates {
            if FileManager.default.fileExists(atPath: src) {
                try? FileManager.default.removeItem(atPath: thumbnailPath) // clear any old thumbnail
                try? FileManager.default.moveItem(atPath: src, toPath: thumbnailPath)
                AppLogger.info("Thumbnail moved from yt-dlp for \(video.youtubeVideoId)")
                break
            }
        }
        // Remove any leftover sibling thumbnails so the videos folder only
        // holds videos.
        for src in ytThumbCandidates where FileManager.default.fileExists(atPath: src) {
            try? FileManager.default.removeItem(atPath: src)
        }

        // Fall back to ffmpeg frame extraction only if yt-dlp didn't produce a thumbnail.
        if !FileManager.default.fileExists(atPath: thumbnailPath) {
            AppLogger.info("Falling back to ffmpeg thumbnail for \(video.youtubeVideoId)")
            try? await ThumbnailService.extract(videoPath: outputPath, outputPath: thumbnailPath)
        }

        updatedVideo.localFilePath = outputPath
        updatedVideo.thumbnailPath = FileManager.default.fileExists(atPath: thumbnailPath) ? thumbnailPath : ""
        updatedVideo.thumbnailVersion = video.thumbnailVersion + 1
        updatedVideo.durationSeconds = duration
        updatedVideo.downloadState = .ready
        updatedVideo.downloadProgress = 1.0
        updatedVideo.downloadError = nil
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
        ], timeout: 60)
        return output.flatMap { Double($0) } ?? 0
    }

    // M4 fix: Resolve via `which` (honors $PATH, MacPorts, nix, custom prefixes)
    // and cache the result. Cache is seeded eagerly by resolveToolPaths() and
    // populated lazily otherwise; sync findX() returns the cached value or the
    // fallback path so call sites inside downloadVideo() stay synchronous.
    private var cachedYtDlpPath: String?
    private var cachedFfprobePath: String?

    private func findYtDlp() -> String {
        if let cached = cachedYtDlpPath { return cached }
        let fallback = ["/opt/homebrew/bin/yt-dlp", "/usr/local/bin/yt-dlp"]
            .first { FileManager.default.isExecutableFile(atPath: $0) } ?? "yt-dlp"
        cachedYtDlpPath = fallback
        return fallback
    }

    private func findFfprobe() -> String {
        if let cached = cachedFfprobePath { return cached }
        let fallback = ["/opt/homebrew/bin/ffprobe", "/usr/local/bin/ffprobe"]
            .first { FileManager.default.isExecutableFile(atPath: $0) } ?? "ffprobe"
        cachedFfprobePath = fallback
        return fallback
    }

    /// Resolves yt-dlp / ffprobe through `which` so non-standard installs
    /// (pipx, MacPorts, nix) work. Called at launch and after a dependency
    /// check; safe to call repeatedly.
    func resolveToolPaths() async {
        cachedYtDlpPath = await ShellRunner.resolveBinary("yt-dlp", fallbacks: [
            "/opt/homebrew/bin/yt-dlp", "/usr/local/bin/yt-dlp",
        ])
        cachedFfprobePath = await ShellRunner.resolveBinary("ffprobe", fallbacks: [
            "/opt/homebrew/bin/ffprobe", "/usr/local/bin/ffprobe",
        ])
    }

    /// Re-fetches YouTube thumbnails for already-downloaded videos using yt-dlp.
    /// Called after a channel sync so existing videos get proper YouTube
    /// thumbnails instead of ffmpeg frame extractions (or missing thumbs).
    func refreshThumbnails(for videosToRefresh: [Video], channel: Channel) async {
        guard let rootFolder = appState?.settings.downloadFolderPath else { return }
        let thumbsDir = channel.thumbnailsPath(rootFolder: rootFolder)
        try? FileManager.default.createDirectory(atPath: thumbsDir, withIntermediateDirectories: true)

        let ytDlp = findYtDlp()

        for video in videosToRefresh where !video.youtubeVideoId.isEmpty {
            let thumbnailPath = ThumbnailService.thumbnailPath(for: video, channel: channel, rootFolder: rootFolder)
            let videoURL = "https://www.youtube.com/watch?v=\(video.youtubeVideoId)"

            // Use a temp base path in the thumbnails dir so yt-dlp writes
            // <tempBase>.jpg (or .webp) right where we can find it.
            let tempBase = (thumbsDir as NSString).appendingPathComponent("refresh_\(video.youtubeVideoId)")

            _ = try? await ShellRunner.run(ytDlp, args: [
                "--skip-download",
                "--write-thumbnail",
                "--convert-thumbnails", "jpg",
                "--no-playlist",
                "--no-warnings",
                "-o", tempBase,
                videoURL
            ], timeout: 30)

            // yt-dlp appends the extension — check .jpg then .webp fallback.
            let candidates = [tempBase + ".jpg", tempBase + ".webp", tempBase + ".png"]
            guard let src = candidates.first(where: { FileManager.default.fileExists(atPath: $0) }) else {
                AppLogger.info("Thumbnail refresh failed for \(video.youtubeVideoId)")
                continue
            }

            try? FileManager.default.removeItem(atPath: thumbnailPath)
            try? FileManager.default.moveItem(atPath: src, toPath: thumbnailPath)

            guard FileManager.default.fileExists(atPath: thumbnailPath) else { continue }

            if var v = appState?.videoById(video.id) {
                v.thumbnailPath = thumbnailPath
                v.thumbnailVersion += 1   // bumps the localtube-thumb:// URL for cache busting
                appState?.updateVideoAndPersist(v, context: "refreshThumbnail")
            }
        }
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
            "--no-warnings",
            url
        ], timeout: 90)
        let raw = output?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        // yt-dlp outputs "NA" when a field is unavailable
        guard !raw.isEmpty, raw != "NA" else { return "" }
        // Decode any residual HTML entities yt-dlp may leave in titles
        // (e.g. &amp; → & , &quot; → " , &#39; → ')
        return raw.htmlEntityDecoded
    }
}

// MARK: - Error line collector
//
// Keeps the last few "ERROR:" lines yt-dlp printed so a failed download
// shows *why* it failed ("Video unavailable", "Sign in to confirm your
// age", …) instead of a generic "yt-dlp download failed".

private final class ErrorLineCollector: @unchecked Sendable {
    private let lock = NSLock()
    private var lines: [String] = []

    func record(_ line: String) {
        let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.hasPrefix("ERROR") || trimmed.lowercased().contains("error:") else { return }
        lock.lock()
        lines.append(trimmed)
        if lines.count > 3 { lines.removeFirst(lines.count - 3) }
        lock.unlock()
    }

    var summary: String {
        lock.lock(); defer { lock.unlock() }
        if lines.isEmpty { return "yt-dlp download failed" }
        return lines.joined(separator: " · ")
            .replacingOccurrences(of: "ERROR: ", with: "")
    }
}
