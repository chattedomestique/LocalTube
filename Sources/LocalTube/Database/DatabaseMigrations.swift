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
