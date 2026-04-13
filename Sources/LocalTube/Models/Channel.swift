import Foundation

// MARK: - Channel Type
enum ChannelType: String, Codable, Sendable {
    case source  // Type A: mirrors a YouTube channel
    case custom  // Type B: curated mix from any channels
}

// MARK: - Channel
struct Channel: Identifiable, Codable, Hashable, Sendable {
    let id: UUID
    var displayName: String
    var emoji: String?
    var type: ChannelType
    /// YouTube channel ID (e.g. UCxxxx or @handle). Only set for Type A.
    var youtubeChannelId: String?
    /// Filesystem-safe folder name. Set at creation; never changed (avoids broken paths).
    let folderName: String
    var sortOrder: Int
    let createdAt: Date
    var bannerPath: String

    // MARK: - Computed

    // M1 fix: Sanitize folderName to prevent path traversal
    var sanitizedFolderName: String {
        folderName
            .replacingOccurrences(of: "..", with: "")
            .replacingOccurrences(of: "/", with: "")
            .replacingOccurrences(of: "\\", with: "")
            .filter { $0.isLetter || $0.isNumber || $0 == "-" || $0 == "_" }
    }

    /// The channel's videos folder path relative to the root download folder.
    func videosPath(rootFolder: String) -> String {
        (rootFolder as NSString).appendingPathComponent("\(sanitizedFolderName)/videos")
    }

    /// The channel's thumbnails folder path relative to the root download folder.
    func thumbnailsPath(rootFolder: String) -> String {
        (rootFolder as NSString).appendingPathComponent("\(sanitizedFolderName)/thumbnails")
    }

    /// The channel's banner file path relative to the root download folder.
    func bannerFilePath(rootFolder: String) -> String {
        (rootFolder as NSString).appendingPathComponent("\(sanitizedFolderName)/banner.jpg")
    }

    // MARK: - Init

    init(
        id: UUID = UUID(),
        displayName: String,
        emoji: String? = nil,
        type: ChannelType,
        youtubeChannelId: String? = nil,
        folderName: String,
        sortOrder: Int = 0,
        createdAt: Date = Date(),
        bannerPath: String = ""
    ) {
        self.id = id
        self.displayName = displayName
        self.emoji = emoji
        self.type = type
        self.youtubeChannelId = youtubeChannelId
        self.folderName = folderName
        self.sortOrder = sortOrder
        self.createdAt = createdAt
        self.bannerPath = bannerPath
    }

    // MARK: - Display

    var displayLabel: String {
        if let emoji = emoji {
            return "\(emoji) \(displayName)"
        }
        return displayName
    }
}
