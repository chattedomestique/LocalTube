import Foundation
import os.log

/// Thin wrapper over os.Logger that also appends to a local log file.
/// H7 fix: All file writes are serialized through a dedicated DispatchQueue.
/// L5 fix: Log file is rotated when it exceeds 10 MB.
/// M10 fix: ISO8601DateFormatter is cached as a static let.
enum AppLogger {
    private static let osLog = os.Logger(subsystem: "com.local.localtube", category: "app")
    private static var fileHandle: FileHandle?
    private static var logFileURL: URL?
    private static let queue = DispatchQueue(label: "com.local.localtube.logger")
    // M10 fix: Reuse formatter instead of creating one per log line
    private static let formatter: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        return f
    }()
    private static let maxLogSize: UInt64 = 10 * 1024 * 1024  // 10 MB

    static func setup() {
        queue.sync {
            guard fileHandle == nil else { return }
            do {
                let logsDir = try AppSupportDirectory.logsDirectory()
                let logFile = logsDir.appendingPathComponent("localtube.log")
                logFileURL = logFile
                if !FileManager.default.fileExists(atPath: logFile.path) {
                    FileManager.default.createFile(atPath: logFile.path, contents: nil)
                }
                fileHandle = try FileHandle(forWritingTo: logFile)
                fileHandle?.seekToEndOfFile()
            } catch {
                osLog.error("Failed to open log file: \(error.localizedDescription)")
            }
        }
    }

    static func info(_ message: String) {
        osLog.info("\(message)")
        append(level: "INFO", message: message)
    }

    static func debug(_ message: String) {
        osLog.debug("\(message)")
        append(level: "DEBUG", message: message)
    }

    static func error(_ message: String) {
        osLog.error("\(message)")
        append(level: "ERROR", message: message)
    }

    private static func append(level: String, message: String) {
        let timestamp = formatter.string(from: Date())
        let line = "[\(timestamp)] [\(level)] \(message)\n"
        guard let data = line.data(using: .utf8) else { return }
        queue.async {
            rotateIfNeeded()
            fileHandle?.write(data)
        }
    }

    // L5 fix: Rotate log file when it exceeds maxLogSize
    private static func rotateIfNeeded() {
        guard let handle = fileHandle, let url = logFileURL else { return }
        let size = handle.offsetInFile
        guard size > maxLogSize else { return }

        handle.closeFile()
        let backupURL = url.deletingLastPathComponent().appendingPathComponent("localtube.log.1")
        try? FileManager.default.removeItem(at: backupURL)
        try? FileManager.default.moveItem(at: url, to: backupURL)
        FileManager.default.createFile(atPath: url.path, contents: nil)
        fileHandle = try? FileHandle(forWritingTo: url)
    }
}
