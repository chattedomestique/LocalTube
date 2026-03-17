import Foundation
import os.log

/// Thin wrapper over os.Logger that also appends to a local log file.
enum AppLogger {
    private static let osLog = os.Logger(subsystem: "com.local.localtube", category: "app")
    private static var fileHandle: FileHandle?

    static func setup() {
        guard fileHandle == nil else { return }
        do {
            let logsDir = try AppSupportDirectory.logsDirectory()
            let logFile = logsDir.appendingPathComponent("localtube.log")
            if !FileManager.default.fileExists(atPath: logFile.path) {
                FileManager.default.createFile(atPath: logFile.path, contents: nil)
            }
            fileHandle = try FileHandle(forWritingTo: logFile)
            fileHandle?.seekToEndOfFile()
        } catch {
            osLog.error("Failed to open log file: \(error.localizedDescription)")
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
        let timestamp = ISO8601DateFormatter().string(from: Date())
        let line = "[\(timestamp)] [\(level)] \(message)\n"
        guard let data = line.data(using: .utf8) else { return }
        fileHandle?.write(data)
    }
}
