import Foundation

// MARK: - Download State
enum DownloadState: String, Codable, Sendable, Equatable {
    case queued
    case downloading
    case ready
    case error
}

// MARK: - Video
struct Video: Identifiable, Codable, Hashable, Sendable {
    let id: UUID
    let channelId: UUID
    let youtubeVideoId: String
    var title: String
    var localFilePath: String
    var thumbnailPath: String
    var downloadedAt: Date
    var durationSeconds: Double
    var resumePositionSeconds: Double
    var downloadState: DownloadState
    var downloadProgress: Double   // 0.0 – 1.0, used when state == .downloading
    var downloadError: String?     // set when state == .error
    var sortOrder: Int

    // MARK: - Computed

    var isPlayable: Bool {
        downloadState == .ready && FileManager.default.fileExists(atPath: localFilePath)
    }

    var formattedDuration: String {
        DurationFormatter.format(seconds: durationSeconds)
    }

    // MARK: - Init

    init(
        id: UUID = UUID(),
        channelId: UUID,
        youtubeVideoId: String,
        title: String,
        localFilePath: String = "",
        thumbnailPath: String = "",
        downloadedAt: Date = Date(),
        durationSeconds: Double = 0,
        resumePositionSeconds: Double = 0,
        downloadState: DownloadState = .queued,
        downloadProgress: Double = 0,
        downloadError: String? = nil,
        sortOrder: Int = 0
    ) {
        self.id = id
        self.channelId = channelId
        self.youtubeVideoId = youtubeVideoId
        self.title = title
        self.localFilePath = localFilePath
        self.thumbnailPath = thumbnailPath
        self.downloadedAt = downloadedAt
        self.durationSeconds = durationSeconds
        self.resumePositionSeconds = resumePositionSeconds
        self.downloadState = downloadState
        self.downloadProgress = downloadProgress
        self.downloadError = downloadError
        self.sortOrder = sortOrder
    }
}

// MARK: - Duration Formatter (used by Video.formattedDuration)
// Full implementation lives in Utilities/DurationFormatter.swift
// Forward declaration used here to avoid circular dependencies.
enum DurationFormatter {
    static func format(seconds: Double) -> String {
        guard seconds > 0 else { return "0:00" }
        let total = Int(seconds)
        let h = total / 3600
        let m = (total % 3600) / 60
        let s = total % 60
        if h > 0 {
            return String(format: "%d:%02d:%02d", h, m, s)
        }
        return String(format: "%d:%02d", m, s)
    }
}
