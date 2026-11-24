# LocalTube — Gameplan (November 2026)

> **Status: DRAFT v2 — all nine audit lanes merged.** Audio & Video, the last lane, is folded into §4 (items 11b, 11c, 20b, 20c, 30b) and detailed in §9.
> **Baseline:** v1.0.37 (build 38), `master` @ `9a3eed7`. **Method:** nine specialist agents, each read-only, each writing a full report to [`audit-2026-11/`](audit-2026-11/). Roughly 135 findings in total; this document de-duplicates and ranks them.
>
> **Confidence legend.** ✔ = confirmed in code, or reproduced in a browser harness with a fake Swift bridge. ? = suspected from reading Swift; **no Swift toolchain or Mac was available**, so nothing Swift-side was built or run. §7 lists everything that needs a real Mac.
> **Effort.** S ≤ ½ day · M 1–3 days · L > 3 days (rough, one developer).

---

## 1. Bottom line

LocalTube's engine is in better shape than the safety net around it. Earlier audits fixed the scary things (JS injection, `curl | bash`, SQL, path traversal, pipe deadlocks, persistence). What is left falls into six buckets, in the order they hurt a real family:

1. **A fresh Mac cannot get started.** The React UI migration dropped the dependency installer and the channel resolver (both now live only in dead SwiftUI). Nothing ever updates yt-dlp, and YouTube now needs an external JS runtime that nothing installs. *(verified by me in code)*
2. **It cannot be driven from a couch.** Cards aren't focusable, there are no focus rings, no arrow-key navigation, dialogs don't close on Esc, and at 1080p 77–100 % of text is ≤ 17 px against a spec that says 28 pt. Controls are 34–44 px against a 96 pt spec.
3. **Kid-safety is a UI convention, not an enforced rule.** The Swift bridge accepts every message in every mode; several menu items and the drive-unplugged screen skip the PIN; the edit/admin session never expires; and PIN recovery doesn't exist.
4. **A handful of bugs lose or misreport data.** A crash mid-migration can brick the database; a video a parent deletes from a synced channel comes back; relocation can delete a good file; finished downloads show "99 %" forever; removing a channel can crash the React tree.
5. **Nothing stops a bad build reaching every install.** Every merge to `master` auto-signs and ships. There are zero tests. The release is probably Apple-Silicon-only.
6. **"Ready" doesn't mean playable.** Nothing verifies a download will play: the format selectors can still produce AV1, Opus-in-MP4 or WebM bytes in a `.mp4`, and a load failure leaves the child on a silent black screen. The screen can also sleep mid-show, because nothing holds a sleep assertion. *(AV-1/2/3/9; I confirmed the silent-failure path and the absence of sleep inhibition in code.)*

Underneath those: the Swift→JS bridge re-sends the whole library on every download/PIN keypress, ~32 % of the Swift is dead code, and the app has **three type scales and two accent colours** with no shared tokens.

## 2. Where our picture of the app was wrong

| What the docs / we assumed | What is true |
|---|---|
| SwiftUI app (spec §2) | Pure AppKit shell + React UI in a `WKWebView`. |
| `Views/**` + `Player/**` are legacy | `Views/**` is dead (~3.6k LOC). **`Player/**` is live**: the player controls are SwiftUI `PlayerControlsOverlay` over `AVPlayerView`. `WebUI/src/screens/PlayerScreen.tsx` is the dead one. *(My own brief had this backwards; caught by two agents, I verified and corrected the others.)* |
| `CODE_REVIEW.md` C3, M7 etc. are open (`TODO.md`) | Fixed. `TODO.md` is stale in several places. |
| H9, M12, C4/L4, P12, M13 "fixed" | **Not fully fixed** (add-videos loading state is a fake 2 s timer; `sendBridgeWithTimeout` is never called; PIN is a single-round salted SHA-256 in UserDefaults, not Keychain; kill-on-quit SIGKILL fallback never runs; progress race remains). |
| Ten-foot UI (28 pt, SF Rounded, 96 pt targets) | `TenFootStyles.swift` holds those tokens but only dead views use them. The player follows them partway; the React UI ignores them (13–17 px text). Resolves to SF Pro, not Rounded. |
| Swift 6 needs ~90 fixes | ~25–45 live diagnostics, and real data-race risk is low. |
| Settings → Auto-lock timer | Timer was removed with the new editing model; `editorAutoLockMinutes` is dead plumbing. |
| Downloads are "always highest quality (4K)" and are Ready once the file exists | The `best` preset prefers H.264 ≤ 1080p but falls back to anything (AV1, Opus-in-MP4, WebM bytes in a `.mp4`). Nothing verifies a file will play, and a load failure is a silent black screen. *(AV-1/2/3; silent-failure path confirmed at `PlayerState.swift:49-72`.)* |

## 3. Step 0 — protect the release path *before* shipping fixes

Because `release.yml` ships every merge, fix the pipeline first, in one small PR:

- **Release ordering:** upload the GitHub Release asset *first*, push the appcast entry last, with rebase-and-retry on the version-bump push (UPD-8, QA-13/14, SEC-14). A failed upload today can leave the newest appcast entry pointing at a 404 and block every install. ✔
- **Gate:** require `tsc` + `eslint` (`rules-of-hooks` as an error) + the new tests to pass before a release job runs; `persist-credentials: false`; `npm ci --ignore-scripts`; pin Actions by SHA; checksum the Sparkle tools download (SEC-14). ✔
- **Universal binary:** set `ARCHES="arm64 x86_64"` — the `lipo` path already exists (UPD-7, QA-9b). ✔ config / ? binary (confirm with `file` on a Mac).
- **Phased rollout** key in the appcast so a bad release reaches a fraction first (UPD-10).

*Effort S–M. Everything below ships through this.*

## 4. Ranked backlog

### P0 — this week (≈ 7–10 dev-days total, each item small)

| # | Item | Evidence IDs | Effort |
|---|---|---|---|
| 1 | **Migration atomicity.** Wrap each migration + `user_version` in one transaction; add a kill-mid-migration test. | QA-4 ✔ | S |
| 2 | **Progress race.** Skip progress for `ready`/`error` videos; flush the rAF buffer before any other event. | QA-1 ✔ (repro'd) | S |
| 3 | **`Channel.tsx` hooks crash.** Early return before ~15 hooks → React #300 on `channelRemoved`. Split the component; make `rules-of-hooks` blocking. | QA-2 ✔ (repro'd) | S |
| 4 | **Relocation safety.** "Move" must compare size/mtime before deleting a source; resume downloads if the pre-backup fails. | QA-7, QA-8 ✔ | S |
| 5 | **Contrast tokens.** `--text-tertiary #55555f` (2.2–2.6:1, used 50×) → ~`#9A9085`; lift accent + dark ink; `--control-edge` for inputs. Clears ~60 % of 147 failing text runs. | DSG-1/2/10 ✔ | S |
| 6 | **Keyboard/window basics.** One global `:focus-visible` ring; `inert` closed overlays (select, queue tray); `.fullScreenPrimary`; pin `darkAqua` + dark window bg + `color-scheme: dark`; add ⌘W + Help menu; `validateMenuItem` for dynamic items. | UI-2/3/6/7/8, DSG-5 ✔ / ? | S (≈ 1 day together) |
| 7 | **Cheap kid-safety closes.** PIN-gate *Locate Library…*; gate Reveal/Verify/⌘, by mode; `WKNavigationDelegate` allowlist + drop/contextmenu suppression; hide player before showing PIN on ⌘E; viewer can't change persisted autoplay mode. | SEC-2/3/4/18/19, UX-11 | S–M |
| 8 | **Readability floor.** ≥ 13 px admin / 14 px viewer; render error text + Retry *outside* the `opacity:.4` card wrapper; `overflow-wrap:anywhere`, 2-line title slot, `title=` tooltips. | TYP-3/4, DSG-6 ✔ | S |
| 9 | **Startup honesty.** Add `isLibraryLoaded` + splash (stops the false "No channels yet"); delete the eager thumbnail preloader (it requests every thumbnail at app root). | ARC-4, ARC-2a ✔ | S |
| 10 | **Async honesty.** Swift returns a result toast for add-videos ("Queued 3, 1 skipped"); React waits for it; require ID for source channels; fix toasts that never dismiss while progress streams. | UX-6, H9 ✔ | S |
| 11 | **Bound the first sync.** `--playlist-end`/"latest N · new only · all" choice with count + disk preflight; incremental syncs capped. A 3,000-video channel currently queues 3,000 downloads unprompted. | UPD-3 ✔ | M |
| 11b | **Playback-safe format policy.** Strict `avc1 + m4a` selector chain first; real extension in `-o` (not a hard-coded `.mp4`); `--remux-video mp4`; audio-only via `-x --audio-format m4a`. Today's fallbacks can yield AV1, Opus-in-MP4 or WebM bytes named `.mp4` (reproduced with yt-dlp 2026.10.26 and the app's exact arguments). Snippet in §9. | AV-2 ✔ | S |
| 11c | **Player quick wins.** `.allowsHitTesting(controlsVisible)` on hidden controls (an invisible Back button can currently be tapped); hold `ProcessInfo.beginActivity(.idleDisplaySleepDisabled…)` while playing (none exists); absolute `seek(toFraction:)` for scrubbing with loose tolerance and a clamp. | AV-4/8/9 ✔ absent / ? | S |

### P1 — next 2–4 weeks: *works on a fresh Mac, from a couch, safe for kids*

| # | Item | Evidence IDs | Effort |
|---|---|---|---|
| 12 | **Managed downloader.** Download the standalone `yt-dlp` + a pinned JS runtime into Application Support; update on launch/24 h with `.prev` rollback and a canary self-test; remove the `python3`/Homebrew requirement; "Fix downloads" button + diagnostics. | UPD-1/2/13 ✔ + web research | L |
| 13 | **First-run wizard + Add-channel preview.** Post-PIN steps: tools → first profile → first channel. URL parser accepting `@handle`, `/channel/`, `/c/`, `/user/`, playlist, `youtu.be`; show name/count/est. GB; "Show to" profile checklist (new channels are currently visible to nobody). | UX-5, UPD-4 ✔ | M–L |
| 14 | **Couch-ready UI.** Cards as real `<button>`s + roving arrow-key focus; one shared `<Modal>` on `<dialog>` (Esc, focus trap/restore, exit animation) replacing 10 shells; target sizes toward the 96 pt spec in viewer mode. | UI-1/4, UX-1/8 ✔ | M + M |
| 15 | **`uiScale` dial.** `WKWebView.pageZoom` for the WebView **plus a `PlayerMetrics` multiplier in the SwiftUI player** (pageZoom can't reach it); Settings row, View menu ⌘+/⌘−/⌘0, onboarding question ("Is this on a TV?"). Delivers the TV legibility without rewriting 200 inline sizes. | TYP-1 ✔ | S–M |
| 16 | **Bridge authorization.** One `authorize(messageType)` table in Swift (viewer / edit / admin); reject before mutate. Re-lock edit on sleep/screen-lock/profile switch; "Still editing?" idle prompt; ⌘L lock now. | SEC-1/5, UX-3 ✔ | M |
| 17 | **PIN recovery.** Delete the dead plaintext recovery phrase; Change PIN + Forgot PIN gated by `LocalAuthentication` (Touch ID / Mac password); send stored PIN length to JS (React hard-codes 4 digits, legacy PINs may be 6). | SEC-6, UX-2, QA-5 ✔ | M |
| 18 | **Deletes you can trust.** Confirm + undo toast with soft-delete to Trash (undo currently restores only the DB row); `excluded_videos` tombstones so sync never resurrects deletions; retry counter + backoff so private/removed videos aren't retried forever. | UX-4, QA-3/16, UPD-5/6 ✔ | M |
| 19 | **Tests & CI foundation.** Vitest on the `store.ts` reducer (15 named event sequences); promote the mock-bridge harness to `WebUI/e2e/` Playwright (chromium + webkit); Swift test target with an in-memory-DB seam (`LibraryPaths`, migrations, `ShellRunner` fakes, fake `yt-dlp` script). | QA test plan | M–L |
| 20 | **Live player fixes.** `ChromeDisc` dark-ink discs + centre scrim (glyph contrast 1.0–1.4 → 5.4–7.0 on bright frames); accessibility labels + focusable controls; Increase-Contrast/Reduce-Transparency; stop resume being silent (add "Start over"). | DSG addendum, UX-10 ✔ | S–M |
| 20b | **Playable-or-repair pipeline.** After download *and* in Verify: an ffprobe whitelist gate (H.264 + AAC in MP4) and a normaliser keyed on ffprobe, not the extension (copy compatible streams, transcode non-AAC audio, re-encode VP9/AV1/10-bit to H.264 — `h264_videotoolbox` on a Mac). At play time observe `AVPlayerItem.status` with no 10 s cap; on failure show a Back card, queue a repair and emit `playbackFailed`. Today a load failure is a silent black screen. | AV-1/3 ✔ | M–L |
| 20c | **Playback polish pack.** Push the new resume position to React after stop (`videosUpserted`), mark complete at ≥ 95 %, add "Resume / Start over" chips (revive `ResumePromptOverlay`), flush on quit; Now Playing + media keys + pause on audio-route change; persisted volume + per-profile ceiling. | AV-5/10/11 ✔ absent | M |

### P2 — 1–2 months: scale, design system, hygiene

| # | Item | Evidence IDs | Effort |
|---|---|---|---|
| 21 | **Bridge partial updates.** Send slices (`gates`, `downloads`, `catalog`) or `videosUpserted` instead of re-serialising the whole library (677 B/video → 3.3 MB at 5k) on download completion, sync, and each PIN press. | ARC-1 ✔ code / ? cost | M |
| 22 | **Thumbnails.** Off-main reads; 320 px derivatives at download time. Paginate list view (100k DOM nodes at 10k videos) and Library Feed (45k at 5k); selector store so one progress tick doesn't re-render ~6k components. | ARC-2/3/6 ✔ | M |
| 23 | **Design system.** Token pass (34 white alphas, 20 radii, 37 shadows, 5 purples → a scale); one `.material` glass recipe (14 blur recipes, 20–32 live `backdrop-filter` layers, up to 8 full-viewport `blur(64px)` images); fix ambient background freezing during downloads; **Swift forwards Reduce Motion / Transparency / Increase Contrast to `<html data-*>`** (WebKit has no `prefers-reduced-transparency`); shared primitives (Button, IconButton, Modal, ConfirmDialog, Select, TextField, Card, Chip, Tabs, EmptyState). | DSG-4/7/8, UI-9, ARC-5 ✔ | L |
| 24 | **Type roles.** Six role tokens + Numeric/Mono; codemod 207 inline font sizes (22 distinct values); `ui-rounded` stack; tabular numerals; one shared scale across React + SwiftUI. | TYP-2/6/8 ✔ / ? | M |
| 25 | **Delete dead code — after porting.** ~4.2k Swift LOC (all `Views/**` except `Color.ltAccent`; 158 dead lines in `VideoPlayerView.swift`; `BridgeMessage`/`AnyCodable`; orphan undo) + `PlayerScreen.tsx` (536) + unused CSS/assets. **Port first:** `ltAccent`, the channel resolver, the dependency installer. | ARC §7 ✔ | M |
| 26 | **Contract + concurrency.** One JSON Schema → generated TS + Swift wire types (CI diff check); then Swift 6 per the 6-step plan (~3–5 days, start with `StrictConcurrency` warnings under `.v5`). | ARC-11, SEC §6 | L |
| 27 | **Distribution.** Developer ID + hardened runtime + notarization ($99/yr), DMG, "Move to Applications" translocation banner, Sparkle gentle-reminder delegate so an update never interrupts playback. | UPD-9/10, SEC-15 | M |
| 28 | **Quieter downloads.** Merge the duplicate title-probe process (also captures tags); concurrency 4 → 2; `--sleep-requests`; global backoff on 429/403; `NWPathMonitor` + wake-time catch-up sync; sleep-safe watchdog (`systemUptime`, `ProcessInfo.beginActivity`). | UPD-11/12, QA-6 ✔ / ? | M |
| 29 | **Residual security.** CSP via a `localtube-app://` scheme; yt-dlp `--ignore-config --no-exec --`; validate `youtubeVideoId` as 11 chars; log perms 0600 + redaction; PBKDF2 + reject trivial PINs; `npm audit` bumps. | SEC-8…16 | S–M |
| 30 | **DB write batching + `verify()` decoupling.** One transaction per bulk insert; `synchronous=NORMAL`; verify shouldn't gate resume/sync. | ARC-7/8 | S–M |
| 30b | **Player correctness & polish.** "Next" follows the *displayed* order (send `videoIds` in `playVideo`; today it uses channel `sortOrder`); one item-scoped end observer + generation token (also closes the player race hazards in the security report); panel `level = .normal`, F key, hide idle cursor, don't let the red button quit the app mid-video; download disk-space preflight; duration backfill; black-frame detection for thumbnails. | AV-6/7/12–17 ✔ / ? | M |

### P3 — features, ranked by kid/parent value ÷ effort

1. **Continue Watching + watched badge** — resume data already exists (S–M).
2. **"Surprise me" shuffle** per profile (S).
3. **Ship the Playlists UI** — Swift side (create/rename/delete/active) already exists; React says "coming soon" (M).
4. **Review queue + age limit** for auto-synced videos so uploads don't land in kids' libraries unseen; per-profile lock (M–L).
5. **Bedtime sleep timer** that fades the volume then pauses; per-profile watch-time limits; loudness normalisation (`ebur128` measure + attenuate-only gain, needs schema v10) so one loud video can't startle a child (M; AV-11).
6. Sort modes, tag search, hide-a-video (from `TODO.md`).
7. **SponsorBlock-style segment removal**, `--download-archive`, YouTube-playlist sources, keep-newest-N / auto-delete watched, overnight-only schedule.
8. Captions toggle, AirPlay picker, PiP, an "up next" countdown, and audio-only mode with artwork instead of a black screen (AV-10/16). *(Now Playing + media keys are in P1 item 20c.)*

## 5. Workstreams (so implementation can run in parallel without collisions)

| Stream | Scope | Main files | Conflict hotspot |
|---|---|---|---|
| A Release & CI | §3, #19, #27 | `.github/`, `Scripts/` | — |
| B Downloader & YouTube | #11, #12, #13, #18 (sync part), #28 | `Services/*`, `AppState`, `DatabaseMigrations` | migration numbering (next is 10) |
| C Safety & auth (Swift) | #1, #4, #7, #16, #17 | `Bridge/LocalTubeBridge.swift`, `AppDelegate`, `PINService` | `LocalTubeBridge.swift` (896 lines) |
| D Couch UI (React) | #3, #6, #8, #14, #15 | `Channel.tsx`, `Library.tsx`, `components/*` | `Channel.tsx` (1,450 lines), **committed bundle** |
| E Design system | #5, #20, #23, #24 | `index.css`, tokens, SwiftUI player | touches everything → land after D's primitives |
| F Scale & hygiene | #9, #21, #22, #25, #26, #30 | `BridgeEventEmitter`, `store.ts`, dead-code removal | do after C/D to avoid rebase pain |
| G Playback | #11b, #11c, #20, #20b, #20c, #30b | `Player/*`, `Bridge/PlayerOverlayController.swift`, `Models/AppSettings.swift`, yt-dlp args in `DownloadService` | `DownloadService` is shared with stream B — land the format policy (#11b) first |

⚠ **Merge-conflict magnet:** `Sources/LocalTube/Resources/WebUI/` (the committed Vite bundle) conflicted on 20 of the last 58 commits. Either serialise UI PRs or stop committing the bundle (release.yml already rebuilds it; QA confirmed a stale bundle can't ship, only PR artifacts can be stale).

## 6. Decisions needed from you

1. **TV app or desktop app?** Recommendation: keep the dense default, add the `uiScale` dial (#15) and ask at onboarding — no rewrite.
2. **Developer ID + notarization ($99/yr)?** Recommend yes once the app runs on any Mac other than yours (Gatekeeper/translocation can block Sparkle updates on ad-hoc builds ?).
3. **Managed yt-dlp + JS runtime instead of Homebrew?** Recommend yes — it is the single biggest reliability win, and removes Python/Xcode-tools prompts.
4. **Edit-session policy.** `EDITING_MODEL.md` says no timer. Recommend: no hard timer, but an idle prompt + re-lock on sleep/lock/profile switch.
5. **Review queue for auto-synced videos — default on?** It adds a parent step but closes the "unseen content reaches kids" gap.
6. **Playlists:** ship the UI (Swift is ready) or hide the "coming soon" tab until then?
7. **Delete the dead SwiftUI tree** after the port in #25?
8. **One accent colour.** Player is gold (`ltAccent`), React is violet; the spec asks for warm, saturated, one accent per state. Pick one.
9. **Default quality.** The spec says "always highest available (4K)"; the Audio & Video audit shows that is how AV1/Opus files that don't play get in. Recommend **H.264 + AAC, ≤ 1080p by default** (plays on every Mac, smaller files), with 4K as an opt-in per setting or channel.

## 7. Needs a real Mac to confirm (consolidated)

- Release zip architecture (`file LocalTube`); Intel refusal.
- Sparkle updating an ad-hoc-signed app (quarantine, translocation, non-admin); first launch from a zip/AirDrop on macOS 14/15/26.
- `.fullScreenPrimary` absence → does ⌃⌘F / the green button enter fullscreen?
- Light-mode title bar + launch flash (no `appearance`/background pinned).
- `ui-rounded` → SF Pro Rounded in WKWebView; `pageZoom` on the main view; the 5.6 px skip "10" in the live player at 22 pt.
- WKWebView Tab focus without Full Keyboard Access; drop-navigation on the main frame; ⌘C/⌘V in fields; Edit-menu Undo state.
- Sleep/wake vs the 10-minute download watchdog; `NSCalendarDayChanged` after sleep; orphan ffmpeg on quit.
- `⌘E` mid-playback (PIN modal under the panel), `⌘,` flash in viewer mode.
- Real cost of full `stateUpdate`s, thumbnail bursts, `backdrop-filter` stacks at 4K, `verify()` at 10k videos → **Instruments**: Time Profiler (signpost `emit`), Hangs, File Activity/`fs_usage`, Allocations on WebContent, Core Animation.
- Strict-concurrency warning counts; PIN/UserDefaults and Keychain behaviour across ad-hoc updates.
- Which codecs `isPlayable`/`isDecodable` accept (AV1, Opus-in-MP4, VP9/WebM named `.mp4`) on Intel, M1/M2 and M3 under macOS 14/15; whether `AVPlayerView` holds a display-sleep assertion on its own (`pmset -g assertions`) for video and audio-only; hidden-control hit-testing; scrub overshoot; media-key and headphone-unplug behaviour; opens that take longer than the 10 s poll on a slow disk or NAS.

## 8. Lane reports

| Lane | Report | Findings (≈) |
|---|---|---|
| UI | [`audit-2026-11/ui.md`](audit-2026-11/ui.md) | 22 |
| UX | [`audit-2026-11/ux.md`](audit-2026-11/ux.md) | 13 |
| Design & colour (+ live-player addendum) | [`audit-2026-11/dsg.md`](audit-2026-11/dsg.md) | 10 + addendum |
| Typography & wireframes (8 ASCII wireframes inside) | [`audit-2026-11/typography.md`](audit-2026-11/typography.md) | 12 |
| Updating & YouTube | [`audit-2026-11/updating.md`](audit-2026-11/updating.md) | 13 |
| QA (incl. 30-min Mac smoke script, test plan) | [`audit-2026-11/qa.md`](audit-2026-11/qa.md) | ~20 |
| Security & concurrency | [`audit-2026-11/sec.md`](audit-2026-11/sec.md) | 19 |
| Performance & architecture (dead-code list, refactor roadmap) | [`audit-2026-11/arc.md`](audit-2026-11/arc.md) | 11 |
| Audio & video (format experiments, recommended format policy) | [`audit-2026-11/av.md`](audit-2026-11/av.md) | 17 |

> Note: DSG-3 in the original design report measured the dead React player and is void; the addendum replaces it.

## 9. Audio & Video — findings and format policy

Full report: [`audit-2026-11/av.md`](audit-2026-11/av.md). Method: static review of the **live SwiftUI player** (`Player/*`, `PlayerOverlayController`), plus experiments — yt-dlp 2026.10.26 format selection with the app's exact arguments, and `ffprobe`/`ffmpeg` on Linux. Verdict: the happy path (H.264 + AAC MP4 at ≤ 1080p in the native panel) is plausible; **the unhappy paths are undefended.**

| ID | Severity | Status | Finding | Backlog |
|---|---|---|---|---|
| AV-1 | Critical | ✔ code · ? runtime | Load errors are swallowed (`try?`), readiness is polled for 10 s then silently abandoned, and there is no `.failed` / `isPlayable` handling → silent black screen. The 10 s cap also gives up on slow HDD/NAS opens. *(I confirmed `PlayerState.swift:49-72`.)* | 20b |
| AV-2 | Major | ✔ reproduced | Selector fallbacks can yield AV1 (up to 2160p), Opus-in-MP4, or WebM bytes in a `.mp4`; AVPlayer doesn't open WebM. | 11b |
| AV-3 | Major | ✔ | Post-download check is only `fileExists` + an ffprobe duration where `try?` turns failure into 0; Verify checks existence only; no remux/transcode fallback. | 20b |
| AV-4 | Major | ? | Scrub drag uses a relative skip from a `currentTime` that updates every 0.5 s, with zero seek tolerance and no upper clamp → overshoot; a skip near the end triggers "advance". | 11c |
| AV-5 | Major | ✔ | After playback Swift never pushes the new resume position to React (stale "Resume at…"); no "completed" rule; progress is per video, not per profile (siblings overwrite each other); resume is silent with no Start over; thresholds disagree (5 s card vs 10 s player); no flush on quit. | 20c |
| AV-6 | Major | ✔ | Sequential/shuffle use channel `sortOrder`, not the order the user sees (5 sorts + filters on screen). | 30b |
| AV-7 | Minor–Major | ? | Two end-of-item observers race; `isPlaying` is hand-toggled, not derived from `timeControlStatus`; the load Task is never cancelled; `isLooping` persists across videos (spec: per video). H1/H8 from March are fixed. | 30b |
| AV-8 | Major | ? | Hidden controls use `.opacity(0)` with no `.allowsHitTesting` (*I confirmed `allowsHitTesting` appears nowhere in the file*): tapping the invisible top-left Back exits the video. | 11c |
| AV-9 | Major | ✔ absent | No `beginActivity` / IOPM assertion anywhere (*I grepped*): the screen can sleep or lock mid-show on a TV; audio-only has no video to hold an assertion. | 11c |
| AV-10 | Major | ✔ absent | No Now Playing, `MPRemoteCommandCenter`, AirPlay, PiP, captions or route-change handling (*grepped*). Suspected: a media key launches Music; unplugging headphones moves audio to the Mac speakers. | 20c / P3 |
| AV-11 | Major | ✔ | Volume isn't remembered, no mute or ceiling; no loudness normalisation (a sudden loud video startles a child). | 20c / P3 |
| AV-12 | Major | ? | Panel is `.floating` + `.canJoinAllSpaces` and covers only the content area; the title bar stays live and its red button quits the app mid-video; ⌃⌘F likely hits a non-fullscreen-capable panel; no F key; cursor never hides. Spec says "full-screen only". | 30b |
| AV-13–17 | Minor | ✔ | Thumbnail seek at 1 s: a 0.6 s clip exits 0 with no file and a black-intro clip gives a pure-black JPEG; duration can stay 0 (renders a 100 % resume bar); no disk-space preflight; audio-only is a global setting with a black-screen player; keys can be stolen by the volume slider. | 30b |

**Recommended format policy** (AV-2 — selector and both ffmpeg normaliser commands were exercised on Linux; macOS decode support is *not* verified):

```text
-f "bv*[vcodec^=avc1][height<=H]+ba[ext=m4a]/b[vcodec^=avc1][acodec^=mp4a][height<=H]/bv*[height<=H]+ba/b[height<=H]"
-S "res:H,vcodec:h264,acodec:aac,ext:mp4:m4a"
--merge-output-format mp4 --remux-video mp4
-o "<base>.%(ext)s" --print after_move:filepath
# audio-only:  -f "ba[acodec^=mp4a]/ba" -x --audio-format m4a
```

Then normalise by what `ffprobe` reports, **not** by file extension: keep H.264 + AAC as-is; transcode non-AAC audio to AAC; re-encode VP9 / AV1 / 10-bit video to H.264 `yuv420p` (`h264_videotoolbox` on a Mac). Finish with a runtime check (`isPlayable` and `isDecodable`) and the repair path in 20b.

**How this moved the plan:** AV adds three P0 items (format selector, hidden-control hit-testing, sleep inhibition), the largest new P1 item (playable-or-repair, 20b), and decision 9 (default quality). Items 12 (managed downloader), 11b and 20b are one theme — *downloads you can trust* — and are best released together.
