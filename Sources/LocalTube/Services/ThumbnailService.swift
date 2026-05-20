import Foundation
import AppKit

enum ThumbnailService {
    /// Extracts a thumbnail frame from a video file using ffmpeg.
    /// Seeks to 1s rather than 5s so the frame extraction succeeds for short
    /// clips (intros, shorts, sub-5-second videos) that would otherwise hit
    /// EOF and produce a black image.
    @discardableResult
    static func extract(
        videoPath: String,
        outputPath: String
    ) async throws -> String {
        let ffmpegPath = await findFfmpeg()
        _ = try await ShellRunner.run(ffmpegPath, args: [
            "-y",
            "-i", videoPath,
            "-ss", "1",
            "-vframes", "1",
            "-q:v", "2",
            outputPath
        ])
        return outputPath
    }

    /// Loads a thumbnail image from disk. Returns nil if file doesn't exist.
    static func image(atPath path: String) -> NSImage? {
        guard !path.isEmpty, FileManager.default.fileExists(atPath: path) else { return nil }
        return NSImage(contentsOfFile: path)
    }

    // MARK: - Path Helpers

    static func thumbnailPath(
        for video: Video,
        channel: Channel,
        rootFolder: String
    ) -> String {
        let dir = channel.thumbnailsPath(rootFolder: rootFolder)
        return (dir as NSString).appendingPathComponent("\(video.id.uuidString).jpg")
    }

    private static func findFfmpeg() async -> String {
        await ShellRunner.resolveBinary("ffmpeg", fallbacks: [
            "/opt/homebrew/bin/ffmpeg",
            "/usr/local/bin/ffmpeg",
            "/usr/bin/ffmpeg",
        ])
    }
}
