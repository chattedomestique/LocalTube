# Playlist System — Design Plan

Pre-implementation planning document. Captures intent, mental model,
data schema, bridge protocol, UI design, edge cases, phasing, and
**open questions** that need to be answered before code is written.

---

## 1. Mental Model

I considered three options. Each implies a different UX.

### Option A — Queue + Playlists are distinct (YouTube web pattern)
- Queue is transient ("Up next")
- Playlists are persistent named lists
- You can "play a playlist" which loads it into the queue
- "Save queue as playlist" exists

**Pro**: clear separation; matches what most users know from YouTube.
**Con**: two concepts to learn. Adds a "save queue" step. Kids find it
confusing.

### Option B — Just one queue per profile, no named playlists
**Pro**: simplest.
**Con**: doesn't satisfy your "multiple playlists" requirement.

### Option C — Playlists ARE the unit; one is always "active" *(RECOMMENDED)*
- Every profile has 1..N playlists
- Exactly one is "active" at any time — that's what plays + what the
  slide-out tray shows
- Every profile starts with a default playlist called **"Up Next"**
  (system-owned, can be cleared but not renamed or deleted)
- New named playlists can be created (Bedtime, Roadtrip, etc.) and
  any of them can be made active
- "Add to queue" = "add to active playlist"
- "Add to..." picker = adds to any chosen playlist (with "+ New
  playlist" at the bottom)

**Why C**: collapses Queue and Playlists into one concept. The active
playlist *is* the queue. Kids only ever need to think about "what's
playing next" — power users (parents) can build out named lists.

**Decision: going with C unless you push back.**

---

## 2. Data Schema (migration 8)

```sql
CREATE TABLE playlists (
    id TEXT PRIMARY KEY NOT NULL,
    profile_id TEXT NOT NULL,
    name TEXT NOT NULL,
    sort_order INTEGER NOT NULL DEFAULT 0,
    created_at REAL NOT NULL,
    -- system playlist (1 = "Up Next", auto-created per profile, can't
    -- be renamed or deleted, but can be cleared)
    is_system INTEGER NOT NULL DEFAULT 0,
    FOREIGN KEY (profile_id) REFERENCES profiles(id) ON DELETE CASCADE
);

CREATE INDEX idx_playlists_profile ON playlists(profile_id);

CREATE TABLE playlist_videos (
    playlist_id TEXT NOT NULL,
    video_id TEXT NOT NULL,
    sort_order INTEGER NOT NULL,
    added_at REAL NOT NULL,
    PRIMARY KEY (playlist_id, video_id),
    FOREIGN KEY (playlist_id) REFERENCES playlists(id) ON DELETE CASCADE,
    FOREIGN KEY (video_id) REFERENCES videos(id) ON DELETE CASCADE
);

CREATE INDEX idx_playlist_videos_playlist ON playlist_videos(playlist_id);

-- Per-profile preferences. Adding two columns rather than a JSON blob
-- because we want them queryable and Swift-typed.
ALTER TABLE profiles ADD COLUMN active_playlist_id TEXT;
ALTER TABLE profiles ADD COLUMN auto_playback_mode TEXT;
-- auto_playback_mode ∈ { 'repeat', 'sequential', 'random', 'exit' };
-- nil → default 'exit'
```

**Migration also auto-creates the "Up Next" system playlist for every
existing profile** and sets it as their active_playlist_id.

**Notes**:
- Same video can appear multiple times in a playlist if the user adds it
  twice. Most apps allow this. We will too.
- Same video can appear in multiple playlists (it's not consumed when
  added).
- Deleting a video CASCADEs out of every playlist. Empty playlists are
  fine.
- Deleting a profile CASCADEs its playlists.

---

## 3. Bridge Protocol

### State (carried in `bridgePayload()`)
```ts
playlists: Record<profileId, Playlist[]>
playlistVideos: Record<playlistId, string[]>  // ordered video ids
// activePlaylistId + autoPlaybackMode go on the Profile object itself
```

### Diff events (Swift → JS)
- `playlistUpserted` — `{ profileId, playlist }`
- `playlistRemoved` — `{ profileId, playlistId }`
- `playlistVideosUpdated` — `{ playlistId, videoIds }`  *(canonical order)*
- `activePlaylistChanged` — `{ profileId, activePlaylistId }`
- `autoPlaybackModeChanged` — `{ profileId, mode }`

### Commands (JS → Swift)
- `createPlaylist` — `{ profileId, name }` → returns id via upsert event
- `renamePlaylist` — `{ playlistId, name }` (rejected if `is_system`)
- `deletePlaylist` — `{ playlistId }` (rejected if `is_system`)
- `addToPlaylist` — `{ playlistId, videoId, position? }`
- `removeFromPlaylist` — `{ playlistId, videoId }`
- `reorderPlaylist` — `{ playlistId, videoIds }` (full canonical order
  after the drag — server replaces, no diff math needed)
- `clearPlaylist` — `{ playlistId }`  *(works on `is_system` too)*
- `setActivePlaylist` — `{ profileId, playlistId }`
- `setAutoPlaybackMode` — `{ profileId, mode }`

All commands emit the matching diff event for React to apply.

---

## 4. UI

### 4.1 Add-to-card affordance
- New icon button in the **top-right corner** of every ready video card
- Default: small "+" inside a circular glass background, visible only on
  card hover (mirrors the heart icon's behaviour, but mirrored to the
  opposite corner)
- **Single click** → add to the active playlist + show a small toast
  ("Added to Up Next")
- **Click the chevron** (next to the +) → opens a "Add to…" menu:
  - list of profile's playlists, each clickable
  - "+ New playlist" at the bottom

Heart sits top-left, add-to-queue sits top-right — symmetric, never
overlap.

### 4.2 Queue tray (slide-out from right)
- Width: 360px, full-height
- Toggle: persistent icon top-right of the app top bar; badge shows
  count when > 0
- Animation: slide in/out (transform: translateX), 240ms ease-out
- Backdrop: optional dim overlay that closes on click (mobile-style),
  configurable — start without it so the tray feels like a side panel
  not a modal

Tray structure (top to bottom):
1. **Header** — `Up Next` (or active playlist name) with a dropdown
   chevron. Clicking opens the playlist picker
2. **Playlist switcher** (expandable) — list of playlists with
   active highlight; "+ New playlist" at the bottom
3. **Body** — scrollable list of videos
   - Thumbnail (small), title (line-clamp 2), duration
   - Now-playing indicator on the active item
   - Drag handle on the left for reordering
   - Trash icon on the right to remove
4. **Footer** — "Clear queue" button (destructive style, opens
   confirmation modal)

### 4.3 Auto-playback options
- Lives in the **player overlay** controls, behind a gear-style menu
  (next to the loop button we already have)
- Four mutually-exclusive options:
  - ⟳ Repeat — replay this video
  - ⇉ Sequential — next video in the channel
  - ⤮ Random — random video from this channel
  - ⤴ Exit — return to channel view (current default)
- Per-profile, persisted via `setAutoPlaybackMode`

Note: when playing from a **queue**, auto-playback mode is ignored —
the queue's next item plays. Only applies to channel-initiated playback.

### 4.4 Drag-to-reorder
- HTML5 drag-and-drop API; `draggable="true"` on each row
- Visible drop indicator (a thin accent line between rows)
- On drop, dispatch `reorderPlaylist` with the full new order
- Keyboard: focus a row, ↑/↓ moves it (parallel affordance for ten-foot
  remote + accessibility)

---

## 5. Player integration

`PlayerState` gains:
- `playSource: ChannelPlay(channelId) | QueuePlay(playlistId)`
- On `itemDidPlayToEndTime`:
  - If `playSource = QueuePlay`: advance to next video in the playlist
    (queue plays through to the end, then stops or exits player —
    parent's choice via auto-playback when queue is exhausted? Let's
    keep it simple: when queue ends, exit player)
  - If `playSource = ChannelPlay`: apply `autoPlaybackMode`

"Now playing" indicator in the tray follows `playSource` + the
playlist's current video pointer.

---

## 6. Edge Cases

| Case | Handling |
|---|---|
| Profile created with no Up Next playlist | Migration ensures every existing profile gets one; new profiles get one created at `addProfile` time |
| Delete the only playlist (Up Next is system, can't delete) | Can't happen — Up Next can't be deleted |
| Deleting the currently-active named playlist | `active_playlist_id` falls back to Up Next |
| Video gets deleted | CASCADE removes from playlists; UI updates via `playlistVideosUpdated` event for affected playlists |
| Channel a video belongs to gets deleted | Same — CASCADE through channel → video → playlist |
| Video in playlist becomes un-downloaded (`error` state) | Show with greyed-out style + "unavailable" badge; don't auto-skip yet (parent might retry) |
| User switches profile mid-playback | Stop playback. Active playlist is per-profile, so new profile sees their own playlist |
| Duplicate video added | Allowed; appears twice in the list |
| Queue with 1 video, that video ends | Stops; exits player (queue exhausted) |
| Adding to playlist while no profile active (editor mode) | The "+ Add to queue" button on a card is HIDDEN in editor mode (it's a viewer-mode interaction, like the favorites heart) |
| Renaming a playlist mid-edit while another tab/window is open | Last-write-wins; bridge event re-syncs everyone |

---

## 7. Phasing

To avoid a 3000-line PR, ship in slices that each leave the app working:

### Phase 1 — Schema + Up Next + Add-to-queue + Tray *(MVP)*
- Migration 8 (tables + auto-create Up Next per profile)
- DatabaseService CRUD
- LibraryStore.playlists + .playlistVideos
- AppState forwarders
- Bridge: events + handlers for `createPlaylist`, `addToPlaylist`,
  `removeFromPlaylist`, `clearPlaylist`, `reorderPlaylist`,
  `setActivePlaylist`
- React store reducer cases
- Tray component (single-playlist view; no switcher yet)
- "+ Add to queue" icon on VideoCard
- Tray toggle in top bar

**At this point: kids can build a queue and reorder it. No named
playlists yet, no auto-advance yet.**

### Phase 2 — Auto-advance player
- PlayerState gains `playSource`
- Tray item click → play (advance pointer)
- On end-of-video while in queue mode → next queue item
- Tray "now playing" highlight

### Phase 3 — Multiple named playlists
- Playlist switcher in tray header
- Create / rename / delete UI
- Add-to-card chevron menu ("Add to…")

### Phase 4 — Auto-playback modes
- `auto_playback_mode` column wired up
- Player gear menu with 4 mode options
- On end-of-video in `ChannelPlay` mode → apply chosen behaviour

### Phase 5 — Polish
- Empty states (empty playlist, no playlists)
- Toast notifications on add-to-queue
- "Just added" highlight animation
- Keyboard shortcuts (Cmd+Q to toggle tray, ↑/↓ to reorder selected)

---

## 8. Ethos check

- ✅ **Offline-first** — all DB-backed
- ✅ **Per-profile isolation** — playlist owned by `profile_id`
- ✅ **Kid-empowering** — viewer mode users can fully manage their own
  queue/playlists; doesn't require parent intervention
- ✅ **Silky animations** — slide-in tray, smooth row reorder, no
  popping
- ✅ **Clean hierarchy** — tray is auxiliary, doesn't take over the
  screen; primary content stays primary
- ✅ **"Nothing fancy"** — Option C collapses two concepts (queue +
  playlists) into one
- ✅ **Bridge diff events** — never emit full state on a playlist
  mutation
- ✅ **Migration discipline** — append-only, idempotent system-playlist
  seeding

One concern: **complexity creep.** Even Option C is the most we've
added in one feature. Phase 1 alone touches ~10 files. The phasing
above is the mitigation.

---

## 9. Best-practices review

- **Naming**: `playlists` / `playlist_videos` mirror our existing
  `profiles` / `profile_channels` / `profile_favorites` pattern.
  Consistent.
- **Sort order**: full-list replacement on reorder (not delta-based).
  Simpler and matches what we did for `setProfileChannels`.
- **Drag-and-drop**: HTML5 DnD has rough edges but is dependency-free
  and meets the bar; if it feels bad we can swap to a small library
  later without touching the data model.
- **React perf**: tray re-render when playlistVideos updates — memoize
  list rows by video id like we do for VideoCard.
- **Accessibility**: keyboard reorder + ARIA `aria-grabbed` for
  draggable items + `role="listbox"` for the playlist.
- **State source of truth**: Swift is canonical; React state derives
  from bridge events. Don't introduce local-only UI state for playlist
  contents.

---

## 10. Pre-QA: failure modes I want to test

Before shipping Phase 1, manually run through:

1. Fresh install, create profile, see Up Next auto-created
2. Add 5 videos to queue; reorder via drag; remove middle item;
   clear queue with confirm dialog
3. Add a video; switch profile; verify queue is the new profile's
   (empty) queue, not the prior one
4. Delete a video that's in the queue; verify it disappears from queue
   smoothly
5. Delete the channel a queued video belongs to; verify CASCADE
6. Open tray, scroll a long queue (50+ items); verify no jank
7. Tray exit animation works (no pop on close)
8. App relaunch: queue persists exactly as left

---

## 11. Open questions for you

These materially change implementation. I'd rather decide them with you
than assume.

1. **"Up Next" naming** — happy with that, or do you want "My Queue" /
   "Now Playing" / something else?
2. **Tray toggle location** — top-right of the library/channel top bar
   feels right to me. Always visible, with a count badge. Acceptable?
3. **Editor mode**: do parents ever need to create/edit a playlist
   directly for a kid's profile, or is "switch to the kid's profile to
   curate" sufficient? I'd default to the latter — much simpler — but
   if you envision parents pre-loading "Bedtime" for the kids that's
   different.
4. **Adding to a specific (non-active) playlist** — chevron-menu on the
   card seems right but it's another bit of complexity on a small card.
   Alternative: only add-to-active from cards, manage everything else
   from the tray. Less powerful but cleaner. **Preference?**
5. **Drag-to-reorder fidelity** — HTML5 DnD is fine for v1; if you
   want pixel-perfect reorder UX from day one, I should reach for a
   small library (`@dnd-kit/sortable` is the modern standard, ~30kb).
   The bundle is already 490kB so a 30kB addition isn't crazy.
6. **When the queue runs out** — exit the player (my default), or loop
   the queue, or replay the last item?
7. **Should the tray remember its open/closed state across app
   launches**, or always start closed?
