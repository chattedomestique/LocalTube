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

        // Check Homebrew first
        let brewPath = await ShellRunner.which("brew")
        if brewPath == nil {
            await installHomebrew()
        }

        if !status.python3 {
            await installBrewPackage("python3")
        }
        if !status.ytDlp {
            await installBrewPackage("yt-dlp")
        }
        if !status.ffmpeg {
            await installBrewPackage("ffmpeg")
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

    private func installHomebrew() async {
        appendLog("Installing Homebrew...")
        let script = "/bin/bash"
        let args = ["-c", "curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh | /bin/bash"]
        _ = ShellRunner.stream(script, args: args) { [weak self] line in
            Task { @MainActor [weak self] in self?.appendLog(line) }
        } onCompletion: { [weak self] code in
            Task { @MainActor [weak self] in
                if code != 0 {
                    self?.installError = "Homebrew installation failed (exit \(code))"
                } else {
                    self?.appendLog("Homebrew installed.")
                }
            }
        }
        // Wait for installation to complete (simple polling)
        for _ in 0..<120 {
            try? await Task.sleep(nanoseconds: 1_000_000_000)
            if await ShellRunner.which("brew") != nil { break }
        }
    }

    private func installBrewPackage(_ name: String) async {
        appendLog("Installing \(name) via Homebrew...")
        await withCheckedContinuation { (cont: CheckedContinuation<Void, Never>) in
            _ = ShellRunner.stream("/opt/homebrew/bin/brew", args: ["install", name]) { [weak self] line in
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
