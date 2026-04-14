import AppKit
import AVKit
import AVFoundation
import Foundation

// MARK: - Player Overlay Controller
//
// Manages an NSPanel that floats above the WKWebView as a child window,
// hosting the native AVPlayerView. This approach keeps AVKit's internal
// layer tree completely separate from WKWebView's rendering pipeline —
// the two views never share a parent NSView, preventing layer composition issues.

@MainActor
final class PlayerOverlayController {

    private(set) var playerPanel: NSPanel?
    private var playerState: PlayerState?
    weak var parentWindow: NSWindow?
    weak var emitter: BridgeEventEmitter?

    // MARK: - Show / Hide

    func show(video: Video, appState: AppState) {
        guard video.isPlayable else { return }

        // Re-use existing panel if present, otherwise create fresh
        let panel: NSPanel
        let state: PlayerState

        if let existing = playerPanel, let existingState = playerState {
            panel = existing
            state = existingState
        } else {
            let (p, s) = buildPanel()
            playerPanel = p
            playerState = s
            state = s
            panel = p
        }

        state.appState = appState

        // Size the panel to match the parent window's content area
        if let parent = parentWindow {
            let frame = parent.contentView?.window?.frame ?? parent.frame
            panel.setFrame(frame, display: false)
            let alreadyChild = parent.childWindows?.contains { $0 === panel } ?? false
            if !alreadyChild {
                parent.addChildWindow(panel, ordered: .above)
            }
        }

        panel.makeKeyAndOrderFront(nil)
        // Use saved position only if > 10 s in; otherwise restart from beginning.
        // The full resume-or-restart prompt is handled by VideoPlayerView in the
        // SwiftUI path; this bridge path applies the same threshold silently.
        let startSeconds = video.resumePositionSeconds > 10 ? video.resumePositionSeconds : 0
        state.play(video: video, startSeconds: startSeconds)

        // Observe player stop to auto-hide
        observePlayerStop(state: state)
    }

    func hide() {
        playerState?.stop()
        dismiss()
    }

    // MARK: - Private

    private func buildPanel() -> (NSPanel, PlayerState) {
        let panel = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: 1280, height: 720),
            styleMask:   [.borderless, .nonactivatingPanel],
            backing:     .buffered,
            defer:       false
        )
        panel.isOpaque = true
        panel.backgroundColor = .black
        panel.level = .floating
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.isMovableByWindowBackground = false
        panel.hidesOnDeactivate = false

        let state = PlayerState()

        // Build the SwiftUI-equivalent player UI using AppKit directly so we avoid
        // another SwiftUI scene lifecycle. AVPlayerView + overlay controls view.
        let avView = AVPlayerView()
        avView.player = state.player
        avView.controlsStyle = .none
        avView.videoGravity = .resizeAspect
        avView.translatesAutoresizingMaskIntoConstraints = false

        let overlay = PlayerOverlayView(playerState: state) { [weak self] in
            self?.hide()
        }
        overlay.translatesAutoresizingMaskIntoConstraints = false

        let container = NSView()
        container.wantsLayer = true
        container.layer?.backgroundColor = NSColor.black.cgColor

        container.addSubview(avView)
        container.addSubview(overlay)

        NSLayoutConstraint.activate([
            avView.topAnchor.constraint(equalTo: container.topAnchor),
            avView.bottomAnchor.constraint(equalTo: container.bottomAnchor),
            avView.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            avView.trailingAnchor.constraint(equalTo: container.trailingAnchor),

            overlay.topAnchor.constraint(equalTo: container.topAnchor),
            overlay.bottomAnchor.constraint(equalTo: container.bottomAnchor),
            overlay.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            overlay.trailingAnchor.constraint(equalTo: container.trailingAnchor),
        ])

        panel.contentView = container
        return (panel, state)
    }

    private func observePlayerStop(state: PlayerState) {
        // When video ends, dismiss automatically
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
    }
}

// MARK: - Player Overlay View (AppKit)
//
// Simple AppKit view that shows player controls on top of AVPlayerView.
// This is intentionally minimal — just back button, play/pause, skip.

final class PlayerOverlayView: NSView {
    private let playerState: PlayerState
    private let onBack: () -> Void
    private var trackingArea: NSTrackingArea?
    private var hideTimer: Timer?

    private let backButton    = NSButton()
    private let playButton    = NSButton()
    private let skipBackBtn   = NSButton()
    private let skipFwdBtn    = NSButton()
    private let topGradient   = NSView()
    private let bottomGradient = NSView()
    private var controlsAlpha: CGFloat = 1.0

    init(playerState: PlayerState, onBack: @escaping () -> Void) {
        self.playerState = playerState
        self.onBack      = onBack
        super.init(frame: .zero)
        setupUI()
    }

    required init?(coder: NSCoder) { fatalError() }

    // MARK: - Setup

    private func setupUI() {
        wantsLayer = true
        layer?.backgroundColor = NSColor.clear.cgColor

        // Back button
        backButton.title = "← Back"
        backButton.bezelStyle = .inline
        backButton.isBordered = false
        backButton.contentTintColor = .white
        backButton.font = NSFont.systemFont(ofSize: 16, weight: .semibold)
        backButton.target = self
        backButton.action = #selector(backTapped)
        backButton.translatesAutoresizingMaskIntoConstraints = false

        // Play/Pause
        playButton.image = NSImage(systemSymbolName: "play.fill", accessibilityDescription: "Play")
        playButton.contentTintColor = .white
        playButton.isBordered = false
        playButton.imageScaling = .scaleProportionallyDown
        playButton.target = self
        playButton.action = #selector(playTapped)
        playButton.translatesAutoresizingMaskIntoConstraints = false
        playButton.widthAnchor.constraint(equalToConstant: 64).isActive = true
        playButton.heightAnchor.constraint(equalToConstant: 64).isActive = true

        // Skip back
        skipBackBtn.image = NSImage(systemSymbolName: "gobackward.10", accessibilityDescription: "Skip back 10s")
        skipBackBtn.contentTintColor = .white
        skipBackBtn.isBordered = false
        skipBackBtn.target = self
        skipBackBtn.action = #selector(skipBack)
        skipBackBtn.translatesAutoresizingMaskIntoConstraints = false
        skipBackBtn.widthAnchor.constraint(equalToConstant: 44).isActive = true
        skipBackBtn.heightAnchor.constraint(equalToConstant: 44).isActive = true

        // Skip forward
        skipFwdBtn.image = NSImage(systemSymbolName: "goforward.10", accessibilityDescription: "Skip forward 10s")
        skipFwdBtn.contentTintColor = .white
        skipFwdBtn.isBordered = false
        skipFwdBtn.target = self
        skipFwdBtn.action = #selector(skipForward)
        skipFwdBtn.translatesAutoresizingMaskIntoConstraints = false
        skipFwdBtn.widthAnchor.constraint(equalToConstant: 44).isActive = true
        skipFwdBtn.heightAnchor.constraint(equalToConstant: 44).isActive = true

        let centerStack = NSStackView(views: [skipBackBtn, playButton, skipFwdBtn])
        centerStack.spacing = 48
        centerStack.translatesAutoresizingMaskIntoConstraints = false

        addSubview(backButton)
        addSubview(centerStack)

        NSLayoutConstraint.activate([
            backButton.topAnchor.constraint(equalTo: topAnchor, constant: 24),
            backButton.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 32),

            centerStack.centerXAnchor.constraint(equalTo: centerXAnchor),
            centerStack.centerYAnchor.constraint(equalTo: centerYAnchor),
        ])

        scheduleHide()
    }

    // MARK: - Actions

    @objc private func backTapped()    { onBack() }
    @objc private func playTapped()    { Task { @MainActor in self.playerState.togglePlayPause(); self.updatePlayButton() } }
    @objc private func skipBack()      { Task { @MainActor in self.playerState.skip(seconds: -10) } }
    @objc private func skipForward()   { Task { @MainActor in self.playerState.skip(seconds:  10) } }

    private func updatePlayButton() {
        let name = playerState.isPlaying ? "pause.fill" : "play.fill"
        playButton.image = NSImage(systemSymbolName: name, accessibilityDescription: nil)
    }

    // MARK: - Controls Visibility

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let t = trackingArea { removeTrackingArea(t) }
        trackingArea = NSTrackingArea(
            rect: bounds,
            options: [.mouseMoved, .mouseEnteredAndExited, .activeInActiveApp],
            owner: self,
            userInfo: nil
        )
        addTrackingArea(trackingArea!)
    }

    override func mouseMoved(with event: NSEvent) {
        showControls()
    }

    override func mouseDown(with event: NSEvent) {
        showControls()
    }

    private func showControls() {
        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = 0.2
            animator().alphaValue = 1
        }
        scheduleHide()
    }

    private func scheduleHide() {
        hideTimer?.invalidate()
        hideTimer = Timer.scheduledTimer(withTimeInterval: 4, repeats: false) { [weak self] _ in
            Task { @MainActor [weak self] in
                NSAnimationContext.runAnimationGroup { ctx in
                    ctx.duration = 0.4
                    self?.animator().alphaValue = 0
                }
            }
        }
    }

    // MARK: - Key events (Esc, Space, arrows)

    override var acceptsFirstResponder: Bool { true }

    override func keyDown(with event: NSEvent) {
        Task { @MainActor in
            switch event.keyCode {
            case 53: onBack()                                    // Esc
            case 49: playerState.togglePlayPause()              // Space
            case 123: playerState.skip(seconds: -10)            // Left
            case 124: playerState.skip(seconds:  10)            // Right
            case 125: playerState.setVolume(playerState.player.volume - 0.1)  // Down
            case 126: playerState.setVolume(playerState.player.volume + 0.1)  // Up
            default: break
            }
            showControls()
            updatePlayButton()
        }
    }
}
