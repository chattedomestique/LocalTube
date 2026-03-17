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

    // MARK: - Computed

    /// The channel's videos folder path relative to the root download folder.
    func videosPath(rootFolder: String) -> String {
        (rootFolder as NSString).appendingPathComponent("\(folderName)/videos")
    }

    /// The channel's thumbnails folder path relative to the root download folder.
    func thumbnailsPath(rootFolder: String) -> String {
        (rootFolder as NSString).appendingPathComponent("\(folderName)/thumbnails")
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
        createdAt: Date = Date()
    ) {
        self.id = id
        self.displayName = displayName
        self.emoji = emoji
        self.type = type
        self.youtubeChannelId = youtubeChannelId
        self.folderName = folderName
        self.sortOrder = sortOrder
        self.createdAt = createdAt
    }

    // MARK: - Display

    var displayLabel: String {
        if let emoji = emoji {
            return "\(emoji) \(displayName)"
        }
        return displayName
    }
}
