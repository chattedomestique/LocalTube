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

    @Environment(AppState.self)   private var appState
    @Environment(PlayerState.self) private var playerState

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            NativePlayerView(player: playerState.player)
                .ignoresSafeArea()

            PlayerControlsOverlay(onBack: { goBack() })
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
        playerState.play(video: video)
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

// MARK: - Player Controls Overlay

struct PlayerControlsOverlay: View {
    @Environment(PlayerState.self) private var playerState
    var onBack: () -> Void

    var body: some View {
        ZStack {
            // Gradient scrims (top + bottom)
            VStack {
                LinearGradient(
                    colors: [Color.black.opacity(0.7), Color.clear],
                    startPoint: .top, endPoint: .bottom
                )
                .frame(height: 140)
                Spacer()
                LinearGradient(
                    colors: [Color.clear, Color.black.opacity(0.7)],
                    startPoint: .top, endPoint: .bottom
                )
                .frame(height: 180)
            }
            .ignoresSafeArea()
            .opacity(playerState.controlsVisible ? 1 : 0)

            // Top bar: Back + Title + Loop
            VStack {
                HStack(alignment: .center, spacing: 0) {
                    backButton
                    Spacer()
                    if let title = playerState.currentVideo?.title {
                        Text(title)
                            .font(.ltHeadline)
                            .foregroundStyle(Color.ltText)
                            .lineLimit(1)
                            .padding(.horizontal, 20)
                    }
                    Spacer()
                    loopButton
                }
                .padding(.horizontal, 32)
                .padding(.top, 24)
                Spacer()
            }
            .opacity(playerState.controlsVisible ? 1 : 0)

            // Center: Skip / Play / Skip
            HStack(spacing: 48) {
                skipButton(seconds: -10, icon: "gobackward.10")
                playPauseButton
                skipButton(seconds: 10, icon: "goforward.10")
            }
            .opacity(playerState.controlsVisible ? 1 : 0)

            // Bottom: Progress + Volume
            VStack {
                Spacer()
                VStack(spacing: 16) {
                    progressBar
                    volumeBar
                }
                .padding(.horizontal, 40)
                .padding(.bottom, 40)
            }
            .opacity(playerState.controlsVisible ? 1 : 0)
        }
        .animation(
            NSWorkspace.shared.shouldReduceMotion ? nil : .easeInOut(duration: 0.25),
            value: playerState.controlsVisible
        )
        .contentShape(Rectangle())
        .onTapGesture { playerState.showControls() }
        .onHover { if $0 { playerState.showControls() } }
    }

    // MARK: - Buttons

    private var backButton: some View {
        Button(action: onBack) {
            HStack(spacing: 8) {
                Image(systemName: "chevron.left").font(.system(size: 22, weight: .semibold))
                Text("Back").font(.ltHeadline)
            }
            .foregroundStyle(Color.ltText)
        }
        .buttonStyle(.plain)
        .frame(minWidth: LT.minTargetSize, minHeight: LT.minTargetSize)
        .accessibilityLabel("Back to library")
    }

    private var loopButton: some View {
        Button { playerState.toggleLoop() } label: {
            Image(systemName: playerState.isLooping ? "repeat.1" : "repeat")
                .font(.system(size: LT.sfSymbolSize * 0.7))
                .foregroundStyle(playerState.isLooping ? Color.ltAccent : Color.ltTextSecondary)
        }
        .buttonStyle(.plain)
        .frame(width: LT.minTargetSize, height: LT.minTargetSize)
        .accessibilityLabel(playerState.isLooping ? "Loop on" : "Loop off")
    }

    private var playPauseButton: some View {
        Button { playerState.togglePlayPause() } label: {
            Image(systemName: playerState.isPlaying ? "pause.fill" : "play.fill")
                .font(.system(size: 64))
                .foregroundStyle(Color.ltText)
        }
        .buttonStyle(.plain)
        .frame(width: LT.minTargetSize * 1.2, height: LT.minTargetSize * 1.2)
        .accessibilityLabel(playerState.isPlaying ? "Pause" : "Play")
    }

    private func skipButton(seconds: Double, icon: String) -> some View {
        Button { playerState.skip(seconds: seconds) } label: {
            Image(systemName: icon)
                .font(.system(size: LT.sfSymbolSize))
                .foregroundStyle(Color.ltText)
        }
        .buttonStyle(.plain)
        .frame(width: LT.minTargetSize, height: LT.minTargetSize)
        .accessibilityLabel(seconds < 0 ? "Skip back 10 seconds" : "Skip forward 10 seconds")
    }

    // MARK: - Progress Bar

    private var progressBar: some View {
        VStack(spacing: 8) {
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule().fill(Color.ltTextTertiary.opacity(0.5)).frame(height: 6)
                    Capsule()
                        .fill(Color.ltAccent)
                        .frame(
                            width: playerState.duration > 0
                                ? geo.size.width * CGFloat(playerState.currentTime / playerState.duration)
                                : 0,
                            height: 6
                        )
                }
                .contentShape(Rectangle())
                .gesture(
                    DragGesture(minimumDistance: 0).onChanged { value in
                        let frac = max(0, min(1, value.location.x / geo.size.width))
                        playerState.skip(seconds: frac * playerState.duration - playerState.currentTime)
                    }
                )
            }
            .frame(height: 6)

            HStack {
                Text(DurationFormatter.format(seconds: playerState.currentTime))
                    .font(.ltCaption).foregroundStyle(Color.ltTextSecondary)
                Spacer()
                Text(DurationFormatter.format(seconds: playerState.duration))
                    .font(.ltCaption).foregroundStyle(Color.ltTextSecondary)
            }
        }
    }

    // MARK: - Volume Bar

    private var volumeBar: some View {
        HStack(spacing: 12) {
            Image(systemName: "speaker.fill").font(.system(size: 20)).foregroundStyle(Color.ltTextSecondary)
            Slider(
                value: Binding(
                    get: { Double(playerState.player.volume) },
                    set: { playerState.setVolume(Float($0)) }
                ),
                in: 0...1
            )
            .tint(Color.ltAccent)
            .frame(maxWidth: 200)
            Image(systemName: "speaker.wave.3.fill").font(.system(size: 20)).foregroundStyle(Color.ltTextSecondary)
        }
    }
}
