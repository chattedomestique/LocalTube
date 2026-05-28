import Foundation

// MARK: - Playlist
//
// A profile-scoped, ordered list of videos. Every profile has one
// `isSystem` playlist named "Up Next" (auto-created, cannot be renamed
// or deleted, but can be cleared) plus any number of named playlists.
// Exactly one playlist per profile is "active" at a time — that's what
// the slide-out tray shows and what plays through.
//
// Permission model: adults curate (edit layer / admin); kids consume
// (read-only tray). See EDITING_MODEL.md and PLAYLISTS_PLAN.md.
struct Playlist: Identifiable, Codable, Hashable, Sendable {
    let id: UUID
    let profileId: UUID
    var name: String
    var sortOrder: Int
    let createdAt: Date
    /// The auto-created "Up Next" playlist. Can't be renamed/deleted.
    let isSystem: Bool

    init(
        id: UUID = UUID(),
        profileId: UUID,
        name: String,
        sortOrder: Int = 0,
        createdAt: Date = Date(),
        isSystem: Bool = false
    ) {
        self.id = id
        self.profileId = profileId
        self.name = name
        self.sortOrder = sortOrder
        self.createdAt = createdAt
        self.isSystem = isSystem
    }
}
