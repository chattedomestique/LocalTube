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

    // MARK: - Channels

    func fetchAllChannels() throws -> [Channel] {
        guard let db = db else { throw DatabaseError.openFailed("Not opened") }
        let sql = "SELECT id, display_name, emoji, type, youtube_channel_id, folder_name, sort_order, created_at FROM channels ORDER BY sort_order ASC, created_at ASC;"
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
        let sql = "INSERT INTO channels (id, display_name, emoji, type, youtube_channel_id, folder_name, sort_order, created_at) VALUES (?, ?, ?, ?, ?, ?, ?, ?);"
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

        guard sqlite3_step(stmt) == SQLITE_DONE else {
            throw DatabaseError.execFailed(String(cString: sqlite3_errmsg(db)))
        }
    }

    func updateChannel(_ channel: Channel) throws {
        guard let db = db else { throw DatabaseError.openFailed("Not opened") }
        let sql = "UPDATE channels SET display_name=?, emoji=?, sort_order=? WHERE id=?;"
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else {
            throw DatabaseError.prepareFailed(String(cString: sqlite3_errmsg(db)))
        }
        defer { sqlite3_finalize(stmt) }

        bind(stmt: stmt!, index: 1, text: channel.displayName)
        bindNullable(stmt: stmt!, index: 2, text: channel.emoji)
        sqlite3_bind_int64(stmt, 3, Int64(channel.sortOrder))
        bind(stmt: stmt!, index: 4, text: channel.id.uuidString)

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
               download_state, download_progress, download_error, sort_order
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
            download_state, download_progress, download_error, sort_order)
        VALUES (?,?,?,?,?,?,?,?,?,?,?,?,?);
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

        guard sqlite3_step(stmt) == SQLITE_DONE else {
            throw DatabaseError.execFailed(String(cString: sqlite3_errmsg(db)))
        }
    }

    func updateVideo(_ video: Video) throws {
        guard let db = db else { throw DatabaseError.openFailed("Not opened") }
        let sql = """
        UPDATE videos SET title=?, local_file_path=?, thumbnail_path=?,
            duration_seconds=?, resume_position_seconds=?,
            download_state=?, download_progress=?, download_error=?, sort_order=?
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
        bind(stmt: stmt!, index: 10, text: video.id.uuidString)

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

    private func channelFromStatement(_ stmt: OpaquePointer) -> Channel {
        let id = UUID(uuidString: String(cString: sqlite3_column_text(stmt, 0))) ?? UUID()
        let displayName = String(cString: sqlite3_column_text(stmt, 1))
        let emoji = sqlite3_column_type(stmt, 2) != SQLITE_NULL
            ? String(cString: sqlite3_column_text(stmt, 2)) : nil
        let typeRaw = String(cString: sqlite3_column_text(stmt, 3))
        let type = ChannelType(rawValue: typeRaw) ?? .custom
        let youtubeChannelId = sqlite3_column_type(stmt, 4) != SQLITE_NULL
            ? String(cString: sqlite3_column_text(stmt, 4)) : nil
        let folderName = String(cString: sqlite3_column_text(stmt, 5))
        let sortOrder = Int(sqlite3_column_int64(stmt, 6))
        let createdAt = Date(timeIntervalSince1970: sqlite3_column_double(stmt, 7))
        return Channel(
            id: id, displayName: displayName, emoji: emoji, type: type,
            youtubeChannelId: youtubeChannelId, folderName: folderName,
            sortOrder: sortOrder, createdAt: createdAt
        )
    }

    private func videoFromStatement(_ stmt: OpaquePointer) -> Video {
        let id = UUID(uuidString: String(cString: sqlite3_column_text(stmt, 0))) ?? UUID()
        let channelId = UUID(uuidString: String(cString: sqlite3_column_text(stmt, 1))) ?? UUID()
        let youtubeVideoId = String(cString: sqlite3_column_text(stmt, 2))
        let title = String(cString: sqlite3_column_text(stmt, 3))
        let localFilePath = String(cString: sqlite3_column_text(stmt, 4))
        let thumbnailPath = String(cString: sqlite3_column_text(stmt, 5))
        let downloadedAt = Date(timeIntervalSince1970: sqlite3_column_double(stmt, 6))
        let durationSeconds = sqlite3_column_double(stmt, 7)
        let resumePosition = sqlite3_column_double(stmt, 8)
        let stateRaw = String(cString: sqlite3_column_text(stmt, 9))
        let state = DownloadState(rawValue: stateRaw) ?? .queued
        let progress = sqlite3_column_double(stmt, 10)
        let error = sqlite3_column_type(stmt, 11) != SQLITE_NULL
            ? String(cString: sqlite3_column_text(stmt, 11)) : nil
        let sortOrder = Int(sqlite3_column_int64(stmt, 12))
        return Video(
            id: id, channelId: channelId, youtubeVideoId: youtubeVideoId, title: title,
            localFilePath: localFilePath, thumbnailPath: thumbnailPath,
            downloadedAt: downloadedAt, durationSeconds: durationSeconds,
            resumePositionSeconds: resumePosition, downloadState: state,
            downloadProgress: progress, downloadError: error, sortOrder: sortOrder
        )
    }

    // MARK: - Bind Helpers

    private func bind(stmt: OpaquePointer, index: Int32, text: String) {
        sqlite3_bind_text(stmt, index, (text as NSString).utf8String, -1, nil)
    }

    private func bindNullable(stmt: OpaquePointer, index: Int32, text: String?) {
        if let text = text {
            sqlite3_bind_text(stmt, index, (text as NSString).utf8String, -1, nil)
        } else {
            sqlite3_bind_null(stmt, index)
        }
    }
}
