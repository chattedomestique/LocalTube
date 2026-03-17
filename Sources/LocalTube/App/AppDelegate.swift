import AppKit
import SwiftUI

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationWillFinishLaunching(_ notification: Notification) {
        // Set up logging as early as possible
        AppLogger.setup()
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        AppLogger.info("LocalTube launched (PID \(ProcessInfo.processInfo.processIdentifier))")
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        true
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows: Bool) -> Bool {
        if !hasVisibleWindows {
            NSApp.windows.first?.makeKeyAndOrderFront(nil)
        }
        return true
    }
}
