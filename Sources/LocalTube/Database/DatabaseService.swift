import Foundation
import SQLite3

// MARK: - Database Service

actor DatabaseService {
    private var db: OpaquePointer?
    static let shared = DatabaseService()

    private init() {}

    // MARK: - Setup

    private(set) var isOpen = false

    func open() throws {
        if isOpen { return }
        let dbURL = try AppSupportDirectory.databaseURL()
        guard sqlite3_open(dbURL.path, &db) == SQLITE_OK else {
            let msg = db.map { String(cString: sqlite3_errmsg($0)) } ?? "Unknown"
            if let handle = db { sqlite3_close(handle) }
            db = nil
            throw DatabaseError.openFailed(msg)
        }
        // Enable WAL mode and foreign keys
        sqlite3_exec(db, "PRAGMA journal_mode=WAL;", nil, nil, nil)
        sqlite3_exec(db, "PRAGMA foreign_keys=ON;", nil, nil, nil)
        // Wait up to 5 s for a lock held by another process (a previous
        // instance still shutting down) instead of failing immediately.
        sqlite3_busy_timeout(db, 5000)
        guard let db = db else { throw DatabaseError.openFailed("db is nil") }

        // Snapshot the database before any schema migration so the user can
        // roll back to the previous build if this one misbehaves. A fresh
        // (version 0) database has nothing worth backing up.
        let onDisk = DatabaseMigrations.currentVersion(db: db)
        if onDisk > 0 && onDisk < DatabaseMigrations.latestVersion {
            do {
                let url = try backupDatabase(label: "pre-migration-v\(onDisk)")
                AppLogger.info("Database backed up before migration: \(url.path)")
            } catch {
                // A failed backup must not block launch, but it must be loud.
                AppLogger.error("Database backup before migration failed: \(error.localizedDescription)")
            }
        }

        try DatabaseMigrations.run(db: db)
        isOpen = true
    }

    // MARK: - Backups
    //
    // Uses SQLite's online backup API, which produces a consistent copy
    // even while in WAL mode (a plain file copy would miss the WAL tail).
    // Keeps the newest `maxBackups` snapshots and prunes the rest.

    private static let maxBackups = 10

    @discardableResult
    func backupDatabase(label: String) throws -> URL {
        guard let db else { throw DatabaseError.openFailed("Not opened") }
        let dir = try AppSupportDirectory.backupsDirectory()
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyyMMdd-HHmmss"
        let safeLabel = label.filter { $0.isLetter || $0.isNumber || $0 == "-" || $0 == "_" }
        let dest = dir.appendingPathComponent("library-\(safeLabel)-\(formatter.string(from: Date())).sqlite")

        var backupDb: OpaquePointer?
        guard sqlite3_open(dest.path, &backupDb) == SQLITE_OK, let backupHandle = backupDb else {
            let msg = backupDb.map { String(cString: sqlite3_errmsg($0)) } ?? "Unknown"
            if let handle = backupDb { sqlite3_close(handle) }
            throw DatabaseError.openFailed("backup target: \(msg)")
        }
        defer { sqlite3_close(backupHandle) }

        guard let backup = sqlite3_backup_init(backupHandle, "main", db, "main") else {
            throw DatabaseError.execFailed("backup init: \(String(cString: sqlite3_errmsg(backupHandle)))")
        }
        let stepRC = sqlite3_backup_step(backup, -1)
        let finishRC = sqlite3_backup_finish(backup)
        guard stepRC == SQLITE_DONE, finishRC == SQLITE_OK else {
            try? FileManager.default.removeItem(at: dest)
            throw DatabaseError.execFailed("backup step rc=\(stepRC) finish rc=\(finishRC)")
        }

        pruneBackups(in: dir)
        return dest
    }

    private func pruneBackups(in dir: URL) {
        guard let items = try? FileManager.default.contentsOfDirectory(
            at: dir, includingPropertiesForKeys: [.contentModificationDateKey], options: [.skipsHiddenFiles]
        ) else { return }
        let snapshots = items
            .filter { $0.lastPathComponent.hasPrefix("library-") && $0.pathExtension == "sqlite" }
            .sorted { a, b in
                let dateA = (try? a.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? Date.distantPast
                let dateB = (try? b.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? Date.distantPast
                return dateA > dateB
            }
        guard snapshots.count > Self.maxBackups else { return }
        for old in snapshots[Self.maxBackups...] {
            try? FileManager.default.removeItem(at: old)
        }
    }

    // MARK: - Path relocation
    //
    // Rewrites every stored absolute path that begins with `oldPrefix` so
    // it begins with `newPrefix` instead. Both prefixes must end with "/"
    // so "/Volumes/Lib" never matches "/Volumes/Library". Uses substr()
    // rather than LIKE because paths routinely contain `_` and `%`.
    // Runs inside one transaction and returns the number of rows touched.

    func rewritePathPrefix(from oldPrefix: String, to newPrefix: String) throws -> Int {
        guard let db else { throw DatabaseError.openFailed("Not opened") }
        guard oldPrefix.hasSuffix("/"), newPrefix.hasSuffix("/") else {
            throw DatabaseError.execFailed("rewritePathPrefix: prefixes must end with '/'")
        }
        let statements = [
            "UPDATE videos SET local_file_path = ? || substr(local_file_path, length(?) + 1) WHERE substr(local_file_path, 1, length(?)) = ?;",
            "UPDATE videos SET thumbnail_path = ? || substr(thumbnail_path, length(?) + 1) WHERE substr(thumbnail_path, 1, length(?)) = ?;",
            "UPDATE channels SET banner_path = ? || substr(banner_path, length(?) + 1) WHERE substr(banner_path, 1, length(?)) = ?;",
        ]
        var total = 0
        try beginTransaction()
        do {
            for sql in statements {
                var stmt: OpaquePointer?
                guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else {
                    throw DatabaseError.prepareFailed(String(cString: sqlite3_errmsg(db)))
                }
                bind(stmt: stmt!, index: 1, text: newPrefix)
                bind(stmt: stmt!, index: 2, text: oldPrefix)
                bind(stmt: stmt!, index: 3, text: oldPrefix)
                bind(stmt: stmt!, index: 4, text: oldPrefix)
                let rc = sqlite3_step(stmt)
                sqlite3_finalize(stmt)
                guard rc == SQLITE_DONE else {
                    throw DatabaseError.execFailed(String(cString: sqlite3_errmsg(db)))
                }
                total += Int(sqlite3_changes(db))
            }
            try commitTransaction()
        } catch {
            rollbackTransaction()
            throw error
        }
        return total
    }

    /// Updates only the two file-location columns of a video. Used by the
    /// verify/heal pass so it doesn't clobber live download progress.
    func updateVideoPaths(id: UUID, localFilePath: String, thumbnailPath: String) throws {
        guard let db else { throw DatabaseError.openFailed("Not opened") }
        let sql = "UPDATE videos SET local_file_path=?, thumbnail_path=? WHERE id=?;"
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else {
            throw DatabaseError.prepareFailed(String(cString: sqlite3_errmsg(db)))
        }
        defer { sqlite3_finalize(stmt) }
        bind(stmt: stmt!, index: 1, text: localFilePath)
        bind(stmt: stmt!, index: 2, text: thumbnailPath)
        bind(stmt: stmt!, index: 3, text: id.uuidString)
        guard sqlite3_step(stmt) == SQLITE_DONE else {
            throw DatabaseError.execFailed(String(cString: sqlite3_errmsg(db)))
        }
    }

    /// Bulk-persists a set of videos in one transaction. Same as
    /// `updateVideosBatched` but tolerant of an empty input.
    func persistVideos(_ videos: [Video]) throws {
        guard !videos.isEmpty else { return }
        try updateVideosBatched(videos)
    }

    // H5 fix: Transaction helpers for multi-step writes
    func beginTransaction() throws {
        guard let db else { throw DatabaseError.openFailed("Not opened") }
        var errMsg: UnsafeMutablePointer<CChar>?
        let rc = sqlite3_exec(db, "BEGIN IMMEDIATE;", nil, nil, &errMsg)
        if rc != SQLITE_OK {
            let msg = errMsg.map { String(cString: $0) } ?? "Unknown"
            sqlite3_free(errMsg)
            throw DatabaseError.execFailed(msg)
        }
    }

    func commitTransaction() throws {
        guard let db else { throw DatabaseError.openFailed("Not opened") }
        var errMsg: UnsafeMutablePointer<CChar>?
        let rc = sqlite3_exec(db, "COMMIT;", nil, nil, &errMsg)
        if rc != SQLITE_OK {
            let msg = errMsg.map { String(cString: $0) } ?? "Unknown"
            sqlite3_free(errMsg)
            throw DatabaseError.execFailed(msg)
        }
    }

    func rollbackTransaction() {
        guard let db else { return }
        sqlite3_exec(db, "ROLLBACK;", nil, nil, nil)
    }

    // H5 fix: Batch helpers that wrap N writes in a single BEGIN/COMMIT so
    // reorder operations are atomic and ~10× faster (one fsync vs. N fsyncs).

    func updateChannelsBatched(_ channels: [Channel]) throws {
        try beginTransaction()
        do {
            for ch in channels { try updateChannel(ch) }
            try commitTransaction()
        } catch {
            rollbackTransaction()
            throw error
        }
    }

    func updateVideosBatched(_ videos: [Video]) throws {
        try beginTransaction()
        do {
            for v in videos { try updateVideo(v) }
            try commitTransaction()
        } catch {
            rollbackTransaction()
            throw error
        }
    }

    // MARK: - Channels

    func fetchAllChannels() throws -> [Channel] {
        guard let db = db else { throw DatabaseError.openFailed("Not opened") }
        let sql = "SELECT id, display_name, emoji, type, youtube_channel_id, folder_name, sort_order, created_at, banner_path, last_synced_at, last_sync_error FROM channels ORDER BY sort_order ASC, created_at ASC;"
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else {
            throw DatabaseError.prepareFailed(String(cString: sqlite3_errmsg(db)))
        }
        defer { sqlite3_finalize(stmt) }

        var channels: [Channel] = []
        while sqlite3_step(stmt) == SQLITE_ROW {
            channels.append(channelFromStatement(stmt!))
        }
        return channels
    }

    func insertChannel(_ channel: Channel) throws {
        guard let db = db else { throw DatabaseError.openFailed("Not opened") }
        let sql = "INSERT INTO channels (id, display_name, emoji, type, youtube_channel_id, folder_name, sort_order, created_at, banner_path) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?);"
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else {
            throw DatabaseError.prepareFailed(String(cString: sqlite3_errmsg(db)))
        }
        defer { sqlite3_finalize(stmt) }

        bind(stmt: stmt!, index: 1, text: channel.id.uuidString)
        bind(stmt: stmt!, index: 2, text: channel.displayName)
        bindNullable(stmt: stmt!, index: 3, text: channel.emoji)
        bind(stmt: stmt!, index: 4, text: channel.type.rawValue)
        bindNullable(stmt: stmt!, index: 5, text: channel.youtubeChannelId)
        bind(stmt: stmt!, index: 6, text: channel.folderName)
        sqlite3_bind_int64(stmt, 7, Int64(channel.sortOrder))
        sqlite3_bind_double(stmt, 8, channel.createdAt.timeIntervalSince1970)
        bind(stmt: stmt!, index: 9, text: channel.bannerPath)

        guard sqlite3_step(stmt) == SQLITE_DONE else {
            throw DatabaseError.execFailed(String(cString: sqlite3_errmsg(db)))
        }
    }

    func updateChannel(_ channel: Channel) throws {
        guard let db = db else { throw DatabaseError.openFailed("Not opened") }
        let sql = "UPDATE channels SET display_name=?, emoji=?, sort_order=?, banner_path=? WHERE id=?;"
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else {
            throw DatabaseError.prepareFailed(String(cString: sqlite3_errmsg(db)))
        }
        defer { sqlite3_finalize(stmt) }

        bind(stmt: stmt!, index: 1, text: channel.displayName)
        bindNullable(stmt: stmt!, index: 2, text: channel.emoji)
        sqlite3_bind_int64(stmt, 3, Int64(channel.sortOrder))
        bind(stmt: stmt!, index: 4, text: channel.bannerPath)
        bind(stmt: stmt!, index: 5, text: channel.id.uuidString)

        guard sqlite3_step(stmt) == SQLITE_DONE else {
            throw DatabaseError.execFailed(String(cString: sqlite3_errmsg(db)))
        }
    }

    func updateChannelBanner(id: UUID, bannerPath: String) throws {
        guard let db = db else { throw DatabaseError.openFailed("Not opened") }
        let sql = "UPDATE channels SET banner_path=? WHERE id=?;"
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else {
            throw DatabaseError.prepareFailed(String(cString: sqlite3_errmsg(db)))
        }
        defer { sqlite3_finalize(stmt) }

        bind(stmt: stmt!, index: 1, text: bannerPath)
        bind(stmt: stmt!, index: 2, text: id.uuidString)

        guard sqlite3_step(stmt) == SQLITE_DONE else {
            throw DatabaseError.execFailed(String(cString: sqlite3_errmsg(db)))
        }
    }

    func deleteChannel(id: UUID) throws {
        guard let db = db else { throw DatabaseError.openFailed("Not opened") }
        let sql = "DELETE FROM channels WHERE id=?;"
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else {
            throw DatabaseError.prepareFailed(String(cString: sqlite3_errmsg(db)))
        }
        defer { sqlite3_finalize(stmt) }
        bind(stmt: stmt!, index: 1, text: id.uuidString)
        guard sqlite3_step(stmt) == SQLITE_DONE else {
            throw DatabaseError.execFailed(String(cString: sqlite3_errmsg(db)))
        }
    }

    // MARK: - Videos

    func fetchVideos(forChannelId channelId: UUID) throws -> [Video] {
        guard let db = db else { throw DatabaseError.openFailed("Not opened") }
        let sql = """
        SELECT id, channel_id, youtube_video_id, title, local_file_path, thumbnail_path,
               downloaded_at, duration_seconds, resume_position_seconds,
               download_state, download_progress, download_error, sort_order, thumbnail_version
        FROM videos WHERE channel_id=? ORDER BY sort_order ASC, downloaded_at ASC;
        """
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else {
            throw DatabaseError.prepareFailed(String(cString: sqlite3_errmsg(db)))
        }
        defer { sqlite3_finalize(stmt) }
        bind(stmt: stmt!, index: 1, text: channelId.uuidString)

        var videos: [Video] = []
        while sqlite3_step(stmt) == SQLITE_ROW {
            videos.append(videoFromStatement(stmt!))
        }
        return videos
    }

    func insertVideo(_ video: Video) throws {
        guard let db = db else { throw DatabaseError.openFailed("Not opened") }
        let sql = """
        INSERT INTO videos (id, channel_id, youtube_video_id, title, local_file_path,
            thumbnail_path, downloaded_at, duration_seconds, resume_position_seconds,
            download_state, download_progress, download_error, sort_order, thumbnail_version)
        VALUES (?,?,?,?,?,?,?,?,?,?,?,?,?,?);
        """
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else {
            throw DatabaseError.prepareFailed(String(cString: sqlite3_errmsg(db)))
        }
        defer { sqlite3_finalize(stmt) }

        bind(stmt: stmt!, index: 1, text: video.id.uuidString)
        bind(stmt: stmt!, index: 2, text: video.channelId.uuidString)
        bind(stmt: stmt!, index: 3, text: video.youtubeVideoId)
        bind(stmt: stmt!, index: 4, text: video.title)
        bind(stmt: stmt!, index: 5, text: video.localFilePath)
        bind(stmt: stmt!, index: 6, text: video.thumbnailPath)
        sqlite3_bind_double(stmt, 7, video.downloadedAt.timeIntervalSince1970)
        sqlite3_bind_double(stmt, 8, video.durationSeconds)
        sqlite3_bind_double(stmt, 9, video.resumePositionSeconds)
        bind(stmt: stmt!, index: 10, text: video.downloadState.rawValue)
        sqlite3_bind_double(stmt, 11, video.downloadProgress)
        bindNullable(stmt: stmt!, index: 12, text: video.downloadError)
        sqlite3_bind_int64(stmt, 13, Int64(video.sortOrder))
        sqlite3_bind_int64(stmt, 14, Int64(video.thumbnailVersion))

        guard sqlite3_step(stmt) == SQLITE_DONE else {
            throw DatabaseError.execFailed(String(cString: sqlite3_errmsg(db)))
        }
    }

    func updateVideo(_ video: Video) throws {
        guard let db = db else { throw DatabaseError.openFailed("Not opened") }
        let sql = """
        UPDATE videos SET title=?, local_file_path=?, thumbnail_path=?,
            duration_seconds=?, resume_position_seconds=?,
            download_state=?, download_progress=?, download_error=?, sort_order=?,
            thumbnail_version=?
        WHERE id=?;
        """
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else {
            throw DatabaseError.prepareFailed(String(cString: sqlite3_errmsg(db)))
        }
        defer { sqlite3_finalize(stmt) }

        bind(stmt: stmt!, index: 1, text: video.title)
        bind(stmt: stmt!, index: 2, text: video.localFilePath)
        bind(stmt: stmt!, index: 3, text: video.thumbnailPath)
        sqlite3_bind_double(stmt, 4, video.durationSeconds)
        sqlite3_bind_double(stmt, 5, video.resumePositionSeconds)
        bind(stmt: stmt!, index: 6, text: video.downloadState.rawValue)
        sqlite3_bind_double(stmt, 7, video.downloadProgress)
        bindNullable(stmt: stmt!, index: 8, text: video.downloadError)
        sqlite3_bind_int64(stmt, 9, Int64(video.sortOrder))
        sqlite3_bind_int64(stmt, 10, Int64(video.thumbnailVersion))
        bind(stmt: stmt!, index: 11, text: video.id.uuidString)

        guard sqlite3_step(stmt) == SQLITE_DONE else {
            throw DatabaseError.execFailed(String(cString: sqlite3_errmsg(db)))
        }
    }

    func deleteVideo(id: UUID) throws {
        guard let db = db else { throw DatabaseError.openFailed("Not opened") }
        let sql = "DELETE FROM videos WHERE id=?;"
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else {
            throw DatabaseError.prepareFailed(String(cString: sqlite3_errmsg(db)))
        }
        defer { sqlite3_finalize(stmt) }
        bind(stmt: stmt!, index: 1, text: id.uuidString)
        guard sqlite3_step(stmt) == SQLITE_DONE else {
            throw DatabaseError.execFailed(String(cString: sqlite3_errmsg(db)))
        }
    }

    func updateResumePosition(videoId: UUID, seconds: Double) throws {
        guard let db = db else { throw DatabaseError.openFailed("Not opened") }
        let sql = "UPDATE videos SET resume_position_seconds=? WHERE id=?;"
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else {
            throw DatabaseError.prepareFailed(String(cString: sqlite3_errmsg(db)))
        }
        defer { sqlite3_finalize(stmt) }
        sqlite3_bind_double(stmt, 1, seconds)
        bind(stmt: stmt!, index: 2, text: videoId.uuidString)
        sqlite3_step(stmt)
    }

    // MARK: - Profiles

    func fetchAllProfiles() throws -> [Profile] {
        guard let db = db else { throw DatabaseError.openFailed("Not opened") }
        let sql = "SELECT id, name, emoji, sort_order, created_at, icon, color, active_playlist_id, auto_playback_mode FROM profiles ORDER BY sort_order ASC, created_at ASC;"
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else {
            throw DatabaseError.prepareFailed(String(cString: sqlite3_errmsg(db)))
        }
        defer { sqlite3_finalize(stmt) }

        var profiles: [Profile] = []
        while sqlite3_step(stmt) == SQLITE_ROW {
            let id = UUID(uuidString: columnText(stmt!, 0)) ?? UUID()
            let name = columnText(stmt!, 1)
            let emoji = columnTextOptional(stmt!, 2)
            let sortOrder = Int(sqlite3_column_int64(stmt!, 3))
            let createdAt = Date(timeIntervalSince1970: sqlite3_column_double(stmt!, 4))
            let icon = columnTextOptional(stmt!, 5)
            let color = columnTextOptional(stmt!, 6)
            let activePlaylistId = columnTextOptional(stmt!, 7).flatMap(UUID.init(uuidString:))
            let autoPlaybackMode = columnTextOptional(stmt!, 8)
            profiles.append(Profile(
                id: id, name: name, emoji: emoji, icon: icon, color: color,
                sortOrder: sortOrder, createdAt: createdAt,
                activePlaylistId: activePlaylistId, autoPlaybackMode: autoPlaybackMode
            ))
        }
        return profiles
    }

    func setActivePlaylist(profileId: UUID, playlistId: UUID?) throws {
        guard let db = db else { throw DatabaseError.openFailed("Not opened") }
        let sql = "UPDATE profiles SET active_playlist_id=? WHERE id=?;"
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else {
            throw DatabaseError.prepareFailed(String(cString: sqlite3_errmsg(db)))
        }
        defer { sqlite3_finalize(stmt) }
        bindNullable(stmt: stmt!, index: 1, text: playlistId?.uuidString)
        bind(stmt: stmt!, index: 2, text: profileId.uuidString)
        guard sqlite3_step(stmt) == SQLITE_DONE else {
            throw DatabaseError.execFailed(String(cString: sqlite3_errmsg(db)))
        }
    }

    func setAutoPlaybackMode(profileId: UUID, mode: String) throws {
        guard let db = db else { throw DatabaseError.openFailed("Not opened") }
        let sql = "UPDATE profiles SET auto_playback_mode=? WHERE id=?;"
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else {
            throw DatabaseError.prepareFailed(String(cString: sqlite3_errmsg(db)))
        }
        defer { sqlite3_finalize(stmt) }
        bind(stmt: stmt!, index: 1, text: mode)
        bind(stmt: stmt!, index: 2, text: profileId.uuidString)
        guard sqlite3_step(stmt) == SQLITE_DONE else {
            throw DatabaseError.execFailed(String(cString: sqlite3_errmsg(db)))
        }
    }

    // MARK: - Playlists

    func fetchAllPlaylists() throws -> [Playlist] {
        guard let db = db else { throw DatabaseError.openFailed("Not opened") }
        let sql = "SELECT id, profile_id, name, sort_order, created_at, is_system FROM playlists ORDER BY is_system DESC, sort_order ASC, created_at ASC;"
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else {
            throw DatabaseError.prepareFailed(String(cString: sqlite3_errmsg(db)))
        }
        defer { sqlite3_finalize(stmt) }
        var result: [Playlist] = []
        while sqlite3_step(stmt) == SQLITE_ROW {
            guard let id = UUID(uuidString: columnText(stmt!, 0)),
                  let pid = UUID(uuidString: columnText(stmt!, 1)) else { continue }
            result.append(Playlist(
                id: id, profileId: pid, name: columnText(stmt!, 2),
                sortOrder: Int(sqlite3_column_int64(stmt!, 3)),
                createdAt: Date(timeIntervalSince1970: sqlite3_column_double(stmt!, 4)),
                isSystem: sqlite3_column_int64(stmt!, 5) != 0
            ))
        }
        return result
    }

    /// Returns playlistId → ordered video ids.
    func fetchAllPlaylistVideos() throws -> [UUID: [UUID]] {
        guard let db = db else { throw DatabaseError.openFailed("Not opened") }
        let sql = "SELECT playlist_id, video_id FROM playlist_videos ORDER BY playlist_id, sort_order ASC;"
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else {
            throw DatabaseError.prepareFailed(String(cString: sqlite3_errmsg(db)))
        }
        defer { sqlite3_finalize(stmt) }
        var result: [UUID: [UUID]] = [:]
        while sqlite3_step(stmt) == SQLITE_ROW {
            guard let plid = UUID(uuidString: columnText(stmt!, 0)),
                  let vid = UUID(uuidString: columnText(stmt!, 1)) else { continue }
            result[plid, default: []].append(vid)
        }
        return result
    }

    func insertPlaylist(_ playlist: Playlist) throws {
        guard let db = db else { throw DatabaseError.openFailed("Not opened") }
        let sql = "INSERT INTO playlists (id, profile_id, name, sort_order, created_at, is_system) VALUES (?, ?, ?, ?, ?, ?);"
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else {
            throw DatabaseError.prepareFailed(String(cString: sqlite3_errmsg(db)))
        }
        defer { sqlite3_finalize(stmt) }
        bind(stmt: stmt!, index: 1, text: playlist.id.uuidString)
        bind(stmt: stmt!, index: 2, text: playlist.profileId.uuidString)
        bind(stmt: stmt!, index: 3, text: playlist.name)
        sqlite3_bind_int64(stmt, 4, Int64(playlist.sortOrder))
        sqlite3_bind_double(stmt, 5, playlist.createdAt.timeIntervalSince1970)
        sqlite3_bind_int64(stmt, 6, playlist.isSystem ? 1 : 0)
        guard sqlite3_step(stmt) == SQLITE_DONE else {
            throw DatabaseError.execFailed(String(cString: sqlite3_errmsg(db)))
        }
    }

    func updatePlaylist(_ playlist: Playlist) throws {
        guard let db = db else { throw DatabaseError.openFailed("Not opened") }
        let sql = "UPDATE playlists SET name=?, sort_order=? WHERE id=?;"
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else {
            throw DatabaseError.prepareFailed(String(cString: sqlite3_errmsg(db)))
        }
        defer { sqlite3_finalize(stmt) }
        bind(stmt: stmt!, index: 1, text: playlist.name)
        sqlite3_bind_int64(stmt, 2, Int64(playlist.sortOrder))
        bind(stmt: stmt!, index: 3, text: playlist.id.uuidString)
        guard sqlite3_step(stmt) == SQLITE_DONE else {
            throw DatabaseError.execFailed(String(cString: sqlite3_errmsg(db)))
        }
    }

    func deletePlaylist(id: UUID) throws {
        guard let db = db else { throw DatabaseError.openFailed("Not opened") }
        let sql = "DELETE FROM playlists WHERE id=?;"
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else {
            throw DatabaseError.prepareFailed(String(cString: sqlite3_errmsg(db)))
        }
        defer { sqlite3_finalize(stmt) }
        bind(stmt: stmt!, index: 1, text: id.uuidString)
        guard sqlite3_step(stmt) == SQLITE_DONE else {
            throw DatabaseError.execFailed(String(cString: sqlite3_errmsg(db)))
        }
    }

    /// Replaces a playlist's video membership atomically (used for
    /// reorder + clear). Single add/remove go through dedicated methods.
    func setPlaylistVideos(playlistId: UUID, videoIds: [UUID]) throws {
        try beginTransaction()
        do {
            guard let db = db else { throw DatabaseError.openFailed("Not opened") }
            var delStmt: OpaquePointer?
            guard sqlite3_prepare_v2(db, "DELETE FROM playlist_videos WHERE playlist_id=?;", -1, &delStmt, nil) == SQLITE_OK else {
                throw DatabaseError.prepareFailed(String(cString: sqlite3_errmsg(db)))
            }
            bind(stmt: delStmt!, index: 1, text: playlistId.uuidString)
            if sqlite3_step(delStmt) != SQLITE_DONE { sqlite3_finalize(delStmt); throw DatabaseError.execFailed(String(cString: sqlite3_errmsg(db))) }
            sqlite3_finalize(delStmt)

            let ins = "INSERT INTO playlist_videos (playlist_id, video_id, sort_order, added_at) VALUES (?, ?, ?, ?);"
            let now = Date().timeIntervalSince1970
            for (i, vid) in videoIds.enumerated() {
                var insStmt: OpaquePointer?
                guard sqlite3_prepare_v2(db, ins, -1, &insStmt, nil) == SQLITE_OK else {
                    throw DatabaseError.prepareFailed(String(cString: sqlite3_errmsg(db)))
                }
                bind(stmt: insStmt!, index: 1, text: playlistId.uuidString)
                bind(stmt: insStmt!, index: 2, text: vid.uuidString)
                sqlite3_bind_int64(insStmt, 3, Int64(i))
                sqlite3_bind_double(insStmt, 4, now)
                if sqlite3_step(insStmt) != SQLITE_DONE { sqlite3_finalize(insStmt); throw DatabaseError.execFailed(String(cString: sqlite3_errmsg(db))) }
                sqlite3_finalize(insStmt)
            }
            try commitTransaction()
        } catch {
            rollbackTransaction()
            throw error
        }
    }

    /// Appends a video to the end of a playlist (or no-ops if already
    /// present). sortOrder is the count of existing rows.
    func addVideoToPlaylist(playlistId: UUID, videoId: UUID, sortOrder: Int) throws {
        guard let db = db else { throw DatabaseError.openFailed("Not opened") }
        let sql = "INSERT OR IGNORE INTO playlist_videos (playlist_id, video_id, sort_order, added_at) VALUES (?, ?, ?, ?);"
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else {
            throw DatabaseError.prepareFailed(String(cString: sqlite3_errmsg(db)))
        }
        defer { sqlite3_finalize(stmt) }
        bind(stmt: stmt!, index: 1, text: playlistId.uuidString)
        bind(stmt: stmt!, index: 2, text: videoId.uuidString)
        sqlite3_bind_int64(stmt, 3, Int64(sortOrder))
        sqlite3_bind_double(stmt, 4, Date().timeIntervalSince1970)
        guard sqlite3_step(stmt) == SQLITE_DONE else {
            throw DatabaseError.execFailed(String(cString: sqlite3_errmsg(db)))
        }
    }

    func removeVideoFromPlaylist(playlistId: UUID, videoId: UUID) throws {
        guard let db = db else { throw DatabaseError.openFailed("Not opened") }
        let sql = "DELETE FROM playlist_videos WHERE playlist_id=? AND video_id=?;"
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else {
            throw DatabaseError.prepareFailed(String(cString: sqlite3_errmsg(db)))
        }
        defer { sqlite3_finalize(stmt) }
        bind(stmt: stmt!, index: 1, text: playlistId.uuidString)
        bind(stmt: stmt!, index: 2, text: videoId.uuidString)
        guard sqlite3_step(stmt) == SQLITE_DONE else {
            throw DatabaseError.execFailed(String(cString: sqlite3_errmsg(db)))
        }
    }

    func insertProfile(_ profile: Profile) throws {
        guard let db = db else { throw DatabaseError.openFailed("Not opened") }
        let sql = "INSERT INTO profiles (id, name, emoji, sort_order, created_at, icon, color) VALUES (?, ?, ?, ?, ?, ?, ?);"
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else {
            throw DatabaseError.prepareFailed(String(cString: sqlite3_errmsg(db)))
        }
        defer { sqlite3_finalize(stmt) }
        bind(stmt: stmt!, index: 1, text: profile.id.uuidString)
        bind(stmt: stmt!, index: 2, text: profile.name)
        bindNullable(stmt: stmt!, index: 3, text: profile.emoji)
        sqlite3_bind_int64(stmt, 4, Int64(profile.sortOrder))
        sqlite3_bind_double(stmt, 5, profile.createdAt.timeIntervalSince1970)
        bindNullable(stmt: stmt!, index: 6, text: profile.icon)
        bindNullable(stmt: stmt!, index: 7, text: profile.color)
        guard sqlite3_step(stmt) == SQLITE_DONE else {
            throw DatabaseError.execFailed(String(cString: sqlite3_errmsg(db)))
        }
    }

    func updateProfile(_ profile: Profile) throws {
        guard let db = db else { throw DatabaseError.openFailed("Not opened") }
        let sql = "UPDATE profiles SET name=?, emoji=?, sort_order=?, icon=?, color=? WHERE id=?;"
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else {
            throw DatabaseError.prepareFailed(String(cString: sqlite3_errmsg(db)))
        }
        defer { sqlite3_finalize(stmt) }
        bind(stmt: stmt!, index: 1, text: profile.name)
        bindNullable(stmt: stmt!, index: 2, text: profile.emoji)
        sqlite3_bind_int64(stmt, 3, Int64(profile.sortOrder))
        bindNullable(stmt: stmt!, index: 4, text: profile.icon)
        bindNullable(stmt: stmt!, index: 5, text: profile.color)
        bind(stmt: stmt!, index: 6, text: profile.id.uuidString)
        guard sqlite3_step(stmt) == SQLITE_DONE else {
            throw DatabaseError.execFailed(String(cString: sqlite3_errmsg(db)))
        }
    }

    func deleteProfile(id: UUID) throws {
        guard let db = db else { throw DatabaseError.openFailed("Not opened") }
        let sql = "DELETE FROM profiles WHERE id=?;"
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else {
            throw DatabaseError.prepareFailed(String(cString: sqlite3_errmsg(db)))
        }
        defer { sqlite3_finalize(stmt) }
        bind(stmt: stmt!, index: 1, text: id.uuidString)
        guard sqlite3_step(stmt) == SQLITE_DONE else {
            throw DatabaseError.execFailed(String(cString: sqlite3_errmsg(db)))
        }
    }

    /// Returns a map of profileId → set of assigned channel ids.
    func fetchAllProfileChannels() throws -> [UUID: Set<UUID>] {
        guard let db = db else { throw DatabaseError.openFailed("Not opened") }
        let sql = "SELECT profile_id, channel_id FROM profile_channels;"
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else {
            throw DatabaseError.prepareFailed(String(cString: sqlite3_errmsg(db)))
        }
        defer { sqlite3_finalize(stmt) }

        var result: [UUID: Set<UUID>] = [:]
        while sqlite3_step(stmt) == SQLITE_ROW {
            guard let profileId = UUID(uuidString: columnText(stmt!, 0)),
                  let channelId = UUID(uuidString: columnText(stmt!, 1)) else { continue }
            result[profileId, default: []].insert(channelId)
        }
        return result
    }

    /// Replaces a profile's channel assignments atomically.
    func setProfileChannels(profileId: UUID, channelIds: [UUID]) throws {
        try beginTransaction()
        do {
            guard let db = db else { throw DatabaseError.openFailed("Not opened") }
            // Wipe existing assignments for this profile
            let del = "DELETE FROM profile_channels WHERE profile_id=?;"
            var delStmt: OpaquePointer?
            guard sqlite3_prepare_v2(db, del, -1, &delStmt, nil) == SQLITE_OK else {
                throw DatabaseError.prepareFailed(String(cString: sqlite3_errmsg(db)))
            }
            bind(stmt: delStmt!, index: 1, text: profileId.uuidString)
            if sqlite3_step(delStmt) != SQLITE_DONE {
                sqlite3_finalize(delStmt)
                throw DatabaseError.execFailed(String(cString: sqlite3_errmsg(db)))
            }
            sqlite3_finalize(delStmt)

            // Insert new ones, preserving the supplied order
            let ins = "INSERT INTO profile_channels (profile_id, channel_id, sort_order) VALUES (?, ?, ?);"
            for (i, cid) in channelIds.enumerated() {
                var insStmt: OpaquePointer?
                guard sqlite3_prepare_v2(db, ins, -1, &insStmt, nil) == SQLITE_OK else {
                    throw DatabaseError.prepareFailed(String(cString: sqlite3_errmsg(db)))
                }
                bind(stmt: insStmt!, index: 1, text: profileId.uuidString)
                bind(stmt: insStmt!, index: 2, text: cid.uuidString)
                sqlite3_bind_int64(insStmt, 3, Int64(i))
                if sqlite3_step(insStmt) != SQLITE_DONE {
                    sqlite3_finalize(insStmt)
                    throw DatabaseError.execFailed(String(cString: sqlite3_errmsg(db)))
                }
                sqlite3_finalize(insStmt)
            }
            try commitTransaction()
        } catch {
            rollbackTransaction()
            throw error
        }
    }

    // MARK: - Helpers

    // H4 fix: Safe column text reader that handles NULL without crashing.
    // sqlite3_column_text returns NULL for SQL NULL values; String(cString:)
    // would crash on a nil pointer.
    private func columnText(_ stmt: OpaquePointer, _ col: Int32) -> String {
        sqlite3_column_type(stmt, col) != SQLITE_NULL
            ? String(cString: sqlite3_column_text(stmt, col))
            : ""
    }

    private func columnTextOptional(_ stmt: OpaquePointer, _ col: Int32) -> String? {
        sqlite3_column_type(stmt, col) != SQLITE_NULL
            ? String(cString: sqlite3_column_text(stmt, col))
            : nil
    }

    private func channelFromStatement(_ stmt: OpaquePointer) -> Channel {
        let id = UUID(uuidString: columnText(stmt, 0)) ?? UUID()
        let displayName = columnText(stmt, 1)
        let emoji = columnTextOptional(stmt, 2)
        let typeRaw = columnText(stmt, 3)
        let type = ChannelType(rawValue: typeRaw) ?? .custom
        let youtubeChannelId = columnTextOptional(stmt, 4)
        let folderName = columnText(stmt, 5)
        let sortOrder = Int(sqlite3_column_int64(stmt, 6))
        let createdAt = Date(timeIntervalSince1970: sqlite3_column_double(stmt, 7))
        let bannerPath = columnText(stmt, 8)
        let lastSyncedAt: Date? = sqlite3_column_type(stmt, 9) != SQLITE_NULL
            ? Date(timeIntervalSince1970: sqlite3_column_double(stmt, 9))
            : nil
        let lastSyncError = columnTextOptional(stmt, 10)
        return Channel(
            id: id, displayName: displayName, emoji: emoji, type: type,
            youtubeChannelId: youtubeChannelId, folderName: folderName,
            sortOrder: sortOrder, createdAt: createdAt, bannerPath: bannerPath,
            lastSyncedAt: lastSyncedAt, lastSyncError: lastSyncError
        )
    }

    // MARK: - Channel sync state

    func updateChannelSyncState(id: UUID, lastSyncedAt: Date?, lastSyncError: String?) throws {
        guard let db = db else { throw DatabaseError.openFailed("Not opened") }
        let sql = "UPDATE channels SET last_synced_at=?, last_sync_error=? WHERE id=?;"
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else {
            throw DatabaseError.prepareFailed(String(cString: sqlite3_errmsg(db)))
        }
        defer { sqlite3_finalize(stmt) }
        if let t = lastSyncedAt {
            sqlite3_bind_double(stmt, 1, t.timeIntervalSince1970)
        } else {
            sqlite3_bind_null(stmt, 1)
        }
        bindNullable(stmt: stmt!, index: 2, text: lastSyncError)
        bind(stmt: stmt!, index: 3, text: id.uuidString)
        guard sqlite3_step(stmt) == SQLITE_DONE else {
            throw DatabaseError.execFailed(String(cString: sqlite3_errmsg(db)))
        }
    }

    // MARK: - Profile favorites

    /// Returns a map of profileId → set of favorited video IDs.
    func fetchAllProfileFavorites() throws -> [UUID: Set<UUID>] {
        guard let db = db else { throw DatabaseError.openFailed("Not opened") }
        let sql = "SELECT profile_id, video_id FROM profile_favorites;"
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else {
            throw DatabaseError.prepareFailed(String(cString: sqlite3_errmsg(db)))
        }
        defer { sqlite3_finalize(stmt) }
        var result: [UUID: Set<UUID>] = [:]
        while sqlite3_step(stmt) == SQLITE_ROW {
            guard let pid = UUID(uuidString: columnText(stmt!, 0)),
                  let vid = UUID(uuidString: columnText(stmt!, 1)) else { continue }
            result[pid, default: []].insert(vid)
        }
        return result
    }

    func addFavorite(profileId: UUID, videoId: UUID) throws {
        guard let db = db else { throw DatabaseError.openFailed("Not opened") }
        let sql = "INSERT OR IGNORE INTO profile_favorites (profile_id, video_id, created_at) VALUES (?, ?, ?);"
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else {
            throw DatabaseError.prepareFailed(String(cString: sqlite3_errmsg(db)))
        }
        defer { sqlite3_finalize(stmt) }
        bind(stmt: stmt!, index: 1, text: profileId.uuidString)
        bind(stmt: stmt!, index: 2, text: videoId.uuidString)
        sqlite3_bind_double(stmt, 3, Date().timeIntervalSince1970)
        guard sqlite3_step(stmt) == SQLITE_DONE else {
            throw DatabaseError.execFailed(String(cString: sqlite3_errmsg(db)))
        }
    }

    // MARK: - Profile hidden channels

    /// Returns a map of profileId → set of channel ids the profile has
    /// hidden from view (while keeping the channel assignment).
    func fetchAllProfileHiddenChannels() throws -> [UUID: Set<UUID>] {
        guard let db = db else { throw DatabaseError.openFailed("Not opened") }
        let sql = "SELECT profile_id, channel_id FROM profile_hidden_channels;"
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else {
            throw DatabaseError.prepareFailed(String(cString: sqlite3_errmsg(db)))
        }
        defer { sqlite3_finalize(stmt) }
        var result: [UUID: Set<UUID>] = [:]
        while sqlite3_step(stmt) == SQLITE_ROW {
            guard let pid = UUID(uuidString: columnText(stmt!, 0)),
                  let cid = UUID(uuidString: columnText(stmt!, 1)) else { continue }
            result[pid, default: []].insert(cid)
        }
        return result
    }

    func hideChannel(profileId: UUID, channelId: UUID) throws {
        guard let db = db else { throw DatabaseError.openFailed("Not opened") }
        let sql = "INSERT OR IGNORE INTO profile_hidden_channels (profile_id, channel_id, hidden_at) VALUES (?, ?, ?);"
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else {
            throw DatabaseError.prepareFailed(String(cString: sqlite3_errmsg(db)))
        }
        defer { sqlite3_finalize(stmt) }
        bind(stmt: stmt!, index: 1, text: profileId.uuidString)
        bind(stmt: stmt!, index: 2, text: channelId.uuidString)
        sqlite3_bind_double(stmt, 3, Date().timeIntervalSince1970)
        guard sqlite3_step(stmt) == SQLITE_DONE else {
            throw DatabaseError.execFailed(String(cString: sqlite3_errmsg(db)))
        }
    }

    func unhideChannel(profileId: UUID, channelId: UUID) throws {
        guard let db = db else { throw DatabaseError.openFailed("Not opened") }
        let sql = "DELETE FROM profile_hidden_channels WHERE profile_id=? AND channel_id=?;"
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else {
            throw DatabaseError.prepareFailed(String(cString: sqlite3_errmsg(db)))
        }
        defer { sqlite3_finalize(stmt) }
        bind(stmt: stmt!, index: 1, text: profileId.uuidString)
        bind(stmt: stmt!, index: 2, text: channelId.uuidString)
        guard sqlite3_step(stmt) == SQLITE_DONE else {
            throw DatabaseError.execFailed(String(cString: sqlite3_errmsg(db)))
        }
    }

    func removeFavorite(profileId: UUID, videoId: UUID) throws {
        guard let db = db else { throw DatabaseError.openFailed("Not opened") }
        let sql = "DELETE FROM profile_favorites WHERE profile_id=? AND video_id=?;"
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else {
            throw DatabaseError.prepareFailed(String(cString: sqlite3_errmsg(db)))
        }
        defer { sqlite3_finalize(stmt) }
        bind(stmt: stmt!, index: 1, text: profileId.uuidString)
        bind(stmt: stmt!, index: 2, text: videoId.uuidString)
        guard sqlite3_step(stmt) == SQLITE_DONE else {
            throw DatabaseError.execFailed(String(cString: sqlite3_errmsg(db)))
        }
    }

    private func videoFromStatement(_ stmt: OpaquePointer) -> Video {
        let id = UUID(uuidString: columnText(stmt, 0)) ?? UUID()
        let channelId = UUID(uuidString: columnText(stmt, 1)) ?? UUID()
        let youtubeVideoId = columnText(stmt, 2)
        let title = columnText(stmt, 3)
        let localFilePath = columnText(stmt, 4)
        let thumbnailPath = columnText(stmt, 5)
        let downloadedAt = Date(timeIntervalSince1970: sqlite3_column_double(stmt, 6))
        let durationSeconds = sqlite3_column_double(stmt, 7)
        let resumePosition = sqlite3_column_double(stmt, 8)
        let stateRaw = columnText(stmt, 9)
        let state = DownloadState(rawValue: stateRaw) ?? .queued
        let progress = sqlite3_column_double(stmt, 10)
        let error = columnTextOptional(stmt, 11)
        let sortOrder = Int(sqlite3_column_int64(stmt, 12))
        let thumbnailVersion = Int(sqlite3_column_int64(stmt, 13))
        return Video(
            id: id, channelId: channelId, youtubeVideoId: youtubeVideoId, title: title,
            localFilePath: localFilePath, thumbnailPath: thumbnailPath,
            downloadedAt: downloadedAt, durationSeconds: durationSeconds,
            resumePositionSeconds: resumePosition, downloadState: state,
            downloadProgress: progress, downloadError: error, sortOrder: sortOrder,
            thumbnailVersion: thumbnailVersion
        )
    }

    // MARK: - Bind Helpers

    // SQLITE_TRANSIENT (-1) tells SQLite to copy the string immediately so it
    // never holds a dangling pointer into a temporary Swift/NSString buffer.
    private static let sqliteTransient = unsafeBitCast(-1, to: sqlite3_destructor_type.self)

    private func bind(stmt: OpaquePointer, index: Int32, text: String) {
        sqlite3_bind_text(stmt, index, text, -1, DatabaseService.sqliteTransient)
    }

    private func bindNullable(stmt: OpaquePointer, index: Int32, text: String?) {
        if let text = text {
            sqlite3_bind_text(stmt, index, text, -1, DatabaseService.sqliteTransient)
        } else {
            sqlite3_bind_null(stmt, index)
        }
    }
}
