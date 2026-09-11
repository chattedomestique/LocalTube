# LocalTube — TODO

Living list of work to be done. Items marked **★** are the user's explicit
requests; items without are things I noticed and want to fix. Strike them
out with `~~~~` as they ship.

Priority is rough: **P0** = ship soon, **P1** = next, **P2** = whenever,
**P3** = nice-to-have.

---

## Features

### ★ Playlists / queue [P0]
- [ ] Right-side slide-out tray that holds the current queue.
- [ ] **Add to queue** affordance on every video card (icon top-right
      corner of the card — distinct from the favorite heart top-left).
- [ ] In-tray: drag-reorder, remove individual videos, **Clear queue**
      button with confirmation modal.
- [ ] Queue persists across app launches per profile (DB-backed, not
      `localStorage` — survives reinstall, syncs across UI mounts).
- [ ] Support **multiple named playlists** per profile (Recently Added,
      Bedtime, Roadtrip…). Save current queue as a named playlist;
      load a saved playlist into the queue.
- [ ] Auto-advance through the queue while playing.

**Approach.** New `playlists` + `playlist_videos` tables. Bridge events:
`playlistUpserted`, `playlistRemoved`, `playlistVideosUpdated`. React store
gains `playlists` slice keyed by profile. Player listens for "end of
video" → if queue has a next item, play it.

---

### ★ Auto-playback options [P0]
Per-profile preference for what happens when a video ends in channel-view
playback (i.e. NOT in queue playback):
- [ ] **Repeat** currently-playing video
- [ ] **Sequential** — play next video in the channel
- [ ] **Random** — pick a random video from the channel
- [ ] **Exit** — return to channel view (current behavior)

**Approach.** Per-profile setting (`profile_settings` table or JSON blob
on profile). Default = Exit. Surface as a small selector in the player
controls (gear menu or similar).

---

### ★ Verify favorites filtering actually works [P0]
- [ ] Manually verify: heart a video → switch to Favorites filter →
      only favorites appear. Toggling heart while filter is on should
      update list smoothly (no flicker).
- [ ] Edge case: 0 favorites + Favorites filter on → empty state
      ("No favorites yet — tap the heart on a video").
- [ ] Search should still work while the filter is on.

---

### ★ Refresh channel for missing/new videos [P0]
Current `Sync` button checks for new videos but doesn't re-download videos
that previously failed or were deleted on disk.
- [x] Extend sync to also: (a) requeue any video whose `localFilePath`
      no longer exists on disk, (b) requeue videos in `error` state.
      (`AppState.requeueMissingAndFailed` — see AUDIT_2026-09.md)
- [x] Show count — logged per sync; Settings → Library shows pending /
      failed counts and the last Verify result.

**Approach.** After `ChannelSyncService.fetchVideoList` succeeds, walk
existing videos: stat `localFilePath`, if missing → flip to `.queued`
and `enqueue` via `DownloadService`.

---

### ★ Search tags too [P1]
Right now search only matches `title`. We don't store tags yet.
- [ ] Capture yt-dlp tags during download (`--print %(tags)j`) into a
      new `videos.tags` JSON column (migration 8).
- [ ] React search predicate: match against title + tags.
- [ ] Tag chips on video card (optional, hover-revealed).

---

### ★ Sort videos [P1]
- [ ] Sort modes: **Custom** (current `sort_order`), **Alphabetical**,
      **Date added** (`downloadedAt`), **Duration**, **Most recently
      viewed**.
- [ ] Sort dropdown next to the view-mode toggle on the channel page.
- [ ] Per-profile preference; persists across app launches.

---

### ★ Watch tracking [P0 — blocks several sort modes]
- [ ] New table `profile_watches (profile_id, video_id, last_watched_at,
      watch_count, completed)`. Cleans up on profile/video delete via
      CASCADE.
- [ ] PlayerState updates `last_watched_at` on play, increments
      `watch_count` on play-to-end (not on every scrub).
- [ ] "Continue watching" surface for partially-watched videos. Use
      existing `resumePositionSeconds` — show only videos with progress
      between 5% and 95%.

---

### ★ Hide a video without deleting it [P1]
- [ ] Per-profile-per-video "hidden" flag (new `profile_hidden_videos`
      junction). Hidden videos don't appear in the channel view for
      that profile.
- [ ] Editor mode shows hidden videos with a "Hidden" badge + unhide
      button so parents can manage.
- [ ] "Show hidden" toggle in channel header (editor mode only).

---

### Continue watching rail [P2]
- [ ] On the library, above the channel grid, a horizontal row of
      "Continue watching" cards (videos with `resumePositionSeconds`
      between 5% and 95%, scoped to the active profile).

### Global favorites view [P2]
- [ ] A "Favorites" pseudo-channel pinned at the top of the library
      that aggregates favorited videos across all of the profile's
      assigned channels.

### Background channel sync [P2]
- [x] Re-sync of all source channels on every launch and at local
      midnight while the app is open (`AppDelegate.observeMidnight`,
      `AppState.autoSyncSourceChannels`).
- [ ] Configurable interval.
- [ ] Manual setting: "Auto-sync interval".
- [ ] Visible "Last synced" timestamp on each channel card (we already
      store `lastSyncedAt`).

### Bulk operations in editor [P3]
- [ ] Multi-select videos (shift-click), then: delete / hide / move
      to another channel / add to queue.

### Picture-in-picture [P3]
- [ ] Toggle PiP from the player controls. macOS supports native PiP
      for `AVPlayer` via `AVPictureInPictureController`.

---

## Bugs & Polish

- [ ] **Modal exits still pop.** Only the profile picker and PIN entry
      use `MountWithExit`. Every other modal (delete confirm, add
      videos, add channel, edit profile, banner upload picker) unmounts
      instantly. Wrap them all in `MountWithExit` or build a generic
      `<Modal show={...}>` wrapper.
- [ ] **No active-download chip in library top bar.** Got dropped in
      the navigation refactor. Bring it back (small, top-bar-right next
      to the profile chip), so viewers can see "still downloading…"
      without entering editor mode.
- [ ] **Search input loses focus on render.** When typing fast, store
      updates can re-mount the search input region. Add `key={channel.id}`
      to the input or move the search state up a level.
- [ ] **Player doesn't remember volume across sessions.** Persist
      `player.volume` to localStorage / UserDefaults, restore on launch.
- [ ] **Reduce-motion not respected.** `NSWorkspace.shouldReduceMotion`
      is checked in one place (player controls); audit React side too —
      respect `prefers-reduced-motion`.
- [x] **Channel file cleanup on delete.** Channel folder goes to the
      Trash; video delete removes file + thumbnail + `.part` leftovers.
      (The confirm dialogs already promised this.)
- [x] **Download queue never clears completed entries.** Finished
      entries are trimmed to the most recent 100.
- [ ] **Empty-search state.** When search returns zero results, the
      "Clear Search" button is there but the messaging could be
      friendlier.
- [x] **Channel banner upload doesn't show error feedback** — now a
      toast via the `toast` bridge event.

---

## Accessibility

- [ ] **Focus trap in modals.** Currently focus can tab out of a modal
      and onto background content. Trap Tab/Shift-Tab within the modal
      while it's open.
- [ ] **Restore focus on modal close** to the element that opened it.
- [ ] **Keyboard nav for the picker.** Arrow keys to move between
      profile tiles, Enter to pick, Tab to cycle through the corner
      Editor/Settings buttons.
- [ ] **ARIA roles audit.** Modals have `role="dialog"` already; verify
      `aria-labelledby` points at the title `h2` in each.
- [ ] **Screen reader friendliness** of decorative SVGs — most need
      `aria-hidden="true"`.

---

## Tech debt (the architecture review I keep deferring)

### Swift 6 strict concurrency [P1]
- [ ] Flip `Package.swift` from `.v5` to `.v6`. Expected ~90 errors
      across:
      - `AppLogger` (static `FileHandle`, `URL`, `ISO8601DateFormatter`
        as nonisolated globals)
      - `PINService` (static `defaults`, `failedAttempts`, `lockoutUntil`)
      - `ShellRunner` (captured mutable `buffer` Data in @Sendable
        closures, local `processBuffer()` capture)
      - Shared `ISO8601DateFormatter` constants throughout
- [ ] Fix categorically: wrap mutable state in actors or
      `nonisolated(unsafe)` (with justification comments); replace
      buffer mutation with a lock-protected `Box` class.

### Bridge typing [P2]
- [ ] Replace remaining `[String: Any]` payloads in `LocalTubeBridge`
      with concrete `Codable` payload structs per message type. Decode
      directly instead of `as?` casting.
- [ ] Generate or hand-mirror TS types from Swift to keep one source
      of truth for the wire format.

### Tests [P1]
- [ ] **Zero unit tests currently exist.** Highest-value places to add
      coverage:
      - `DatabaseMigrations` — round-trip migrations against an
        in-memory DB
      - `LibraryStore` CRUD — channels, videos, profiles, favorites
      - `ChannelSyncService.fetchVideoList` — mock yt-dlp output
      - React reducer (`store.ts applyBridgeEvent`) — all diff events
- [ ] Smoke test in CI: build the .app, launch it headless, verify
      window opens.

### Security follow-ups from the original code review
- [ ] **C3** — Homebrew/yt-dlp install path still downloads + pipes
      `curl | bash` (in `DependencyService.installMissing`). Either
      bundle binaries OR verify a SHA-256 against a hardcoded hash
      before executing.
- [x] **M3** — `ShellRunner.stream` has an inactivity watchdog
      (downloads: 10 min); `run` now kills the process on timeout and no
      longer deadlocks on >64 KB of output.
- [x] **H3** — `AppDelegate` uses true optionals + guards.

### Logging
- [ ] **AppLogger** lines are uncategorised. Add a category param
      (`info("download", "started: ...")`) so we can filter `localtube.log`
      by area when debugging.
- [ ] **User-visible logs.** Surface the last 100 log lines in a
      hidden Settings → Diagnostics panel for support.

### Build / release
- [ ] **`Scripts/setup-sparkle.sh`** still has UTF-8 ellipsis chars
      that bash 3.2 chokes on (release.sh got fixed, this didn't).
- [ ] **Bundle size.** Adding `@phosphor-icons/react` pushed the JS
      bundle from ~300 kB to ~490 kB. Consider switching to per-icon
      imports we already use individually so tree-shaking actually
      works, or use the `@phosphor-icons/web` font-icon variant which
      is smaller.

---

## Library maintenance (added Sept 2026 — see AUDIT_2026-09.md)

- [ ] Offer to clean up leftover `.part` / unreferenced files from the
      Verify result (currently reported only).
- [ ] Import unreferenced `.mp4` files found in a channel folder as
      videos (needs the YouTube id — parse it from a `.info.json` if we
      start writing one with `--write-info-json`).
- [ ] Relocation progress per file (currently per channel).
- [ ] Unit tests for `LibraryPaths` and `DatabaseService.rewritePathPrefix`.

## Notes on approach

- **Migrations are append-only** — never edit an existing one. We're
  at 7; the next one is 8.
- **All bridge mutations** should emit a typed diff event (not
  `emitStateUpdate`) per the pattern in `BridgeEventEmitter`.
- **State changes for the active profile** must be keyed by
  `profileId` in the DB and in the React store map. Never assume
  "the current profile" at write time — accept the id as a param so
  multi-window / future scenarios stay correct.
- **Animations** — favor CSS transitions or scroll-driven CSS where
  available; avoid driving per-frame style mutations from JS scroll
  handlers (we learned this the hard way with the header parallax).
