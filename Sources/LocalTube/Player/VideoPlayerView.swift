import SwiftUI
import AVFoundation
import AVKit
import AppKit

// MARK: - Native AVPlayerView wrapper
//
// AVPlayerView is Apple's own AppKit view for video playback on macOS.
// It manages its own internal layer tree, handles window transitions,
// and renders video correctly in every context — no manual CALayer wiring.
//
// controlsStyle = .none hides the built-in transport controls so we can
// show our own PlayerControlsOverlay on top.

struct NativePlayerView: NSViewRepresentable {
    let player: AVPlayer

    func makeNSView(context: Context) -> AVPlayerView {
        let v = AVPlayerView()
        v.player           = player
        v.controlsStyle    = .none
        v.videoGravity     = .resizeAspect
        return v
    }

    func updateNSView(_ v: AVPlayerView, context: Context) {
        if v.player !== player { v.player = player }
    }
}

// MARK: - Video Player View

struct VideoPlayerView: View {
    let videoId: UUID

    @Environment(AppState.self)    private var appState
    @Environment(PlayerState.self) private var playerState
    @State private var resumePromptVideo: Video?

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            NativePlayerView(player: playerState.player)
                .ignoresSafeArea()

            PlayerControlsOverlay(onBack: { goBack() })

            if let video = resumePromptVideo {
                ResumePromptOverlay(
                    video: video,
                    onResume: {
                        resumePromptVideo = nil
                        playerState.play(video: video, startSeconds: video.resumePositionSeconds)
                    },
                    onStartOver: {
                        resumePromptVideo = nil
                        playerState.play(video: video, startSeconds: 0)
                    }
                )
                .transition(.opacity)
                .animation(.easeInOut(duration: 0.25), value: resumePromptVideo == nil)
            }
        }
        .onAppear  { startPlayback() }
        .onDisappear { playerState.stop() }
        .toolbar(.hidden)
        .onKeyPress(.space)      { playerState.togglePlayPause(); return .handled }
        .onKeyPress(.leftArrow)  { playerState.skip(seconds: -10); return .handled }
        .onKeyPress(.rightArrow) { playerState.skip(seconds:  10); return .handled }
        .onKeyPress(.upArrow)    { playerState.setVolume(playerState.player.volume + 0.1); return .handled }
        .onKeyPress(.downArrow)  { playerState.setVolume(playerState.player.volume - 0.1); return .handled }
        .onKeyPress(.escape)     { goBack(); return .handled }
        .onTapGesture { playerState.showControls() }
    }

    private func startPlayback() {
        guard let video = appState.videoById(videoId) else { return }
        if video.resumePositionSeconds > 10 {
            // Show resume prompt — don't start playback yet
            resumePromptVideo = video
        } else {
            playerState.play(video: video, startSeconds: 0)
        }
        // Do NOT auto-enter full screen — the transition causes SwiftUI to
        // rebuild the view hierarchy, firing onDisappear → stop() which kills
        // playback mid-transition.  Users can use the green traffic-light button
        // or View → Enter Full Screen (⌃⌘F) whenever they want.
    }

    private func goBack() {
        playerState.stop()
        // Exit full screen if the user entered it manually, so we return to the
        // normal windowed library view.
        if let window = NSApp.mainWindow, window.styleMask.contains(.fullScreen) {
            window.toggleFullScreen(nil)
        }
        if !appState.viewerPath.isEmpty { appState.viewerPath.removeLast() }
    }
}

// MARK: - Resume Prompt Overlay

private struct ResumePromptOverlay: View {
    let video: Video
    let onResume: () -> Void
    let onStartOver: () -> Void

    var body: some View {
        ZStack {
            LTScrimBackground()

            VStack(spacing: 24) {
                Image(systemName: "play.circle.fill")
                    .font(.system(size: 88))
                    .foregroundStyle(Color.ltAccent)

                VStack(spacing: 8) {
                    Text(video.title)
                        .font(.ltHeadline)
                        .foregroundStyle(Color.ltText)
                        .multilineTextAlignment(.center)
                        .lineLimit(2)

                    Text("You watched \(DurationFormatter.format(seconds: video.resumePositionSeconds)) of this video.")
                        .font(.ltBody)
                        .foregroundStyle(Color.ltTextSecondary)
                }

                HStack(spacing: 16) {
                    Button("Start Over", action: onStartOver)
                        .buttonStyle(LTSecondaryButtonStyle())

                    Button("Resume from \(DurationFormatter.format(seconds: video.resumePositionSeconds))", action: onResume)
                        .buttonStyle(LTButtonStyle())
                }
            }
            .padding(48)
            .frame(maxWidth: 520)
        }
    }
}

// MARK: - Glass Button Helpers

/// Circular glass-morphism transport button with hover + press states.
private struct GlassCircleButton: View {
    let icon: String
    let fontSize: CGFloat
    let size: CGFloat
    let action: () -> Void

    @State private var isHovered = false
    @State private var isPressed = false

    var body: some View {
        ZStack {
            Circle().fill(.ultraThinMaterial)
            Circle().fill(Color.white.opacity(isPressed ? 0.38 : isHovered ? 0.26 : 0.16))
            Circle().strokeBorder(Color.white.opacity(isHovered ? 0.50 : 0.24), lineWidth: 1)
            Image(systemName: icon)
                .font(.system(size: fontSize, weight: .semibold))
                .foregroundStyle(Color.white)
                .contentTransition(.symbolEffect(.replace))
        }
        .frame(width: size, height: size)
        .scaleEffect(isPressed ? 0.88 : isHovered ? 1.06 : 1.0)
        .shadow(color: .black.opacity(isHovered ? 0.55 : 0.4),
                radius: isHovered ? 28 : 16, y: isHovered ? 8 : 4)
        .animation(isPressed ? .easeOut(duration: 0.09)
                             : .spring(response: 0.3, dampingFraction: 0.7),
                   value: isHovered)
        .animation(.easeOut(duration: 0.09), value: isPressed)
        .onHover { isHovered = $0 }
        .onTapGesture { action() }
        .simultaneousGesture(
            DragGesture(minimumDistance: 0)
                .onChanged { _ in isPressed = true }
                .onEnded   { _ in isPressed = false }
        )
    }
}

/// Play/pause button — observes PlayerState directly so spacebar (via
/// PlayerPanel.keyDown → PlayerState.togglePlayPause) updates the icon
/// without relying on a parent re-render passing a new `icon` param.
private struct PlayPauseButton: View {
    @Environment(PlayerState.self) private var playerState

    @State private var isHovered = false
    @State private var isPressed = false

    var body: some View {
        let icon = playerState.isPlaying ? "pause.fill" : "play.fill"
        ZStack {
            Circle().fill(.ultraThinMaterial)
            Circle().fill(Color.white.opacity(isPressed ? 0.38 : isHovered ? 0.26 : 0.16))
            Circle().strokeBorder(Color.white.opacity(isHovered ? 0.50 : 0.24), lineWidth: 1)
            Image(systemName: icon)
                .font(.system(size: 34, weight: .semibold))
                .foregroundStyle(Color.white)
                .contentTransition(.symbolEffect(.replace))
        }
        .frame(width: 84, height: 84)
        .scaleEffect(isPressed ? 0.88 : isHovered ? 1.06 : 1.0)
        .shadow(color: .black.opacity(isHovered ? 0.55 : 0.4),
                radius: isHovered ? 28 : 16, y: isHovered ? 8 : 4)
        .animation(isPressed ? .easeOut(duration: 0.09)
                             : .spring(response: 0.3, dampingFraction: 0.7),
                   value: isHovered)
        .animation(.easeOut(duration: 0.09), value: isPressed)
        .onHover { isHovered = $0 }
        .onTapGesture { playerState.togglePlayPause() }
        .simultaneousGesture(
            DragGesture(minimumDistance: 0)
                .onChanged { _ in isPressed = true }
                .onEnded   { _ in isPressed = false }
        )
    }
}

// MARK: - Scrub Bar

private struct ScrubBar: View {
    @Environment(PlayerState.self) private var playerState

    @State private var isHovered  = false
    @State private var isDragging = false

    var body: some View {
        VStack(spacing: 8) {
            GeometryReader { geo in
                let progress = playerState.duration > 0
                    ? CGFloat(playerState.currentTime / playerState.duration)
                    : 0
                let active   = isHovered || isDragging
                let trackH   = CGFloat(active ? 8 : 4)
                let knobX    = geo.size.width * progress - 8   // centre the 16-pt knob

                ZStack(alignment: .leading) {
                    // Track background
                    Capsule()
                        .fill(Color.white.opacity(0.28))
                        .frame(height: trackH)

                    // Filled portion
                    Capsule()
                        .fill(Color.ltAccent)
                        .frame(width: max(0, geo.size.width * progress), height: trackH)

                    // Draggable knob
                    Circle()
                        .fill(Color.white)
                        .frame(width: 16, height: 16)
                        .shadow(color: .black.opacity(0.5), radius: 4, y: 2)
                        .opacity(active ? 1 : 0)
                        .offset(x: max(0, min(geo.size.width - 16, knobX)))
                }
                .animation(.easeInOut(duration: 0.16), value: active)
                .contentShape(Rectangle())
                .onHover { isHovered = $0 }
                .gesture(
                    DragGesture(minimumDistance: 0)
                        .onChanged { value in
                            isDragging = true
                            let frac = max(0, min(1, value.location.x / geo.size.width))
                            playerState.skip(seconds: frac * playerState.duration - playerState.currentTime)
                        }
                        .onEnded { _ in isDragging = false }
                )
            }
            .frame(height: 28)

            HStack {
                Text(DurationFormatter.format(seconds: playerState.currentTime))
                    .font(.system(size: 20, weight: .medium).monospacedDigit())
                    .foregroundStyle(Color.white.opacity(0.9))
                Spacer()
                Text(DurationFormatter.format(seconds: playerState.duration))
                    .font(.system(size: 20, weight: .medium).monospacedDigit())
                    .foregroundStyle(Color.white.opacity(0.9))
            }
        }
    }
}

/// Rounded-rect glass back button (matches React BackButton).
private struct GlassBackButton: View {
    let action: () -> Void

    @State private var isHovered = false
    @State private var isPressed = false

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 10).fill(.ultraThinMaterial)
            RoundedRectangle(cornerRadius: 10)
                .fill(Color.white.opacity(isPressed ? 0.28 : isHovered ? 0.18 : 0.08))
            RoundedRectangle(cornerRadius: 10)
                .strokeBorder(Color.white.opacity(isHovered ? 0.36 : 0.14), lineWidth: 1)
            HStack(spacing: 5) {
                Image(systemName: "chevron.left")
                    .font(.system(size: 13, weight: .semibold))
                Text("Back")
                    .font(.system(size: 15, weight: .semibold))
            }
            .foregroundStyle(Color.white)
        }
        .frame(width: 88, height: 36)
        .scaleEffect(isPressed ? 0.88 : isHovered ? 1.06 : 1.0)
        .shadow(color: .black.opacity(0.4),
                radius: isHovered ? 14 : 2, y: isHovered ? 4 : 1)
        .animation(isPressed ? .easeOut(duration: 0.09)
                             : .spring(response: 0.3, dampingFraction: 0.7),
                   value: isHovered)
        .animation(.easeOut(duration: 0.09), value: isPressed)
        .onHover { isHovered = $0 }
        .onTapGesture { action() }
        .simultaneousGesture(
            DragGesture(minimumDistance: 0)
                .onChanged { _ in isPressed = true }
                .onEnded   { _ in isPressed = false }
        )
    }
}

// MARK: - Player Controls Overlay

struct PlayerControlsOverlay: View {
    @Environment(PlayerState.self) private var playerState
    var onBack: () -> Void

    var body: some View {
        ZStack {
            // Gradient scrims (top + bottom)
            VStack {
                LinearGradient(
                    colors: [Color.black.opacity(0.72), Color.black.opacity(0.48),
                             Color.black.opacity(0.18), Color.clear],
                    startPoint: .top, endPoint: .bottom
                )
                .frame(height: 160)
                Spacer()
                LinearGradient(
                    colors: [Color.clear, Color.black.opacity(0.22),
                             Color.black.opacity(0.52), Color.black.opacity(0.75)],
                    startPoint: .top, endPoint: .bottom
                )
                .frame(height: 170)
            }
            .ignoresSafeArea()
            .opacity(playerState.controlsVisible ? 1 : 0)

            // Top bar: Back + Title
            VStack {
                HStack(alignment: .center, spacing: 14) {
                    GlassBackButton(action: onBack)
                    if let title = playerState.currentVideo?.title {
                        Text(title)
                            .font(.system(size: 22, weight: .semibold))
                            .foregroundStyle(Color.white)
                            .lineLimit(1)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
                .padding(.horizontal, 48)
                .padding(.top, 40)
                Spacer()
            }
            .opacity(playerState.controlsVisible ? 1 : 0)

            // Center: Skip / Play / Skip
            HStack(spacing: 44) {
                GlassCircleButton(icon: "gobackward.10", fontSize: 22, size: 66) {
                    playerState.skip(seconds: -10)
                }
                PlayPauseButton()
                GlassCircleButton(icon: "goforward.10", fontSize: 22, size: 66) {
                    playerState.skip(seconds: 10)
                }
            }
            .opacity(playerState.controlsVisible ? 1 : 0)

            // Bottom: Scrub bar + time labels + volume
            VStack {
                Spacer()
                VStack(spacing: 16) {
                    ScrubBar()
                    HStack(spacing: 12) {
                        Image(systemName: "speaker.fill")
                            .font(.system(size: 18))
                            .foregroundStyle(Color.white.opacity(0.6))
                        Slider(
                            value: Binding(
                                get: { Double(playerState.player.volume) },
                                set: { playerState.setVolume(Float($0)) }
                            ),
                            in: 0...1
                        )
                        .tint(Color.ltAccent)
                        .frame(maxWidth: 200)
                        Image(systemName: "speaker.wave.3.fill")
                            .font(.system(size: 18))
                            .foregroundStyle(Color.white.opacity(0.6))
                        Spacer()
                        loopButton
                    }
                }
                .padding(.horizontal, 48)
                .padding(.bottom, 40)
            }
            .opacity(playerState.controlsVisible ? 1 : 0)
        }
        .animation(
            NSWorkspace.shared.shouldReduceMotion ? nil : .easeInOut(duration: 0.4),
            value: playerState.controlsVisible
        )
        .contentShape(Rectangle())
        .onTapGesture { playerState.showControls() }
        // onContinuousHover fires on every mouse-move, not just enter/exit,
        // so controls stay visible while the cursor is moving.
        .onContinuousHover { phase in
            if case .active = phase { playerState.showControls() }
        }
    }

    // MARK: - Loop Button

    private var loopButton: some View {
        Button { playerState.toggleLoop() } label: {
            Image(systemName: playerState.isLooping ? "repeat.1" : "repeat")
                .font(.system(size: 18, weight: .medium))
                .foregroundStyle(playerState.isLooping ? Color.ltAccent : Color.white.opacity(0.6))
        }
        .buttonStyle(.plain)
        .frame(width: 36, height: 36)
        .accessibilityLabel(playerState.isLooping ? "Loop on" : "Loop off")
    }

}
