import Foundation

// MARK: - Profile
//
// A profile is a named, emoji-tagged "view" of the library. Each profile
// is assigned a subset of channels (via the profile_channels junction
// table); when that profile is active, Viewer Mode only shows those
// channels. Editor Mode is profile-agnostic — parents always see
// everything.
//
// If no profiles exist, the app falls back to "all channels visible"
// mode (existing installs keep working with no migration friction).
struct Profile: Identifiable, Codable, Hashable, Sendable {
    let id: UUID
    var name: String
    var emoji: String?
    var sortOrder: Int
    let createdAt: Date

    init(
        id: UUID = UUID(),
        name: String,
        emoji: String? = nil,
        sortOrder: Int = 0,
        createdAt: Date = Date()
    ) {
        self.id = id
        self.name = name
        self.emoji = emoji
        self.sortOrder = sortOrder
        self.createdAt = createdAt
    }
}
