# Playlist System — Design Plan

Pre-implementation planning document. Captures intent, mental model,
data schema, bridge protocol, UI design, edge cases, phasing, and
**open questions** that need to be answered before code is written.

> **Permission model (clarified)**: playlists are **curated by adults
> only**. Editor mode is the only place to add/remove/reorder/clear or
> create/rename/delete playlists. Viewer mode is **read-only
> consumption** — kids see their playlists, choose which one to play,
> tap items to play them, and watch them auto-advance. They cannot
> modify contents.
>
> This is the single most important constraint and shapes every UI
> decision below.

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

The UI split is now driven entirely by the permission model:
**curate in editor mode, consume in viewer mode**.

### 4.1 Editor mode — quick add from a video card
- "+ Add to playlist" icon in the **top-right corner** of every ready
  video card (matches the favorite heart top-left; symmetric corners)
- **Visible only in editor mode** (no add button for kids — they can't
  add to their own queue)
- **Click** opens a compact popover:
  1. **Target profile** — small avatar row of all profiles. Pick one.
     Last-used profile is remembered and pre-selected.
  2. **Target playlist** — list of that profile's playlists (including
     their default Up Next). Pick one.
  3. "+ New playlist" at the bottom of the playlist list
- After the add, a toast confirms ("Added to Sarah's Up Next")

### 4.2 Editor mode — Playlists tab (full management surface)
A new fourth tab in `EditorShell` next to Channels / Profiles /
Settings. Layout matches the Profiles tab so it feels familiar:
- **Left sidebar**: profile list (same as Profiles tab). Click a
  profile to view their playlists.
- **Middle column**: the selected profile's playlists — sortable list,
  rename inline, delete, "+ New playlist", set-active toggle.
- **Right column**: the selected playlist's videos — drag to reorder,
  remove individual videos, clear playlist with confirm, per-profile
  auto-playback mode selector at the top.

This is where parents do the bulk of curation. The card popover (4.1)
is the quick-add path for when they're browsing a channel.

### 4.3 Viewer mode — tray (consume only, read-only)
A slide-out tray on the right side, **available to kids but read-
only**. They use it to play through their curated content.
- Width: 360px, full-height
- Toggle: persistent icon top-right of the app top bar, with a count
  badge when > 0
- Animation: transform: translateX, 240ms ease-out
- No backdrop (feels like a side panel, not a modal)

Tray contents in viewer mode:
1. **Header** — active playlist name; chevron opens a switcher
   listing this profile's playlists. Tapping a playlist makes it
   active (changes what plays next). No "+ New playlist", no rename,
   no delete.
2. **Body** — scrollable list of videos. Thumbnail + title + duration.
   Now-playing indicator on the current item. **Tap a video** to jump
   to it. **No drag handles, no remove buttons, no clear button.**
3. **Empty state** — friendly message ("Your queue is empty. Ask a
   grown-up to add some videos!"). No add-to-queue affordance.

### 4.4 Auto-playback options (parent setting, takes effect in viewer)
- **Configured by parents** in the Editor > Playlists tab, on each
  profile (alongside their playlists)
- Four mutually-exclusive options for what happens at end-of-video
  during **channel-initiated** playback (not queue playback):
  - ⟳ Repeat — replay this video
  - ⇉ Sequential — next video in the channel
  - ⤮ Random — random video from this channel
  - ⤴ Exit — return to channel view (current default)
- Stored on `profiles.auto_playback_mode`; applied during the viewer
  session

When playing from a **queue**, auto-playback mode is ignored — the
queue's next item plays. Only applies to channel-initiated playback.

### 4.5 Drag-to-reorder (editor mode only)
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
| Adding to playlist in viewer mode | The "+ Add to playlist" button on cards is HIDDEN in viewer mode (kids can't add to their own queue). It only appears in editor mode. |
| Editor mode adds requiring profile context | The card popover (4.1) forces an explicit profile + playlist pick before adding |
| Kid switches active playlist mid-watch | Allowed — current playback continues, but the next end-of-video advances inside the newly-active playlist if queue-sourced |
| Renaming a playlist mid-edit while another tab/window is open | Last-write-wins; bridge event re-syncs everyone |

---

## 7. Phasing

To avoid a 3000-line PR, ship in slices that each leave the app working.

### Phase 1 — Schema + Up Next + viewer-mode read-only tray *(MVP)*
- Migration 8 (tables + auto-create Up Next per profile, including
  retroactively for existing profiles)
- DatabaseService CRUD
- LibraryStore.playlists + .playlistVideos
- AppState forwarders
- Bridge: events + handlers for `createPlaylist`, `addToPlaylist`,
  `removeFromPlaylist`, `clearPlaylist`, `reorderPlaylist`,
  `setActivePlaylist`
- React store reducer cases
- **Read-only tray in viewer mode** (slide-out, shows active playlist
  contents, no edit affordances)
- Tray toggle in top bar
- (Editor side stubbed — playlists exist but can't be edited yet)

**At this point**: viewer mode shows an empty Up Next tray with a
"ask a grown-up to add videos" empty state. Foundation is in place.

### Phase 2 — Editor-mode quick add from cards
- "+ Add to playlist" icon on video cards (editor mode only)
- Card popover: profile picker → playlist picker → toast confirm
- Last-used target remembered per session
- Parents can now populate any profile's Up Next from a channel page

**At this point**: parents can add videos; kids can see them in the
tray and tap to play. No auto-advance yet, no named playlists, no
reordering.

### Phase 3 — Editor > Playlists tab
- New fourth tab in `EditorShell` (Channels | Profiles | Settings →
  + Playlists)
- Three-column layout: profile sidebar → playlists list → videos in
  selected playlist
- Create / rename / delete playlists (not the system Up Next)
- Reorder videos in a playlist (drag in editor)
- Remove videos, clear playlist with confirm
- Auto-playback mode selector at the top of each profile's section

**At this point**: parents have full curation. Kids still consume.

### Phase 4 — Auto-advance player
- PlayerState gains `playSource: ChannelPlay | QueuePlay`
- Tray item tap (viewer) → play, set playSource = QueuePlay
- On end-of-video while in QueuePlay → advance to next in playlist
- On end-of-video while in ChannelPlay → apply
  `profile.auto_playback_mode`
- Now-playing indicator in tray follows current item

**At this point**: the actual playback flow works end-to-end.

### Phase 5 — Polish
- Switching active playlist in viewer (chevron in tray header)
- Empty states (empty playlist, no playlists yet for profile)
- Toast notifications on add-to-playlist (editor)
- "Just added" highlight animation on the targeted playlist
- Keyboard shortcuts (Cmd+Q to toggle tray)
- `MountWithExit` on the tray for smooth slide-out

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

Reduced list — the permission-model clarification answered some of the
prior questions.

1. **"Up Next" naming** — happy with that, or do you want "My Queue" /
   "Now Playing" / something else?
2. **Tray toggle location** — top-right of the library/channel top bar,
   always visible, with a count badge. Acceptable?
3. **Can kids switch active playlist in viewer mode?** I'd say yes
   (chevron in tray header opens a profile-scoped picker — read-only,
   no editing). Confirm?
4. **Drag-to-reorder fidelity** (editor side only now) — HTML5 DnD vs
   `@dnd-kit/sortable` (~30kB)? HTML5 DnD is fine to start; reach for
   the library if it feels bad.
5. **Queue exhausted in viewer playback** — exit the player (my
   default), loop the queue, or replay the last item?
6. **Tray open/closed state across launches** — persist or always
   start closed? My instinct: always start closed in viewer mode (kids
   don't need it always-open); editor mode could remember.
7. **Quick-add icon on cards in editor mode** — confirm the icon-only
   approach (popover on click). Alternative: dragging a video to the
   tray could add it, if the tray is open. More fancy. Probably
   overkill for v1.
