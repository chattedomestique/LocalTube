# QA audit — LocalTube v1.0.37 (finding prefix QA-)

Scope: correctness, regression safety, test strategy, CI. Read-only. Swift was reviewed statically only (no toolchain here);
everything labelled `confirmed` was seen in code and, for UI items, reproduced in the mock-bridge harness
(scripts + screenshots in `.../scratchpad/work-qa/`: race1.cjs, hooks1.cjs, fav1.cjs, misc1.cjs, shots/).

## 0. Verdict
Zero tests, lint not enforced, CI only proves "it compiles and packages". The code itself is better than that safety net suggests:
20 of the 40 March-2026 review items are genuinely fixed, 10 partially, 5 not, 5 are legacy/n-a. But I found two reproducible
WebUI defects (a stale-progress reducer race and a conditional-hooks crash), several state-machine/relocation/migration hazards
that only a real Mac or a test harness will expose, and a release config that looks arm64-only. Nothing here is a ship-stopper
for the current userbase, but several are exactly the "silent, family-visible" failures this product cannot afford
(deleted video comes back; PIN you can never type; video stuck at 99% forever).

## 1. Health checks (all run today)
| Check | Result |
|---|---|
| `tsc -p tsconfig.app.json --noEmit` | PASS (0 errors, 5.6 s). `tsconfig.node.json` also PASS. |
| `eslint .` | **24 errors + 6 warnings** (docs claim 26 errors). By rule: `react-hooks/rules-of-hooks` 15 (all `Channel.tsx:221-321`), `no-unused-vars` 5 (AddVideosModal:10, Channel:6,30,31,44), `set-state-in-effect` 3 (AmbientBackground:39, MountWithExit:36, PlayerScreen:342), `react-hooks/purity` 1 (ChannelCard:103 `Date.now()` in render), `exhaustive-deps` 5 warnings + 1 unused-disable. |
| Real bug risk of the 24 | **15 rules-of-hooks = real crash (QA-2).** purity `Date.now` in render = stale "x minutes ago" label, low. set-state-in-effect x3 = extra render, style. unused-vars x5 = dead code (`parseYouTubeUrls`, `COLLAPSE_DISTANCE`, `easeOutCubic`, `playlists`, `thumbUrl`). exhaustive-deps: `Channel.tsx:123,261` useMemo deps are hand-rolled (`sortedVideos.length > 0`) — works by accident. |
| Bundle drift | Built current source to `work-qa/dist`: `index-Vj9DQRXL.js` (537.6 kB, 145 kB gz) + `index-BGCauS9Y.css` — **byte-identical (cmp) to the committed bundle**. Build is deterministic across machines. No drift today. |
| Can a stale bundle ship? | **Releases: no.** `release.yml` runs `npm ci && npm run build` (tsc -b + vite) *before* `Scripts/release.sh` → `package_app.sh` copies `Sources/.../Resources` → `git add -A Sources/LocalTube/Resources/WebUI`. **PR artifacts: yes.** `build.yml` `macos` job has no `needs: webui` and never builds the WebUI, so the .app a reviewer downloads contains whatever is committed (QA-13). The drift check there is `continue-on-error: true` (advisory) although the build is deterministic. |
| `npm run lint` in CI | Not run anywhere. 24 errors can grow unnoticed. |

### Workflow review (`.github/workflows/build.yml`, `release.yml`)
- No test step of any kind in either workflow; `release.yml` publishes on every non-.md merge to master with **no gate** (it does not depend on `build.yml`; a direct push or an unreviewed merge ships). Branch protection/required checks unknown.
- `build.yml` triggers: `pull_request` + `workflow_dispatch` only (AUDIT_2026-09 says "and pushes to master" — wrong; release.yml covers pushes).
- `build.yml` has no `permissions:` block (inherits repo default, possibly write-all); `release.yml` correctly has `contents: write`. Actions pinned by tag (`@v4`), not SHA.
- Release ordering hazard (`Scripts/release.sh`): `git push origin HEAD` (line 201, carries the new `appcast.xml`) happens **before** `gh release create` (216). A failure between them, or the ~seconds window, leaves a signed appcast entry whose zip 404s; subsequent releases don't repair it (QA-14).
- `release.sh:67` downloads Sparkle tools with no checksum and then feeds them `SPARKLE_PRIVATE_KEY` — supply-chain gap (SEC/UPD).
- Version loop: guarded twice (`!startsWith(head_commit.message,'Release ')` + GITHUB_TOKEN pushes don't re-trigger). If master advances during the 5-8 min build, `git push origin HEAD` is rejected: run fails after building; next merge retries — no loop, but a silently lost release.
- `concurrency: release / cancel-in-progress: false` is right (serialises); with 3 rapid merges GitHub keeps only the newest pending run — acceptable because each builds master HEAD.
- Intel: `package_app.sh:27-30` builds only `$(uname -m)`; `release.yml` sets no `ARCHES`; `macos-15` is arm64 → **published zip is very likely arm64-only** (QA-9b; confirm with `file LocalTube.app/Contents/MacOS/LocalTube`). Many TV/projector Macs are Intel minis.
- Caching: `.build` cached by `Package.resolved` hash only (fine); npm cached. Artifacts retained 14/30 days.

## 2. Verification of old claims

### 2a. CODE_REVIEW.md (40) — status
Totals: **fixed 20 · partial 10 · open/not-fixed 5 · legacy n/a 5.**

| ID | Status | Evidence / note |
|---|---|---|
| C1 path traversal (thumb) | fixed* | `ThumbnailURLSchemeHandler.swift:65-90` standardize + ext allow-list + library-root check. *Residual: `contains("..")` (l.79) rejects legit roots like `Kids...Videos` (QA-17). |
| C2 XSS/JS interpolation | fixed | `BridgeEventEmitter.swift:30-48` ASCII-escaped JSON -> base64 -> `atob`. |
| C3 curl\|bash | fixed | `DependencyService.swift:56-73` requires brew, `brew install`. TODO.md still lists it unchecked (stale). |
| C4 PIN plaintext | **partial** | Salted SHA-256 in UserDefaults (`PINService.swift:44-49`): not plaintext, but a 4-digit PIN falls to offline brute force in <1 ms; recovery phrase stored plaintext (l.49). |
| C5 PIN in React state | open (accepted) | `PINEntry.tsx:6` still `useState` string. Low. |
| C6 SQL interpolation | fixed | `DatabaseMigrations.swift:78-85`. |
| C7 handlers leak | fixed | `WebWindowController.swift:224-227`. |
| H1 time observer (PlayerState) | fixed (live code!) | `Player/PlayerState.swift:192` + `PlayerOverlayController.swift:274`. NB: BRIEF calls `Player/**` dead; `PlayerState` is live. |
| H2 @unchecked Sendable | fixed | `DownloadQueueItem.swift:15-19` @MainActor. |
| H3 IUO in AppDelegate | fixed | no `!` declarations remain. |
| H4 NULL String(cString:) | fixed | `columnText/columnTextOptional` `DatabaseService.swift:~770-780`. |
| H5 transactions | **partial** | Batch helpers + relocation use `BEGIN IMMEDIATE` (l.116-229, 596, 736). Migrations 2/3/6/7/9 are not atomic with `user_version` (QA-4); channel+video inserts are independent fire-and-forget Tasks. |
| H6 error boundary | **partial** | `App.tsx:22-35,238` exists (harness shows "Something went wrong / Try Again"); only `console.error`, never reports to Swift. |
| H7 logger | fixed* | queue + rotation OK. *`FileHandle.write(_:)` (AppLogger.swift:59) raises an ObjC exception on ENOSPC = crash when disk full (QA-12, suspected). |
| H8 PlayerOverlay observer | fixed | cleanup only in `deinit` (l.268-274) but one panel/state is reused so observers do not accumulate. |
| **H9 handleAddVideos loading** | **NOT fixed** | `Channel.tsx:196-204` closes via 2 s `setTimeout`, not on confirmation; `AddVideosModal.tsx:41-44` still `setAdding(true); onAdd(); setAdding(false)` synchronously (QA-10). |
| M1 folderName traversal | fixed | `Channel.swift:38-47` + `uniqueFolderName`. |
| M2 isPlayable TOCTOU | fixed | `Video.swift:36`; playVideo checks file once (`LocalTubeBridge.swift:361`). |
| M3 ShellRunner timeout | fixed | `ShellRunner.swift:53-132, 208`. |
| M4 hardcoded brew paths | **partial** | `which` + fallbacks exist (`ShellRunner.swift:261-279`) but a Finder-launched app has launchd's minimal PATH, so pipx/MacPorts/nix installs are still NOT found (suspected; AUDIT P7 claim overstated). |
| M5 PIN rate limit | fixed | `PINService.swift:78-105`, persisted. Clock-forward bypass (edge list). |
| M6 triple-tap bypass | n/a (legacy SwiftUI) | |
| M7 BridgeMessageType | fixed | `LocalTubeBridge.swift:35-94`. Wire contract TS<->Swift currently in sync (script run: 44 message types match, 32/33 events match; `downloadProgressBatch` is JS-internal). |
| M8 AnyCodable | open | `BridgeMessage.swift:73-78`; handlers still `[String: Any]`. |
| M9 allowFileAccessFromFileURLs | open | `WebWindowController.swift:94`. |
| M10 formatter caching | fixed | |
| M11 bridge validation | **partial** | length caps on PIN/name/URLs (`:441-449,538,620`), but `youtubeVideoId` accepts any host with `?v=` and any `youtu.be/<anything>` (no 11-char check); no editor-mode gate on destructive handlers. |
| **M12 bridge timeout** | **NOT fixed** | `bridge.ts:19-45 sendBridgeWithTimeout` is never called (grep) and monkey-patches `dispatch` (would leak/mis-chain on timeout). UI is still fire-and-forget. |
| M13 progress race | **partial** | unknown ids are dropped (`store.ts:150,187`), but ordering race remains (QA-1, reproduced). |
| M14 accessibility | partial | `role=dialog` present on modals; only 2 `aria-hidden` in src; no focus trap/restore. |
| M15 silent task failures | partial | `persist()` logs; fire-and-forget remains; user-visible errors rare. |
| M16 tools-version | partial | tools 6.0 but `.swiftLanguageMode(.v5)` (`Package.swift:28`). |
| L1 .task | n/a legacy | |
| L2 magic numbers | n/a legacy | |
| L3 @MainActor views | n/a legacy | |
| L4 recovery entropy | fixed* | 6 words (`PINService.swift:~130`). *Phrase is never shown to the user and no flow consumes it (QA-5). Fallback phrase is a hard-coded constant. |
| L5 log rotation | fixed | |
| L6 thumb seek | partial | `-ss 1` (ThumbnailService.swift:18); <1 s clips still black. |
| L7 scroll anim | n/a legacy | |
| L8 title after download | fixed | `fetchVideoTitle` (`DownloadService.swift:519-537`). |

### 2b. TODO.md — Bugs & Polish / Accessibility / Tech debt
| Item | Status |
|---|---|
| Modal exits still pop | open (`MountWithExit` used only in App.tsx) |
| Active-download chip in library | **fixed but unchecked** (`Library.tsx:242-255`) |
| Search input loses focus | cannot reproduce (harness: typed while 5 stateUpdate+progress events fired; focus and value kept) |
| Player volume persistence | open (no persistence; `PlayerOverlayController.swift:308-310` only nudges) |
| Reduce-motion (React) | open (no `prefers-reduced-motion` anywhere in `WebUI/src`) |
| Channel file cleanup / queue trim / banner error toast | [x] verified (`AppState.swift:294-329`, `DownloadService.swift:253`, `LocalTubeBridge.swift:~770`) |
| Empty-search state | open, and the favorites variant is worse (QA-9) |
| A11y: focus trap, restore focus, picker keyboard nav, ARIA audit, decorative SVGs | all open (0 focus-trap code; ProfilePicker has no key handler; 2 `aria-hidden`) |
| Tech debt: Swift 6 flip, bridge typing, tests, logging categories, Settings diagnostics, setup-sparkle.sh non-ASCII (still present, l.2-7), bundle size (537.6 kB, Vite warns >500 kB) | open |
| C3 / M3 / H3 boxes | C3 unchecked but fixed; M3, H3 verified fixed |
| "Migrations: we're at 7, next is 8" | stale — schema is v9 |
| **Tests [P1]: "zero unit tests"** | confirmed: `git ls-files` has no test/spec file |

### 2c. AUDIT_2026-09.md spot-check (30 of 32 claims checked)
Held up: P1 (`DownloadService.swift:156-172`, `LibraryStore.swift:410-424`), P2 (`:118-135`, bridge `:663`), P3 (`LibraryStore.swift:578`), P4 (`LocalTubeBridge.swift:623-636`, `AppState.swift:473`), P5 (`AppState.swift:496,522-548`), P6 (`LocalTubeBridge.swift:358-374`), P8 (`:540-565`), P9 (`:44`; ShellRunner watchdog), P10 (`AppSettings.swift:17-29`), P11 (`:253`), L1-L2 (`AppState.swift:294-329`, `LibraryStore.swift:434`, `Channel.swift:38`), L4 (`LocalTubeBridge.swift:430`), L5 (`:828`), R1 (`LibraryMaintenanceService.swift:564-687`), R2 (`AppDelegate.swift:146-166`), R3 (`AppSettings.swift:81-89`), R4 (`BridgeEventEmitter.swift:271-281`), H1-H5, H7 (`:696-700`), H8, H10, H11 (no `.DS_Store` tracked), H6 (persisted lockout, `PINService.swift:19-31`).
Qualified / not fully true: **P7** (`which` in a Finder-launched app cannot see pipx/MacPorts), **P12** (`AppDelegate.swift:180-185` -> `forceTerminate` schedules SIGKILL after 3 s but the process exits first, and yt-dlp's ffmpeg child is not in the kill path — QA-15, suspected), **L3** (React `channelRemoved`/`profileRemoved` do NOT prune favorites/playlists/profileChannels; it works only because the bridge sends a full `stateUpdate` right after, `LocalTubeBridge.swift:587,879`), **H9** ("surfaced as blocking error screen" true, but see QA-4: a failed migration is unrecoverable without manual backup restore), **verification note** ("26 lint errors", "build.yml runs on pushes").

### Claimed fixed but NOT (or only nominally)
1. **H9** React add-videos loading state — a 2 s timer; modal path unchanged.
2. **M12** bridge request timeout — helper written, never used, unsafe if used.
3. **C4/L4** PIN hardening — hash in plist is trivially reversible; the "recovery phrase" is plaintext and unreachable.
4. **M4 / P7** non-standard install discovery — only works from a Terminal-launched app.
5. **P12** kill-on-quit — SIGKILL grace never runs; grandchild ffmpeg survives (suspected).
6. **M13** React progress race — drops unknown ids but the rAF batch re-writes terminal states (reproduced).
7. **H5** transactions — migrations/`user_version` still non-atomic.
8. **L3 (React half)** — relies on a follow-up snapshot.

## 3. Prioritised bug list (repro)
Severity = family impact. `confirmed` = seen in code (+ harness where noted). Needs-Mac items flagged.

**QA-1 | Major | confirmed (harness)** — Stale buffered progress flips finished downloads back to "downloading NN%".
`WebUI/src/store.ts:521-535` buffers `downloadProgress` in a rAF batch while `downloadCompleted`/`stateUpdate` are applied immediately; the later `downloadProgressBatch` (`:161-195`) forces `downloadState:'downloading'` with the old progress. Swift sends `.completed` then a full `stateUpdate` (`AppDelegate.swift:354-359`), so nothing corrects it until the next unrelated snapshot. Repro (`work-qa/race1.cjs`): scenario `channel`; in one JS turn dispatch `downloadProgress{c1-v12,0.99}`, `downloadCompleted`, `stateUpdate(video ready)`; after 300 ms the card shows 99%. Also triggers whenever the WebView is hidden/minimised (rAF is throttled) while downloads finish (suspected on WKWebView). Fix: in both progress cases skip entries whose current state is `ready`/`error`; and flush the buffer synchronously before applying any non-progress event. S / High.

**QA-2 | Major | confirmed (harness)** — Channel screen crashes (React #300 -> ErrorBoundary) when its channel disappears.
`Channel.tsx:164` returns early, then calls ~15 hooks (`:221-321`) — the 15 `rules-of-hooks` ESLint errors. Repro (`hooks1.cjs`): scenario `channel`, dispatch `channelRemoved{c1}` -> "Something went wrong — Minified React error #300". Reachable via any stateUpdate that drops the open channel (library reload, relocation, future sync/dedupe code). Fix: split into `Channel` (resolves channel, early-return) + `ChannelBody({channel})`, or move the return below the hooks; add `rules-of-hooks` as a blocking CI rule. S / High.

**QA-3 | Major | confirmed (code)** — A video the parent deletes from a *synced* channel is re-added and re-downloaded at the next launch/midnight sync.
`AppState.swift:472-489` builds `existingSet` from current rows only; `removeVideo` deletes the row (`LibraryStore.swift:553`). No tombstone. Parents curating a kid's channel see content they removed come back, plus the bandwidth/disk cost. Fix: migration 10 `excluded_videos(channel_id, youtube_video_id)` written by `removeVideo` for source channels; sync skips it; show "Removed (n)" with restore in Admin. M / High.

**QA-4 | Major | confirmed (code), low probability / high impact** — Migrations are not atomic with `user_version`, and ALTER migrations are not idempotent.
`DatabaseMigrations.swift:23-61`: each `migrationN` runs, *then* `setUserVersion` (result unchecked, `:84`). Migrations 2,3,6,7,9 are bare `ALTER TABLE ADD COLUMN` (`:131-139,193-196,283-285,259-260`; 9 does 2 ALTERs after its transaction). A kill/throw between the ALTER and the PRAGMA makes every later launch fail with "duplicate column name" -> blocking error screen (H9) -> app unusable until the user restores a backup by hand. Fix: run each migration inside one `BEGIN IMMEDIATE ... PRAGMA user_version=N; COMMIT` (SQLite DDL is transactional) and check the PRAGMA rc. S / High. Regression test in §4.

**QA-5 | Major | confirmed (code); affected population unknown** — PIN length mismatch and no recovery path.
React `PINEntry.tsx:51` (`slice(0,4)`) and `PINSetup.tsx:62-77` hard-code 4 digits; Swift accepts 4-8 (`LocalTubeBridge.swift:441-449`) and `storedPINLength()` (`PINService.swift:63`, default 6, never sent to JS) is dead. Anyone whose PIN was set by the older 6-digit SwiftUI flow can never unlock Admin (and burns attempts into the 5 s/30 s/5 min lockout). Recovery phrase is generated, stored plaintext (`:49`), never shown; `PINService.deleteAll()` (`:107`) has no caller. Forgetting the PIN = `defaults delete` or reinstall. Fix: include `pinLength` in `stateUpdate`, make PINEntry length-aware, and add a "Forgot PIN?" path gated by `LocalAuthentication` (macOS login password/Touch ID). M / High.

**QA-6 | Major | suspected (needs Mac)** — Sleep/wake kills in-flight downloads; nothing prevents sleep.
Watchdog compares wall-clock `Date()` (`ShellRunner.swift:234`) against last output with a 10-minute limit (`DownloadService.swift:44`); after a >10 min sleep the first tick after wake terminates a download that would have recovered and marks it `error` ("stalled"); auto-retry only happens at the next sync. No `ProcessInfo.beginActivity` / sleep assertion anywhere (grep). Overnight downloads on a TV Mac are the norm. Fix: measure idle with `ProcessInfo.systemUptime` (does not advance during sleep) and reset on `NSWorkspace.didWakeNotification`; hold `.idleSystemSleepDisabled` while the queue is non-empty (opt-out in Settings). S / High.

**QA-7 | Major | confirmed (code)** — Relocation "Move" can delete the good source file.
`LibraryMaintenanceService.swift:712-716`: when the destination already has a file with the same name, the *source* is removed on the assumption they're identical (existence check only). After an interrupted earlier move/Finder copy, a truncated destination file causes the complete original to be deleted. Fix: compare size (+mtime); on mismatch keep both, report a conflict. S / High.

**QA-8 | Minor | confirmed (code)** — A failed relocation precondition silently halts downloads. `cancelAll()` at `LibraryMaintenanceService.swift:611` precedes the DB backup; the backup-failure `return` (`:617-619`) never calls `resumePendingDownloads()`; queue items are `.cancelled`, videos `.queued`, nothing restarts until relaunch. Fix: cancel after the backup, or resume in a `defer`. S / Med.

**QA-9 | Minor | confirmed (harness)** — Favorites filter edge cases (TODO P0 "verify favorites filtering").
(a) 0 favorites + Favorites filter -> "No videos found / Nothing matches \"\"" with a "Clear Search" button that does nothing (`Channel.tsx:917-948`; shot `work-qa/shots/fav-A-zero-favorites.png`). The designed "No favorites yet — tap the heart" state does not exist. (b) `currentPage` is only reset on channel/search change (`:100`): on page 3 of a 400-video channel, click "Favorites (2)" -> **0 cards and no pager** (blank screen; shot `fav-B-page3-then-favorites.png`); same after sort change or deleting the last video on the last page. Fix: derive `page = min(currentPage, totalPages-1)`, reset on filter/sort, add the favorites empty state. S / Med. Search + filter composition itself is correct (`:237-243`).

**QA-9b | Major | confirmed (config), binary needs Mac** — Release build is host-arch only (arm64 on `macos-15`). `Scripts/package_app.sh:27-30`, `release.yml` has no `ARCHES`. Intel Macs (common TV/projector boxes; app claims macOS 14+, Intel supported by Sonoma) cannot launch it. Fix: `ARCHES="arm64 x86_64"` (script already `lipo`s), verify Sparkle slice; ~2x macOS minutes. S / High.

**QA-10 | Minor | confirmed** — H9/M12 claimed fixed but aren't (see §2). Dead `sendBridgeWithTimeout`; delete or implement correlation ids. S / Low.

**QA-11 | Minor | confirmed** — 24 lint errors, no CI lint, docs say 26. Ratchet: fail on `rules-of-hooks`/`purity` now, burn down the rest. S / Med.

**QA-12 | Minor | suspected** — Disk full crashes the app: `AppLogger.swift:59 fileHandle?.write(data)` raises an Obj-C exception on ENOSPC, and every bridge message logs. Use `try handle.write(contentsOf:)`. S / Med.

**QA-13 | Minor | confirmed** — PR artifacts ship the committed (possibly stale) WebUI; drift check is advisory though the build is deterministic. Make `macos` depend on `webui` and consume the fresh bundle; make the diff blocking. S / Low.

**QA-14 | Minor | confirmed** — Appcast pushed before the Release asset exists; Sparkle tools downloaded unverified next to the private key (`release.sh:67,201,216`). Reorder (release first, appcast commit last), checksum-pin the tools. S / Med (UPD/SEC).

**QA-15 | Minor | suspected** — Quit leaves ffmpeg children and no SIGKILL (`AppDelegate.swift:184`; `ShellRunner.forceTerminate`). Put yt-dlp in its own process group and `killpg`; wait ~1 s in `applicationShouldTerminate`. S / Low.

**QA-16 | Minor | confirmed** — Every launch/midnight sync retries every errored video forever (`AppState.swift:543-546`), including permanently private/removed ones: each costs a 90 s title fetch + a failing download and flips cards back to "queued". Add attempt counter/backoff and a "permanent failure" state keyed on yt-dlp message. S / Med.

**QA-17 | Minor | confirmed** — Thumbnail handler rejects any path containing `..` (`ThumbnailURLSchemeHandler.swift:79`), so a library root such as `~/Videos/Kids...` shows no thumbnails. `standardizedFileURL` already resolved traversal; drop the substring test. S / Low.

**QA-18 | Minor | confirmed** — Testability/corruption: `DatabaseService.shared` private init + hard-wired path (`DatabaseService.swift:8-18`); invalid stored UUID becomes a fresh random `UUID()` on every load (`:793,941`), orphaning the row's children silently. Add `init(path:)`, skip+log bad rows. S / Med.

**QA-19 | Minor | suspected** — Fire-and-forget `Task { persist(...) }` writes (`LibraryStore.swift:578-590`) carry no ordering guarantee; a stale snapshot could land after a newer one. Route DB writes through one serial AsyncStream. M / Low.

**QA-20 | Docs** — AUDIT: "build.yml runs on pushes", "26 lint errors"; TODO: "schema at 7", `.v5` tools; BRIEF: `Player/PlayerState.swift` is live.

## 4. Automated test plan

### 4.1 Make Swift testable (prerequisite, S-M)
- `Package.swift`: add `.testTarget(name: "LocalTubeTests", dependencies: ["LocalTube"])`; SwiftPM can `@testable import` an executable target (macOS, Swift 6.0). If the `@main` entry/Sparkle link gets in the way, extract `LocalTubeCore` (Database, Models, Utilities, ShellRunner, ChannelSync parsers, LibraryPaths, PINService with injected clock) — also lets these tests run on a **Linux** runner in a `swift:6.0` container at 1x minutes (needs a system-library target for sqlite3).
- Seams: `DatabaseService.init(path:)` (+ `:memory:`), `AppSupportDirectory` base dir via `LOCALTUBE_SUPPORT_DIR`, `DownloadService(ytDlpPath:ffprobePath:)`, a `handle(type:payload:)` entry on `LocalTubeBridge` that doesn't need `WKScriptMessage`.
- Use Swift Testing (`import Testing`) — Xcode 16 / macos-15 has it.

### 4.2 Swift tests, in priority order
1. **LibraryPaths** (pure, 30 min): trailing slash, `..`, `/a/bc` vs `/a/b`, `~`, duplicate separators, **NFC vs NFD** names, `rebase`, `candidateLocations`, `isSafeComponent`.
2. **Migrations**: fresh -> v9 `sqlite_master` snapshot; fixture DBs v1..v8 -> v9 (check data preserved); re-run is a no-op; **kill-mid-migration** (apply ALTER, skip PRAGMA, run again — fails today = QA-4 regression test); FK cascades (delete channel -> videos, favorites, playlist_videos, profile_channels gone); `PRAGMA foreign_key_check` and `integrity_check` empty; backup created exactly when `0 < v < latest`; prune keeps 10.
3. **DatabaseService**: CRUD round-trips including NULL columns (emoji, last_synced_at, thumbnail), `rewritePathPrefix` with `_`/`%` paths + lookalike prefix + rollback on failure, `setProfileChannels` with duplicate ids (PK violation rolls back), invalid-UUID rows (QA-18).
4. **ShellRunner vs fake binaries** (shell scripts in a temp dir): exit 0/!=0, 200 KB stdout (pipe >64 KB), stderr-only, timeout (child `sleep 100`), stall watchdog (prints once then sleeps), SIGTERM-ignoring child -> SIGKILL, lingering grandchild (EOF safety net), missing/non-executable binary -> `launchFailedExitCode`, spaces/unicode args.
5. **DownloadService vs `fake-yt-dlp.sh`** (modes by env var: `ok`, `slow`, `fail:"ERROR: Video unavailable"`, `hang`, `partial`): queued->downloading->ready; error text surfaced; cancel mid-run; **retry after failure** (P2); de-dup (double enqueue); `maxConcurrent` honoured with 10 items; resume after "relaunch" (new service, same DB); folder-unavailable pause + resume; delete mid-download doesn't resurrect (`:219`); progress parse; DB-write failure on completion (`:221`) does not mark a downloaded file as error.
6. **Parsers/pure logic**: `youtubeVideoId` (watch, youtu.be, shorts, embed, `&list=`, `?v=-oBAD`, non-YouTube host with `v=`, music./m.), `slugified` (emoji-only, RTL, CJK, >50 chars), `Channel.sanitizedFolderName`, `uniqueFolderName`, `ChannelSyncService` line parser (tabs/newlines in titles, `NA`), `htmlEntityDecoded`, `DownloadQuality.ytDlpFormat`, `AppSettings` decoding of every historical JSON shape, `PINService` lockout schedule with fake clock (incl. clock moved back/forward).
7. **LibraryMaintenance** on temp dirs: verify/heal (renamed slug, moved root), relocate move/adopt/switch, partial failure, **merge conflict with truncated destination (QA-7)**, backup-failure path resumes downloads (QA-8). Same-volume vs cross-volume via a `hdiutil` RAM disk on the macOS runner.
8. **Bridge handlers**: for each of the 44 message types feed nil/missing/wrong-typed/oversized/bad-UUID payloads; assert no mutation and no crash; assert destructive handlers are rejected unless `isEditing || appMode == .editor` (does not exist today — decide policy first).

### 4.3 TypeScript — Vitest on the reducer (S, ~1 day)
Export `applyBridgeEvent`/`reducer` (move to `store/reducer.ts`); `vitest` with `environment: 'node'`. Exact sequences:
1. S1: `stateUpdate(full)` -> `channelUpserted(new)` -> `videosUpserted([a,b])` -> `videoRemoved(a)` => channel has `[b]`; `playlistVideos`/`profileFavorites` pruned of `a`.
2. **S2 (QA-1)**: `stateUpdate(v downloading .6)` -> `downloadProgressBatch({v:.97})` -> `downloadCompleted(v)` -> `stateUpdate(v ready)` -> late `downloadProgressBatch({v:.97})` => `v.downloadState==='ready'`, progress 1. Provider-level variant with a fake `requestAnimationFrame` proves the flush-before-other-events rule.
3. S3: progress for unknown id returns the same object reference.
4. S4: `downloadError(v)` -> late progress => stays `error`; `downloadCompleted` clears `activeDownload` only when ids match.
5. S5: `stateUpdate` omitting `activeDownload`/`libraryLoadError` clears them; partial `settings`/`dependencyStatus` merge; `videos` merge keeps untouched channels (and document the ghost-key behaviour for removed channels).
6. S6: `channelUpserted` existing id replaces in place; new id inserted sorted by `sortOrder`; creates empty `videos[id]`.
7. S7: `channelRemoved` deletes `videos[id]` but leaves `profileChannels`/favorites untouched (pin current behaviour), then a snapshot heals.
8. S8: `videosUpserted` merge-by-id, stable order on equal `sortOrder`, empty incoming no-op.
9. S9: `profileUpserted` -> `profileRemoved(active)` clears `activeProfileId`; (after fix) prunes favorites/hidden/playlists.
10. S10: `favoriteChanged`/`channelHiddenChanged` idempotent add/remove, unknown profile creates key.
11. S11: `playlistUpserted` -> `playlistVideosUpdated` -> `playlistRemoved`; `activePlaylistChanged(null)` -> `undefined`.
12. S12: `libraryFolderPicked(cancelled)` -> `libraryRelocationProgress` -> `libraryRelocated(ok:false)` => error toast, progress cleared.
13. S13: 6 toasts => 4 kept, unique ids.
14. S14: 1,000-video snapshot + 4 progress/frame budget (<5 ms per event) — perf guard.
15. S15: fuzz — random event streams never throw and never leave `videos` keys for channels absent from `channels` after a snapshot.
Plus a **contract test** (`scripts/check-bridge-contract.mjs`, runs on Linux in seconds): parse `types.ts` `BridgeMessage`/`BridgeEvent` and Swift `BridgeMessageType` + `emit("...")` names; fail on drift. I ran an equivalent today: currently in sync.

### 4.4 UI smoke — promote the mock-bridge harness (M, ~2 days, High value)
Recommendation: **yes, promote it to `WebUI/e2e/`** as a Playwright CI job (ubuntu, 1x minutes, ~2-4 min). It already renders the real bundle, drives 18 scenarios, records messages sent to Swift, and found QA-1/2/9 in minutes.
What it needs:
- `@playwright/test` devDependency + `playwright.config.ts` with two projects: `chromium` and `webkit` (closer to WKWebView's engine; still not identical).
- Build to a throwaway dir: `vite build --outDir .e2e-dist --emptyOutDir` (never the committed bundle); serve with `vite preview`.
- Convert `lib.cjs` to a Playwright fixture; `MOCK_INIT` becomes `addInitScript`; keep the fake-Swift `__bridgeSend` and make it **faithful**: always send *full* `stateUpdate`s (the harness's partial `{showPINEntry:true}` snapshots do not happen in production and mask the `activeDownload` clearing rule).
- Determinism for screenshots: stub `Math.random` (`Channel.tsx initialBgThumb`), `page.clock` for `Date.now` (`ChannelCard.tsx:103`), `reducedMotion:'reduce'`, `animations:'disabled'`, run in the official Playwright container, baselines updated only from CI; tolerance ~0.2 %. Fonts (SF Rounded) don't exist on Linux — baselines are for layout regressions, not typography review.
- Tests to ship first: (1) every scenario renders with **zero `console.error`/pageerror**; (2) QA-1/2/9 regressions; (3) message-contract assertions via `h.sent()` (e.g. delete confirm sends `deleteVideo{videoId}`); (4) axe-core on 6 screens; (5) PIN flow (wrong PIN shows lockout countdown); (6) 400-video channel renders <=24 cards.
- Move `fixtures.cjs` + 24 gradient thumbs (216 KB) into the repo.

### 4.5 CI job layout
```
build.yml (pull_request)
  webui         ubuntu   (~3 min, 1x)   npm ci; tsc --noEmit; eslint (ratchet: rules-of-hooks/purity blocking);
                                        vitest; contract test; vite build -> upload dist; drift check BLOCKING
  e2e           ubuntu   (~4 min, 1x)   playwright (chromium+webkit); upload report/diffs on failure
  macos         macos-15 (~9-11 min)    needs: webui (download fresh bundle into Resources/WebUI)
                                        swift build -c debug; swift test --parallel; package release (ARCHES=arm64 x86_64);
                                        codesign verify; `file` shows both slices; upload zip
  (optional) core-linux  swift:6.0 container, 1x   `swift test --filter LocalTubeCore` once the Core target exists
release.yml (push master)
  gate job     = same webui + macos tests (reuse via workflow_call) -> `release` needs: gate
  release      reorder release.sh: build -> zip -> sign -> gh release create -> then commit/push appcast+version;
                checksum-pin Sparkle tools; permissions least-privilege; pin actions by SHA
  post-release smoke (macos-15): download the published zip, verify EdDSA + codesign, unzip, launch with a `--smoke` flag
                (WebView loads, `getState` answers, exit 0) — needs a Mac to design/confirm
```
macOS-minute cost: GitHub bills macOS at 10x on private repos (free on public). One PR push today ~ 6-8 real min = 60-80 billed; adding debug tests + universal build ~ 10-12 real = 100-120 billed. Mitigations: `cancel-in-progress` (already), `paths:` filter (skip `macos` when only `WebUI/**` changes and no Swift/Scripts changed — the Linux jobs cover it), cache `.build`, run `swift test` in the same job as the debug build (one resolve/compile), and move pure logic to a Linux-testable `LocalTubeCore` so most Swift tests cost 1x.

## 5. Manual smoke test — real Mac (30-45 min)
Use a fresh macOS user (or `defaults delete com.local.localtube; rm -rf ~/Library/Application\ Support/LocalTube`), brew-installed `yt-dlp` + `ffmpeg`, a TV/second display if possible. Source of truth for each "expect" is the product spec; record failures with the log at `~/Library/Application Support/LocalTube/logs/localtube.log`.

A. Install & launch (5 min)
1. Unzip the release, move to /Applications, open (right-click > Open if Gatekeeper warns). Expect: window opens < 3 s; Welcome/onboarding; no beachball.
2. `file /Applications/LocalTube.app/Contents/MacOS/LocalTube`. Expect: **arm64 + x86_64** (QA-9b).
3. Launch twice quickly. Expect: one instance remains; no data loss (note: second launch kills the first).
4. Dependencies card with brew/yt-dlp/ffmpeg present = green. Rename `yt-dlp` temporarily: card shows missing and install path explains Homebrew requirement.

B. Onboarding, PIN, modes (5 min)
5. Choose a library folder on the internal disk. Expect: onboarding ends without relaunch.
6. Set a PIN (4 digits). Expect: "PIN Set!"; confirm mismatch is rejected.
7. Enter Admin: wrong PIN x3. Expect: shake + lockout countdown (5 s), not "Incorrect PIN" forever. Correct PIN enters Admin.
8. Quit and relaunch during a lockout. Expect: lockout persists. Set system clock forward 10 min: record whether lockout clears (known bypass).
9. Viewer cannot reach Admin controls without PIN; "Exit Admin" returns to Viewer.

C. Profiles & channels (5 min)
10. Create 2 profiles (icon+colour), assign different channels. Switch profiles: only assigned channels visible. Hide a channel for one profile.
11. Add a custom channel; add 3 video URLs (a normal video, a Short, a 3 h video). Expect: cards appear immediately as Queued with placeholder titles, then real titles.
12. Add a *source* channel by @handle. Expect: "Syncing..." then videos queued; banner appears.

D. Download lifecycle (7 min)
13. Watch 3 downloads: progress rises (may reset once for video+audio), **ends at Ready and stays Ready** (QA-1) while the window is minimised for part of it.
14. Cancel by quitting mid-download; relaunch. Expect: resumes automatically (no Retry), `.part` reused.
15. Disconnect Wi-Fi mid-download. Expect: error with readable message; reconnect + Retry works the first time.
16. Delete a video from a *synced* channel, quit, relaunch. Expect (desired): it does NOT come back (QA-3 will fail today).
17. Sleep the Mac 12+ min during a download, wake. Expect: download resumes or is re-queued, not "stalled" (QA-6).

E. Playback (7 min)
18. Play a ready video from Viewer. Expect: first frame < 1 s; controls fade; arrow keys/space/esc work; Esc exits to the same scroll position.
19. Seek, quit mid-video, relaunch, play again. Expect: resumes near the position.
20. Let a video end in each auto-playback mode (exit / sequential / repeat / random). Expect: matches label; "Up Next" queue plays in order, tolerates a removed video.
21. Volume up/down, mute; relaunch (volume currently not remembered). Play on an external display / AirPlay / full screen; plug/unplug the display mid-play.
22. Rename a ready file in Finder, then play it. Expect: toast "missing... re-queued", no black player.

F. Library management (5 min)
23. Delete a video, then a channel. Expect: files gone / folder in Trash; Settings -> Library counts update.
24. Settings -> Verify Now. Expect: totals match; orphan/partial files reported, nothing deleted.
25. Settings -> Change... -> **Move** to a second folder (preferably an external drive). Expect: progress per channel; everything plays after; old folder empty. Repeat with a pre-existing same-named *truncated* file in the destination (QA-7) — source must survive.
26. Eject the drive holding the library. Expect: "Library folder not found"; reconnect resumes by itself and resumes downloads.

G. Resilience & polish (5 min)
27. `kill -9` the app mid-download and mid-sync, relaunch. Expect: library intact, queue resumes, no duplicate yt-dlp children (`pgrep -fl yt-dlp`).
28. Fill the disk (or use a tiny disk image as library) during a download. Expect: readable error, app still responsive, no crash (QA-12).
29. Change language/region to one with decimal commas (e.g. de_DE). Expect: sizes/durations/progress render sanely.
30. Dark/Light, Reduce Motion, Reduce Transparency, 4K display at 200 %: no clipped text; keyboard-only (Tab/arrows/Enter/Esc) can reach every Viewer control; VoiceOver speaks card titles.
31. About: version equals the zip; Check for Updates... reaches the appcast.
32. Quit with Cmd-Q while 4 downloads run; `pgrep -fl "yt-dlp|ffmpeg"` after 5 s. Expect: nothing left (QA-15).

### Shorter pre-release checklist (~10 min)
1. `file` shows arm64+x86_64; version/build match tag; codesign verify.
2. Fresh-user launch -> onboarding -> pick folder -> add 1 video -> plays.
3. Wrong PIN lockout + correct PIN; Exit Admin.
4. Quit mid-download -> relaunch resumes.
5. Delete video from a synced channel -> relaunch -> stays deleted.
6. Verify Now has no unexpected missing/orphans on the real family library copy.
7. Check for Updates... finds the *previous* version's feed entry and the new zip downloads (HTTP 200).
8. Upgrade-in-place from the previous release on a copy of a real library: migrations run, backup file appears in `backups/`.
9. Play from external drive; eject/replug.
10. Skim `localtube.log` for `ERROR` lines.

## 6. Edge cases (what the code does today)
| Case | Current behaviour / risk |
|---|---|
| Offline | `fetchVideoTitle`/sync fail quietly (`""`/`lastSyncError`); downloads fail -> `error` w/ message; Retry works (P2). Auto retry only at next sync. |
| Disk full | yt-dlp error surfaces; DB write failures only logged (`persist`); **logger may crash** (QA-12). |
| Drive unplugged mid-download | `processNext` checks the folder only at slot start (`DownloadService.swift:185`); running downloads fail -> `error`; poll every 5 s resumes the queue; failed ones wait for sync/Verify. Thumbnails 404 meanwhile. |
| 1000+ videos | Full snapshot on every completion/error/relocation: harness 400 videos x 20 snapshots = 62 ms (OK); 5k videos untested; DOM is paged (24). JSON+base64 cost grows linearly (ARC lane). |
| Emoji / RTL / very long titles | Folder/file names go through `slugified()` (emoji-only -> `channel`, capped 50 chars + uuid8) so FS is safe; JS renders raw titles — needs a visual pass (UI lane). |
| Profile deleted while its video plays | Not handled in code I read: queue source `.queue(playlistId)` may reference a deleted playlist; `activeProfileId` cleared mid-playback (`LibraryStore.swift:329-341`). Needs Mac. |
| Double-launch | `SingleInstanceGuard` **terminates the older instance** (not activate-existing); can interrupt a relocation/migration in the old process. DB `busy_timeout` 5 s. |
| System clock change | PIN lockout is an absolute `Date` (forward = bypass); `.NSCalendarDayChanged` fires on clock edits -> extra auto-sync; `downloadedAt` ordering shifts. |
| Sleep/wake mid-download | QA-6 (suspected). Midnight sync relies on `.NSCalendarDayChanged` which also fires on wake (good). |
| Kill mid-migration | QA-4. Kill mid-download: P1 resume works; orphan ffmpeg child possible (QA-15). |
| Corrupted DB | `sqlite3_open` succeeds on garbage; `getUserVersion` returns 0 on prepare error -> tries migration 1 -> throws -> blocking error screen. No "restore latest backup" button although 10 snapshots exist. |
| Localised macOS | `Double(String)` is locale-independent; yt-dlp output is English; backups use `en_US_POSIX`. NFC/NFD folder names (accents) vs string-compare in `LibraryPaths.isPath` — suspected mismatch on non-English user folders. |
| Non-admin user | Homebrew install requires admin; `DependencyService` refuses without brew -> no downloads. Product decision: bundle yt-dlp/ffmpeg or give a non-brew path (UPD lane). |
| Intel Mac | Release is likely arm64-only (QA-9b). Fallback tool paths include `/usr/local/bin`, so the code intended Intel support. |

## 7. Cross-lane notes
- UPD: `release.sh` appcast-before-asset ordering and unverified Sparkle tools download (QA-14); Homebrew-only dependency model blocks non-admin users; `which` can't see pipx/MacPorts from a Finder launch.
- SEC: Swift destructive bridge handlers have no editor-mode gate (`LocalTubeBridge.swift:580-588, 651-657, 696-703`); PIN hash + plaintext recovery phrase in UserDefaults; `allowFileAccessFromFileURLs` still on (`WebWindowController.swift:94`); `youtubeVideoId` accepts arbitrary hosts / unvalidated ids.
- AV: `PlayerState` end-of-item observer uses `object: nil` (any item) and resume-save fires ~twice per 5 s window (`PlayerState.swift:158-185`); `Player/PlayerState.swift` is live code, not dead.
- ARC: every state change ships the whole library as JSON/base64 (`BridgeEventEmitter.swift:244-269`); 537.6 kB single chunk; `videoRemoved`/`channelRemoved` reducers rescan all channels.
- UX: no focus trap/restore, no picker keyboard nav, reduce-motion ignored; favorites empty state missing (QA-9).
