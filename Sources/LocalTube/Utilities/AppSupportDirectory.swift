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

    static func databaseURL() throws -> URL {
        try localtubeDirectory().appendingPathComponent("library.sqlite")
    }
}
