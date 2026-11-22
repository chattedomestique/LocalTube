# LocalTube — Gameplan (November 2026)

> **Status: DRAFT v1.** Eight of nine audit lanes are merged below. **Audio & Video is still running** — its slot is §9 and it may re-rank a few items.
> **Baseline:** v1.0.37 (build 38), `master` @ `9a3eed7`. **Method:** nine specialist agents, each read-only, each writing a full report to [`audit-2026-11/`](audit-2026-11/). Roughly 120 findings in total; this document de-duplicates and ranks them.
>
> **Confidence legend.** ✔ = confirmed in code, or reproduced in a browser harness with a fake Swift bridge. ? = suspected from reading Swift; **no Swift toolchain or Mac was available**, so nothing Swift-side was built or run. §7 lists everything that needs a real Mac.
> **Effort.** S ≤ ½ day · M 1–3 days · L > 3 days (rough, one developer).

---

## 1. Bottom line

LocalTube's engine is in better shape than the safety net around it. Earlier audits fixed the scary things (JS injection, `curl | bash`, SQL, path traversal, pipe deadlocks, persistence). What is left falls into five buckets, in the order they hurt a real family:

1. **A fresh Mac cannot get started.** The React UI migration dropped the dependency installer and the channel resolver (both now live only in dead SwiftUI). Nothing ever updates yt-dlp, and YouTube now needs an external JS runtime that nothing installs. *(verified by me in code)*
2. **It cannot be driven from a couch.** Cards aren't focusable, there are no focus rings, no arrow-key navigation, dialogs don't close on Esc, and at 1080p 77–100 % of text is ≤ 17 px against a spec that says 28 pt. Controls are 34–44 px against a 96 pt spec.
3. **Kid-safety is a UI convention, not an enforced rule.** The Swift bridge accepts every message in every mode; several menu items and the drive-unplugged screen skip the PIN; the edit/admin session never expires; and PIN recovery doesn't exist.
4. **A handful of bugs lose or misreport data.** A crash mid-migration can brick the database; a video a parent deletes from a synced channel comes back; relocation can delete a good file; finished downloads show "99 %" forever; removing a channel can crash the React tree.
5. **Nothing stops a bad build reaching every install.** Every merge to `master` auto-signs and ships. There are zero tests. The release is probably Apple-Silicon-only.

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

## 3. Step 0 — protect the release path *before* shipping fixes

Because `release.yml` ships every merge, fix the pipeline first, in one small PR:

- **Release ordering:** upload the GitHub Release asset *first*, push the appcast entry last, with rebase-and-retry on the version-bump push (UPD-8, QA-13/14, SEC-14). A failed upload today can leave the newest appcast entry pointing at a 404 and block every install. ✔
- **Gate:** require `tsc` + `eslint` (`rules-of-hooks` as an error) + the new tests to pass before a release job runs; `persist-credentials: false`; `npm ci --ignore-scripts`; pin Actions by SHA; checksum the Sparkle tools download (SEC-14). ✔
- **Universal binary:** set `ARCHES="arm64 x86_64"` — the `lipo` path already exists (UPD-7, QA-9b). ✔ config / ? binary (confirm with `file` on a Mac).
- **Phased rollout** key in the appcast so a bad release reaches a fraction first (UPD-10).

*Effort S–M. Everything below ships through this.*

## 4. Ranked backlog

### P0 — this week (≈ 6–9 dev-days total, each item small)

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

### P3 — features, ranked by kid/parent value ÷ effort

1. **Continue Watching + watched badge** — resume data already exists (S–M).
2. **"Surprise me" shuffle** per profile (S).
3. **Ship the Playlists UI** — Swift side (create/rename/delete/active) already exists; React says "coming soon" (M).
4. **Review queue + age limit** for auto-synced videos so uploads don't land in kids' libraries unseen; per-profile lock (M–L).
5. **Bedtime sleep timer** with volume fade; per-profile volume ceiling; watch-time limits (M; *Audio & Video lane to confirm*).
6. Sort modes, tag search, hide-a-video (from `TODO.md`).
7. **SponsorBlock-style segment removal**, `--download-archive`, YouTube-playlist sources, keep-newest-N / auto-delete watched, overnight-only schedule.
8. PiP / AirPlay / Now Playing + media keys (*Audio & Video lane*).

## 5. Workstreams (so implementation can run in parallel without collisions)

| Stream | Scope | Main files | Conflict hotspot |
|---|---|---|---|
| A Release & CI | §3, #19, #27 | `.github/`, `Scripts/` | — |
| B Downloader & YouTube | #11, #12, #13, #18 (sync part), #28 | `Services/*`, `AppState`, `DatabaseMigrations` | migration numbering (next is 10) |
| C Safety & auth (Swift) | #1, #4, #7, #16, #17 | `Bridge/LocalTubeBridge.swift`, `AppDelegate`, `PINService` | `LocalTubeBridge.swift` (896 lines) |
| D Couch UI (React) | #3, #6, #8, #14, #15 | `Channel.tsx`, `Library.tsx`, `components/*` | `Channel.tsx` (1,450 lines), **committed bundle** |
| E Design system | #5, #20, #23, #24 | `index.css`, tokens, SwiftUI player | touches everything → land after D's primitives |
| F Scale & hygiene | #9, #21, #22, #25, #26, #30 | `BridgeEventEmitter`, `store.ts`, dead-code removal | do after C/D to avoid rebase pain |

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
| Audio & video | *pending* | — |

> Note: DSG-3 in the original design report measured the dead React player and is void; the addendum replaces it.

## 9. Audio & Video — pending

The Audio & Video agent was blocked on a Bash permission prompt (it runs `ffmpeg`/`ffprobe` experiments). Open questions it owns, and which feed the backlog above: whether the yt-dlp format selectors can produce VP9/AV1/Opus/WebM that AVPlayer can't play (and whether anything verifies playability or remuxes), resume/volume persistence, audio-route changes, loudness consistency, captions, PiP/AirPlay/Now-Playing/media keys, sleep inhibition during playback, thumbnail seek on short videos, and end-of-video/queue behaviour.
