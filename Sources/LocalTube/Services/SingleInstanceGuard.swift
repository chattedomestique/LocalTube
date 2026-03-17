import Foundation
import AppKit

enum SingleInstanceGuard {
    /// Terminates any other running instance of LocalTube.
    /// Called synchronously at launch before any UI is shown.
    static func enforceAndContinue() {
        let bundleId = Bundle.main.bundleIdentifier ?? "com.local.localtube"
        let currentPID = ProcessInfo.processInfo.processIdentifier
        let others = NSRunningApplication.runningApplications(withBundleIdentifier: bundleId)
            .filter { $0.processIdentifier != currentPID }

        guard !others.isEmpty else { return }

        for app in others {
            AppLogger.info("SingleInstanceGuard: terminating prior instance PID \(app.processIdentifier)")
            app.terminate()
        }

        // Wait up to 2 seconds for prior instances to exit
        let deadline = Date().addingTimeInterval(2)
        while Date() < deadline {
            let stillRunning = NSRunningApplication.runningApplications(withBundleIdentifier: bundleId)
                .filter { $0.processIdentifier != currentPID && !$0.isTerminated }
            if stillRunning.isEmpty { break }
            Thread.sleep(forTimeInterval: 0.1)
        }

        AppLogger.info("SingleInstanceGuard: enforcement complete")
    }
}
