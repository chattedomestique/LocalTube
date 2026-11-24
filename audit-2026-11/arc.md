# ARC report — Performance, Architecture & Maintainability (LocalTube 1.0.37)

Lane tag `ARC-`. Method: code-first review, then measurements in the mock-bridge harness (Chromium, 4 CPU, software GL; the
harness `dist` is built from current source and its chunk hash `index-Vj9DQRXL.js` is identical to the committed
`Sources/LocalTube/Resources/WebUI/assets/index-Vj9DQRXL.js`, so the committed bundle is in sync with `WebUI/src`).
Swift is STATIC REVIEW ONLY; every Swift runtime cost below is `suspected` and listed under "Needs a real Mac".
Scripts + raw output: `scratchpad/work-arc/` (`scale.cjs`, `tick.cjs`, `extra.cjs`, `payload.cjs`, `sm.cjs`, `deadcode.py`, `unused.py`).

**PM correction folded in (what changed):** my first pass followed the brief and treated `Sources/LocalTube/Player/**` as dead.
That was wrong. `Bridge/PlayerOverlayController.swift:144-150` hosts the SwiftUI `PlayerControlsOverlay`
(`Player/VideoPlayerView.swift:354`) in an `NSHostingView` above the `AVPlayerView`, and nothing in Swift sets `__playerMode`
/ `LocalTubePlayer`, so `WebUI/src/screens/PlayerScreen.tsx` is the dead one. I recomputed the dead-code list symbol by symbol
(section 7) and added the live SwiftUI player to the perf review (ARC-9).

---------------------------------------------------------------------------------------------------------------------

## 1. Measurements

All "confirmed" numbers are from the real React bundle in headless Chromium with a fake bridge. Fixture thumbnails are unique
URLs serving a 1280x720 JPEG (134 KB) to mimic yt-dlp thumbnails. Chromium != WebKit; absolute ms will differ on a Mac, the
scaling shape will not.

| # | Metric | Value | Where / how |
|---|---|---|---|
| M1 | Channel **grid** DOM nodes | **452 at 400, 5,000 and 10,000 videos** (constant) | `Channel.tsx:245-249,956` pagination (pageSize 24 default) works; `scale.cjs` |
| M2 | Channel **list view** DOM nodes | 4,120 / 30,120 / 50,120 / **100,120** at 400 / 3k / 5k / 10k | `Channel.tsx:1039` renders all `sortedVideos`; ~10 nodes per row |
| M3 | Toggle grid->list time | 137 ms / 865 ms / 1.38 s / **3.45 s** (same sizes); long task max 1.5 s at 10k; renderer RSS 818 -> 1,434 -> 1,782 -> 2,685 MB | `scale.cjs` |
| M4 | Library **Feed tab** mount | 3,630 nodes/103 ms (400); 27,030 nodes/**866 ms** (3k); 45,030 nodes/**1.99 s** (5k) | `Library.tsx:646-694` renders every ready video, no paging |
| M5 | Library (channels tab) DOM nodes | 479-485 at 400..10,000 videos (O(channels)) | `scale.cjs` |
| M6 | Thumbnail requests fired at hydration | 420 / 3,020 / 5,020 / **10,020** (= every video, whichever screen is showing) | `useThumbnailPreloader.ts:26-42`, mounted at `App.tsx:150` |
| M7 | JS heap after hydrate | 3.4 / 7.3 / 10.3 / 17.8 MB at 400 / 3k / 5k / 10k | negligible; React state is not the memory problem |
| M8 | Renderer RSS after preload (Library) | 757 / 921 / 950 / 1,008 MB | Chromium discards decoded data, so no blow-up here; WebKit behaviour is unknown (Mac) |
| M9 | Swift-shaped `stateUpdate` payload | **677 B/video**: 263 KB (400), 1.98 MB (3k), **3.3 MB (5k)**, 6.6 MB (10k) JSON; x1.33 as base64 JS string: 4.4 MB at 5k, 8.8 MB at 10k | `payload.cjs` (realistic UUIDs/paths, 10% titles with emoji/curly quotes, ASCII-escaped as `BridgeEventEmitter` does). The in-code comment "~1.5 MB for a 300-video library" (`BridgeEventEmitter.swift:122`) is ~6x my number: unverified either way, log `base64.count` on a Mac |
| M10 | JS-side decode of that payload (`atob` + `JSON.parse`) | 0.6 / 4.7 / 7.8 / 16.4 ms | cheap; the expensive half is Swift (ARC-1) |
| M11 | Full `stateUpdate` re-apply while on Channel screen | 17 ms (400), **53 ms (5k)** to second rAF, one 181 ms long task; all 24 memoised `VideoCard`s re-render because every object is a new identity | `payload.cjs` |
| M12 | One download-progress tick, Channel screen | 1 commit, **64 components** re-rendered, 0 memoised cards re-rendered (memo works). Script cost per second at 8 ticks/s: 14 / 21 / 29 / 46 ms at 400 / 3k / 5k / 10k (about 1.8 -> 5.8 ms per tick, linear in N: re-sort + filters + preloader loop) | `tick.cjs` |
| M13 | One progress tick, Library channels tab | 1 commit, 39 components; 5.7-6 ms/s layout + 7-8 ms/s style; fine | `tick.cjs` |
| M14 | One progress tick, **Library Feed tab @3k** | **6,011 components re-rendered per tick; 374 ms/s script (about 47 ms/tick); 24 long tasks / 6 s, 24 frames > 50 ms** | `tick.cjs` (`FeedRow` not memoised, `videos` identity changes every tick) |
| M15 | IntersectionObserver rebuilds during downloads | 47 constructions in 6 s (once per tick) | `Channel.tsx:321-363` deps `[pagedVideos, commitDominant]` |
| M16 | Ambient-background rotation during downloads | 47 `setInterval(9s)` resets in 6 s; **0 layer swaps in 24 s with progress ticks vs 2 without** | `AmbientBackground.tsx:46-56` + `Library.tsx` `ambientSources` memo depends on `videos` |
| M17 | JS bundle | 537.5 KB raw / 145 KB gzip: react-dom 178 KB (33%), **@phosphor-icons/react 163 KB (30%)**, react 8 KB, app code 184 KB (Channel 30.6 KB, Library 16.9 KB, PlayerScreen 9.6 KB dead). CSS 24.6 KB / 5.7 KB gzip | sourcemap build to scratch dir (`sm.cjs`); repo untouched |
| M18 | Phosphor usage | 40 icons imported in `lib/profileIcons.ts:1-12`, **all rendered with `weight="fill"`** (`IconPicker.tsx:71`, `ProfileAvatar.tsx:37`) but each component ships six weights (about 4 KB each) | |
| M19 | First paint before data | UI shows "No channels yet / Ask a grown-up to add channels in Admin mode" until the first full state arrives | `work-arc/initial-empty-state.png`; ARC-4 |
| M20 | `emitStateUpdate` call sites | **33** (19 `LocalTubeBridge.swift`, 11 `AppDelegate.swift`, 3 `WebWindowController.swift` observers) | `grep` |
| M21 | Swift hygiene counts (live code) | 61 `try?`, 67 `Task {` (22 `@MainActor`), 7 `Task.detached`, 8 `@unchecked Sendable`, 3 `assumeIsolated`, 1 `os.Logger` category, 0 tests (no `Tests/`), `isInspectable` never set | `grep` |

---------------------------------------------------------------------------------------------------------------------

## 2. Findings (ranked)

### ARC-1 | Major | confirmed (code) / magnitude suspected | Full-library `stateUpdate` on hot paths
- `BridgeEventEmitter.emitStateUpdate` (`Bridge/BridgeEventEmitter.swift:58`) rebuilds `AppState.bridgePayload()` (`:283-354`) for the ENTIRE library on the main actor: a `[String: Any]` dictionary tree (about 14 boxed values + `ISO8601DateFormatter.string` + percent-encoded `thumbURL` per video), `JSONSerialization`, then `String.asciiSafeJSONString` (`Utilities/StringExtensions.swift:118-150`, a byte-at-a-time `Character(Unicode.Scalar)` append plus `String(format:)` per non-ASCII scalar), base64, interpolated into JS, `evaluateJavaScript` (`:36-48`). 3.3 MB JSON at 5k videos (M9).
- 33 call sites. The hot ones:
  - **Every download completion and failure**: `App/AppDelegate.swift:359,362`. A first sync of a 500-video channel = 500 full dumps.
  - **Every channel sync start and end** (2 per channel): `State/AppState.swift:426,430` post `.channelSyncStateChanged`, observed at `Bridge/WebWindowController.swift:199-210` which emits the full state; then `handleSyncChannel` emits again (`LocalTubeBridge.swift:715`). Auto-sync at launch and midnight (`AppState.swift:555-569`) with S source channels = 2S+ full dumps (plus banner fetch -> `.channelBannerUpdated` -> another, `WebWindowController.swift:186-197`).
  - **Every PIN attempt, PIN dialog open/dismiss, "Admin" press, View > Enter Editor Mode menu**: `LocalTubeBridge.swift:340,464,500,516`, `AppDelegate.swift:207`. A boolean flip ships the whole catalog.
  - Launch: 3 full dumps (`AppDelegate.swift:87,116,119`) + 2S.
- Why it exists: there is no diff event for `showPINEntry`, `needsPINSetup`, `isOnboarding`, `libraryFolderAvailable`, `dependencyStatus`, `syncingChannelIds`, `pendingDownloadCount`, `activeDownload`, `isScanning/lastScan`, so everything uses `stateUpdate`.
- The React reducer ALREADY merges partial `stateUpdate` payloads (`store.ts:115-131`) except two keys it clears when absent (`activeDownload`, `libraryLoadError`, `store.ts:127-129`): "omitted == cleared" is the only thing blocking partial updates.
- Estimated cost at 5k videos (suspected, Swift unmeasurable here): 0.3-1 s of main-thread work per dump; 30+ s cumulative during a big sync; the window beachballs on every PIN press.
- **Fix (M, High):** `emitStateUpdate(_:slices:)` with slices `.gates` (isOnboarding, needsPINSetup, showPINEntry, appMode, isEditing, libraryFolderAvailable, libraryLoadError, settings, dependencyStatus, appVersion), `.downloads` (activeDownload, pendingDownloadCount, syncingChannelIds, isScanning, isRelocating, lastScan), `.catalog` (channels, videos), `.profiles` (profiles, profileChannels, activeProfileId, favorites, hidden, playlists, playlistVideos). Default hot paths to the smallest slice. On download completion send `emitVideosUpserted(channelId:[updated])` (already exists, `BridgeEventEmitter.swift:134`) + `.downloads`. Make the reducer treat `activeDownload: null` / `libraryLoadError: null` as the explicit clear (`'activeDownload' in payload`), never absence. Expected: 3.3 MB -> under 1 KB per hot event (3 orders of magnitude).

### ARC-2 | Major | confirmed (code, WebKit threading per Apple docs) / magnitude suspected | Eager thumbnail flood + synchronous main-thread file reads
- `useThumbnailPreloader(state.videos)` (`App.tsx:150`, `lib/useThumbnailPreloader.ts:26-42`) does `new Image(); img.src = url; img.decode()` for EVERY video at hydration and for new ones later, no throttling. Measured 5,020 requests at 5k, 10,020 at 10k (M6), independent of which screen is open. It also re-walks all videos on every progress tick (part of M12).
- Each request is served by `Bridge/ThumbnailURLSchemeHandler.swift:27-60`: `FileManager.fileExists` + `Data(contentsOf:)` (a full 100-200 KB file read) + `allowedRoots()` + two `LibraryPaths.normalize` per root, all synchronously on the main thread (WebKit invokes scheme handlers on main). 5k thumbnails = about 650 MB read through the main thread in a burst at launch; on an HDD or SMB/NFS library it is far worse. Meanwhile the UI process is also serialising 3 full-state dumps (ARC-1).
- Thumbnails are full YouTube resolution (`--write-thumbnail`, `DownloadService.swift:326-327`, up to 1280x720 = 3.7 MB decoded) displayed in 280 px cards; `Thumb` is `loading="eager"` for every row (`VideoCard.tsx:25-56`), including list/feed rows.
- **Fix:** (S) delete the preloader (the grid is paginated and `Thumb` already `decode()`s on mount); `loading="lazy"` on list/feed rows. (S-M) in the scheme handler read the file on a background queue and hop to main only for `didReceive/didFinish` (WebKit requires main for the task calls). (M) generate a 320x180 (or 480x270) JPEG derivative at download time (`ffmpeg -vf scale` is already a dependency) and serve it for cards; keep the original for the player/ambient; backfill through the existing `scheduleThumbnailRegeneration` (`LibraryMaintenanceService.swift:304-340`). Expected: 10x less IPC/decode, main-thread I/O off the UI thread.

### ARC-3 | Major | confirmed | Two list surfaces are unvirtualised (Channel list view, Library Feed)
- Grid mode is fine (M1). List mode (`Channel.tsx:1036-1050`) and the Feed tab (`Library.tsx:681-692`) map every video: 100,120 DOM nodes at 10k, 3.45 s toggle (M2-M4), and the Feed re-renders 6,011 components per download tick (M14), which makes the UI stutter whenever any download runs.
- **Fix (S-M, High for libraries > 1k):** reuse `pagedVideos` in list mode (same page controls), paginate/window the Feed (e.g. "Recently added" top 100 + "show more"), wrap `FeedRow`/`VideoListRow` in `memo` with the same comparator as `VideoCard` (`VideoCard.tsx:508`), `content-visibility: auto; contain-intrinsic-size` as a cheap extra. A 3 KB windowing lib is optional.

### ARC-4 | Major | confirmed | Startup critical path shows a false "No channels yet" screen; stat on main
- `AppDelegate.swift:68-93`: the async init runs `dependencyService.checkAll()` (`/usr/bin/python3 --version` plus several `which` subprocesses, `DependencyService.swift:30-39,92-111`), then `resolveToolPaths()` (2 more `which`), THEN `loadLibrary()`, THEN the first `emitStateUpdate`. React sends `getState` on mount (`store.ts:542`), Swift answers immediately with the pre-load, empty catalog (`LocalTubeBridge.swift:345-348`), so React renders the empty-library state (screenshot `work-arc/initial-empty-state.png`) until all of that finishes. `LibraryStore.hasLoaded` exists (`LibraryStore.swift:58`) but is not in the bridge payload, so React cannot tell "loading" from "empty".
- `refreshLibraryFolderAvailability()` does a synchronous `stat` on the main thread in `bootstrapAppState` (`AppDelegate.swift:339`), every 5 s while the folder is unavailable (`:147-160`) and in `DownloadService.processNext` (`:185-186`) and `requeueMissingAndFailed` (`AppState.swift:523-525`). On a sleeping external HDD or dead network share a `stat` can block for seconds (suspected).
- **Fix (S, High):** add `isLibraryLoaded` to the payload (from `library.hasLoaded`) and show a skeleton/splash in `App.tsx` until true; start `loadLibrary()` first and run the dependency check concurrently (`async let`); move the `stat` calls to a utility queue and publish the result. Expected: first correct paint = DB load time only, no wrong "empty" flash on every launch.

### ARC-5 | Major | confirmed | Unstable identities make Ambient background freeze and IntersectionObserver churn during downloads
- Root cause = `videos` is a new object every progress tick (`store.ts:132-195`). `Library.tsx` `ambientSources` memo depends on `[visibleChannels, videos]` -> new array each tick -> `AmbientBackground`'s rotation effect (`AmbientBackground.tsx:46-56`, deps `[sources, cycleMs]`) clears and recreates the 9 s interval each tick, so it never fires: measured 0 swaps in 24 s with ticks vs 2 without (M16). The seed effect uses the joined signature (`sourcesSig`) and is fine; the rotation effect should use it too.
- Same cause in `Channel.tsx:321-363`: the IntersectionObserver is torn down and rebuilt on every tick (47 in 6 s, M15), re-observing every card.
- **Fix (S, Med):** depend on `sourcesSig` / a stable `useMemo` keyed on channel and thumbnail ids, not on `videos`; key the Channel IO effect on `pagedVideos.map(v => v.id).join()`. Better: ARC-6.

### ARC-6 | Major (architecture + perf) | confirmed | One context, one reducer, `videos` replaced per tick
- `store.ts:587-605` builds the context value inline each render, so all 15 `useAppStore()` consumers re-render on every action (toast, nav, tick). Only 1 `memo` in the app (`VideoCard`). Progress reducers (`:132-195`) walk every channel with `findIndex` and clone arrays; `videosUpserted` re-sorts (`:264-271`); `videoRemoved` rebuilds every list (`:272-288`).
- Today per-tick cost is tolerable (M12/M13) but linear in N, and it is the multiplier behind M14 and ARC-5.
- **Fix (M, Med):** `useSyncExternalStore` store with selector hooks (`useVideosOfChannel(id)`, `useProfile()`), keep download progress in its own tiny store (`progressById`) so `videos` keeps its identity; reducer split into slice modules; optional `videosById` + `channelVideoIds` normalisation. (A 1 KB external-store lib is an alternative.)

### ARC-7 | Minor-Major | confirmed (code) | Database write patterns (DB is correctly off-main)
- `DatabaseService` is an `actor` (`DatabaseService.swift:6`), WAL on, FK on, sensible indexes (`idx_videos_channel_id`, `idx_videos_channel_sort`, `idx_videos_youtube_id`, per-profile indexes: `DatabaseMigrations.swift:121-122,149,180,242,254,276,299`). No main-thread DB calls, no N+1 reads beyond one `fetchVideos` per channel at launch (`LibraryStore.swift:94-98`). Good.
- Writes are per-row autocommit: `LibraryStore.addVideo` spawns a `Task` + `insertVideo` per video (`LibraryStore.swift:546-550`; a 500-video sync = 500 transactions); verify heal awaits one `updateVideoPaths` per video (`LibraryMaintenanceService.swift:236-244`; a folder move at 10k = 10k commits); `PRAGMA synchronous` stays at FULL under WAL (`DatabaseService.swift:26-27`); resume position is written about twice per 5 s of playback (`PlayerState.swift:164` fires for two observer ticks inside the `< 0.55` window) with an O(N) `videoById` scan each (`LibraryStore.swift:606-616`).
- **Fix (S, Med):** `insertVideos([Video])` in one transaction for sync/add-URLs; `updateVideoPathsBatched`; `PRAGMA synchronous=NORMAL`; save resume at most every 10 s, on pause and on stop. Silent failure: `persist` only logs (`LibraryStore.swift:648-654`); DB failures never reach the UI.

### ARC-8 | Minor | confirmed (code) / suspected (cost) | `verify()` on every launch
- `LibraryMaintenanceService.verify` (`:173-340`) runs on every launch (`AppDelegate.swift:110-113`) and on recheck. The filesystem pass is correctly detached at utility QoS (`:208-218`). Per ready video: about 20 `normalize` calls (`expandingTildeInPath` + `standardizingPath`) and 2-3 `stat`s; plus an orphan walk (`:470-495`) with a `stat` per file. About 25-30k `stat`s and several hundred thousand `normalize`s at 10k videos (suspected 2-5 s CPU).
- It gates `resumePendingDownloads` and `autoSyncSourceChannels` (`AppDelegate.swift:110-119`), so a slow volume delays downloads; `requeueMissingAndFailed` repeats a per-channel `stat` pass on every sync (`AppState.swift:532-536`).
- **Fix (S-M):** do not gate downloads/sync on verify; run the orphan walk only on manual "Verify Library"; cache `LibraryPaths.normalize` results for the scan; skip when root mtime + counts are unchanged since the last scan.

### ARC-9 | Major (partly AV lane) | confirmed (code) / suspected (runtime) | Live SwiftUI player overlay (PM request)
Files: `Bridge/PlayerOverlayController.swift`, `Player/PlayerState.swift`, `Player/VideoPlayerView.swift:165-525`.
- Time observer: `addPeriodicTimeObserver(forInterval: 0.5 s, queue: .main)` (`PlayerState.swift:157-168`). 2 Hz publish into `@Observable currentTime` is fine; only `ScrubBar` reads it (`VideoPlayerView.swift:257-300`). Redundant `Task { @MainActor }` hop inside a `.main` callback; harmless.
- **Mouse-move storm:** `onContinuousHover { showControls() }` (`:451-453`) runs on every mouse event (60-120 Hz): sets `controlsVisible = true` unconditionally (an `@Observable` write notifies readers even if unchanged, suspected) and cancels + recreates a `Task.sleep(4 s)` each time (`PlayerState.swift:114-133`). Guard with `if !controlsVisible` and only re-arm the timer when more than 250 ms have passed.
- **Hidden controls stay in the tree:** the controls are hidden with `.opacity(controlsVisible ? 1 : 0)` only (`:380,398,410,441`). Four `.ultraThinMaterial` backdrops, three 28-pt shadows and a `Slider` stay instantiated and hit-testable above the video for the entire playback (suspected GPU cost on a 4K TV; also invisible buttons react to hover). Conditionally build the subtree (`if controlsVisible`) with the existing transition.
- **Scrub drag:** `ScrubBar` drag calls `playerState.skip(seconds: frac*duration - currentTime)` on every drag event (`VideoPlayerView.swift:287-295`); `skip` is a zero-tolerance seek (`PlayerState.swift:85-91`) relative to the live `player.currentTime()`, but the delta is computed against the 2 Hz stale `currentTime`. After the first seek the baselines disagree and the error compounds per event (suspected: overshoot/jumps), and zero-tolerance seeks at event rate force repeated decode-from-keyframe. Use tolerant seeks while dragging, one precise seek on `.onEnded`, absolute target (not delta), serialise on `seek(completionHandler:)`. (Cross-lane AV.)
- Resume persistence cadence: see ARC-7. `PlayerState.play` polls `item.status` every 100 ms for up to 10 s on the main actor (`:56-61`) and does not cancel the previous Task, so `playNext` can run an older Task's `seek` against the new item (suspected race). Use `item.publisher(for: \.status)` / `asset.load(.isPlayable)`.
- `stop()`/`hide()` save the resume position but never tell React (`updateResumePosition` emits nothing, `LibraryStore.swift:606-616`), so resume badges stay stale until the next full dump. Emit `videosUpserted` after `stop()`.

### ARC-10 | Minor | confirmed | Bundle, CSS and dependency hygiene
- 537 KB bundle (M17). Phosphor is 30% for 40 icons used only as `fill`: inline the 40 fill SVG paths (about 28 KB raw, -130 KB). Code-splitting is NOT worth it: the bundle loads from disk and parses in tens of ms, and the app is one WebView. Delete dead `PlayerScreen` (-9.6 KB min).
- Tailwind is used only for Preflight (0 Tailwind-style utility classNames in `src/`; all styling is inline `style={{}}` (Channel 89, Editor 52, Library 47) + `index.css`). `@tailwindcss/vite@4.2.1` declares `peerDependencies.vite: ^5.2 || ^6 || ^7` against vite 8.0.0, which is why CI needs `npm ci --legacy-peer-deps` (`build.yml:40`, `release.yml:74`). `@tailwindcss/vite@4.3.5` (latest) lists `^8`, so a bump removes the flag; dropping Tailwind (replace Preflight with a 3 KB reset) removes `tailwindcss`, `@tailwindcss/vite`, and the unused `autoprefixer` + `postcss` (no postcss config exists).
- Freshness (`npm outdated`): react/react-dom 19.2.4 -> 19.3.1, vite 8.0.0 -> 8.3.8, @tailwindcss/vite 4.2.1 -> 4.3.5, plugin-react 6.0.1 -> 6.3.0, typescript-eslint 8.57.1 -> 8.73.0, eslint 9.39 (v10 exists; stay), typescript 5.9.3 (7.0.2 exists; stay, `typescript-eslint` caps `<6`). Sparkle: `Package.resolved` pins 2.9.1; `Scripts/setup-sparkle.sh:17` downloads tools 2.6.4 (version skew, and `tar ... || true` hides extraction failure, `:25`; its printed Gist/`APPCAST_URL` instructions, `:59-61`, contradict the current `raw.githubusercontent` appcast in `version.env`).
- `version.env` is tracked (`git ls-files`) although `.gitignore:25` lists it: the ignore rule is inert and misleading (release.sh edits it). Decide: track it and remove the ignore line.
- Shell portability: checked every script for the bash-3.2 hazard (`$var` directly followed by a non-ASCII byte under `set -u`): 0 occurrences; no bash-4-isms (`declare -A`, `mapfile`, `${x^^}`). Non-ASCII appears only in echo/comment text. `setup-sparkle.sh` public-key scrape `grep -oE '[A-Za-z0-9+/=]{40,}' | head -1` (`:41`) is heuristic.
- Committed bundle (`Sources/LocalTube/Resources/WebUI/`): 20 of 58 commits touch it; every UI change renames the hashed `assets/index-*.js` + `index.html`, so two parallel PRs always conflict. `release.yml:67-74` already rebuilds it in CI on every merge; `compile_and_run.sh:28-32` rebuilds locally. The CI freshness check is advisory-only (`build.yml:46-56`, `continue-on-error`). Alternatives: stop committing it (placeholder `index.html` so `swift build` works, `package_app.sh` runs `npm run build`), or keep it but force stable file names (`build.rollupOptions.output.entryFileNames: 'assets/app.js'`) so diffs become content-only and a `.gitattributes` `merge=ours`/`-diff` rule can apply.
- Unused CSS: 9 selectors, about 111 lines (`.lt-surface`, `.lt-surface-el`, `.lt-glass`, `.lt-glass-light`, `.lt-glass-panel`, `.lt-icon-btn`, `.lt-editor-toggle`, `.line-clamp-1`, `.lt-panel-in`), 0 references in `src/`. Backdrop-filter is declared 54 times; the channel/library ambient background stacks up to 5 (Channel, `MAX_BG_LAYERS`) or 4 (Library) layers, each with two full-viewport images blurred 64 px / 40 px + `mix-blend-mode: screen` (`Channel.tsx:1170-1235`, `AmbientBackground.tsx:100-140`); GPU cost at 4K is untestable here (Needs a Mac).

### ARC-11 | Major (maintainability) | confirmed | God files and duplicated, untyped wire contract
- `Channel.tsx` is 1,450 lines of which **`Channel()` is one 1,130-line component** (`:40-1169`) with 89 inline style objects, 10 `useState`, 9 `useMemo`, 2 IntersectionObservers, banner/search/sort/pagination/ambient/list/modal logic in one function.
- `Library.tsx` 923, `store.ts` 613, `LocalTubeBridge.swift` 896 (about 45 handlers + about 300 lines of `payload["x"] as? T` parsing), `DatabaseService.swift` 983 (every method repeats prepare/bind/step/finalize), `LibraryMaintenanceService.swift` 839 (verify + scanner + relocate + delete helpers).
- CODE_REVIEW M7 is **fixed-already**: `BridgeMessageType(rawValue:)` + exhaustive `switch` drives dispatch (`LocalTubeBridge.swift:35-94`). M8 stands in a different form: `BridgeMessage` + `AnyCodable` (`BridgeMessage.swift:71-115`) are never referenced (dead), while real payloads are still `[String: Any]` with blind `as?` casts, hand-mirrored in `WebUI/src/types.ts` (282 lines) and `BridgeEventEmitter.swift` (427 lines). `types.ts` also mixes a JS-internal synthetic event (`downloadProgressBatch`) into the wire union.
- Error handling: `LibraryStore.persist` logs and swallows (`:648-654`); 67 fire-and-forget `Task {}`; 61 `try?` (13 in `LibraryMaintenanceService`, 10 in `DownloadService`, e.g. thumbnail `removeItem/moveItem` failures at `DownloadService.swift:383-384` are invisible). One `os.Logger` category ("app", `AppLogger.swift:9`), interpolated `String` messages are redacted as `<private>` in Console by default; no `OSSignposter`. `isInspectable` is never set, so Safari Web Inspector cannot attach to the WKWebView in a release build (macOS 13.3+).
- There are no automated tests at all (no `Tests/` target in `Package.swift`, no vitest in `WebUI/package.json`): every refactor below is blind without at least reducer + `LibraryPaths` + scanner tests (QA lane).

---------------------------------------------------------------------------------------------------------------------

## 3. Ranked perf fixes with expected gain

| Rank | Fix | Effort | Expected gain |
|---|---|---|---|
| 1 | Slice partial `stateUpdate` + `videosUpserted` on completion (ARC-1) | M | 3.3 MB -> under 1 KB per hot event at 5k; removes the largest main-thread stalls (sync, PIN, completions) |
| 2 | Delete preloader + off-main thumbnail reads (+ 320 px derivatives) (ARC-2) | S + M | removes 5k-10k main-thread file reads at launch; 10x less image IPC/decode |
| 3 | Loading flag + init order + stat off-main (ARC-4) | S | no false "empty" screen; first correct paint = DB load only |
| 4 | Paginate list/feed + memo rows (ARC-3) | S-M | 100k -> about 500 DOM nodes at 10k; Feed tick 47 ms -> under 1 ms |
| 5 | Stable deps for Ambient/IO (ARC-5) | S | fixes frozen ambient rotation during downloads, removes 47 IO rebuilds/6 s |
| 6 | DB batching + `synchronous=NORMAL` + resume throttle (ARC-7) | S | sync/verify writes from N fsyncs to 1; fewer WAL syncs while watching |
| 7 | Selector store / progress store (ARC-6) | M | per-tick cost independent of library size |
| 8 | Player overlay guards + tolerant scrub seek (ARC-9) | S-M | smoother 4K playback + scrubbing (Mac to confirm) |
| 9 | Verify off the critical path (ARC-8) | S-M | downloads/sync start immediately on large libraries |
| 10 | Inline Phosphor fill icons, drop Tailwind, delete dead code (ARC-10) | S-M | -130 KB JS, no `--legacy-peer-deps`, fewer deps |

## 4. Architecture-debt ranking

1. Hand-duplicated, untyped bridge contract + full-snapshot coupling (ARC-1, ARC-11).
2. God units: `Channel()` 1,130 lines; `LocalTubeBridge` 896; `DatabaseService` 983; `LibraryMaintenanceService` 839; `store.ts` 613 (ARC-11).
3. Dead code about 32% of Swift LOC + a dead React screen (section 7).
4. No tests; Swift 5 language mode (`Package.swift:21-26`) hides data-race issues (SEC lane).
5. Observability gaps: one log category, no signposts, no Web Inspector, payload sizes unlogged.
6. Committed build artefacts and Tailwind peer-conflict workaround.

### Proposed decomposition
**`Channel.tsx` (1,450) ->** `screens/channel/ChannelScreen.tsx` (composition, about 150), `useChannelVideos.ts` (sort/filter/search/favourites/paging, pure + unit-testable, about 120), `useAmbientBackdrop.ts` (IO + rolling layers, about 130), `ChannelBanner.tsx`, `ChannelTopBar.tsx` (sticky bar, view toggle, sort, page size), `VideoGrid.tsx`, `VideoList.tsx` (windowed), `Pagination.tsx`, `DeleteChannelDialog.tsx`, `AddVideosDialog.tsx`, `BgBlurLayer.tsx`, `FavoritesFilterPill.tsx`, plus a shared `style` token file replacing the repeated inline blur/glass objects.
**`Library.tsx` (923) ->** `LibraryScreen.tsx`, `ChannelsTab.tsx`, `FeedTab.tsx` (windowed + memo), `PlaylistsTab.tsx`, `LibraryTopBar.tsx`, `EditingBanner.tsx`, `ProfileChip.tsx`, `useVisibleChannels.ts`.
**`store.ts` (613) ->** `store/` : `reducer/{catalog,profiles,playlists,downloads,ui}.ts`, `selectors.ts`, `progressStore.ts`, `AppStoreProvider.tsx` (about 60), `bridgeEvents.ts` (generated, below).
**`LocalTubeBridge.swift` (896) ->** `BridgeRouter` (decode + dispatch, about 80) and one handler file per domain as `extension LocalTubeBridge`/small structs: `PINHandlers`, `ChannelHandlers`, `VideoHandlers`, `ProfileHandlers`, `PlaylistHandlers`, `LibraryHandlers`, `PlayerHandlers`, `SettingsHandlers`; payloads decoded into `Decodable` structs (kills about 300 lines of `as?` guards).
**`DatabaseService.swift` (983) ->** keep the `actor` + connection/migrations in `DatabaseService.swift` (about 120), move SQL into `Database/Repos/{Channels,Videos,Profiles,Playlists,Favorites}+DB.swift` as actor extensions, and add a 40-line `Statement` helper (`prepare/bind/step/finalize` with `defer`) that removes about 40% of the file.
**`LibraryMaintenanceService.swift` (839) ->** `LibraryScanner` (pure, nonisolated, unit-tested: scan, resolve, orphan walk), `LibraryRelocator`, `LibraryFileDeleter`, and a thin `@MainActor LibraryMaintenanceService` that only applies results to state.

### Wire contract: one schema -> both languages
1. Author `Bridge/contract/bridge.schema.json` (JSON Schema 2020-12): `Video`, `Channel`, `Profile`, `Playlist`, `AppState` (every field optional for partial updates, explicit `null` for clears), `BridgeEvent` and `BridgeMessage` as `oneOf` discriminated on `type`.
2. Generate both sides in a dev script (`quicktype` from JSON Schema emits TypeScript and Swift `Codable`): `WebUI/src/generated/bridge.ts` and `Sources/LocalTube/Bridge/Generated/BridgeContract.swift`. Commit the output; CI (the Linux job already runs node) re-generates and `git diff --exit-code`s, so the two sides cannot drift. (Alternatives: TypeSpec, or zod -> JSON Schema if runtime validation of events on the JS side is wanted.)
3. Swift receives `WKScriptMessage.body` via `JSONSerialization -> Data -> JSONDecoder` into the generated `BridgeMessage`, and the `switch` becomes exhaustive on payload-typed cases.
4. Swift sends `Encodable` events with `JSONEncoder` (no `[String: Any]` boxing) and delivers them with `WKWebView.callAsyncJavaScript("window.LocalTubeBridge.dispatchJSON(json)", arguments: ["json": jsonString], in: nil, contentWorld: .page)`: the string argument is marshalled natively, so the `asciiSafeJSONString` loop (`StringExtensions.swift:118-150`), the base64 + `atob` round-trip (33% inflation) and the JS string interpolation all disappear. JS side: `dispatchJSON = s => dispatch(JSON.parse(s))`.
5. Move `downloadProgressBatch` out of the wire union into a JS-internal type.

---------------------------------------------------------------------------------------------------------------------

## 5. Refactor roadmap (each step independently shippable)

0. **Dead-code purge (S, no behaviour change).** Move `Color.ltAccent` to a 5-line `Utilities/Color+LT.swift`, then delete per section 7. Verify on a Mac/CI build (`swift build`) + `tsc -b`.
1. **JS quick wins (S).** Remove the preloader; stable deps for `AmbientBackground`/Channel IO; paginate Channel list view + Feed; `memo` `FeedRow`/`VideoListRow`; `loading="lazy"` on non-grid thumbnails.
2. **Startup (S).** `isLibraryLoaded` in the payload + splash; DB load first, deps check concurrent; move folder `stat`s off main.
3. **Partial state updates (M).** Introduce `emitStateUpdate(slices:)`; fix omit==clear in the reducer; switch completion/PIN/sync paths; add `OSSignposter` + payload byte log around `emit` to prove the gain.
4. **DB batching (S).** `insertVideos`, `updateVideoPathsBatched`, `synchronous=NORMAL`, resume throttle; surface persist failures as an error toast.
5. **Thumbnails (M).** Off-main reads in the scheme handler; 320 px derivatives at download + backfill in verify; serve derivatives to cards.
6. **Verify off the critical path (S-M).** Decouple from resume/sync; orphan walk only on manual verify.
7. **Store (M).** Selector store + separate progress store; slice the reducer (keeps public hook API, so screens migrate one by one).
8. **Screen decomposition (M each, one PR per screen).** `Channel.tsx` first, then `Library.tsx`.
9. **Wire contract (M-L).** Schema + codegen + typed Swift decode + `Encodable` events + `callAsyncJavaScript`; do it after step 3 so the slices are in the schema.
10. **Swift file decomposition (M).** Bridge handlers, DB repos + `Statement`, maintenance scanner; add unit tests for `LibraryPaths` and `LibraryScanner` (pure) in the same PRs.
11. **Packaging hygiene (S-M).** Inline Phosphor fill icons; bump `@tailwindcss/vite` or drop Tailwind and remove `--legacy-peer-deps`; stop committing the bundle (or stable file names); fix `setup-sparkle.sh`; drop the inert `.gitignore` `version.env` line; `isInspectable` under a debug flag.
12. **Player polish (S-M).** Overlay guards, tolerant scrub, single `seek` pipeline (see ARC-9; coordinate with AV).

---------------------------------------------------------------------------------------------------------------------

## 6. Instruments traces to collect on a Mac (Release build, real library of 1k and 5k+ videos)

1. **Time Profiler**, cold launch to first interactive paint, main thread only, invert call tree. Look for `BridgeEventEmitter.emit` -> `JSONSerialization.data`, `String.asciiSafeJSONString`, `AppState.bridgePayload`, `Video.bridgePayload`, `ISO8601DateFormatter.string`; `ThumbnailURLSchemeHandler.webView(_:start:)` -> `Data(contentsOf:)`; `LibraryPaths.normalize`. Wrap `emit` in `OSSignposter` intervals tagged with event name and byte count so the Points of Interest lane shows how many `stateUpdate`s fire at launch, during one download completion, and for one PIN attempt.
2. **Hangs** (plus Time Profiler) while: launching, finishing a download, syncing a 20-channel account, typing a PIN, toggling Admin. Any hang over 250 ms with `emit` in the stack confirms ARC-1.
3. **System Trace** (or `fs_usage -w -f filesys`) at launch: main thread blocked in `stat`/`read` (ARC-2/4), thread-state lanes during `verify`, count of `stat64` calls from the maintenance scan. Repeat with the library on an external HDD and on an SMB share.
4. **Allocations + VM Tracker**, attach to `com.apple.WebKit.WebContent` (Choose Process > All Processes): mark generations after hydration, after opening a channel, after toggling list view; compare 400 vs 5k videos (ARC-2/3). Separately, Leaks/Allocations on the app process for 20 play/stop cycles (`PlayerState`, `AVPlayer`, observer tokens).
5. **Core Animation + Metal System Trace** at 4K: Library and Channel screens idle and while scrolling (blurred ambient layers + backdrop-filters), and the player overlay over a 4K video with controls hidden vs shown (materials in the tree). Watch GPU utilisation, frame time, offscreen-rendered layers.
6. **Safari Web Inspector** on the WKWebView (needs `isInspectable = true` in a debug build): Performance timeline while a download runs on Library > Feed and Channel; confirm commit counts and the IO churn.

## 7. Verified dead-code deletion list (recomputed after PM correction)

Method: symbol-level reference scan (`work-arc/deadcode.py`, `unused.py`) with comments stripped, seeded from all non-`Views/` Swift plus the LIVE half of `Player/VideoPlayerView.swift`; manual confirmation of every hit.

**Truth about the old premise:** `Player/**` is LIVE (`PlayerState.swift` 203 LOC; `VideoPlayerView.swift` 525 LOC, of which the live part is lines 165-525). `Views/**` is unreachable from the AppKit entry point; the only symbol the live player pulls from it is **`Color.ltAccent`** (`Views/Shared/TenFootStyles.swift:14`, used at `VideoPlayerView.swift:273,428,462,487`). Everything else in `TenFootStyles` (`ltText`, `ltTextSecondary`, `ltHeadline`, `ltBody`, `LTScrimBackground`, `LTButtonStyle`, `LTSecondaryButtonStyle`, ...) is referenced only from `ResumePromptOverlay` (`:125-163`), which is itself only used by the dead `VideoPlayerView` struct (`:33-121`, instantiated only by dead `ViewerRootView.swift:19`).

### A. Swift

| Path | LOC | Notes |
|---|---|---|
| `Sources/LocalTube/Views/ContentRootView.swift` | 36 | never instantiated |
| `Views/Viewer/ViewerRootView.swift` | 39 | only caller of dead `VideoPlayerView` |
| `Views/Viewer/ViewerChannelView.swift` | 253 | |
| `Views/Viewer/ViewerLibraryView.swift` | 111 | |
| `Views/Editor/AddVideosView.swift` | 284 | |
| `Views/Editor/AutoLockTimerView.swift` | 43 | timer removed |
| `Views/Editor/DownloadQueuePanel.swift` | 140 | |
| `Views/Editor/EditorChannelDetailView.swift` | 388 | |
| `Views/Editor/EditorRootView.swift` | 225 | |
| `Views/Editor/NewChannelFlow.swift` | 575 | |
| `Views/Onboarding/DependencyCheckView.swift` | 145 | |
| `Views/Onboarding/DownloadFolderOnboardingView.swift` | 62 | |
| `Views/Onboarding/PINSetupView.swift` | 170 | |
| `Views/Settings/SettingsView.swift` | 293 | |
| `Views/Shared/ChannelCard.swift` | 88 | |
| `Views/Shared/DownloadStateBadge.swift` | 43 | |
| `Views/Shared/MouseTrackingView.swift` | 65 | |
| `Views/Shared/NumpadView.swift` | 96 | |
| `Views/Shared/PINEntryOverlay.swift` | 93 | |
| `Views/Shared/PINRecoveryView.swift` | 87 | |
| `Views/Shared/VideoCard.swift` | 152 | |
| `Views/Shared/TenFootStyles.swift` | 261 | **keep only `Color.ltAccent`** (move 1 line to `Utilities/Color+LT.swift`) |
| **Subtotal `Views/**`** | **3,649 (22 files)** | net 3,648 after moving `ltAccent` |
| `Player/VideoPlayerView.swift` lines 6-163 (`NativePlayerView`, `VideoPlayerView`, `ResumePromptOverlay`) | 158 | dead region of a live file; lines 165-525 stay |
| `Utilities/AccessibilityHelpers.swift` lines 14-55 (`ConditionalAnimationModifier`, `reducibleAnimation`, `TenFootFocusModifier`, `tenFootFocusRing`) | 42 | zero references anywhere; **keep** lines 1-12 (`NSWorkspace.shouldReduceMotion`, used at `VideoPlayerView.swift:444`) |
| `Bridge/BridgeMessage.swift` lines 71-115 (`struct BridgeMessage`, `AnyCodable`) | 45 | enum `BridgeMessageType` above it is live |
| `State/AppState.swift`: `ViewerDestination` (43-46), `viewerPath`, `currentVideoId` (69-70), `editorSelectedChannelId` (119), `undoManager` (123-125,166), `onEditorTimerTick` (141) | about 15 | |
| `State/LibraryStore.swift`: all `undoManager?.registerUndo/setActionName` blocks (about `449-454, 472-491, 505-508, 541-544, 558-561`) + `undoManager` var | about 40 | `undoManager` is never assigned anywhere in live or dead code, so undo has never worked in this build |
| `Services/ChannelResolverService.swift`: `resolve`, `fetchVideoURLs`, `extractChannelId`, `ResolvedChannel`, line collector (keep `findYtDlp`, used by sync/banner) | about 95 | only dead `NewChannelFlow`/`AddVideosView` call them |
| `Services/DownloadService.swift` `refreshThumbnails` (471-517) | 47 | comment says "called after a channel sync"; nothing calls it: delete or wire |
| `Services/DependencyService.swift` `installMissing` + `installBrewPackage` + `installLog/isInstalling/installError` | about 60 | only dead `DependencyCheckView` used it; no bridge message exists. Either delete or build the React "Install via Homebrew" flow (UPD) |
| Misc one-offs: `PINService.loadRecoveryPhrase/storedPINLength/deleteAll/PINError`, `SettingsService.resolveBookmark` (+ bookmark creation in `save`), `Video.formattedDuration`, `Channel.displayLabel`, `String.isYouTubeVideoURL`, `LibraryStore.visibleChannels`, `DependencyStatus.allSatisfied/missingNames`, `AppState.editorRemainingSeconds` + payload key | about 50 | each has exactly 1 reference (its declaration) |
| **Swift total** | **about 4,200 of 13,008 LOC (about 32%)** | the brief's "about 4.4k" overcounted by treating live `Player/**` (728 LOC) as dead |

### B. WebUI
| Path | LOC / size | Notes |
|---|---|---|
| `WebUI/src/screens/PlayerScreen.tsx` | 536 (9.6 KB of the min bundle) | no Swift code sets `__playerMode`/`LocalTubePlayer`; the live player is SwiftUI |
| `WebUI/src/main.tsx` lines 5, 7-14 (`PlayerScreen` import, `isPlayerMode` branch) | about 8 | |
| `WebUI/src/bridge.ts` `sendBridgeWithTimeout` (14-44) | about 31 | zero callers; also monkey-patches `LocalTubeBridge.dispatch` and leaves the wrapper installed on timeout |
| `WebUI/src/App.css` | 1 | not imported |
| `WebUI/src/assets/{hero.png 44.9 KB, react.svg 4.1 KB, vite.svg 8.7 KB}` | n/a | not imported (Vite template leftovers) |
| `WebUI/public/icons.svg` | 4.9 KB, shipped into `Resources/WebUI/icons.svg` | not referenced by `index.html` or any source |
| `WebUI/README.md` | 73 | unmodified Vite template |
| `index.css` unused selectors (9) | about 111 | list in ARC-10 |
| `src/lib/useThumbnailPreloader.ts` | 42 | delete with ARC-2 (a perf fix, not just dead) |
| Vestigial: `editorAutoLockMinutes` (setting kept in `types.ts`, `Settings.tsx:79-84`, Swift `AppSettings` + validation at `LocalTubeBridge.swift:686-688`) | small | the auto-lock timer was removed (EDITING_MODEL), no UI renders it |
| Dependencies: `autoprefixer`, `postcss` (no config), and `tailwindcss` + `@tailwindcss/vite` if Preflight is replaced | 4 devDeps | |

---------------------------------------------------------------------------------------------------------------------

## 8. Needs a real Mac to confirm
- Main-thread cost of a full `stateUpdate` at 1k/5k/10k videos, and the count of them at launch / per download completion / per PIN press (ARC-1).
- `ThumbnailURLSchemeHandler` main-thread burst at launch, WebContent memory with 5k+ thumbnails, effect of removing the preloader (ARC-2).
- Whether an `@Observable` write of an unchanged value notifies SwiftUI readers (ARC-9 mouse-move storm); GPU cost of hidden materials/shadows over 4K video; scrub-drag overshoot.
- GPU/frame cost of the stacked blurred ambient layers + backdrop-filters at 4K in WKWebView.
- `verify()` duration at 10k videos on SSD, external HDD, SMB share; `stat` on an unreachable volume at launch.
- WKWebView behaviour of 10k `<img>` in list view (Chromium numbers above are shape only).

## 9. Cross-lane notes
- **AV:** scrub-drag delta uses stale `currentTime` (`VideoPlayerView.swift:292` vs `PlayerState.swift:85-91`); resume position is never pushed to React after `stop()`; stale `play` Task can seek the next item.
- **UI/UX:** wrong "No channels yet" flash at every launch (ARC-4); titles stay "Video xxxx" until the download completes because the title update at `DownloadService.swift:284-288` is never emitted; Channel view-toggle buttons have no `aria-label` (`Channel.tsx:686-690`).
- **SEC:** PIN verifier lives in `UserDefaults` (`PINService.swift:7-12`); `allowFileAccessFromFileURLs` is on (`WebWindowController.swift:84`); Swift language mode v5 (`Package.swift:21-26`).
- **UPD:** `DependencyService.installMissing` has no bridge message (orphan feature); `refreshThumbnails` orphan; `setup-sparkle.sh` tool version 2.6.4 vs framework 2.9.1 and stale Gist instructions; `python3 --version` gate (`DependencyService.swift:92-98`) needs Xcode CLT but the standalone yt-dlp binary may not need Python at all.
- **QA:** zero Swift/JS tests; bundle freshness check is advisory-only; `npm ci` needs `--legacy-peer-deps`.
- **DSG:** up to 10 full-viewport blurred images (+ blend mode) per screen and 54 `backdrop-filter` declarations.
