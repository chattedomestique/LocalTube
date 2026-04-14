import AppKit
import AVKit
import AVFoundation
import WebKit
import Foundation

// MARK: - Player Overlay Controller
//
// Manages an NSPanel that floats above the WKWebView as a child window.
// The panel has two layers:
//
//   1. AVPlayerView  (bottom) — native video rendering via AVKit
//   2. WKWebView     (top)    — transparent React overlay (PlayerScreen.tsx)
//                               loaded with window.__playerMode = true so
//                               main.tsx renders PlayerScreen instead of App
//
// Swift pushes player state (time, duration, title, isPlaying) to React via
// window.LocalTubePlayer.dispatch(), and React sends commands back
// (toggle, seekBack, seekForward, seek, close) via the LocalTubePlayer
// WKScriptMessageHandler.

@MainActor
final class PlayerOverlayController {

    private(set) var playerPanel: NSPanel?
    private var playerState: PlayerState?
    private var playerWebView: WKWebView?
    weak var parentWindow: NSWindow?
    weak var emitter: BridgeEventEmitter?

    /// Called when the player panel is dismissed (back button or video end).
    var onDismiss: (() -> Void)?

    // MARK: - Show / Hide

    func show(video: Video, appState: AppState) {
        guard video.isPlayable else { return }

        let panel: NSPanel
        let state: PlayerState
        let webView: WKWebView

        if let existingPanel = playerPanel,
           let existingState = playerState,
           let existingWeb   = playerWebView {
            panel   = existingPanel
            state   = existingState
            webView = existingWeb
        } else {
            let built = buildPanel()
            playerPanel   = built.panel
            playerState   = built.state
            playerWebView = built.webView
            panel   = built.panel
            state   = built.state
            webView = built.webView
        }

        state.appState = appState

        // Wire state changes → push to React UI
        state.onStateChanged = { [weak self] in
            self?.pushPlayerState()
        }

        // Size panel to the content area only (below the title bar) so the
        // title bar stays exposed and the window remains draggable.
        if let parent = parentWindow, let contentView = parent.contentView {
            let contentScreenFrame = parent.convertToScreen(contentView.frame)
            panel.setFrame(contentScreenFrame, display: false)
            let alreadyChild = parent.childWindows?.contains { $0 === panel } ?? false
            if !alreadyChild {
                parent.addChildWindow(panel, ordered: .above)
            }
        }

        panel.makeKeyAndOrderFront(nil)
        panel.makeFirstResponder(webView)

        let startSeconds = video.resumePositionSeconds > 10 ? video.resumePositionSeconds : 0
        state.play(video: video, startSeconds: startSeconds)

        observePlayerStop(state: state)
    }

    func hide() {
        playerState?.stop()
        dismiss()
    }

    // MARK: - State → React bridge

    private func pushPlayerState() {
        guard let state = playerState, let webView = playerWebView else { return }
        let payload: [String: Any] = [
            "isPlaying":   state.isPlaying,
            "currentTime": state.currentTime,
            "duration":    state.duration,
            "title":       state.currentVideo?.title ?? "",
        ]
        guard let data = try? JSONSerialization.data(withJSONObject: payload),
              let json = String(data: data, encoding: .utf8) else { return }
        let js = """
        if (window.LocalTubePlayer) {
            window.LocalTubePlayer.dispatch({ type: 'playerState', payload: \(json) });
        }
        """
        webView.evaluateJavaScript(js, in: nil, in: .page) { _ in }
    }

    // MARK: - Panel construction

    private func buildPanel() -> (panel: NSPanel, state: PlayerState, webView: WKWebView) {
        // ── NSPanel ──────────────────────────────────────────────────────────
        let panel = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: 1280, height: 720),
            styleMask:   [.borderless, .nonactivatingPanel],
            backing:     .buffered,
            defer:       false
        )
        panel.isOpaque                   = true
        panel.backgroundColor            = .black
        panel.level                      = .floating
        panel.collectionBehavior         = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.isMovableByWindowBackground = false
        panel.hidesOnDeactivate          = false

        // ── PlayerState ──────────────────────────────────────────────────────
        let state = PlayerState()

        // ── AVPlayerView (bottom layer — actual video) ───────────────────────
        let avView = AVPlayerView()
        avView.player        = state.player
        avView.controlsStyle = .none
        avView.videoGravity  = .resizeAspect
        avView.translatesAutoresizingMaskIntoConstraints = false

        // ── WKWebView (top layer — transparent React controls) ───────────────
        let config = WKWebViewConfiguration()
        config.preferences.setValue(true, forKey: "allowFileAccessFromFileURLs")

        // Inject __playerMode flag + LocalTubePlayer bridge before React mounts.
        // main.tsx reads window.__playerMode at startup and renders <PlayerScreen>
        // instead of <App> when it's true.
        let bridgeJS = """
        window.__playerMode = true;
        window.LocalTubePlayer = {
            _handlers: {},
            on: function(event, fn) {
                if (!this._handlers[event]) this._handlers[event] = [];
                this._handlers[event].push(fn);
            },
            dispatch: function(evt) {
                var handlers = this._handlers[evt.type] || [];
                for (var i = 0; i < handlers.length; i++) {
                    try { handlers[i](evt.payload); } catch(e) {}
                }
            },
            send: function(msg) {
                try {
                    window.webkit.messageHandlers.LocalTubePlayer.postMessage(msg);
                } catch(e) {}
            }
        };
        """
        config.userContentController.addUserScript(
            WKUserScript(source: bridgeJS, injectionTime: .atDocumentStart, forMainFrameOnly: true)
        )

        // Isolated handler class avoids retain cycle: WKUserContentController
        // holds the handler strongly; if PlayerOverlayController were the handler
        // it would be retained indefinitely and leak the whole panel.
        let commandHandler = PlayerCommandHandler { [weak self] command, value in
            guard let self else { return }
            switch command {
            case "playerReady":
                // React mounted — push current state immediately so UI is in sync
                self.pushPlayerState()
            case "toggle":
                self.playerState?.togglePlayPause()
            case "seekBack":
                self.playerState?.skip(seconds: -10)
            case "seekForward":
                self.playerState?.skip(seconds: 10)
            case "seek":
                // value is 0–1 fractional progress
                if let fraction = value,
                   let dur = self.playerState?.duration,
                   let cur = self.playerState?.currentTime {
                    self.playerState?.skip(seconds: fraction * dur - cur)
                }
            case "close":
                self.hide()
            default:
                break
            }
        }
        config.userContentController.add(commandHandler, name: "LocalTubePlayer")

        let webView = WKWebView(frame: .zero, configuration: config)
        webView.setValue(false, forKey: "drawsBackground")   // transparent over video
        webView.allowsBackForwardNavigationGestures = false
        webView.translatesAutoresizingMaskIntoConstraints = false

        // Load the same React bundle the main window uses
        if let resourceURL = Bundle.main.resourceURL {
            let candidates: [URL] = [
                resourceURL.appendingPathComponent("Resources/WebUI/index.html"),
                resourceURL.appendingPathComponent("WebUI/index.html"),
            ]
            if let indexURL = candidates.first(where: { FileManager.default.fileExists(atPath: $0.path) }) {
                webView.loadFileURL(indexURL, allowingReadAccessTo: indexURL.deletingLastPathComponent())
            }
        }

        // ── Container ────────────────────────────────────────────────────────
        let container = NSView()
        container.wantsLayer = true
        container.layer?.backgroundColor = NSColor.black.cgColor

        container.addSubview(avView)
        container.addSubview(webView)   // webView on top

        NSLayoutConstraint.activate([
            avView.topAnchor.constraint(equalTo: container.topAnchor),
            avView.bottomAnchor.constraint(equalTo: container.bottomAnchor),
            avView.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            avView.trailingAnchor.constraint(equalTo: container.trailingAnchor),

            webView.topAnchor.constraint(equalTo: container.topAnchor),
            webView.bottomAnchor.constraint(equalTo: container.bottomAnchor),
            webView.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            webView.trailingAnchor.constraint(equalTo: container.trailingAnchor),
        ])

        panel.contentView = container
        return (panel, state, webView)
    }

    // MARK: - Private helpers

    private func observePlayerStop(state: PlayerState) {
        NotificationCenter.default.addObserver(
            forName: .AVPlayerItemDidPlayToEndTime,
            object: nil,
            queue: .main
        ) { [weak self, weak state] _ in
            Task { @MainActor [weak self, weak state] in
                guard let self, let state, !state.isLooping else { return }
                self.dismiss()
            }
        }
    }

    private func dismiss() {
        if let panel = playerPanel, let parent = parentWindow {
            parent.removeChildWindow(panel)
            panel.orderOut(nil)
        }
        onDismiss?()
    }
}

// MARK: - Player Command Handler
//
// Separate NSObject subclass so WKUserContentController's strong retain of the
// handler does not create a cycle back to PlayerOverlayController.

private final class PlayerCommandHandler: NSObject, WKScriptMessageHandler {
    private let handler: @MainActor (String, Double?) -> Void

    init(handler: @escaping @MainActor (String, Double?) -> Void) {
        self.handler = handler
    }

    func userContentController(
        _ userContentController: WKUserContentController,
        didReceive message: WKScriptMessage
    ) {
        guard let body    = message.body as? [String: Any],
              let command = body["command"] as? String else { return }
        let value = body["value"] as? Double
        Task { @MainActor in self.handler(command, value) }
    }
}
