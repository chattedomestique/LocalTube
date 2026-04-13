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
    /// M3 fix: Runs a command with an optional timeout. Validates binary exists before launch.
    static func run(
        _ launchPath: String,
        args: [String],
        environment: [String: String]? = nil,
        timeout: TimeInterval = 120
    ) async throws -> String {
        // M3 fix: Validate the binary exists before attempting launch
        guard FileManager.default.isExecutableFile(atPath: launchPath) else {
            throw ShellError.launchFailed("Binary not found or not executable: \(launchPath)")
        }

        return try await withThrowingTaskGroup(of: String.self) { group in
            group.addTask {
                try await withCheckedThrowingContinuation { continuation in
                    let process = Process()
                    process.executableURL = URL(fileURLWithPath: launchPath)
                    process.arguments = args

                    var env = ProcessInfo.processInfo.environment
                    env["PATH"] = "/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin:" + (env["PATH"] ?? "")
                    // Force UTF-8 I/O for Python-based tools (yt-dlp, etc.) so
                    // emoji and non-ASCII characters are not garbled when the
                    // app process has no locale set (common in .app bundles).
                    env["PYTHONIOENCODING"] = "utf-8"
                    env["PYTHONLEGACYWINDOWSSTDIO"] = "0"
                    env["LANG"] = env["LANG"] ?? "en_US.UTF-8"
                    env["LC_ALL"] = env["LC_ALL"] ?? "en_US.UTF-8"
                    env["LC_CTYPE"] = "UTF-8"
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
                        // String(decoding:as:) never fails — invalid UTF-8 sequences
                        // become U+FFFD replacement characters instead of silently
                        // dropping all output (which the `?? ""` fallback would do).
                        let outStr = String(decoding: outData, as: UTF8.self)
                        let errStr = String(decoding: errData, as: UTF8.self)
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

            // M3 fix: Timeout task
            group.addTask {
                try await Task.sleep(nanoseconds: UInt64(timeout * 1_000_000_000))
                throw ShellError.launchFailed("Process timed out after \(Int(timeout))s")
            }

            let result = try await group.next()!
            group.cancelAll()
            return result
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
        // Force UTF-8 I/O for Python-based tools (yt-dlp, etc.)
        env["PYTHONIOENCODING"] = "utf-8"
        env["PYTHONLEGACYWINDOWSSTDIO"] = "0"
        env["LANG"] = env["LANG"] ?? "en_US.UTF-8"
        env["LC_ALL"] = env["LC_ALL"] ?? "en_US.UTF-8"
        env["LC_CTYPE"] = "UTF-8"
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
                let line = String(decoding: lineData, as: UTF8.self)
                onLine(line)
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
            if !buffer.isEmpty {
                onLine(String(decoding: buffer, as: UTF8.self))
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
