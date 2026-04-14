import Foundation
import AVFoundation
import Observation

@Observable
@MainActor
final class PlayerState {
    let player = AVPlayer()

    var currentVideo: Video?
    var isPlaying: Bool = false
    var controlsVisible: Bool = true
    var isLooping: Bool = false
    var duration: Double = 0
    var currentTime: Double = 0

    private var hideControlsTask: Task<Void, Never>?
    private var timeObserverToken: Any?
    private var itemEndObserver: Any?
    weak var appState: AppState?   // internal so ViewerRootView can wire it post-init

    init(appState: AppState? = nil) {
        self.appState = appState
        setupPlayer()
    }

    // MARK: - Playback

    /// Begin playback of `video` from an explicit position.
    /// Pass `startSeconds: 0` to play from the beginning, or the saved
    /// `video.resumePositionSeconds` to resume. The resume/start decision
    /// is made by the caller (VideoPlayerView) based on the saved position.
    func play(video: Video, startSeconds: Double) {
        guard video.isPlayable else { return }
        currentVideo = video

        let url  = URL(fileURLWithPath: video.localFilePath)
        let asset = AVURLAsset(url: url)
        let item  = AVPlayerItem(asset: asset)
        player.replaceCurrentItem(with: item)

        isPlaying = true
        showControls()

        // Wait for the item to reach .readyToPlay before calling play().
        // This is important for codecs like AV1 that need the hardware
        // decoder to initialise before the first frame can be displayed.
        // Without this, AVPlayerView shows a gray placeholder until ready.
        Task {
            // Load duration and playback-ready status together.
            let (dur, _) = (try? await asset.load(.duration, .tracks)) ?? (nil, nil)
            if let dur, dur.isValid, !dur.isIndefinite {
                self.duration = CMTimeGetSeconds(dur)
            }

            // Wait for the item to be ready (up to 10 s for slow decoders)
            var waited = 0
            while item.status != .readyToPlay && waited < 100 {
                try? await Task.sleep(nanoseconds: 100_000_000) // 100 ms
                waited += 1
            }

            guard item.status == .readyToPlay else { return }

            if startSeconds > 0 {
                let time = CMTime(seconds: startSeconds, preferredTimescale: 600)
                let tol  = CMTime(seconds: 1, preferredTimescale: 600)
                await player.seek(to: time, toleranceBefore: tol, toleranceAfter: tol)
            }

            player.play()
        }
    }

    func togglePlayPause() {
        if isPlaying {
            player.pause()
        } else {
            player.play()
        }
        isPlaying.toggle()
        showControls()
    }

    func skip(seconds: Double) {
        let current = CMTimeGetSeconds(player.currentTime())
        let target = max(0, current + seconds)
        let time = CMTime(seconds: target, preferredTimescale: 600)
        player.seek(to: time, toleranceBefore: .zero, toleranceAfter: .zero)
        showControls()
    }

    func setVolume(_ volume: Float) {
        player.volume = max(0, min(1, volume))
        showControls()
    }

    func stop() {
        // Don't save position if video played to end — it was already reset to 0
        let pos = CMTimeGetSeconds(player.currentTime())
        if duration <= 0 || pos < duration - 2 {
            saveResumePosition()
        }
        player.pause()
        player.replaceCurrentItem(with: nil)
        isPlaying = false
        currentVideo = nil
        duration = 0
        currentTime = 0
    }

    // MARK: - Controls Visibility

    func showControls() {
        controlsVisible = true
        scheduleControlsHide()
    }

    private func scheduleControlsHide() {
        hideControlsTask?.cancel()
        hideControlsTask = Task {
            try? await Task.sleep(nanoseconds: 4_000_000_000)
            guard !Task.isCancelled else { return }
            await MainActor.run { self.controlsVisible = false }
        }
    }

    func toggleLoop() {
        isLooping.toggle()
        // .none keeps the player at the last frame; our itemEndObserver handles seek-back
        player.actionAtItemEnd = .none
    }

    // MARK: - Resume Position

    private func saveResumePosition() {
        guard let video = currentVideo else { return }
        let pos = CMTimeGetSeconds(player.currentTime())
        appState?.updateResumePosition(videoId: video.id, seconds: pos)
    }

    // MARK: - Setup

    private func setupPlayer() {
        // Local files don't need adaptive buffering — disabling this removes
        // the artificial startup stall AVPlayer adds for network streams.
        player.automaticallyWaitsToMinimizeStalling = false

        // Periodic observer: update currentTime + persist resume position every 5 s
        let interval = CMTime(seconds: 0.5, preferredTimescale: 600)
        timeObserverToken = player.addPeriodicTimeObserver(forInterval: interval, queue: .main) { [weak self] time in
            guard let self = self else { return }
            let seconds = CMTimeGetSeconds(time)
            Task { @MainActor in
                self.currentTime = seconds
                // Save resume position every 5 seconds
                if seconds > 0 && seconds.truncatingRemainder(dividingBy: 5) < 0.55 {
                    self.saveResumePosition()
                }
            }
        }

        // Loop: proper item-end notification instead of polling the time observer
        itemEndObserver = NotificationCenter.default.addObserver(
            forName: .AVPlayerItemDidPlayToEndTime,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                guard let self else { return }
                if self.isLooping {
                    self.player.seek(to: .zero)
                    self.player.play()
                } else {
                    self.isPlaying = false
                    // Reset resume position so the video starts from the beginning next time
                    if let video = self.currentVideo {
                        self.appState?.updateResumePosition(videoId: video.id, seconds: 0)
                    }
                }
            }
        }
    }

    nonisolated func cleanup() {
        let (timeToken, endObserver) = MainActor.assumeIsolated {
            (timeObserverToken, itemEndObserver)
        }
        if let timeToken {
            player.removeTimeObserver(timeToken)
        }
        if let endObserver {
            NotificationCenter.default.removeObserver(endObserver)
        }
    }
}
