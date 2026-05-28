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

    // Single end-of-playback observer token. Re-used across show() calls so
    // we don't accumulate one observer per video played in a session.
    private var endObserverToken: NSObjectProtocol?

    // Playback context for auto-advance. Set by show(); read on
    // end-of-video to decide whether to advance (queue) or apply the
    // profile's playback mode (channel).
    private var playSource: PlaybackSource?
    private var currentVideoId: UUID?
    private weak var appState: AppState?

    // MARK: - Show / Hide

    func show(video: Video, appState: AppState, source: PlaybackSource) {
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
        self.appState = appState
        self.playSource = source
        self.currentVideoId = video.id

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
        emitter?.emitNowPlayingChanged(videoId: video.id)
    }

    /// Plays the next video in the existing panel without rebuilding it.
    private func playNext(_ video: Video, state: PlayerState) {
        currentVideoId = video.id
        state.play(video: video, startSeconds: 0)
        emitter?.emitNowPlayingChanged(videoId: video.id)
    }

    /// Advances the active profile's channel-playback mode to the next
    /// option (exit → sequential → repeatOne → random → …) and keeps the
    /// React side in sync. Invoked from the player overlay's autoplay
    /// button. No-op when no profile is active (nowhere to persist).
    private func cycleAutoplayMode() {
        guard let appState, let pid = appState.activeProfileId else { return }
        let next = appState.activeProfileAutoPlaybackMode.next
        appState.setAutoPlaybackMode(profileId: pid, mode: next)
        emitter?.emitAutoPlaybackModeChanged(profileId: pid, mode: next.rawValue)
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
            rootView: PlayerControlsOverlay(
                onBack: { [weak self] in self?.hide() },
                onCycleAutoplay: { [weak self] in self?.cycleAutoplayMode() }
            )
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
        // Tear down any prior registration so repeated show() calls don't
        // accumulate observers that all fire on the next end-of-playback.
        if let token = endObserverToken {
            NotificationCenter.default.removeObserver(token)
            endObserverToken = nil
        }
        endObserverToken = NotificationCenter.default.addObserver(
            forName: .AVPlayerItemDidPlayToEndTime,
            object: nil,
            queue: .main
        ) { [weak self, weak state] _ in
            Task { @MainActor [weak self, weak state] in
                guard let self, let state, !state.isLooping else { return }
                self.advanceOrDismiss()
            }
        }
    }

    // MARK: - Auto-advance

    /// Called at natural end-of-playback. Picks the next video to play
    /// based on the playback source + the profile's playback mode; if
    /// there's nothing to advance to, tears the panel down.
    private func advanceOrDismiss() {
        guard let state = playerState,
              let appState,
              let source = playSource,
              let currentId = currentVideoId,
              let next = nextVideo(after: currentId, source: source, appState: appState)
        else {
            dismiss()
            return
        }
        playNext(next, state: state)
    }

    /// Resolves what should play after `videoId`. Returns nil to signal
    /// "stop" — end of a queue, channel mode `.exit`, or nothing playable
    /// remains.
    ///
    ///   • Queue source: always advances to the next *playable* queued item,
    ///     ignoring the profile's channel-playback mode.
    ///   • Channel source: applies the active profile's `PlaybackMode`.
    private func nextVideo(after videoId: UUID, source: PlaybackSource, appState: AppState) -> Video? {
        switch source {
        case .queue(let playlistId):
            let ids = appState.playlistVideos[playlistId] ?? []
            guard let idx = ids.firstIndex(of: videoId), idx + 1 < ids.count else { return nil }
            for nextId in ids[(idx + 1)...] {
                if let v = appState.videoById(nextId), v.isPlayable { return v }
            }
            return nil

        case .channel(let channelId):
            let playable = appState.videosForChannel(channelId)
                .filter { $0.isPlayable }
                .sorted { $0.sortOrder < $1.sortOrder }
            switch appState.activeProfileAutoPlaybackMode {
            case .exit:
                return nil
            case .repeatOne:
                return appState.videoById(videoId)
            case .sequential:
                guard let idx = playable.firstIndex(where: { $0.id == videoId }),
                      idx + 1 < playable.count else { return nil }
                return playable[idx + 1]
            case .random:
                let pool = playable.filter { $0.id != videoId }
                // If the channel has a single playable video, replay it
                // rather than dead-ending.
                return pool.randomElement() ?? (playable.count == 1 ? playable.first : nil)
            }
        }
    }

    private func dismiss() {
        if let token = endObserverToken {
            NotificationCenter.default.removeObserver(token)
            endObserverToken = nil
        }
        playSource = nil
        currentVideoId = nil
        emitter?.emitNowPlayingChanged(videoId: nil)
        if let panel = playerPanel, let parent = parentWindow {
            parent.removeChildWindow(panel)
            panel.orderOut(nil)
        }
        onDismiss?()
    }

    deinit {
        if let token = endObserverToken {
            NotificationCenter.default.removeObserver(token)
        }
        // PlayerState owns its time/itemEnd observers; tear them down too so the
        // panel's AVPlayer stops emitting periodic callbacks after dismissal.
        playerState?.cleanup()
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
    // .nonactivatingPanel intentionally prevents the panel from stealing app
    // activation, but the side effect is that clicking it doesn't promote it
    // to key window — so keyboard shortcuts (space, arrows) silently break
    // once focus drifts elsewhere. mouseDown reclaims key status explicitly.
    override func mouseDown(with event: NSEvent) {
        if !isKeyWindow { makeKey() }
        super.mouseDown(with: event)
    }

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
