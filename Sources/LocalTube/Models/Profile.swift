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
    /// Phosphor icon name (e.g. "Heart", "Rocket"). Resolved client-side.
    var icon: String?
    /// Profile color key (e.g. "coral", "sky") from PROFILE_COLORS.
    var color: String?
    var sortOrder: Int
    let createdAt: Date

    init(
        id: UUID = UUID(),
        name: String,
        emoji: String? = nil,
        icon: String? = nil,
        color: String? = nil,
        sortOrder: Int = 0,
        createdAt: Date = Date()
    ) {
        self.id = id
        self.name = name
        self.emoji = emoji
        self.icon = icon
        self.color = color
        self.sortOrder = sortOrder
        self.createdAt = createdAt
    }
}
