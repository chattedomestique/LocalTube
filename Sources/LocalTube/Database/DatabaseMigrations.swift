import Foundation
import SQLite3

// MARK: - Database Migrations

enum DatabaseMigrations {
    static func run(db: OpaquePointer) throws {
        let currentVersion = getUserVersion(db: db)
        if currentVersion < 1 {
            try migration1CreateTables(db: db)
            setUserVersion(db: db, version: 1)
        }
        if currentVersion < 2 {
            try migration2AddChannelBanner(db: db)
            setUserVersion(db: db, version: 2)
        }
        if currentVersion < 3 {
            try migration3AddThumbnailVersion(db: db)
            setUserVersion(db: db, version: 3)
        }
        if currentVersion < 4 {
            try migration4AddVideosSortIndex(db: db)
            setUserVersion(db: db, version: 4)
        }
        if currentVersion < 5 {
            try migration5AddProfiles(db: db)
            setUserVersion(db: db, version: 5)
        }
        if currentVersion < 6 {
            try migration6AddProfileIconColor(db: db)
            setUserVersion(db: db, version: 6)
        }
        if currentVersion < 7 {
            try migration7SyncStateAndFavorites(db: db)
            setUserVersion(db: db, version: 7)
        }
        if currentVersion < 8 {
            try migration8HiddenChannels(db: db)
            setUserVersion(db: db, version: 8)
        }
        if currentVersion < 9 {
            try migration9Playlists(db: db)
            setUserVersion(db: db, version: 9)
        }
    }

    // MARK: - Version Tracking

    private static func getUserVersion(db: OpaquePointer) -> Int {
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, "PRAGMA user_version;", -1, &stmt, nil) == SQLITE_OK else {
            return 0
        }
        defer { sqlite3_finalize(stmt) }
        guard sqlite3_step(stmt) == SQLITE_ROW else { return 0 }
        return Int(sqlite3_column_int(stmt, 0))
    }

    // C6 fix: Avoid string interpolation for SQL. PRAGMA user_version doesn't
    // support bind parameters, so we validate the integer range and use a
    // hardcoded format string that cannot inject arbitrary SQL.
    private static func setUserVersion(db: OpaquePointer, version: Int) {
        guard version >= 0, version <= 9999 else {
            AppLogger.error("DatabaseMigrations: version \(version) out of range")
            return
        }
        let sql = String(format: "PRAGMA user_version = %d;", Int32(version))
        sqlite3_exec(db, sql, nil, nil, nil)
    }

    // MARK: - Migration 1: Initial Schema

    private static func migration1CreateTables(db: OpaquePointer) throws {
        let sql = """
        BEGIN TRANSACTION;

        CREATE TABLE IF NOT EXISTS channels (
            id TEXT PRIMARY KEY NOT NULL,
            display_name TEXT NOT NULL,
            emoji TEXT,
            type TEXT NOT NULL,
            youtube_channel_id TEXT,
            folder_name TEXT NOT NULL,
            sort_order INTEGER NOT NULL DEFAULT 0,
            created_at REAL NOT NULL
        );

        CREATE TABLE IF NOT EXISTS videos (
            id TEXT PRIMARY KEY NOT NULL,
            channel_id TEXT NOT NULL,
            youtube_video_id TEXT NOT NULL,
            title TEXT NOT NULL,
            local_file_path TEXT NOT NULL DEFAULT '',
            thumbnail_path TEXT NOT NULL DEFAULT '',
            downloaded_at REAL NOT NULL,
            duration_seconds REAL NOT NULL DEFAULT 0,
            resume_position_seconds REAL NOT NULL DEFAULT 0,
            download_state TEXT NOT NULL DEFAULT 'queued',
            download_progress REAL NOT NULL DEFAULT 0,
            download_error TEXT,
            sort_order INTEGER NOT NULL DEFAULT 0,
            FOREIGN KEY (channel_id) REFERENCES channels(id) ON DELETE CASCADE
        );

        CREATE INDEX IF NOT EXISTS idx_videos_channel_id ON videos(channel_id);
        CREATE INDEX IF NOT EXISTS idx_videos_youtube_id ON videos(youtube_video_id);

        COMMIT;
        """
        try exec(db: db, sql: sql)
    }

    // MARK: - Migration 2: Add channel banner_path

    private static func migration2AddChannelBanner(db: OpaquePointer) throws {
        try exec(db: db, sql: "ALTER TABLE channels ADD COLUMN banner_path TEXT NOT NULL DEFAULT '';")
    }

    // MARK: - Migration 3: Add thumbnail_version for cache-busting

    private static func migration3AddThumbnailVersion(db: OpaquePointer) throws {
        try exec(db: db, sql: "ALTER TABLE videos ADD COLUMN thumbnail_version INTEGER NOT NULL DEFAULT 0;")
    }

    // MARK: - Migration 4: Composite index for the hot-path videos query
    //
    // fetchVideos(forChannelId:) filters by channel_id and orders by sort_order.
    // The existing idx_videos_channel_id covers the WHERE but forces a sort step
    // for each channel page load; adding sort_order to the index lets SQLite
    // satisfy the ORDER BY from the index directly.

    private static func migration4AddVideosSortIndex(db: OpaquePointer) throws {
        try exec(db: db, sql: "CREATE INDEX IF NOT EXISTS idx_videos_channel_sort ON videos(channel_id, sort_order);")
    }

    // MARK: - Migration 5: Profiles + profile_channels junction
    //
    // Profiles let families curate per-kid views of the library. Each
    // profile is assigned a subset of channels through the junction table.
    // ON DELETE CASCADE on both FKs keeps the junction clean when either
    // side is deleted — no orphaned assignments to garbage-collect.

    private static func migration5AddProfiles(db: OpaquePointer) throws {
        let sql = """
        BEGIN TRANSACTION;

        CREATE TABLE IF NOT EXISTS profiles (
            id TEXT PRIMARY KEY NOT NULL,
            name TEXT NOT NULL,
            emoji TEXT,
            sort_order INTEGER NOT NULL DEFAULT 0,
            created_at REAL NOT NULL
        );

        CREATE TABLE IF NOT EXISTS profile_channels (
            profile_id TEXT NOT NULL,
            channel_id TEXT NOT NULL,
            sort_order INTEGER NOT NULL DEFAULT 0,
            PRIMARY KEY (profile_id, channel_id),
            FOREIGN KEY (profile_id) REFERENCES profiles(id) ON DELETE CASCADE,
            FOREIGN KEY (channel_id) REFERENCES channels(id) ON DELETE CASCADE
        );

        CREATE INDEX IF NOT EXISTS idx_profile_channels_profile ON profile_channels(profile_id);

        COMMIT;
        """
        try exec(db: db, sql: sql)
    }

    // MARK: - Migration 6: Profile icon + color
    //
    // Adds Phosphor icon name + soft-palette color key per profile. Both
    // nullable — legacy profiles (emoji-only) keep rendering via the
    // ProfileAvatar fallback chain.

    private static func migration6AddProfileIconColor(db: OpaquePointer) throws {
        try exec(db: db, sql: "ALTER TABLE profiles ADD COLUMN icon TEXT;")
        try exec(db: db, sql: "ALTER TABLE profiles ADD COLUMN color TEXT;")
    }

    // MARK: - Migration 7: Channel sync state + per-profile favorites
    //
    // - Channels get last_synced_at + last_sync_error so the UI can show
    //   "Last synced 2 min ago" or surface the failure reason. Previously
    //   ChannelSyncService swallowed errors into the log; now we keep
    //   them on the channel record itself.
    // - profile_favorites: M:N junction. Per-profile per-video. Two
    //   profiles assigned the same channel maintain independent favorite
    //   lists. ON DELETE CASCADE on both FKs keeps it self-cleaning.

    // MARK: - Migration 8: Per-profile hidden channels
    //
    // Distinct from removing a channel from a profile (which deletes the
    // profile_channels row). Hiding keeps the assignment but flags the
    // channel as not-visible in the viewer. Easy to unhide; parents may
    // want to temporarily de-clutter without re-doing setup.
    // CASCADE on both FKs keeps this junction self-cleaning.

    // MARK: - Migration 9: Playlists + per-profile playback prefs
    //
    // playlists: profile-scoped ordered video lists. is_system flags the
    // auto-created "Up Next" queue. playlist_videos: the ordered
    // membership. Two new profile columns: active_playlist_id (which
    // playlist the tray shows / plays) and auto_playback_mode (Phase 4).
    //
    // The "Up Next" system playlist isn't seeded here — SQLite can't
    // generate UUIDs in pure SQL. LibraryStore.ensureUpNextPlaylists()
    // creates one per profile on load (and at profile-creation time),
    // which also covers profiles added after this migration runs.

    private static func migration9Playlists(db: OpaquePointer) throws {
        let sql = """
        BEGIN TRANSACTION;

        CREATE TABLE IF NOT EXISTS playlists (
            id TEXT PRIMARY KEY NOT NULL,
            profile_id TEXT NOT NULL,
            name TEXT NOT NULL,
            sort_order INTEGER NOT NULL DEFAULT 0,
            created_at REAL NOT NULL,
            is_system INTEGER NOT NULL DEFAULT 0,
            FOREIGN KEY (profile_id) REFERENCES profiles(id) ON DELETE CASCADE
        );

        CREATE INDEX IF NOT EXISTS idx_playlists_profile ON playlists(profile_id);

        CREATE TABLE IF NOT EXISTS playlist_videos (
            playlist_id TEXT NOT NULL,
            video_id TEXT NOT NULL,
            sort_order INTEGER NOT NULL,
            added_at REAL NOT NULL,
            PRIMARY KEY (playlist_id, video_id),
            FOREIGN KEY (playlist_id) REFERENCES playlists(id) ON DELETE CASCADE,
            FOREIGN KEY (video_id) REFERENCES videos(id) ON DELETE CASCADE
        );

        CREATE INDEX IF NOT EXISTS idx_playlist_videos_playlist ON playlist_videos(playlist_id);

        COMMIT;
        """
        try exec(db: db, sql: sql)
        try exec(db: db, sql: "ALTER TABLE profiles ADD COLUMN active_playlist_id TEXT;")
        try exec(db: db, sql: "ALTER TABLE profiles ADD COLUMN auto_playback_mode TEXT;")
    }

    private static func migration8HiddenChannels(db: OpaquePointer) throws {
        let sql = """
        BEGIN TRANSACTION;

        CREATE TABLE IF NOT EXISTS profile_hidden_channels (
            profile_id TEXT NOT NULL,
            channel_id TEXT NOT NULL,
            hidden_at REAL NOT NULL,
            PRIMARY KEY (profile_id, channel_id),
            FOREIGN KEY (profile_id) REFERENCES profiles(id) ON DELETE CASCADE,
            FOREIGN KEY (channel_id) REFERENCES channels(id) ON DELETE CASCADE
        );

        CREATE INDEX IF NOT EXISTS idx_phc_profile ON profile_hidden_channels(profile_id);

        COMMIT;
        """
        try exec(db: db, sql: sql)
    }

    private static func migration7SyncStateAndFavorites(db: OpaquePointer) throws {
        try exec(db: db, sql: "ALTER TABLE channels ADD COLUMN last_synced_at REAL;")
        try exec(db: db, sql: "ALTER TABLE channels ADD COLUMN last_sync_error TEXT;")

        let sql = """
        BEGIN TRANSACTION;

        CREATE TABLE IF NOT EXISTS profile_favorites (
            profile_id TEXT NOT NULL,
            video_id TEXT NOT NULL,
            created_at REAL NOT NULL,
            PRIMARY KEY (profile_id, video_id),
            FOREIGN KEY (profile_id) REFERENCES profiles(id) ON DELETE CASCADE,
            FOREIGN KEY (video_id) REFERENCES videos(id) ON DELETE CASCADE
        );

        CREATE INDEX IF NOT EXISTS idx_profile_favorites_profile ON profile_favorites(profile_id);

        COMMIT;
        """
        try exec(db: db, sql: sql)
    }

    // MARK: - Helpers

    private static func exec(db: OpaquePointer, sql: String) throws {
        var errMsg: UnsafeMutablePointer<CChar>?
        let rc = sqlite3_exec(db, sql, nil, nil, &errMsg)
        if rc != SQLITE_OK {
            let msg = errMsg.map { String(cString: $0) } ?? "Unknown error"
            sqlite3_free(errMsg)
            throw DatabaseError.execFailed(msg)
        }
    }
}

// MARK: - Database Error

enum DatabaseError: Error, LocalizedError {
    case openFailed(String)
    case prepareFailed(String)
    case execFailed(String)
    case notFound

    var errorDescription: String? {
        switch self {
        case .openFailed(let msg): return "Failed to open database: \(msg)"
        case .prepareFailed(let msg): return "Failed to prepare statement: \(msg)"
        case .execFailed(let msg): return "SQL execution failed: \(msg)"
        case .notFound: return "Record not found"
        }
    }
}
