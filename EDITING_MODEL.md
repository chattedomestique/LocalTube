# Editing Model — Inline Edit Layers + Admin Mode

A redesign of how editing works in LocalTube. Replaces the current
"enter editor mode → navigate to a separate Editor screen" pattern with
**inline edit layers on every page that has editable content**, plus a
separate **Admin mode** for global operations.

This document supersedes the parts of `PLAYLISTS_PLAN.md` that assumed
the existing editor-mode model. Playlists fit cleanly into this new
model — see §7.

---

## 1. The two modes

| Mode | Trigger | Scope | Exit |
|---|---|---|---|
| **Edit layer** (per page) | PIN, from an "Edit" button on any editable page | Local to the current page; manipulates **the active profile's view** of content | "Exit Edit Mode" button on the page; no timer |
| **Admin mode** (global) | PIN, from picker OR from inside an edit layer | Library-wide, cross-profile, system config | "Exit Admin" button; no timer |

**Both are PIN-gated.** PIN once per *editing session*; once authorized,
you can move between edit layers and admin without re-PIN. Hard exit
of either resets the session.

**No auto-lock timer in either.** The current 10-minute idle timer is
removed. Exit is always an explicit click.

---

## 2. Why this is better

- **Context preservation**: edits happen on the page they apply to.
  Reorder Sarah's channels while looking at Sarah's channel grid.
- **Reduced cognitive load**: one mental model per page. No flipping
  between "viewer" and "editor" mental worlds.
- **Faster workflows**: tap edit, change, exit. No tab-switching.
- **Better preview**: parent sees exactly what the kid sees while
  editing — same layout, same components, edit affordances overlaid.
- **Single-purpose Admin**: admin only houses operations that are
  genuinely cross-profile / global. Smaller surface area, easier to
  reason about.

---

## 3. What lives where

### Edit layer responsibilities (per-profile, per-page)

| Page | Edit-layer operations |
|---|---|
| Library — **Channels** tab | Reorder channels · Hide channels from this profile · Remove channels from this profile |
| Library — **Playlists** tab | Reorder playlists · Rename · Delete · Create new playlist |
| Library — **Feed** tab | (Read-only feed; no edit layer) |
| Channel page (videos list) | Reorder videos · Hide videos · Toggle favorites in bulk · Add multiple to playlist |
| Playlist page | Reorder videos in this playlist · Remove videos |

### Admin mode responsibilities (global)

| Surface | Operations |
|---|---|
| Channels (global) | Create channels · Sync source channels · Delete channels (system-wide) · Edit channel metadata (name, emoji, banner) |
| Profiles | Create / edit / delete profiles · Assign channels to profiles · Change PIN · Manage avatars |
| Settings | Download folder · Dependencies · Auto-lock (now removed) · Other system prefs |

Notice the split: edit layer is about **a profile's view** of content.
Admin is about **the content itself + the system**. A parent in edit
layer says "Sarah shouldn't see Cocomelon"; in admin they say "Delete
Cocomelon from the entire library."

---

## 4. UX rules for the edit layer

While in edit layer on a page:

1. **Navigation into deeper layers is blocked.** Channel cards don't
   open the channel. Video cards don't open the player. Playlist
   tiles don't open the playlist. The user must exit edit mode first.
2. **Lateral navigation (between top-level tabs) is allowed.** Going
   from Channels → Playlists → Feed within the Library stays inside
   the edit session.
3. **The page chrome makes the mode visible.** A persistent banner /
   chip / outline indicates "Editing Sarah's channels" — clear and
   constant. Plus a sticky "Exit Edit Mode" button.
4. **All edit affordances reveal at once.** Reorder handles + delete
   buttons + hide toggles appear together. Not hover-revealed; this
   isn't subtle, it's a mode.
5. **Mutations are immediate.** No "save changes" button. Every change
   commits as it happens (we already work this way for everything
   else). The "Exit Edit Mode" button just leaves the mode — there's
   nothing to confirm because everything is already saved.

> Note: the original ask mentioned "save/cancel". I'm proposing
> **immediate commits** instead because it matches the rest of the app
> (channels, profiles, favorites all commit on action). A save/cancel
> flow would be inconsistent and add a stale-state problem. **If you
> want save/cancel, say so** and I'll add a draft state with rollback.

---

## 5. Per-page anatomy of edit layer

### Library top bar in edit layer

```
[ Profile chip ]  ⚙ Editing Sarah's library         [ Admin ]  [ Exit Edit Mode ]
        ├ Channels    Playlists    Feed
```

- Profile chip stays so context is obvious
- Center label tells the parent who they're editing
- "Admin" button = jump to global admin (PIN session carries over)
- "Exit Edit Mode" returns to plain viewer for that profile

### Library Channels tab in edit layer

- Channel cards gain a left-edge **drag handle**
- Top-right corner shows a small **× (remove from profile)** button
- A toggle on each card: 👁 visible / 👁‍🗨 hidden
- Tap on card does **not** navigate; instead toggles selection or shows
  edit context (no-op is also acceptable)

### Channel page in edit layer

- Top bar gains the same "Editing Sarah's view of …" label
- Each video card: drag handle, hide toggle, remove-from-playlist
  bulk options
- Tapping a video does **not** open the player

### Playlists tab / playlist detail in edit layer

- Similar: drag handles, rename inline, delete, add-new-playlist
- Inside a playlist, drag video rows, remove via × button
- Clear playlist button at the bottom (with confirmation)

---

## 6. Tabs on the Library

Renaming the current "channels grid" view to **Library**, and giving
it three tabs:

### Channels (default)
- Today's behaviour: grid of channel cards
- Plus sort dropdown: **Name** / **Most watched** / **Recently
  updated**
- "Most watched" needs the watch tracking system (TODO P0)
- "Recently updated" uses `channel.lastSyncedAt` + max video
  `downloadedAt`

### Playlists
- Grid of playlist tiles. Each tile shows: playlist name, item count,
  thumbnail collage (2x2 of the first 4 videos), accent color matching
  active state
- Tap → playlist detail page (videos in order, with "play all")
- In edit layer: drag-reorder tiles, rename inline, delete with
  confirm, "+ New playlist" tile

### Feed
- All videos from all the profile's visible channels, sorted by
  **newest downloaded first**
- Effectively a chronological cross-channel river
- Each row: small channel emoji/avatar + thumbnail + title + "Added 2
  days ago"
- No edit layer (the feed is derived; you edit channels/videos at
  source)

---

## 7. Playlists in the new model

The plan from `PLAYLISTS_PLAN.md` mostly stays, with these changes:

### Single kind of playlist — profile-scoped
- **No "channel-specific playlists" as a separate concept.** A
  playlist that happens to only contain Cocomelon videos is just a
  profile playlist the parent named "Cocomelon Favorites." The data
  model stays flat (one `playlists` table, no `scope_channel_id`).
- Channel pages can still show "playlists containing this channel's
  videos" as a passive info chip if useful, but it's a query, not a
  data model.

This avoids the convolution you flagged.

### Editing model
- **Adults still curate, kids consume** — unchanged constraint
- BUT: curation happens *inline in the edit layer*, not in a separate
  Admin > Playlists tab
- The Library > Playlists tab is the primary management surface,
  edited via the page's edit layer
- The card-popover quick-add from a channel page also moves into the
  edit layer (was going to be editor-mode-only; now it's edit-layer-
  only)

### Queue tray
- The slide-out tray is still the kid's primary view of "what's
  playing next"
- Read-only in viewer (consume)
- In edit layer: the tray gains drag handles + remove buttons
- The tray is always profile-scoped (per active profile)

---

## 8. Renames

| Old | New |
|---|---|
| `appMode = .editor` | `appMode = .admin` (or stays `.editor`, just renamed in UI; less code churn) |
| "Editor Mode" UI label | "Admin Mode" |
| `EditorShell` | `AdminShell` |
| Auto-lock timer in editor | **REMOVED** entirely |
| `requestEditorMode` bridge cmd | `requestAdminMode` (or stays for compat with `EditMode` as new addition) |
| Existing Editor screen with tabs | Becomes Admin (Channels global / Profiles / Settings) — narrower scope |

A new state added alongside:
- `isEditing: Bool` — global flag, set after edit-layer PIN
- Maybe `editScope: ProfileId?` — which profile's view we're editing
- Bridge command `enterEditLayer(profileId:)` and `exitEditLayer`

The two states are independent: you can be in `admin` mode and not
editing-any-profile-view. You can be editing-a-profile-view and not
in admin. The "Admin" button inside edit layer flips you to admin
without re-PIN.

---

## 9. PIN session

- One PIN attempt unlocks an *edit session*
- During the session, `isEditing` can be toggled freely without re-PIN
- During the session, `appMode` can flip to `admin` without re-PIN
- Session ends on:
  - Explicit "Exit Edit Mode" / "Exit Admin" AND the other is not
    active
  - Profile switch (going back to picker)
  - App relaunch
- **No timer.** Per your request.

In practice: parent PINs once, edits Sarah's channels, jumps to admin
to add a new channel, exits admin → back in edit layer for Sarah, exits
edit → back to viewer. One PIN entry.

---

## 10. Implementation phasing

This is a big shift. To avoid landing 2000 lines at once, I'd phase it
like this — each phase leaves the app in a working state.

### Phase 0 — Foundation rename
- Rename "Editor" → "Admin" in UI everywhere
- Rename `EditorShell` → `AdminShell` (or alias)
- **Remove the auto-lock timer** entirely (small change, big UX win)
- Picker buttons relabel
- No new behaviour yet — pure rename + timer removal

### Phase 1 — Edit layer scaffold + Library Channels editing
- New `isEditing` state (bridge: command + event)
- Library top bar gains "Edit" button (PIN-gated → sets isEditing)
- "Exit Edit Mode" sticky button
- Channel cards in edit layer: drag-reorder handles, hide toggle,
  remove-from-profile ×
- Channel card click blocked while editing
- Visible "Editing Sarah's library" banner

### Phase 2 — Library tabs (Channels | Playlists | Feed)
- Tab nav on Library
- Channels tab content = current grid
- Playlists tab: read-only grid initially (just shows playlists with
  thumbnail collage + count, tap to drill in)
- Feed tab: chronological video river
- Sort dropdown on Channels tab (Name / Recently updated; "Most
  watched" stubbed until watch tracking ships)

### Phase 3 — Playlist data model + viewer tray (the old "Phase 1" from PLAYLISTS_PLAN.md)
- Migration 8 (playlists, playlist_videos)
- Per-profile Up Next auto-create
- LibraryStore CRUD
- Bridge events + commands
- Slide-out tray on right side (read-only in viewer)

### Phase 4 — Channel page edit layer
- Edit button on Channel page top bar
- Drag-reorder videos, hide toggle, add-to-playlist quick action
- Player navigation blocked while editing

### Phase 5 — Playlist editing in edit layer
- Library Playlists tab gains edit layer (drag, rename, delete)
- Playlist detail page exists, has its own edit layer
- Quick-add from video card → playlist picker popover (edit-layer only)

### Phase 6 — Auto-advance + auto-playback modes
- PlayerState `playSource`
- Queue auto-advance
- Per-profile auto-playback mode (configured in admin? in edit layer?
  — open question, see §11)

### Phase 7 — Watch tracking + viewtime sort
- `profile_watches` table (TODO P0 item)
- "Most watched" sort option becomes real
- Continue-watching surface (separate from playlists)

---

## 11. Open questions

Real decisions I want from you before writing the first line:

1. **Save/cancel vs immediate commit in edit layer.** I'm proposing
   immediate commits (matches everything else in the app). You said
   "save/cancel our changes first" in your ask. Want a draft+save
   flow, or align with the immediate-commit pattern?

2. **Single PIN session covers both edit + admin?** My proposal: yes,
   one PIN unlocks both for the session, exiting either ends the
   session. Acceptable?

3. **Auto-playback mode** — set per-profile by parent. Lives in:
   (a) admin > Profiles > Sarah, OR
   (b) Library edit layer (per-profile context), OR
   (c) the player gear menu (parent has to enter via PIN to change).
   Which feels right?

4. **Tab default on Library**: Channels first (today's behaviour), or
   Feed first (most recent activity)?

5. **Hiding vs removing channels**: do you want both? "Hide" =
   profile won't see it but the assignment stays, easy to unhide.
   "Remove" = unassign from profile (deletes the row in
   `profile_channels`; needs re-add via admin). I think both, but
   they're close in effect — confirm.

6. **Feed tab** scope: only videos from this profile's *assigned*
   channels (per profile_channels), right? Not the entire library.

7. **Edit-layer scoping**: edit layer always edits the active
   profile's view. If parent is in viewer mode without a profile
   selected (i.e. on the picker), they can't enter an edit layer
   (no scope). Confirm: edit layer entry requires an active profile?

8. **Naming the toggle button**: "Edit" / "Edit Library" / "Manage" /
   something else? "Edit" is shortest but slightly ambiguous; "Manage"
   matches the prior Library Manage button.

---

## 12. What this means for the previous playlist plan

Most of `PLAYLISTS_PLAN.md` survives — the data schema, bridge
protocol, tray design, auto-advance logic. What changes:

- ✗ The "Editor > Playlists tab" surface (Phase 3 in old plan) — replaced by inline editing on the Library > Playlists tab
- ✗ The "editor-mode-only quick-add card popover" — becomes
  edit-layer-only
- ✗ The two-tier "editor mode + viewer mode" distinction — replaced
  by viewer + edit-layer + admin

Permission model unchanged: **adults curate, kids consume**. Only the
*mechanism* of curation changes — it's now inline instead of in a
separate screen.
