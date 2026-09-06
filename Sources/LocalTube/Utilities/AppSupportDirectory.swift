import Foundation

enum AppSupportDirectory {
    static func localtubeDirectory() throws -> URL {
        let base = try FileManager.default.url(
            for: .applicationSupportDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        )
        let dir = base.appendingPathComponent("LocalTube", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    static func logsDirectory() throws -> URL {
        let lt = try localtubeDirectory()
        let logs = lt.appendingPathComponent("logs", isDirectory: true)
        try FileManager.default.createDirectory(at: logs, withIntermediateDirectories: true)
        return logs
    }

    /// Where pre-migration / pre-relocation database snapshots live.
    /// Restoring one is the rollback path if a newer build misbehaves:
    /// quit LocalTube, copy the snapshot over `library.sqlite` (and delete
    /// any `library.sqlite-wal` / `-shm` siblings), relaunch the old build.
    static func backupsDirectory() throws -> URL {
        let lt = try localtubeDirectory()
        let backups = lt.appendingPathComponent("backups", isDirectory: true)
        try FileManager.default.createDirectory(at: backups, withIntermediateDirectories: true)
        return backups
    }

    static func databaseURL() throws -> URL {
        try localtubeDirectory().appendingPathComponent("library.sqlite")
    }
}
