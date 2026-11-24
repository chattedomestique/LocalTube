# AV (Audio & Video) audit - LocalTube v1.0.37

Scope: downloaded file on disk -> sound/picture on a child's TV. Swift is STATIC REVIEW ONLY (no Swift toolchain, no macOS here). Anything about AVFoundation/AppKit runtime behaviour is labelled `suspected` and collected under "Needs a real Mac". yt-dlp/ffmpeg behaviour WAS executed here (Linux, yt-dlp 2026.10.26, ffmpeg 6.1.1) against synthetic media; those results are `confirmed (executed)`.

**What changed vs the brief (PM correction folded in):** the live player is NOT a WKWebView overlay. `Bridge/PlayerOverlayController.swift:114-173` builds a borderless `NSPanel` holding an `AVPlayerView` (`controlsStyle = .none`) with an `NSHostingView` of the SwiftUI `PlayerControlsOverlay` (`Player/VideoPlayerView.swift:354`) above it. `Player/PlayerState.swift` and the overlay/scrub/button views in `Player/VideoPlayerView.swift` are LIVE. Dead: `WebUI/src/screens/PlayerScreen.tsx` (536 lines, only reachable via `window.__playerMode`, which no Swift file sets; `main.tsx:10-14`), and in `VideoPlayerView.swift` the `VideoPlayerView` struct (:33-121), `NativePlayerView` (:15-29) and `ResumePromptOverlay` (:125-163), used only by legacy `Views/Viewer/ViewerRootView.swift`. Scope item 4 (WKWebView overlay, JS<->Swift sync, overlay web-content crash) is therefore moot; replaced by SwiftUI hit-testing/focus analysis below.

---------------------------------------------------------------------------

## 1. Ranked playback-reliability risks (with evidence)

### AV-1 | Critical | confirmed (code) / runtime suspected | A file that will not play gives the child a silent black screen
- `Player/PlayerState.swift:35-72`: `play()` sets `isPlaying = true` immediately, then a detached `Task` does `try? await asset.load(.duration, .tracks)` (errors swallowed, :51), polls `item.status` up to 100 x 100 ms (:57-61), and `guard item.status == .readyToPlay else { return }` (:63) just returns. No `.failed` branch, no `item.error`, no `AVPlayerItemFailedToPlayToEndTime` / `PlaybackStalled` observer (grep: none), no message, no auto-dismiss, no bridge event. The overlay keeps showing a "pause" glyph over black.
- The 10 s cap is itself a bug: a spun-down external HDD or NAS that takes >10 s to open the first bytes is abandoned even though the item would have become ready later. `Video.isPlayable` is deliberately only `downloadState == .ready && !localFilePath.isEmpty` (`Models/Video.swift:36-38`, comment says "AVPlayerItem errors are handled at playback time" - they are not).
- `Bridge/LocalTubeBridge.swift:361-374` only guards "file missing"; corrupt/unsupported files pass straight through.
- Fix: observe `item.status` (KVO / `item.publisher(for: \.status)`) with no timeout; on `.failed`, or `try await asset.load(.isPlayable) == false`, or any video track with `isDecodable == false`: show an in-panel "This video can't play right now" with a large Back button, emit a `playbackFailed(videoId, reason)` bridge event, mark the video `.error`/needs-repair and queue a remux/transcode (AV-3). Add `AVPlayerItemFailedToPlayToEndTime` for mid-stream decode errors. Effort M, impact High.

### AV-2 | Major | confirmed (executed) | The yt-dlp selectors can still produce files AVPlayer cannot play, and the file is then marked `.ready`
Evidence: `Models/AppSettings.swift:17-34`, `Services/DownloadService.swift:320-332` (`-f <selector> --merge-output-format mp4 -o <path>.mp4`). I fed the app's exact selectors and flags to yt-dlp 2026.10.26 using synthetic format lists (script `.../work-av/fmtsel.py`) and then ran the real downloader against local fake `info_*.json` scenarios (`.../work-av/info_*.json`, outputs probed with ffprobe):

| YouTube offers | Selector result | File on disk named `*.mp4` | AVPlayer risk |
|---|---|---|---|
| avc1 + m4a (normal) | 137 + 140 | H.264 + AAC in MP4 | OK |
| no avc1, AV1/VP9 + m4a (e.g. a client that omits H.264) | `best` fallback 3 `bestvideo[ext=mp4]+bestaudio[ext=m4a]` = **AV1 up to 2160p** + AAC | `av1,aac` in MP4 (scenario B) | AV1 hardware decode only on M3+; M1/M2/Intel uncertain (sources conflict); 4K60 on an old Mac = stutter. Also bypasses the 1080p cap |
| avc1 video but only Opus audio | fallback 2 `bestvideo[vcodec^=avc1]+bestaudio` | `h264,opus` in MP4 (scenario C) | Opus-in-MP4 is inconsistent on Apple (iOS 17 reports; macOS unconfirmed) -> picture with no sound |
| only a muxed WebM left (VP9) | final `/best` | **WebM bytes in a file named `.mp4`** (`format_name=matroska,webm`, scenario I) | AVPlayer does not open WebM (Apple Developer Forums) -> unplayable |
| Audio-only mode and no m4a | `bestaudio[ext=m4a]/bestaudio` -> Opus | **WebM/Opus bytes named `.mp4`** (scenario G) | unplayable |
| avc1 absent and no mp4 formats at all | all selectors fail | - | "Requested format is not available" shown to parent as a failed download (acceptable but opaque) |
|720p preset, only Opus audio | 720p selector has no `avc1+bestaudio` fallback | - | download fails where `best` would succeed (asymmetry, `AppSettings.swift:33`) |

- The hard-coded `-o <name>.mp4` (DownloadService.swift:304) means yt-dlp never corrects the extension, so container sniffing by extension in AVFoundation sees a lie. The comment at `AppSettings.swift:6-7` acknowledges "AV1/VP9 can stall on first frame" but fallbacks 3 and `/best` re-admit them.
- Whether the fall-through happens in practice depends on which formats YouTube's clients expose that day; the UPD lane notes 2026 SABR-related missing formats (my own search found yt-dlp issue reports of clients returning reduced format sets; not authoritative).
- Fix: see section 2 (policy). Effort S for selector + M for normaliser. Impact High.

### AV-3 | Major | confirmed | No post-download or library-wide playability check; no remux/transcode fallback exists
- `DownloadService.swift:368-373`: after yt-dlp exit 0 the only checks are `fileExists` and an ffprobe duration that is `try?` -> 0 on any failure (:425-434). State goes to `.ready` (:405). No codec/container inspection, no `AVAsset.isPlayable`.
- `LibraryMaintenanceService.verify` checks existence/paths/thumbnails only (:183-298, grep shows no ffprobe/duration/playability work). So a bad file stays "ready" forever, and the only symptom is AV-1 at play time.
- Fix: a `MediaNormalizer` step run after download and as part of Verify: `ffprobe -v error -show_entries format=format_name:stream=codec_type,codec_name,profile,pix_fmt,width,height -of json` (executed here; output is compact and parseable), compare to the whitelist in section 2, and remux/transcode when needed. Add a runtime AVFoundation check in `PlayerState.play` as the second line of defence. Effort M, impact High.

### AV-4 | Major | suspected (static) | Scrub-bar drag uses a stale base and exact seeks
- `VideoPlayerView.swift:287-294`: every drag event calls `playerState.skip(seconds: frac*duration - playerState.currentTime)`. `currentTime` is only refreshed by the 0.5 s periodic observer (`PlayerState.swift:157-168`), while `skip()` adds that delta to the live `player.currentTime()` (:86). After the first seek of a drag the two bases disagree, so the target overshoots by (actual - stale) until the next tick. Each event also issues a zero-tolerance seek (:89), which on YouTube's long-GOP H.264 means decode-from-keyframe per event, with no "chase" pattern.
- `skip()` has no upper clamp (:87): +10 s in the last 10 s seeks past the end -> `DidPlayToEnd` -> advances to the next video or exits.
- Fix: add `seek(toFraction:)` (absolute), tolerance +-0.5-1 s while dragging and `.zero` on release, chase-time pattern (one seek in flight), update `currentTime` immediately, clamp to `duration - 0.5`. Effort S, impact Med-High (the scrub bar is the main mouse control).

### AV-5 | Major | confirmed (code) | Resume position: stale in React, no "completed" rule, shared across profiles, silent
- Stale UI: Swift persists position (`PlayerState.swift:143-147`, `LibraryStore.swift:606-616`) but never tells React. `PlayerOverlayController.dismiss()` emits only `nowPlayingChanged(nil)` (:253-266); React fetches state only at startup (`WebUI/src/store.ts:542`, `Onboarding.tsx:26`). So `VideoCard.tsx:107,430,496` keeps showing the old "Resume at m:ss" and progress bar (even after a finished video was reset to 0) until some unrelated full state update arrives (downloads, sync).
- No completed threshold: `stop()` saves unless within 2 s of the end (`PlayerState.swift:101`), so quitting at 97% resumes at 97%; natural end resets to 0 via the PlayerState observer (:178-186).
- Per video, not per profile (`videos.resume_position_seconds`, `DatabaseService.swift:430`): siblings overwrite each other's progress; "Continue watching" per profile (TODO.md:112-117) would need `profile_watches`.
- Silent resume: `PlayerOverlayController.swift:80` starts at the saved point (>10 s) with no "Start over" (prompt exists only in dead `VideoPlayerView.swift:98-105,125-163`). Thresholds disagree: card shows resume for >5 s (`VideoCard.tsx:107`), player ignores <=10 s.
- Cadence: `seconds.truncatingRemainder(dividingBy: 5) < 0.55` on a 0.5 s observer (`PlayerState.swift:164`) saves 1-2x per 5 s window (harmless, sloppy). `applicationWillTerminate` (`AppDelegate.swift:180-185`) does not flush; quitting via the red close button (`WebWindowController.swift:288-290` -> terminate) can lose up to 5 s plus any in-flight DB `Task`.
- Fix: after stop/end emit `videosUpserted` for that video; rule "if >=95% or <15 s remaining -> store 0 and mark watched"; wall-clock throttle (every 5 s) + save on pause/seek/stop/willTerminate/sleep; offer Resume / Start over chips on the panel; move to per-profile progress when `profile_watches` lands. Effort S-M, impact Med-High.

### AV-6 | Major | confirmed | "Next"/"Shuffle" ignore the order and filters the child sees
- `PlayerOverlayController.swift:231-248` advances by `sortOrder` over all playable videos of the channel. The channel screen offers newest/oldest/title/longest/shortest sorts (`Channel.tsx:152-160`) plus favourites/search filters; the `playVideo` payload carries only `videoId/source/contextId` (`types.ts:231`). A child browsing "newest" and pressing Play gets "Next" from a different hidden order. `.random` can also pick videos hidden from the current filter.
- Fix: send the displayed ordered `videoIds` with `playVideo` for channel source (as the queue already does) and advance within that list. Effort M, impact Med. Unit-test `nextVideo` (pure function candidate).

### AV-7 | Minor-Major | suspected | Two end-of-item observers racing; `PlayerState` is a hand-rolled state machine
- Both `PlayerState.swift:171-189` (registered at init) and `PlayerOverlayController.swift:184-193` (re-registered each `show`) listen to `AVPlayerItemDidPlayToEndTime` with `object: nil` and hop through `Task { @MainActor }`. Today PlayerState's task runs first (sets `isPlaying=false`, resets resume of the OLD video), then the overlay's task calls `playNext`. If the order ever flips (observer re-registration order, different queue), `playNext` sets `isPlaying=true`/`currentVideo=next` and PlayerState's task then sets `isPlaying=false` and **resets the next video's resume to 0**.
- `isPlaying` is toggled manually (`PlayerState.swift:75-82`), not derived from `player.timeControlStatus`: Space during loading flips it, then the load task calls `player.play()` unconditionally (:71) -> icon and sound disagree. System pauses (route change, interruption) are not reflected.
- The load `Task` (:49-72) is never cancelled: a quick second `play()` lets the first task write a stale `duration` (:52) or perform its `seek` on the new item (:68).
- `isLooping` is never reset in `play()`/`stop()` (:13,:135-139), so Loop toggled once stays on for every later video and `actionAtItemEnd` is left at `.none`; spec says "off by default, toggleable per-video" (`LocalTube_Parameters.md:197`).
- Fix: one item-scoped observer (`object: item`) owned by `PlayerState` with an `onItemEnded` callback; KVO `timeControlStatus` and `currentItem.status`; cancel/generation-token the load task; reset loop per video. Effort M.
- H1/H8 (CODE_REVIEW) status: `fixed-already`. `PlayerState.cleanup()` removes the time and end observers (`PlayerState.swift:192-202`); `PlayerOverlayController` keeps ONE `endObserverToken` (:35,:177-194) and calls `cleanup()` in `deinit` (:268-275). The controller lives for the whole app (`WebWindowController.swift:22,142`), so nothing accumulates. Residual: tokens are not niled after `cleanup()` (a double call would trap) and `deinit` reads main-actor state from a nonisolated context.

### AV-8 | Major | suspected (needs Mac) | Hidden controls are still clickable
- `VideoPlayerView.swift:380,398,410,441` hide each control group with `.opacity(controlsVisible ? 1 : 0)` only. In SwiftUI, opacity 0 views still receive hits. A child (or the curious toddler) tapping where the invisible Back button sits (top-left, 88x36, `:334`), the centre Play/Pause (`:405`), the scrub bar or the Loop/Autoplay buttons will trigger them instead of just revealing the controls; top-left tap = leaves the video.
- Fix: `.allowsHitTesting(playerState.controlsVisible)` on each group; the first interaction only reveals. Effort S, impact Med.

### AV-9 | Major | partly confirmed | No sleep / screen-saver management
- grep over non-legacy Sources: no `beginActivity`, `IOPMAssertion`, `preventsDisplaySleepDuringVideoPlayback`, `NSWorkspace` sleep/wake observers. AVPlayer is believed to hold its own display-sleep assertion for VIDEO (WebKit bug trail on "AVPlayer automatic sleep disabling"; not verified for AVPlayerView on macOS), but audio-only mode (`.audio` quality) has no video, and the system idle-sleep behaviour for a projector/TV is exactly the app's use case. UPD-7 (Sparkle alert timing) also keys off "no display-sleep assertion".
- Fix: `ProcessInfo.processInfo.beginActivity(options: [.idleDisplaySleepDisabled, .idleSystemSleepDisabled, .userInitiated], reason: "Playing video")` while `timeControlStatus == .playing`, `endActivity` on pause/stop/dismiss; pause (or at least save position) on `NSWorkspace.willSleepNotification`. Effort S, impact High (display sleeping mid-movie / lock screen over a kid's show).

### AV-10 | Major | confirmed absent | No Now Playing, media keys, AirPlay, PiP, captions, audio-route handling
grep: zero hits for `MPNowPlayingInfoCenter`, `MPRemoteCommandCenter`, `AVRoutePickerView`, `AVPictureInPictureController`, `AVMediaSelection`/`legible`, `AVAudioSession`/CoreAudio device listeners, `NSCursor` hiding.
- Media keys / Bluetooth remotes/headsets: with no registered remote commands, macOS routes the Play/Pause key elsewhere (suspected: it can launch Music) - the most common "remote" for a Mac on a TV does nothing in LocalTube.
- Headphones unplugged/HDMI TV off/AirPlay drop: playback continues and audio falls to the Mac speakers (suspected; there is no handling). For a kid watching at night with headphones this is a loud-speaker surprise.
- No captions: yt-dlp is never asked for subtitles (`DownloadService.swift:320-332`), no CC button. Useful for early readers, hearing-impaired, and quiet viewing.
- Effort: media keys + Now Playing S-M; route-change pause M; captions M; AirPlay S; PiP not recommended for kids' TV use (Low).

### AV-11 | Major | confirmed | Volume model is weak: not remembered, no mute, no ceiling, no loudness consistency
- `player.volume` is the only control (`PlayerState.swift:93-96`); a fresh launch starts at 1.0 relative gain (TODO.md:156-157 already lists this). No mute key, no per-profile ceiling, and the slider's getter reads `player.volume` which is not observable (`VideoPlayerView.swift:421-427`) so it only repaints on the 0.5 s tick.
- Loudness: no normalisation anywhere (grep "loudnorm/ebur128": none). Executed here: `ffmpeg -af ebur128` measured two synthetic tones at -51.8 vs -24.8 LUFS in ~0.1 s for an 8 s clip (audio-only decode is cheap). Real kids' content spans roughly 10+ LU between channels, so the next video can be a sudden jump.
- Recommended design (no re-encode, non-destructive): at download/verify run `ffmpeg -nostats -i FILE -vn -af ebur128=framelog=quiet -f null -` and parse the final `I:` LUFS; store `loudness_lufs` (DB schema v10); at play set `player.volume = userVolume * min(1, 10^((-16 - lufs)/20))` (attenuate-only, because `AVPlayer.volume` cannot exceed 1.0), then clamp by `profile.maxVolume`. Optional bake-in alternative: `ffmpeg -i in.mp4 -c:v copy -af loudnorm=I=-16:TP=-1.5:LRA=11 -c:a aac -b:a 192k out.mp4` (rewrites the file; use only for outliers). Effort S (persist + ceiling + mute), M (loudness + schema), impact High for parents.

### AV-12 | Major | suspected (needs Mac) | Panel/window behaviour on a TV
- `PlayerOverlayController.swift:120-124`: `level = .floating`, `hidesOnDeactivate = false`, `collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]`. A floating, all-Spaces child panel stays on top of other apps and follows Space switches when LocalTube loses focus (a parent Cmd-Tabbing away leaves a black panel over Safari while audio plays).
- The panel covers only the content area (`:69-71`, `WebWindowController.swift:292-299`), so the title bar and traffic lights stay live during playback; the red button terminates the whole app (`WebWindowController.swift:288-290`) without flushing resume.
- "Enter Full Screen" (`AppDelegate.swift:292`, nil target `toggleFullScreen:`) resolves against the key window, which is the panel while playing; the panel has no `.fullScreenPrimary` so it is likely a no-op during playback (UI lane also notes the main window sets no `.fullScreenPrimary`, `WebWindowController.swift:125-136`). There is no F key. The spec says "Full-screen only - no windowed player" (`LocalTube_Parameters.md:193`); reality is a windowed overlay unless the parent manually enters full screen BEFORE pressing play.
- Cursor never hides (grep `NSCursor`: none), so a TV shows the pointer over the video.
- Fix: `level = .normal` (child windows track the parent), keep `.fullScreenAuxiliary` only, add `F` key -> `parentWindow.toggleFullScreen`, `NSCursor.setHiddenUntilMouseMoves(true)` together with the 4 s control hide, optionally auto-enter full screen when the Viewer starts playing. Effort S-M.

### AV-13 | Minor | confirmed (executed) | Thumbnail fallback still yields missing or black frames (CODE_REVIEW L6: partially fixed)
- `ThumbnailService.swift:15-22` now uses `-ss 1` (was 5 s) but as an OUTPUT option after `-i`, and `extract()` returns `outputPath` without checking a file exists (:23). Executed with ffmpeg 6.1.1: 0.6 s clip -> exit 0 and **no file written**; 2 s black-intro clip -> 1.6 KB JPEG with mean luma `YAVG=0` (pure black); audio-only -> exit 234 (throws, fine). Callers do guard with `fileExists` (`DownloadService.swift:396-399`, `LibraryMaintenanceService.swift:324`), so failure is quiet rather than harmful.
- It is only the fallback: normal path is yt-dlp's `--write-thumbnail --convert-thumbnails jpg` (`DownloadService.swift:326-327,375-399`). But Verify regenerates missing thumbnails with the ffmpeg still (`LibraryMaintenanceService.swift:305-330`), so repaired cards look different (video frame vs YouTube art) and may be black.
- Fix: `ffmpeg -ss <clamp(0.1*duration, 0.3, 30)> -i FILE -frames:v 1 -vf "scale=640:-2" -q:v 3`, reject results with `signalstats` YAVG < 16 and retry at 50% of duration; prefer re-fetching the YouTube thumbnail (`refreshThumbnails`, `DownloadService.swift:474-517`) when online. Effort S, impact Low.

### AV-14 | Minor | confirmed | Duration can silently be 0 forever
- `DownloadService.swift:425-434` uses `try?`; `ShellRunner.run` refuses non-absolute paths (`ShellRunner.swift:55`), and `findFfprobe()` returns the bare name `ffprobe` if `resolveToolPaths()` has not populated the cache and neither Homebrew prefix has it (:451-457). Result 0 -> card "0:00" and `VideoCard.tsx:430` computes `resume/0 = Infinity` (clamped to a full bar). Nothing backfills duration (grep: no duration handling in `LibraryMaintenanceService`).
- Fix: backfill in Verify, and let the player persist `asset.load(.duration)` when the stored value is 0. Effort S.

### AV-15 | Minor | confirmed | No disk-space preflight for downloads
- Only the relocation analyser reads free space (`LibraryMaintenanceService.swift:545`). Four parallel yt-dlp jobs (`DownloadService.swift:35`), each holding separate video+audio temp files before merge (~2x), can fill an external drive; the failure surfaces as the last `ERROR` line (generic) after minutes.
- Fix: before starting a job check `volumeAvailableCapacityForImportantUsage` against `filesize_approx` x 2.5 (or 1.5 GB default); pause the queue with a clear parent-facing message. Effort M.

### AV-16 | Minor | confirmed | Audio-only quality has no matching player experience
- `.audio` yields an `.mp4`-named audio file (`AppSettings.swift:25-28`); the panel shows black with title/controls (AVPlayerView has no video), the thumbnail is not displayed, and it is a GLOBAL setting so a parent downloading a music channel flips every later download. Fix: if the asset has no video track, show the thumbnail full-bleed in the panel; make audio-only a per-channel/per-add option; use `-x --audio-format m4a` (below). Effort S-M.

### AV-17 | Minor | suspected | Keyboard focus can be taken from the panel
- `PlayerPanel.keyDown` (`PlayerOverlayController.swift:299-315`) only sees keys the first responder did not consume. After a click on the SwiftUI `Slider` (volume, `VideoPlayerView.swift:421-429`) or a focused `Button`, arrows/space may be consumed by the control instead (volume nudges instead of seek). `mouseDown` re-keys the panel (:294-297) but not the first responder. Also no `isARepeat` handling (holding an arrow floods seeks) and no `Return`/media keys.

### AV-18 | Minor | confirmed | Dead code to delete
`WebUI/src/screens/PlayerScreen.tsx` (+ `main.tsx:5,10-14` branch, harness `player` scenario); in `Player/VideoPlayerView.swift`: `VideoPlayerView`, `NativePlayerView`; `ResumePromptOverlay` should be REVIVED for AV-5 rather than deleted.

---------------------------------------------------------------------------

## 2. Recommended format / remux policy (concrete)

Principle: the app must only ever hand AVPlayer H.264 (8-bit 4:2:0, up to 1080p) + AAC in an MP4 (or AAC in M4A for audio-only), and must verify that by probing, never by trusting the extension.

**A. Selector (replace `ytDlpFormat`)** with H = 1080/720/480/360 (best = 1080):
```
-f "bv*[vcodec^=avc1][height<=H]+ba[ext=m4a]/b[vcodec^=avc1][acodec^=mp4a][height<=H]/bv*[height<=H]+ba/b[height<=H]"
-S "res:H,vcodec:h264,acodec:aac,ext:mp4:m4a"
--merge-output-format mp4
--remux-video mp4
-o "<base>.%(ext)s"                 # never hard-code .mp4
--print "after_move:filepath"       # learn the real final path
```
(`-t mp4` is a built-in yt-dlp preset for `--merge-output-format mp4 --remux-video mp4 -S vcodec:h264,lang,quality,res,fps,hdr:12,acodec:aac`; it exists in 2026.10.26 `--help` and is a good starting point.) Rules: tier 1-2 are AVPlayer-safe; tier 3-4 are "anything at or below H" and MUST go through the normaliser. Drop `bestvideo[ext=mp4]` (AV1 in MP4) and bare `/best` without a cap. Give every preset the same fallback chain (the 720p selector currently lacks `avc1+bestaudio`). Optionally `--extractor-args "youtube:lang=en"`/`-S lang:en` to avoid auto-dubbed audio (suspected issue, not tested).

**B. Audio-only**: `-f "ba[acodec^=mp4a]/ba" -x --audio-format m4a -o "<base>.%(ext)s"` (yt-dlp transcodes Opus to AAC; result is a real `.m4a`). Store the true path.

**C. What the flags do (executed)**: `--merge-output-format mp4` only chooses the container for merges and does NOT convert codecs or fix a single-stream WebM; `--remux-video mp4` repackages WebM -> MP4 without re-encoding and worked here for VP9 and Opus (but VP9/Opus in MP4 are still not AVPlayer-safe); `--recode-video mp4` transcodes (VP9 WebM -> H.264 MP4 worked; slower). With a literal `-o x.mp4`, yt-dlp 2026.10.26 still downloaded to `x.webm` then remuxed to `x.mp4` when `--remux-video` was set, so adding `--remux-video mp4` alone fixes the "WebM named .mp4" lie but not the codec problem.

**D. Normaliser (post-download and in Verify), keyed on ffprobe not extension**:
- Accept if container is `mov,mp4,m4a`, video `h264` (profile baseline/main/high, `yuv420p`, <=1080p), audio `aac` (or mp3/alac), no more than one video stream.
- Audio not AAC (Opus/Vorbis): `ffmpeg -i in -map 0:v:0 -map 0:a:0 -c:v copy -c:a aac -b:a 160k -movflags +faststart out.mp4` (executed: `h264,opus` -> `h264,aac`).
- Video VP9/AV1/HEVC/10-bit or WebM container: re-encode, on macOS `-c:v h264_videotoolbox -b:v 6M -pix_fmt yuv420p` (untested here; hardware encoder, fast) with libx264 fallback `-preset veryfast -crf 21 -pix_fmt yuv420p` (executed: 8 s 720p VP9 -> H.264 in 1.26 s on 4 cores). Always `-c:a aac -b:a 160k -movflags +faststart`.
- Write to `out.tmp.mp4`, ffprobe it, atomically replace, keep the original until the replacement validates. Count it as the download's final 100 % so the UI does not show "ready" early.
- Runtime second line: `try await asset.load(.isPlayable)` and `tracks.allSatisfy { $0.isDecodable }` in `PlayerState.play` -> failure path of AV-1 queues a repair.
- 4K60/HDR: out of the policy on purpose (H.264 tops out at 1080p on YouTube; HDR/AV1/VP9.2 need a TV/Mac pair that tonemaps correctly). HEVC is not offered by YouTube and not needed.

---------------------------------------------------------------------------

## 3. Features ranked by value for kids/parents
1. **Playback-failure screen + auto-repair + "skip to next"** (AV-1/3): the only way a broken file becomes a recoverable state. Parent value very high, effort M.
2. **Sleep/screen-saver inhibition + pause on system sleep** (AV-9). S.
3. **Media keys + Now Playing (`MPRemoteCommandCenter`: play, pause, toggle, skip +-10, next/prev) and pause when the audio route changes away from headphones/HDMI** (AV-10). S-M.
4. **Sleep timer / "stop after this video"** (15/30/45 min, fade volume over the last 60 s, then pause and show a calm "Time to rest" card; per profile, parent-set). S-M. (UX lane also asks for it.)
5. **Per-profile volume ceiling + remembered volume + mute + attenuate-only loudness normalisation** (AV-11). S then M.
6. **Resume / Start over chips, "watched" marker, >=95 % = completed** (AV-5). S-M.
7. **Captions toggle (CC)**: download `--write-subs --sub-langs "en.*,-live_chat" --embed-subs` (embeds `mov_text` in MP4; yt-dlp `postprocessor/ffmpeg.py:221` confirms `-c:s mov_text`), then `asset.loadMediaSelectionGroup(for: .legible)` and `item.select(option, in: group)`; AVPlayerView renders it. M.
8. **"Up next" countdown** (5-8 s card with Cancel) for queue/sequential instead of a hard cut (`advanceOrDismiss`). S-M.
9. **Playback speed (0.75x/1x/1.25x)**, parent-gated. S.
10. **AirPlay route button** (`AVRoutePickerView` in the controls) for Apple-TV setups. S. PiP: Low value for a kids' TV app.
11. Cursor auto-hide, F fullscreen, auto-enter full screen on play (AV-12). S.

## 4. Exact player controls and keys that should exist
Keys (handled in `PlayerPanel.keyDown`, ignore `isARepeat` for Space/Esc/F/M/C; allow repeat for arrows):

| Key | Action |
|---|---|
| Space, K, Return | Play / Pause |
| Left / Right | -10 s / +10 s (clamped to 0 and duration-0.5) |
| Up / Down | Volume +-5 %, never above profile ceiling |
| M | Mute / unmute |
| F | Toggle full screen of the parent window |
| C | Captions on/off (if track exists) |
| N / P | Next / Previous item when queue or sequential |
| Esc | Back to library (also saves position) |
| 0-9 | Jump to 0-90 % (optional) |
| Media keys | Play/Pause, Next, Previous, +-10 s |
Today only Esc, Space, Left/Right, Up/Down exist (`PlayerOverlayController.swift:302-311`); Up/Down step is 0.1.

Visible controls (auto-hide after 4 s while playing, stay while paused, hit-testing disabled when hidden, cursor hides with them): Back (>=96 pt target per the ten-foot rules; today 88x36 pt, 15 pt label, `VideoPlayerView.swift:334`), title, -10 / Play-Pause / +10 (66/84 pt today), scrub bar with a 44 pt-tall hit area (today 32 pt, `:297`) and absolute seek, elapsed/remaining labels (28 pt today, fine), volume + mute, CC, Next, Loop (per video, resets), Autoplay-mode cycle (consider PIN gate; UX lane). Add accessibility labels/traits to every control (today only Loop and Autoplay have them, `:466,497`).

---------------------------------------------------------------------------

## 5. Experiments performed (all in `.../scratchpad/work-av/`, reproducible)
- `fmtsel.py`: yt-dlp format-selection simulation (synthetic YouTube-like format lists) for the app's `best`, 720p and audio selectors across 8 availability scenarios.
- `info_*.json` + local `python -m http.server`: real yt-dlp 2026.10.26 downloads with the app's exact flags; ffprobe of results (`out/`, `out2/`). Results in AV-2 and policy section C.
- `thumb/`: ffmpeg 6.1.1 run of the app's thumbnail command on 0.6 s, black-intro, normal and audio-only inputs (AV-13).
- `ebur128` loudness measurement (AV-11); remux/transcode commands (policy D).
- Generic web research (no project details): AVPlayer does not open WebM; Opus-in-MP4 support on Apple platforms is inconsistent/undocumented for macOS; AV1 hardware decode is M3-class, software path on older Macs uncertain; AVPlayer has its own display-sleep behaviour that is not authoritatively documented for AVPlayerView; yt-dlp 2026 SABR experiments can reduce the format set for some clients. Sources: Apple Developer Forums threads 722399, 775937, 832486, 739953, 722933, 801791; WebKit Bugzilla 200774; yt-dlp issue 16150.

## 6. Needs a real Mac to confirm
1. `AVURLAsset.isPlayable` / `AVAssetTrack.isDecodable` for: H.264+AAC (control), AV1+AAC, H.264+Opus MP4, VP9 MP4, WebM-bytes-in-.mp4, on macOS 14 and 15, Intel vs M1/M2 vs M3 (test files can be regenerated from `.../work-av/out/*.mp4`).
2. Whether AVPlayerView holds a display-sleep assertion (`pmset -g assertions` during video and during audio-only).
3. Hidden-control hit-testing (AV-8) and that `.allowsHitTesting(false)` fixes it.
4. Panel behaviour: Cmd-Tab with the panel floating, Space switching, external-display/TV placement, red-button quit during play, `⌃⌘F` while the panel is key, green button.
5. Scrub drag overshoot/jitter (AV-4) on a 1080p long-GOP file.
6. Arrow/space consumed after clicking the volume slider (AV-17).
7. Media key and headphone-unplug behaviour with no remote-command registration.
8. Slow-disk open > 10 s (NAS/spun-down HDD) abandoning playback.

## 7. Cross-lane notes
- UI: `WebWindowController.swift:125-136` sets no `.fullScreenPrimary` (UI lane raised it); fullscreen is central to the TV use case. Delete `PlayerScreen.tsx` + `main.tsx:10-14` + harness player scenario.
- UPD: format-selector fall-through depends on YouTube client format availability; add a canary that asserts avc1+m4a is returned; stop hard-coding `.mp4` in `-o`.
- ARC: no `WKNavigationDelegate` / `webViewWebContentProcessDidTerminate` anywhere (grep) so a dead WebContent process leaves a blank main UI (the native player keeps playing); new DB columns (`loudness_lufs`, per-profile resume/maxVolume) need schema v10.
- UX: close button quits the app during playback; in-player autoplay cycle has no PIN; Resume prompt exists in dead code and should be revived.
- QA: add ffprobe fixtures (the `out/` files) and unit tests for `nextVideo` and resume-threshold logic.
