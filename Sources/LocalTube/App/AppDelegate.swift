import AppKit
import Foundation
import Sparkle

// MARK: - App Delegate
//
// Owns the AppState and WebWindowController for the lifetime of the process.
// Also builds the macOS main menu (Quit, Settings, Window menu).

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {

    // MARK: - Owned objects

    // H3 fix: true optionals. Every use goes through a guard so a menu
    // action arriving before applicationDidFinishLaunching can't crash.
    private var appState: AppState?
    private var windowController: WebWindowController?

    // Sparkle updater — must be retained for the lifetime of the app.
    // SUFeedURL in Info.plist tells Sparkle where to find the appcast.
    private let updaterController = SPUStandardUpdaterController(
        startingUpdater: true, updaterDelegate: nil, userDriverDelegate: nil)

    // MARK: - Auto-sync
    //
    // Source channels are checked for new uploads on launch and once a day
    // while the app stays open. The 20h staleness guard means relaunching
    // within the same day won't re-hit YouTube, while the 24h timer keeps a
    // long-running install current. Retained for the app's lifetime.
    private static let autoSyncMaxAge:   TimeInterval = 20 * 60 * 60   // 20 hours
    private static let autoSyncInterval: TimeInterval = 24 * 60 * 60   // daily
    private var autoSyncTimer: Timer?

    // MARK: - Library folder watch
    //
    // While the library folder is unreachable (external drive unplugged),
    // poll for it every few seconds so the "library unavailable" screen
    // clears itself the moment the drive is back — no relaunch needed.
    private static let folderPollInterval: TimeInterval = 5
    private var folderPollTimer: Timer?

    // MARK: - Lifecycle

    nonisolated func applicationWillFinishLaunching(_ notification: Notification) {
        AppLogger.setup()
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        AppLogger.info("LocalTube \(AppState.appVersion) launched (PID \(ProcessInfo.processInfo.processIdentifier))")

        // Build app state
        let appState = AppState()
        self.appState = appState

        // Wire download service back-reference + load settings
        bootstrapAppState(appState)

        // Build the macOS main menu
        buildMainMenu()

        // Create the WebView window (wires up bridge + player overlay)
        let windowController = WebWindowController(appState: appState)
        self.windowController = windowController

        // Show the window and load the React UI
        windowController.window.makeKeyAndOrderFront(nil)
        windowController.loadWebUI()

        // Async init: check dependencies + load library, then push state to JS
        Task { [weak self] in
            guard let self else { return }
            let emitter = windowController.bridge.emitter

            if appState.settings.checkDepsOnLaunch {
                await appState.dependencyService.checkAll()
                appState.dependencyStatus = appState.dependencyService.status
            }
            // Resolve yt-dlp/ffprobe through `which` once so non-Homebrew
            // installs work. (Was never called before — the fallback list
            // silently missed pipx/MacPorts installs and downloads hung.)
            await appState.downloadService.resolveToolPaths()

            await appState.loadLibrary()
            if let err = appState.libraryLoadError {
                AppLogger.error("Library failed to load: \(err)")
            }
            // After library is loaded, push full state to the WebView
            emitter.emitStateUpdate(appState)

            if appState.libraryLoadError == nil {
                await self.startLibraryServices(appState: appState, emitter: emitter)
            }
            self.scheduleDailyAutoSync()
        }
    }

    /// Everything that needs the library folder: verify files on disk
    /// (healing paths after a move, re-queueing anything that vanished),
    /// resume downloads left over from the last session, then check
    /// source channels for new uploads. Skipped — and retried when the
    /// folder comes back — if the folder is unreachable.
    private func startLibraryServices(appState: AppState, emitter: BridgeEventEmitter) async {
        guard appState.refreshLibraryFolderAvailability() else {
            AppLogger.error("Library folder unavailable at launch: \(appState.settings.downloadFolderPath ?? "<none>")")
            emitter.emitStateUpdate(appState)
            startFolderPolling()
            return
        }
        stopFolderPolling()

        if appState.settings.downloadFolderPath != nil {
            let scan = await appState.maintenance.verify(requeueMissing: true)
            emitter.emitLibraryScanCompleted(result: scan)
        }

        await appState.downloadService.resumePendingDownloads()
        emitter.emitStateUpdate(appState)

        // Check source channels for new uploads now (launch), then daily.
        await appState.autoSyncStaleChannels(maxAge: Self.autoSyncMaxAge)
        emitter.emitStateUpdate(appState)
    }

    /// Schedules the once-a-day background check for new uploads. Runs only
    /// while the app stays open; the launch-time check covers fresh starts.
    private func scheduleDailyAutoSync() {
        autoSyncTimer?.invalidate()
        autoSyncTimer = Timer.scheduledTimer(
            withTimeInterval: Self.autoSyncInterval, repeats: true
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                guard let self, let appState = self.appState else { return }
                await appState.autoSyncStaleChannels(maxAge: Self.autoSyncMaxAge)
                self.windowController?.bridge.emitter.emitStateUpdate(appState)
            }
        }
    }

    private func startFolderPolling() {
        guard folderPollTimer == nil else { return }
        folderPollTimer = Timer.scheduledTimer(
            withTimeInterval: Self.folderPollInterval, repeats: true
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                guard let self, let appState = self.appState,
                      let emitter = self.windowController?.bridge.emitter else { return }
                let wasAvailable = appState.libraryFolderAvailable
                let nowAvailable = appState.refreshLibraryFolderAvailability()
                if nowAvailable && !wasAvailable {
                    AppLogger.info("Library folder is reachable again — resuming")
                    emitter.emitStateUpdate(appState)
                    await self.startLibraryServices(appState: appState, emitter: emitter)
                }
            }
        }
    }

    private func stopFolderPolling() {
        folderPollTimer?.invalidate()
        folderPollTimer = nil
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

    func applicationWillTerminate(_ notification: Notification) {
        // Stop yt-dlp children. They are not killed automatically when the
        // parent exits; a survivor would keep writing into the library and
        // race the resumed download on the next launch.
        appState?.downloadService.cancelAll()
        AppLogger.info("LocalTube terminating")
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
        guard let appState, let windowController else { return }
        if appState.appMode == .editor {
            appState.exitEditorMode()
        } else {
            appState.requestEditorMode()
        }
        windowController.bridge.emitter.emitStateUpdate(appState)
    }

    @objc private func verifyLibrary() {
        guard let appState, let windowController else { return }
        let emitter = windowController.bridge.emitter
        emitter.emitLibraryScanStarted()
        Task {
            let result = await appState.maintenance.verify(requeueMissing: true)
            emitter.emitLibraryScanCompleted(result: result)
            emitter.emitStateUpdate(appState)
        }
    }

    @objc private func revealLibraryFolder() {
        guard let appState,
              let path = appState.settings.downloadFolderPath,
              SettingsService.isDirectory(atPath: path) else { return }
        NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: path)])
    }

    @objc private func revealLogs() {
        guard let logs = try? AppSupportDirectory.logsDirectory() else { return }
        NSWorkspace.shared.activateFileViewerSelecting([logs])
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
        appMenu.addItem(withTitle: "Check for Updates…",
                        action: #selector(SPUStandardUpdaterController.checkForUpdates(_:)),
                        keyEquivalent: "")
            .target = updaterController
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

        // ── Library menu ─────────────────────────────────────────────────────
        let libraryMenuItem = NSMenuItem(title: "Library", action: nil, keyEquivalent: "")
        mainMenu.addItem(libraryMenuItem)
        let libraryMenu = NSMenu(title: "Library")
        libraryMenuItem.submenu = libraryMenu

        libraryMenu.addItem(withTitle: "Verify Library Files", action: #selector(verifyLibrary), keyEquivalent: "")
            .target = self
        libraryMenu.addItem(withTitle: "Reveal Library Folder in Finder", action: #selector(revealLibraryFolder), keyEquivalent: "")
            .target = self
        libraryMenu.addItem(.separator())
        libraryMenu.addItem(withTitle: "Reveal Logs in Finder", action: #selector(revealLogs), keyEquivalent: "")
            .target = self

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

    private func bootstrapAppState(_ appState: AppState) {
        // Wire download service back-reference
        appState.setup()

        // Load persisted settings
        let settings = SettingsService.load()
        appState.settings = settings

        // Determine onboarding / gating state. A configured-but-unreachable
        // folder is NOT onboarding — that's the "library unavailable" state.
        appState.isOnboarding   = settings.downloadFolderPath == nil
        appState.needsPINSetup  = !PINService.hasPIN()
        appState.refreshLibraryFolderAvailability()

        // Settings → About → "Check for Updates…" goes through Sparkle's
        // standard updater controller (same as the app-menu item).
        appState.checkForUpdatesHandler = { [weak self] in
            self?.updaterController.checkForUpdates(nil)
        }

        // Wire download service event handler → bridge emitter
        appState.downloadService.eventHandler = { [weak self] event in
            guard let self, let windowController = self.windowController,
                  let state = self.appState else { return }
            let emitter = windowController.bridge.emitter
            switch event {
            case .progress(let videoId, let progress):
                emitter.emitDownloadProgress(videoId: videoId.uuidString, progress: progress)
            case .completed(let videoId):
                emitter.emitDownloadCompleted(videoId: videoId.uuidString)
                // Full snapshot: the finished video's final paths/duration
                // plus whichever download became active next.
                emitter.emitStateUpdate(state)
            case .error(let videoId, let err):
                emitter.emitDownloadError(videoId: videoId.uuidString, error: err)
                emitter.emitStateUpdate(state)
            }
        }

        // Editor timer was removed — admin mode stays open until the
        // parent explicitly exits. See EDITING_MODEL.md.
    }
}
