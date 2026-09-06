import Foundation

// MARK: - Shell Error

enum ShellError: Error, LocalizedError {
    case launchFailed(String)
    case nonZeroExit(Int32, String)
    case timedOut(Int)
    case stalled(Int)

    var errorDescription: String? {
        switch self {
        case .launchFailed(let msg):          return "Failed to launch process: \(msg)"
        case .nonZeroExit(let code, let out): return "Process exited \(code): \(out)"
        case .timedOut(let secs):             return "Process timed out after \(secs)s"
        case .stalled(let secs):              return "Process produced no output for \(secs)s and was stopped"
        }
    }
}

// MARK: - Shell Runner
//
// Two entry points:
//   • run(...)    — collect all output, return stdout on exit 0.
//   • stream(...) — deliver output line by line as it arrives.
//
// Both drain stdout and stderr *while the process runs*. The previous
// implementation of run() only read the pipes from the termination
// handler, which deadlocks as soon as a child writes more than the pipe
// buffer (~64 KB): the child blocks on write, never exits, the handler
// never fires. A yt-dlp --flat-playlist listing of a channel with a few
// hundred videos crosses that line easily, so large channel syncs "timed
// out" for no visible reason.
//
// Both also guarantee the process is actually killed on timeout/stall
// instead of being left running in the background.

enum ShellRunner {

    /// Exit code reported to `stream`'s completion handler when the
    /// process could not be launched at all.
    static let launchFailedExitCode: Int32 = -1
    /// Exit code reported when the inactivity watchdog stopped the process.
    static let stalledExitCode: Int32 = -2

    /// Runs a command to completion and returns its trimmed stdout.
    /// Throws on launch failure, non-zero exit, or timeout (the process is
    /// terminated — SIGTERM, then SIGKILL after a grace period).
    static func run(
        _ launchPath: String,
        args: [String],
        environment: [String: String]? = nil,
        timeout: TimeInterval = 120
    ) async throws -> String {
        guard FileManager.default.isExecutableFile(atPath: launchPath) else {
            throw ShellError.launchFailed("Binary not found or not executable: \(launchPath)")
        }

        let process = makeProcess(launchPath, args: args, environment: environment)
        let collector = OutputCollector()
        let stdout = Pipe()
        let stderr = Pipe()
        process.standardOutput = stdout
        process.standardError = stderr

        let timedOut = AtomicFlag()

        let status: Int32 = try await withThrowingTaskGroup(of: Int32.self) { group in
            group.addTask {
                try await withCheckedThrowingContinuation { (cont: CheckedContinuation<Int32, Error>) in
                    // Resume only once the process has exited AND both
                    // pipes hit EOF, so no trailing output is lost and no
                    // chunk can be appended out of order.
                    let exitStatus = AtomicValue<Int32>(0)
                    let gate = CompletionGate(count: 3) {
                        cont.resume(returning: exitStatus.get())
                    }
                    stdout.fileHandleForReading.readabilityHandler = { handle in
                        let data = handle.availableData
                        if data.isEmpty {
                            handle.readabilityHandler = nil
                            gate.signal()
                        } else {
                            collector.appendStdout(data)
                        }
                    }
                    stderr.fileHandleForReading.readabilityHandler = { handle in
                        let data = handle.availableData
                        if data.isEmpty {
                            handle.readabilityHandler = nil
                            gate.signal()
                        } else {
                            collector.appendStderr(data)
                        }
                    }
                    process.terminationHandler = { p in
                        exitStatus.set(p.terminationStatus)
                        gate.signal()
                        // If a grandchild (ffmpeg spawned by yt-dlp) inherited
                        // the pipes and is still running, EOF may lag behind
                        // the exit. Don't wait on it forever.
                        DispatchQueue.global(qos: .utility).asyncAfter(deadline: .now() + 10) {
                            stdout.fileHandleForReading.readabilityHandler = nil
                            stderr.fileHandleForReading.readabilityHandler = nil
                            gate.force()
                        }
                    }
                    do {
                        try process.run()
                    } catch {
                        stdout.fileHandleForReading.readabilityHandler = nil
                        stderr.fileHandleForReading.readabilityHandler = nil
                        gate.cancel()
                        cont.resume(throwing: ShellError.launchFailed(error.localizedDescription))
                    }
                }
            }

            group.addTask {
                try await Task.sleep(nanoseconds: UInt64(timeout * 1_000_000_000))
                timedOut.set()
                ShellRunner.forceTerminate(process)
                throw ShellError.timedOut(Int(timeout))
            }

            let first = try await group.next()!
            group.cancelAll()
            return first
        }

        if timedOut.isSet {
            throw ShellError.timedOut(Int(timeout))
        }

        let outStr = String(decoding: collector.stdout, as: UTF8.self)
        let errStr = String(decoding: collector.stderr, as: UTF8.self)
        if status == 0 {
            return outStr.trimmingCharacters(in: .whitespacesAndNewlines)
        }
        let combined = (outStr + errStr).trimmingCharacters(in: .whitespacesAndNewlines)
        throw ShellError.nonZeroExit(status, combined)
    }

    /// Runs a command, streaming each line of stdout/stderr to `onLine`.
    /// Returns the Process for cancellation.
    ///
    /// `inactivityTimeout`: if the process emits nothing for this long it
    /// is terminated and `onCompletion` receives `stalledExitCode`. If the
    /// binary can't be launched, `onCompletion` receives
    /// `launchFailedExitCode` (previously the completion never fired and
    /// callers awaiting it hung forever).
    @discardableResult
    static func stream(
        _ launchPath: String,
        args: [String],
        environment: [String: String]? = nil,
        inactivityTimeout: TimeInterval? = nil,
        onLine: @escaping @Sendable (String) -> Void,
        onCompletion: @escaping @Sendable (Int32) -> Void
    ) -> Process {
        let process = makeProcess(launchPath, args: args, environment: environment)
        let stdout = Pipe()
        let stderr = Pipe()
        process.standardOutput = stdout
        process.standardError = stderr

        let lines = LineBuffer(onLine: onLine)
        let exitStatus = AtomicValue<Int32>(0)
        let stalled = AtomicFlag()
        let watchdog = AtomicValue<Task<Void, Never>?>(nil)

        let gate = CompletionGate(count: 3) {
            watchdog.get()?.cancel()
            lines.flush()
            onCompletion(stalled.isSet ? stalledExitCode : exitStatus.get())
        }

        stdout.fileHandleForReading.readabilityHandler = { handle in
            let data = handle.availableData
            if data.isEmpty {
                handle.readabilityHandler = nil
                gate.signal()
            } else {
                lines.append(data)
            }
        }
        stderr.fileHandleForReading.readabilityHandler = { handle in
            let data = handle.availableData
            if data.isEmpty {
                handle.readabilityHandler = nil
                gate.signal()
            } else {
                lines.append(data)
            }
        }
        process.terminationHandler = { p in
            exitStatus.set(p.terminationStatus)
            gate.signal()
            // Same grandchild safety net as run(): a lingering ffmpeg must
            // not keep the completion handler from ever firing.
            DispatchQueue.global(qos: .utility).asyncAfter(deadline: .now() + 15) {
                stdout.fileHandleForReading.readabilityHandler = nil
                stderr.fileHandleForReading.readabilityHandler = nil
                gate.force()
            }
        }

        guard !launchPath.isEmpty, FileManager.default.isExecutableFile(atPath: launchPath) else {
            AppLogger.error("ShellRunner.stream: binary not found or not executable: \(launchPath)")
            stdout.fileHandleForReading.readabilityHandler = nil
            stderr.fileHandleForReading.readabilityHandler = nil
            gate.cancel()
            onCompletion(launchFailedExitCode)
            return process
        }

        do {
            try process.run()
        } catch {
            AppLogger.error("ShellRunner.stream: launch failed for \(launchPath): \(error.localizedDescription)")
            stdout.fileHandleForReading.readabilityHandler = nil
            stderr.fileHandleForReading.readabilityHandler = nil
            gate.cancel()
            onCompletion(launchFailedExitCode)
            return process
        }

        if let inactivityTimeout, inactivityTimeout > 0 {
            let interval = max(1, min(30, inactivityTimeout / 2))
            let task = Task.detached {
                while !Task.isCancelled {
                    try? await Task.sleep(nanoseconds: UInt64(interval * 1_000_000_000))
                    if Task.isCancelled || !process.isRunning { return }
                    if Date().timeIntervalSince(lines.lastActivity) > inactivityTimeout {
                        AppLogger.error("ShellRunner.stream: no output for \(Int(inactivityTimeout))s — terminating \(launchPath)")
                        stalled.set()
                        ShellRunner.forceTerminate(process)
                        return
                    }
                }
            }
            watchdog.set(task)
        }

        return process
    }

    /// SIGTERM now, SIGKILL if the process is still alive 3 s later.
    static func forceTerminate(_ process: Process) {
        guard process.isRunning else { return }
        let pid = process.processIdentifier
        process.terminate()
        DispatchQueue.global(qos: .utility).asyncAfter(deadline: .now() + 3) {
            if process.isRunning {
                kill(pid, SIGKILL)
            }
        }
    }

    /// Resolves the full path of a binary using `which`.
    static func which(_ name: String) async -> String? {
        guard let path = try? await run("/usr/bin/which", args: [name], timeout: 10),
              !path.isEmpty else { return nil }
        return path
    }

    /// Resolves a binary by preferring `which` (honors $PATH, MacPorts, nix,
    /// custom Homebrew prefixes), then falling back to the supplied candidate
    /// list. Returns `name` unchanged as a last resort so callers still get a
    /// usable string for error reporting via the launch validation in run().
    static func resolveBinary(_ name: String, fallbacks: [String]) async -> String {
        if let resolved = await which(name),
           FileManager.default.isExecutableFile(atPath: resolved) {
            return resolved
        }
        if let candidate = fallbacks.first(where: { FileManager.default.isExecutableFile(atPath: $0) }) {
            return candidate
        }
        return name
    }

    // MARK: - Private

    private static func makeProcess(
        _ launchPath: String,
        args: [String],
        environment: [String: String]?
    ) -> Process {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: launchPath)
        process.arguments = args

        var env = ProcessInfo.processInfo.environment
        env["PATH"] = "/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin:" + (env["PATH"] ?? "")
        // Force UTF-8 I/O for Python-based tools (yt-dlp, etc.) so emoji
        // and non-ASCII characters are not garbled when the app process
        // has no locale set (common in .app bundles).
        env["PYTHONIOENCODING"] = "utf-8"
        env["PYTHONLEGACYWINDOWSSTDIO"] = "0"
        env["LANG"] = env["LANG"] ?? "en_US.UTF-8"
        env["LC_ALL"] = env["LC_ALL"] ?? "en_US.UTF-8"
        env["LC_CTYPE"] = "UTF-8"
        if let extra = environment {
            env.merge(extra) { _, new in new }
        }
        process.environment = env
        return process
    }
}

// MARK: - Thread-safe helpers
//
// Pipe readability handlers run on arbitrary GCD threads and the two
// pipes' handlers can fire concurrently, so every piece of shared state
// below is lock-protected. (The old `stream` shared one unguarded `Data`
// buffer between the stdout and stderr handlers.)

private final class AtomicFlag: @unchecked Sendable {
    private let lock = NSLock()
    private var value = false
    func set() { lock.lock(); value = true; lock.unlock() }
    var isSet: Bool { lock.lock(); defer { lock.unlock() }; return value }
}

private final class AtomicValue<T>: @unchecked Sendable {
    private let lock = NSLock()
    private var value: T
    init(_ value: T) { self.value = value }
    func get() -> T { lock.lock(); defer { lock.unlock() }; return value }
    func set(_ newValue: T) { lock.lock(); value = newValue; lock.unlock() }
}

/// Fires `onComplete` exactly once, after `signal()` has been called
/// `count` times. `cancel()` makes it never fire.
private final class CompletionGate: @unchecked Sendable {
    private let lock = NSLock()
    private var remaining: Int
    private var fired = false
    private let onComplete: @Sendable () -> Void

    init(count: Int, onComplete: @escaping @Sendable () -> Void) {
        self.remaining = count
        self.onComplete = onComplete
    }

    func signal() {
        lock.lock()
        remaining -= 1
        let shouldFire = remaining <= 0 && !fired
        if shouldFire { fired = true }
        lock.unlock()
        if shouldFire { onComplete() }
    }

    func cancel() {
        lock.lock()
        fired = true
        lock.unlock()
    }

    /// Fires immediately regardless of outstanding signals (used as a
    /// safety net when a grandchild process keeps a pipe open after the
    /// child has already exited).
    func force() {
        lock.lock()
        let shouldFire = !fired
        fired = true
        lock.unlock()
        if shouldFire { onComplete() }
    }
}

private final class OutputCollector: @unchecked Sendable {
    private let lock = NSLock()
    private var out = Data()
    private var err = Data()

    func appendStdout(_ data: Data) { lock.lock(); out.append(data); lock.unlock() }
    func appendStderr(_ data: Data) { lock.lock(); err.append(data); lock.unlock() }
    var stdout: Data { lock.lock(); defer { lock.unlock() }; return out }
    var stderr: Data { lock.lock(); defer { lock.unlock() }; return err }
}

/// Splits an incoming byte stream into lines and records when output was
/// last seen (for the inactivity watchdog).
private final class LineBuffer: @unchecked Sendable {
    private let lock = NSLock()
    private var buffer = Data()
    private var last = Date()
    private let onLine: @Sendable (String) -> Void

    init(onLine: @escaping @Sendable (String) -> Void) {
        self.onLine = onLine
    }

    var lastActivity: Date { lock.lock(); defer { lock.unlock() }; return last }

    func append(_ data: Data) {
        var ready: [String] = []
        lock.lock()
        last = Date()
        buffer.append(data)
        while let newline = buffer.firstIndex(of: UInt8(ascii: "\n")) {
            let lineData = buffer[buffer.startIndex..<newline]
            ready.append(String(decoding: lineData, as: UTF8.self))
            buffer = Data(buffer[(newline + 1)...])
        }
        lock.unlock()
        for line in ready { onLine(line) }
    }

    /// Delivers any trailing partial line (no terminating newline).
    func flush() {
        lock.lock()
        let rest = buffer
        buffer = Data()
        lock.unlock()
        if !rest.isEmpty {
            onLine(String(decoding: rest, as: UTF8.self))
        }
    }
}
