import AppKit
import AVKit
import AVFoundation
import SwiftUI
import Foundation

// MARK: - Player Overlay Controller
//
// Manages a floating NSPanel with two layers:
//
//   1. AVPlayerView      (bottom) — native AVKit video rendering
//   2. NSHostingView     (top)    — SwiftUI PlayerControlsOverlay
//
// SwiftUI's @Observable machinery drives reactivity automatically:
// PlayerState is observed directly by the SwiftUI view tree, so every
// time/play-pause/duration change re-renders the controls without any
// manual state-push plumbing.
//
// Keyboard events are handled by the PlayerPanel NSPanel subclass so
// they work reliably regardless of WKWebView or SwiftUI focus state.

@MainActor
final class PlayerOverlayController {

    private(set) var playerPanel: PlayerPanel?
    private var playerState: PlayerState?
    weak var parentWindow: NSWindow?
    weak var emitter: BridgeEventEmitter?

    /// Called when the player is dismissed (back button or video end).
    var onDismiss: (() -> Void)?

    // MARK: - Show / Hide

    func show(video: Video, appState: AppState) {
        guard video.isPlayable else { return }

        let panel: PlayerPanel
        let state: PlayerState

        if let existing = playerPanel, let existingState = playerState {
            panel = existing
            state = existingState
        } else {
            let built = buildPanel()
            playerPanel = built.panel
            playerState = built.state
            panel       = built.panel
            state       = built.state
        }

        state.appState = appState

        // Size panel to content area only — leaves title bar exposed for dragging
        if let parent = parentWindow, let contentView = parent.contentView {
            let contentScreenFrame = parent.convertToScreen(contentView.frame)
            panel.setFrame(contentScreenFrame, display: false)
            let alreadyChild = parent.childWindows?.contains { $0 === panel } ?? false
            if !alreadyChild {
                parent.addChildWindow(panel, ordered: .above)
            }
        }

        panel.makeKeyAndOrderFront(nil)

        let startSeconds = video.resumePositionSeconds > 10 ? video.resumePositionSeconds : 0
        state.play(video: video, startSeconds: startSeconds)

        observePlayerStop(state: state)
    }

    func hide() {
        playerState?.stop()
        dismiss()
    }

    // MARK: - Private

    private func buildPanel() -> (panel: PlayerPanel, state: PlayerState) {
        // ── NSPanel ──────────────────────────────────────────────────────────
        let panel = PlayerPanel(
            contentRect: NSRect(x: 0, y: 0, width: 1280, height: 720),
            styleMask:   [.borderless, .nonactivatingPanel],
            backing:     .buffered,
            defer:       false
        )
        panel.isOpaque                    = true
        panel.backgroundColor             = .black
        panel.level                       = .floating
        panel.collectionBehavior          = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.isMovableByWindowBackground = false
        panel.hidesOnDeactivate           = false

        // ── PlayerState ──────────────────────────────────────────────────────
        let state = PlayerState()
        panel.playerState = state

        // Wire the panel's close action
        panel.onClose = { [weak self] in self?.hide() }

        // ── AVPlayerView (bottom layer) ──────────────────────────────────────
        let avView = AVPlayerView()
        avView.player        = state.player
        avView.controlsStyle = .none
        avView.videoGravity  = .resizeAspect
        avView.translatesAutoresizingMaskIntoConstraints = false

        // ── SwiftUI controls overlay (top layer) ─────────────────────────────
        // PlayerControlsOverlay is already written — it reads PlayerState via
        // @Environment and uses SwiftUI .onHover for reliable hover detection.
        let overlayView = NSHostingView(
            rootView: PlayerControlsOverlay(onBack: { [weak self] in self?.hide() })
                .environment(state)
        )
        overlayView.translatesAutoresizingMaskIntoConstraints = false

        // ── Container ────────────────────────────────────────────────────────
        let container = NSView()
        container.wantsLayer = true
        container.layer?.backgroundColor = NSColor.black.cgColor

        container.addSubview(avView)
        container.addSubview(overlayView)   // SwiftUI on top

        NSLayoutConstraint.activate([
            avView.topAnchor.constraint(equalTo: container.topAnchor),
            avView.bottomAnchor.constraint(equalTo: container.bottomAnchor),
            avView.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            avView.trailingAnchor.constraint(equalTo: container.trailingAnchor),

            overlayView.topAnchor.constraint(equalTo: container.topAnchor),
            overlayView.bottomAnchor.constraint(equalTo: container.bottomAnchor),
            overlayView.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            overlayView.trailingAnchor.constraint(equalTo: container.trailingAnchor),
        ])

        panel.contentView = container
        return (panel, state)
    }

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

// MARK: - PlayerPanel
//
// NSPanel subclass that handles keyboard shortcuts independently of
// SwiftUI focus or WKWebView event routing — the most reliable approach
// for key events in a floating, non-activating panel.

final class PlayerPanel: NSPanel {
    var playerState: PlayerState?
    var onClose: (() -> Void)?

    override var canBecomeKey: Bool  { true  }
    override var canBecomeMain: Bool { false }

    override func keyDown(with event: NSEvent) {
        Task { @MainActor [weak self] in
            guard let self else { return }
            switch event.keyCode {
            case 53:  self.onClose?()                                            // Esc
            case 49:  self.playerState?.togglePlayPause()                        // Space
            case 123: self.playerState?.skip(seconds: -10)                       // ←
            case 124: self.playerState?.skip(seconds:  10)                       // →
            case 125: self.playerState?.setVolume(                               // ↓
                        (self.playerState?.player.volume ?? 1) - 0.1)
            case 126: self.playerState?.setVolume(                               // ↑
                        (self.playerState?.player.volume ?? 0) + 0.1)
            default:  break
            }
            self.playerState?.showControls()
        }
    }
}
