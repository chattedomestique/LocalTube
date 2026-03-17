import Foundation
import AppKit

enum ThumbnailService {
    /// Extracts a thumbnail frame at t=5s from a video file using ffmpeg.
    /// Returns the path to the created thumbnail.
    @discardableResult
    static func extract(
        videoPath: String,
        outputPath: String
    ) async throws -> String {
        let ffmpegPath = findFfmpeg()
        _ = try await ShellRunner.run(ffmpegPath, args: [
            "-y",                       // overwrite without asking
            "-i", videoPath,
            "-ss", "5",                 // seek to 5 seconds
            "-vframes", "1",            // extract 1 frame
            "-q:v", "2",                // quality (2 = near-lossless JPEG)
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

    private static func findFfmpeg() -> String {
        let candidates = ["/opt/homebrew/bin/ffmpeg", "/usr/local/bin/ffmpeg", "/usr/bin/ffmpeg"]
        return candidates.first { FileManager.default.fileExists(atPath: $0) } ?? "ffmpeg"
    }
}
