import AppKit
import SwiftUI

// MARK: - App Entry Point
//
// LocalTubeApp is a pure AppKit application — the main window is an NSWindow
// managed by WebWindowController that hosts a WKWebView running the React UI.
//
// SwiftUI is deliberately not used for the main app scene; the @main struct
// simply bootstraps NSApplication and hands off to AppDelegate.

@main
struct LocalTubeApp {
    static func main() {
        // Enforce single instance before any UI appears
        SingleInstanceGuard.enforceAndContinue()

        let app = NSApplication.shared
        let delegate = AppDelegate()
        app.delegate = delegate
        app.run()
    }
}

// MARK: - Notification Names

extension Notification.Name {
    static let newChannelRequested = Notification.Name("LocalTube.newChannelRequested")
}
