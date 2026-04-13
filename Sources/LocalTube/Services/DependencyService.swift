import Foundation
import Observation

// MARK: - Dependency Status

struct DependencyStatus: Sendable {
    var python3: Bool = false
    var ytDlp: Bool = false
    var ffmpeg: Bool = false

    var allSatisfied: Bool { python3 && ytDlp && ffmpeg }

    var missingNames: [String] {
        var missing: [String] = []
        if !python3 { missing.append("Python 3") }
        if !ytDlp { missing.append("yt-dlp") }
        if !ffmpeg { missing.append("ffmpeg") }
        return missing
    }
}

// MARK: - Dependency Service

@Observable
@MainActor
final class DependencyService {
    var status = DependencyStatus()
    var isChecking = false
    var isInstalling = false
    var installLog: [String] = []
    var installError: String?

    // MARK: - Check

    func checkAll() async {
        isChecking = true
        defer { isChecking = false }

        async let py = checkPython3()
        async let yt = checkYtDlp()
        async let ff = checkFfmpeg()

        let (p, y, f) = await (py, yt, ff)
        status = DependencyStatus(python3: p, ytDlp: y, ffmpeg: f)
        AppLogger.info("DependencyService: python3=\(p) yt-dlp=\(y) ffmpeg=\(f)")
    }

    // MARK: - Install

    func installMissing() async {
        isInstalling = true
        installLog = []
        installError = nil
        defer { isInstalling = false }

        // C3 fix: Require Homebrew to be pre-installed instead of downloading
        // and piping arbitrary scripts through bash with no integrity check.
        let brewPath = await ShellRunner.which("brew")
        guard let brewPath else {
            installError = "Homebrew is not installed. Please install it from https://brew.sh and relaunch LocalTube."
            appendLog("ERROR: Homebrew not found.")
            appendLog("Visit https://brew.sh to install Homebrew, then relaunch LocalTube.")
            return
        }

        if !status.python3 {
            await installBrewPackage("python3", brewPath: brewPath)
        }
        if !status.ytDlp {
            await installBrewPackage("yt-dlp", brewPath: brewPath)
        }
        if !status.ffmpeg {
            await installBrewPackage("ffmpeg", brewPath: brewPath)
        }

        await checkAll()
    }

    // MARK: - Private

    private func checkPython3() async -> Bool {
        if let output = try? await ShellRunner.run("/usr/bin/python3", args: ["--version"]) {
            return output.contains("Python 3")
        }
        if let path = await ShellRunner.which("python3"),
           let output = try? await ShellRunner.run(path, args: ["--version"]) {
            return output.contains("Python 3")
        }
        return false
    }

    private func checkYtDlp() async -> Bool {
        let paths = ["/opt/homebrew/bin/yt-dlp", "/usr/local/bin/yt-dlp"]
        for path in paths {
            if FileManager.default.fileExists(atPath: path) { return true }
        }
        return await ShellRunner.which("yt-dlp") != nil
    }

    private func checkFfmpeg() async -> Bool {
        let paths = ["/opt/homebrew/bin/ffmpeg", "/usr/local/bin/ffmpeg"]
        for path in paths {
            if FileManager.default.fileExists(atPath: path) { return true }
        }
        return await ShellRunner.which("ffmpeg") != nil
    }

    private func installBrewPackage(_ name: String, brewPath: String) async {
        appendLog("Installing \(name) via Homebrew...")
        await withCheckedContinuation { (cont: CheckedContinuation<Void, Never>) in
            _ = ShellRunner.stream(brewPath, args: ["install", name]) { [weak self] line in
                Task { @MainActor [weak self] in self?.appendLog(line) }
            } onCompletion: { [weak self] code in
                Task { @MainActor [weak self] in
                    if code != 0 {
                        self?.installError = "Failed to install \(name)"
                    } else {
                        self?.appendLog("✅ \(name) installed.")
                    }
                    cont.resume()
                }
            }
        }
    }

    private func appendLog(_ line: String) {
        guard !line.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        installLog.append(line)
        // Keep log from growing too large
        if installLog.count > 500 {
            installLog.removeFirst(100)
        }
    }
}
