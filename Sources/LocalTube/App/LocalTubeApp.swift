import SwiftUI
import AppKit

@main
struct LocalTubeApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

    @State private var appState = AppState()

    init() {
        // Enforce single instance before any UI appears
        SingleInstanceGuard.enforceAndContinue()
    }

    var body: some Scene {
        WindowGroup {
            ContentRootView()
                .environment(appState)
                .onAppear { onAppear() }
        }
        .windowStyle(.titleBar)
        .windowToolbarStyle(.unified)
        .commands {
            // File menu: New Channel (⌘N)
            // NOTE: The Settings scene below already registers "Settings…" under
            // the app menu (⌘,). Adding CommandGroup(replacing: .appSettings) here
            // would create a duplicate entry, so it is intentionally omitted.
            CommandGroup(replacing: .newItem) {
                Button("New Channel") {
                    if appState.appMode == .editor {
                        NotificationCenter.default.post(name: .newChannelRequested, object: nil)
                    }
                }
                .keyboardShortcut("n", modifiers: .command)
                .disabled(appState.appMode != .editor)
            }

            // View menu: Enter/Exit Editor Mode (⌘E)
            CommandMenu("View") {
                Button(appState.appMode == .editor ? "Exit Editor Mode" : "Enter Editor Mode") {
                    if appState.appMode == .editor {
                        appState.exitEditorMode()
                    } else {
                        appState.requestEditorMode()
                    }
                }
                .keyboardShortcut("e", modifiers: .command)
            }
        }

        // Standard Settings window (⌘,)
        Settings {
            SettingsView()
                .environment(appState)
        }
    }

    // MARK: - App Appear

    private func onAppear() {
        // Wire up download service back-reference
        appState.setup()

        // Load settings
        let settings = SettingsService.load()
        appState.settings = settings

        // Determine gating state
        let folderMissing = settings.downloadFolderPath == nil
        appState.isOnboarding = folderMissing

        // Check if PIN is set up
        appState.needsPINSetup = !PINService.hasPIN()

        // Async init: check dependencies + load library
        Task {
            // Check deps in background
            await appState.dependencyService.checkAll()
            appState.dependencyStatus = appState.dependencyService.status

            // Load library from database
            await appState.loadLibrary()
        }
    }


}

// MARK: - Notification Names

extension Notification.Name {
    static let newChannelRequested = Notification.Name("LocalTube.newChannelRequested")
}
