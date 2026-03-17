import AppKit
import WebKit
import Foundation

// MARK: - Web Window Controller
//
// Creates and manages the main NSWindow hosting a WKWebView that loads
// the bundled React application. Wires up:
//   • ThumbnailURLSchemeHandler for localtube-thumb:// URLs
//   • LocalTubeBridge as the WKScriptMessageHandler
//   • BridgeEventEmitter for Swift → JS events
//   • PlayerOverlayController for native AVPlayer overlay

@MainActor
final class WebWindowController: NSObject, NSWindowDelegate {

    // MARK: - Public

    let window: NSWindow
    let bridge: LocalTubeBridge
    private let webView: WKWebView
    private let playerOverlay: PlayerOverlayController

    // MARK: - Init

    init(appState: AppState) {
        // ── WKWebView configuration ──────────────────────────────────────

        let config = WKWebViewConfiguration()

        // Register custom URL scheme for serving local thumbnails
        config.setURLSchemeHandler(ThumbnailURLSchemeHandler(), forURLScheme: "localtube-thumb")

        // Expose the JS bridge message handler
        let bridge = LocalTubeBridge()
        config.userContentController.add(bridge, name: "LocalTubeBridge")

        // Inject bridge bootstrap script so window.LocalTubeBridge exists
        // before the React app's first render
        let bootstrapJS = """
        window.LocalTubeBridge = {
          _handlers: {},
          dispatch: function(event, payload) {
            var handlers = this._handlers[event] || [];
            for (var i = 0; i < handlers.length; i++) {
              try { handlers[i](payload); } catch(e) { console.error('Bridge handler error:', e); }
            }
          },
          on: function(event, fn) {
            if (!this._handlers[event]) this._handlers[event] = [];
            this._handlers[event].push(fn);
          },
          off: function(event, fn) {
            if (!this._handlers[event]) return;
            this._handlers[event] = this._handlers[event].filter(function(h) { return h !== fn; });
          },
          send: function(msg) {
            try {
              window.webkit.messageHandlers.LocalTubeBridge.postMessage(msg);
            } catch(e) {
              console.warn('Bridge send failed:', e);
            }
          }
        };
        """
        let userScript = WKUserScript(
            source: bootstrapJS,
            injectionTime: .atDocumentStart,
            forMainFrameOnly: true
        )
        config.userContentController.addUserScript(userScript)

        // Allow local file access (needed for loading WebUI assets)
        config.preferences.setValue(true, forKey: "allowFileAccessFromFileURLs")

        // Forward console.log/error from WKWebView to AppLogger for debugging
        let consoleScript = """
        (function() {
          var _log = console.log.bind(console);
          var _err = console.error.bind(console);
          var _warn = console.warn.bind(console);
          function relay(level, args) {
            var msg = Array.from(args).map(function(a) {
              return typeof a === 'object' ? JSON.stringify(a) : String(a);
            }).join(' ');
            window.webkit.messageHandlers.LocalTubeConsole.postMessage({level: level, msg: msg});
          }
          console.log   = function() { _log.apply(console, arguments);  relay('log',  arguments); };
          console.error = function() { _err.apply(console, arguments);  relay('error',arguments); };
          console.warn  = function() { _warn.apply(console, arguments); relay('warn', arguments); };
        })();
        """
        config.userContentController.addUserScript(
            WKUserScript(source: consoleScript, injectionTime: .atDocumentStart, forMainFrameOnly: true)
        )

        // ── WKWebView ────────────────────────────────────────────────────

        let webView = WKWebView(frame: .zero, configuration: config)
        webView.setValue(false, forKey: "drawsBackground")
        webView.allowsBackForwardNavigationGestures = false

        // ── NSWindow ─────────────────────────────────────────────────────

        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 1280, height: 800),
            styleMask:   [.titled, .closable, .miniaturizable, .resizable],
            backing:     .buffered,
            defer:       false
        )
        window.title = "LocalTube"
        window.minSize = NSSize(width: 900, height: 600)
        window.center()

        // WKWebView fills the content area below the native title bar
        window.contentView = webView

        // ── Player Overlay ───────────────────────────────────────────────

        let playerOverlay = PlayerOverlayController()
        playerOverlay.parentWindow = window

        // ── Stitch bridge ────────────────────────────────────────────────

        bridge.appState = appState
        bridge.playerOverlayController = playerOverlay
        bridge.emitter.webView = webView

        self.window  = window
        self.webView = webView
        self.bridge  = bridge
        self.playerOverlay = playerOverlay

        super.init()

        window.delegate = self

        // Register console relay handler
        config.userContentController.add(ConsoleMessageHandler(), name: "LocalTubeConsole")

    }

    // MARK: - Load

    func loadWebUI() {
        // Find the bundled WebUI/index.html in Resources
        guard let resourceURL = Bundle.main.resourceURL else {
            AppLogger.error("WebWindowController: could not find bundle resources")
            return
        }

        // The Vite build outputs to Sources/LocalTube/Resources/WebUI/
        // After SPM copies Resources, it lands at:
        // <bundle>/Contents/Resources/Resources/WebUI/index.html  (SPM .copy wraps in "Resources/")
        let candidates: [URL] = [
            resourceURL.appendingPathComponent("Resources/WebUI/index.html"),
            resourceURL.appendingPathComponent("WebUI/index.html"),
        ]

        guard let indexURL = candidates.first(where: { FileManager.default.fileExists(atPath: $0.path) }) else {
            AppLogger.error("WebWindowController: WebUI/index.html not found in bundle")
            // Show a fallback error page
            loadFallbackPage()
            return
        }

        AppLogger.info("WebWindowController: loading \(indexURL.path)")
        webView.loadFileURL(indexURL, allowingReadAccessTo: indexURL.deletingLastPathComponent())
    }

    private func loadFallbackPage() {
        let html = """
        <!DOCTYPE html>
        <html>
        <head>
          <meta charset="utf-8">
          <style>
            body { background:#0d0d0f; color:#f0f0f4; font-family:-apple-system,sans-serif;
                   display:flex; align-items:center; justify-content:center; height:100vh; margin:0; }
            .msg { text-align:center; }
            h1 { font-size:24px; margin-bottom:8px; }
            p  { color:#8e8e99; font-size:14px; }
          </style>
        </head>
        <body>
          <div class="msg">
            <h1>LocalTube</h1>
            <p>WebUI not found. Run <code>npm run build</code> in the WebUI directory, then rebuild.</p>
          </div>
        </body>
        </html>
        """
        webView.loadHTMLString(html, baseURL: nil)
    }

    // MARK: - NSWindowDelegate

    func windowWillClose(_ notification: Notification) {
        NSApplication.shared.terminate(nil)
    }

    func windowDidResize(_ notification: Notification) {
        // Keep player overlay panel in sync with main window size
        if let panel = playerOverlay.playerPanel,
           panel.isVisible {
            panel.setFrame(window.frame, display: true)
        }
    }
}

// MARK: - Console Message Handler

/// Relays console.log / .error / .warn from the WKWebView to AppLogger for debugging.
private final class ConsoleMessageHandler: NSObject, WKScriptMessageHandler {
    func userContentController(
        _ userContentController: WKUserContentController,
        didReceive message: WKScriptMessage
    ) {
        guard let body  = message.body as? [String: Any],
              let level = body["level"] as? String,
              let msg   = body["msg"]   as? String else { return }
        switch level {
        case "error": AppLogger.error("[WebUI] \(msg)")
        case "warn":  AppLogger.info("[WebUI][warn] \(msg)")
        default:      AppLogger.info("[WebUI] \(msg)")
        }
    }
}
