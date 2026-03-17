import Foundation

// MARK: - Shell Error

enum ShellError: Error, LocalizedError {
    case launchFailed(String)
    case nonZeroExit(Int32, String)

    var errorDescription: String? {
        switch self {
        case .launchFailed(let msg): return "Failed to launch process: \(msg)"
        case .nonZeroExit(let code, let output): return "Process exited \(code): \(output)"
        }
    }
}

// MARK: - Shell Runner

enum ShellRunner {
    /// Runs a command and returns captured stdout. Throws if exit code != 0.
    static func run(
        _ launchPath: String,
        args: [String],
        environment: [String: String]? = nil
    ) async throws -> String {
        try await withCheckedThrowingContinuation { continuation in
            let process = Process()
            process.executableURL = URL(fileURLWithPath: launchPath)
            process.arguments = args

            var env = ProcessInfo.processInfo.environment
            // Ensure Homebrew paths are included
            env["PATH"] = "/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin:" + (env["PATH"] ?? "")
            if let extra = environment {
                env.merge(extra) { _, new in new }
            }
            process.environment = env

            let stdout = Pipe()
            let stderr = Pipe()
            process.standardOutput = stdout
            process.standardError = stderr

            process.terminationHandler = { p in
                let outData = stdout.fileHandleForReading.readDataToEndOfFile()
                let errData = stderr.fileHandleForReading.readDataToEndOfFile()
                let outStr = String(data: outData, encoding: .utf8) ?? ""
                let errStr = String(data: errData, encoding: .utf8) ?? ""
                let combined = outStr + errStr

                if p.terminationStatus == 0 {
                    continuation.resume(returning: outStr.trimmingCharacters(in: .whitespacesAndNewlines))
                } else {
                    continuation.resume(throwing: ShellError.nonZeroExit(p.terminationStatus, combined.trimmingCharacters(in: .whitespacesAndNewlines)))
                }
            }

            do {
                try process.run()
            } catch {
                continuation.resume(throwing: ShellError.launchFailed(error.localizedDescription))
            }
        }
    }

    /// Runs a command, streaming each line of stdout to `onLine`. Returns the Process for cancellation.
    @discardableResult
    static func stream(
        _ launchPath: String,
        args: [String],
        environment: [String: String]? = nil,
        onLine: @escaping @Sendable (String) -> Void,
        onCompletion: @escaping @Sendable (Int32) -> Void
    ) -> Process {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: launchPath)
        process.arguments = args

        var env = ProcessInfo.processInfo.environment
        env["PATH"] = "/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin:" + (env["PATH"] ?? "")
        if let extra = environment {
            env.merge(extra) { _, new in new }
        }
        process.environment = env

        let stdout = Pipe()
        let stderr = Pipe()
        process.standardOutput = stdout
        process.standardError = stderr

        var buffer = Data()

        func processBuffer() {
            while let newline = buffer.firstIndex(of: UInt8(ascii: "\n")) {
                let lineData = buffer[buffer.startIndex..<newline]
                if let line = String(data: lineData, encoding: .utf8) {
                    onLine(line)
                }
                buffer = buffer[(newline + 1)...]
            }
        }

        stdout.fileHandleForReading.readabilityHandler = { handle in
            let data = handle.availableData
            guard !data.isEmpty else { return }
            buffer.append(data)
            processBuffer()
        }

        stderr.fileHandleForReading.readabilityHandler = { handle in
            let data = handle.availableData
            guard !data.isEmpty else { return }
            buffer.append(data)
            processBuffer()
        }

        process.terminationHandler = { p in
            stdout.fileHandleForReading.readabilityHandler = nil
            stderr.fileHandleForReading.readabilityHandler = nil
            // Flush remaining buffer
            let remaining = buffer
            if !remaining.isEmpty, let line = String(data: remaining, encoding: .utf8) {
                onLine(line)
            }
            onCompletion(p.terminationStatus)
        }

        try? process.run()
        return process
    }

    /// Resolves the full path of a binary using `which`.
    static func which(_ name: String) async -> String? {
        try? await run("/usr/bin/which", args: [name])
    }
}
