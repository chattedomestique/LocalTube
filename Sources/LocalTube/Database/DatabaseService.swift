import Foundation
import SQLite3

// MARK: - Database Service

actor DatabaseService {
    private var db: OpaquePointer?
    static let shared = DatabaseService()

    private init() {}

    // MARK: - Setup

    func open() throws {
        let dbURL = try AppSupportDirectory.databaseURL()
        guard sqlite3_open(dbURL.path, &db) == SQLITE_OK else {
            let msg = db.map { String(cString: sqlite3_errmsg($0)) } ?? "Unknown"
            throw DatabaseError.openFailed(msg)
        }
        // Enable WAL mode and foreign keys
        sqlite3_exec(db, "PRAGMA journal_mode=WAL;", nil, nil, nil)
        sqlite3_exec(db, "PRAGMA foreign_keys=ON;", nil, nil, nil)
        guard let db = db else { throw DatabaseError.openFailed("db is nil") }
        try DatabaseMigrations.run(db: db)
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

    // MARK: - Channels

    func fetchAllChannels() throws -> [Channel] {
        guard let db = db else { throw DatabaseError.openFailed("Not opened") }
        let sql = "SELECT id, display_name, emoji, type, youtube_channel_id, folder_name, sort_order, created_at, banner_path FROM channels ORDER BY sort_order ASC, created_at ASC;"
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
        return Channel(
            id: id, displayName: displayName, emoji: emoji, type: type,
            youtubeChannelId: youtubeChannelId, folderName: folderName,
            sortOrder: sortOrder, createdAt: createdAt, bannerPath: bannerPath
        )
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
