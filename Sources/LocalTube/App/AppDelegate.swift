import AppKit
import Foundation

// MARK: - App Delegate
//
// Owns the AppState and WebWindowController for the lifetime of the process.
// Also builds the macOS main menu (Quit, Settings, Window menu).

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {

    // MARK: - Owned objects

    private var appState: AppState!
    private var windowController: WebWindowController!

    // MARK: - Lifecycle

    nonisolated func applicationWillFinishLaunching(_ notification: Notification) {
        AppLogger.setup()
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        AppLogger.info("LocalTube launched (PID \(ProcessInfo.processInfo.processIdentifier))")

        // Build app state
        appState = AppState()

        // Wire download service back-reference + load settings
        bootstrapAppState()

        // Build the macOS main menu
        buildMainMenu()

        // Create the WebView window (wires up bridge + player overlay)
        windowController = WebWindowController(appState: appState)

        // Show the window and load the React UI
        windowController.window.makeKeyAndOrderFront(nil)
        windowController.loadWebUI()

        // Async init: check dependencies + load library, then push state to JS
        Task {
            if appState.settings.checkDepsOnLaunch {
                await appState.dependencyService.checkAll()
                appState.dependencyStatus = appState.dependencyService.status
            }
            await appState.loadLibrary()
            // After library is loaded, push full state to the WebView
            windowController.bridge.emitter.emitStateUpdate(appState)
        }
    }

    nonisolated func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        true
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows: Bool) -> Bool {
        if !hasVisibleWindows {
            windowController?.window.makeKeyAndOrderFront(nil)
        }
        return true
    }

    // MARK: - Menu Actions

    @objc private func quitApp() {
        NSApplication.shared.terminate(nil)
    }

    @objc private func openSettings() {
        // Only allow settings access from editor mode — tell the WebView to navigate
        guard let wc = windowController else { return }
        wc.bridge.emitter.emit("navigateTo", payload: ["screen": "settings"])
    }

    @objc private func toggleEditorMode() {
        guard let appState else { return }
        if appState.appMode == .editor {
            appState.exitEditorMode()
        } else {
            appState.requestEditorMode()
        }
        windowController.bridge.emitter.emitStateUpdate(appState)
    }

    @objc private func showWindow() {
        windowController?.window.makeKeyAndOrderFront(nil)
    }

    // MARK: - Main Menu

    private func buildMainMenu() {
        let mainMenu = NSMenu()

        // ── App menu ─────────────────────────────────────────────────────────
        let appMenuItem = NSMenuItem()
        mainMenu.addItem(appMenuItem)
        let appMenu = NSMenu()
        appMenuItem.submenu = appMenu

        appMenu.addItem(withTitle: "About LocalTube", action: #selector(NSApplication.orderFrontStandardAboutPanel(_:)), keyEquivalent: "")
        appMenu.addItem(.separator())
        appMenu.addItem(withTitle: "Settings…", action: #selector(openSettings), keyEquivalent: ",")
            .target = self
        appMenu.addItem(.separator())
        let hideItem = appMenu.addItem(withTitle: "Hide LocalTube", action: #selector(NSApplication.hide(_:)), keyEquivalent: "h")
        hideItem.target = NSApp
        let hideOthersItem = appMenu.addItem(withTitle: "Hide Others", action: #selector(NSApplication.hideOtherApplications(_:)), keyEquivalent: "h")
        hideOthersItem.keyEquivalentModifierMask = [.command, .option]
        hideOthersItem.target = NSApp
        appMenu.addItem(withTitle: "Show All", action: #selector(NSApplication.unhideAllApplications(_:)), keyEquivalent: "")
            .target = NSApp
        appMenu.addItem(.separator())
        appMenu.addItem(withTitle: "Quit LocalTube", action: #selector(quitApp), keyEquivalent: "q")
            .target = self

        // ── Edit menu ────────────────────────────────────────────────────────
        let editMenuItem = NSMenuItem(title: "Edit", action: nil, keyEquivalent: "")
        mainMenu.addItem(editMenuItem)
        let editMenu = NSMenu(title: "Edit")
        editMenuItem.submenu = editMenu

        editMenu.addItem(withTitle: "Undo", action: #selector(UndoManager.undo), keyEquivalent: "z")
        editMenu.addItem(withTitle: "Redo", action: #selector(UndoManager.redo), keyEquivalent: "Z")
        editMenu.addItem(.separator())
        editMenu.addItem(withTitle: "Cut",        action: #selector(NSText.cut(_:)),        keyEquivalent: "x")
        editMenu.addItem(withTitle: "Copy",       action: #selector(NSText.copy(_:)),       keyEquivalent: "c")
        editMenu.addItem(withTitle: "Paste",      action: #selector(NSText.paste(_:)),      keyEquivalent: "v")
        editMenu.addItem(withTitle: "Select All", action: #selector(NSText.selectAll(_:)),  keyEquivalent: "a")

        // ── View menu ────────────────────────────────────────────────────────
        let viewMenuItem = NSMenuItem(title: "View", action: nil, keyEquivalent: "")
        mainMenu.addItem(viewMenuItem)
        let viewMenu = NSMenu(title: "View")
        viewMenuItem.submenu = viewMenu

        let editorItem = viewMenu.addItem(withTitle: "Enter Editor Mode", action: #selector(toggleEditorMode), keyEquivalent: "e")
        editorItem.target = self
        viewMenu.addItem(.separator())
        viewMenu.addItem(withTitle: "Enter Full Screen", action: #selector(NSWindow.toggleFullScreen(_:)), keyEquivalent: "f")
            .keyEquivalentModifierMask = [.command, .control]

        // ── Window menu ──────────────────────────────────────────────────────
        let windowMenuItem = NSMenuItem(title: "Window", action: nil, keyEquivalent: "")
        mainMenu.addItem(windowMenuItem)
        let windowMenu = NSMenu(title: "Window")
        windowMenuItem.submenu = windowMenu
        NSApp.windowsMenu = windowMenu

        windowMenu.addItem(withTitle: "Minimize", action: #selector(NSWindow.miniaturize(_:)), keyEquivalent: "m")
        windowMenu.addItem(withTitle: "Zoom", action: #selector(NSWindow.zoom(_:)), keyEquivalent: "")
        windowMenu.addItem(.separator())
        windowMenu.addItem(withTitle: "Bring All to Front", action: #selector(NSApplication.arrangeInFront(_:)), keyEquivalent: "")
            .target = NSApp

        NSApp.mainMenu = mainMenu
    }

    // MARK: - Bootstrap

    private func bootstrapAppState() {
        // Wire download service back-reference
        appState.setup()

        // Load persisted settings
        let settings = SettingsService.load()
        appState.settings = settings

        // Determine onboarding / gating state
        appState.isOnboarding   = settings.downloadFolderPath == nil
        appState.needsPINSetup  = !PINService.hasPIN()

        // Wire download service event handler → bridge emitter
        appState.downloadService.eventHandler = { [weak self] event in
            guard let self else { return }
            let emitter = self.windowController.bridge.emitter
            let state   = self.appState!
            switch event {
            case .progress(let videoId, let progress):
                emitter.emitDownloadProgress(videoId: videoId.uuidString, progress: progress)
            case .completed(let videoId):
                emitter.emitDownloadCompleted(videoId: videoId.uuidString)
                emitter.emitStateUpdate(state)
            case .error(let videoId, let err):
                emitter.emitDownloadError(videoId: videoId.uuidString, error: err)
                emitter.emitStateUpdate(state)
            }
        }

        // Wire editor timer tick → bridge emitter
        appState.onEditorTimerTick = { [weak self] remaining in
            self?.windowController.bridge.emitter.emitEditorTimerTick(remainingSeconds: remaining)
        }
    }
}
