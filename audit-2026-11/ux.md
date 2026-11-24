# UX audit (lane: UX-) — LocalTube v1.0.37

Method: read `WebUI/src/**` and the Swift bridge / AppState / PlayerOverlayController; drove the real React UI in the mock-bridge harness with scripted keyboard/pointer probes (scripts in `scratchpad/work-ux/kbd.cjs`, `probe2..6.cjs`; their console output is quoted below as "harness"). Swift is static review only; anything runtime-AppKit/WKWebView is labelled `suspected`.

**PM correction folded in:** the live in-player controls are the SwiftUI `PlayerControlsOverlay` (`Player/VideoPlayerView.swift:354`, hosted at `Bridge/PlayerOverlayController.swift:144`), not `WebUI/src/screens/PlayerScreen.tsx` (dead; `main.tsx` only renders it if `__playerMode`, which Swift never sets). Player UX below is judged from the SwiftUI code. The earlier React-player observations (arrow-up/down and Enter don't reveal controls) were dropped because they do not apply: `PlayerPanel.keyDown` reveals controls on every key and `onContinuousHover` on mouse move.

---

## 0. Verdict

Visually the app is polished and the mode model on paper (viewer / edit layer / admin, EDITING_MODEL.md) is sound and mostly implemented. But as a **ten-foot, remote/keyboard-driven kids' app** it is not operable without a mouse: the cards that open channels and videos are not focusable, there is no focus ring on most controls, no arrow-key navigation anywhere, no focus trap in any modal. For the parent, first-run ends in a dead end (no profile/tools step, no PIN recovery, new channels invisible to every profile), several destructive actions have no confirm/undo (and Undo is wired to nothing), and the "walk away in edit mode" case hands a child full Admin without a PIN.

---

## 1. Friction map (top 10 steps)

| # | Step (persona) | What the user sees | Problem | Fix |
|---|---|---|---|---|
| 1 | First launch -> after PIN (C) | Folder -> "Set Your Editor PIN" -> empty Library "No channels yet. Ask a grown-up to add channels in Admin mode." (`Library.tsx:593-595`) | Message addresses a child but the reader IS the grown-up. No profile step, no tools (yt-dlp/ffmpeg) check, no recovery phrase shown. The old SwiftUI wizard had these (`Views/Onboarding/*`, dead); the live flow lost them. | Post-PIN checklist wizard: 1 tools (Install), 2 first profile, 3 first channel (auto-assigned). Reword empty state by mode. |
| 2 | Forgot PIN (B) | Nothing. | Recovery phrase is generated and stored but never shown (`LocalTubeBridge.swift:475-481`; only `Views/Onboarding/PINSetupView.swift`, dead, displays it). No "Change PIN" / "Forgot PIN" anywhere (grep: no PIN UI in Settings/Profiles). Parent permanently locked out of Admin. | Show phrase on PINSetup; add Settings > Change PIN and PINEntry > "Forgot PIN?" using `PINService.loadRecoveryPhrase`. |
| 3 | Add a channel in Admin, exit, pick Maya (B) | New channel not in Maya's library. | New channels are never assigned to a profile (`LocalTubeBridge.swift:534-563` never calls setProfileChannels). Harness: after `channelUpserted`, `BrandNewChannel` visible to active profile = **false**. Parent must know to go to Admin > Profiles and tick it. | Add Channel modal gets "Show to: [x] Maya [x] Leo" (default all) or auto-assign to all profiles + toast "Added to 3 profiles". |
| 4 | Add videos by URL (B) | Textarea clears instantly, modal closes after a fake 2 s timer (`Channel.tsx:190-205`, CODE_REVIEW H9 **still true**). | Swift silently drops invalid, duplicate and >50 URLs with no feedback (`LocalTubeBridge.swift:612-648`). Parent never learns "2 of 5 were skipped". | Swift returns a result toast ("Queued 3, 1 already added, 1 not a YouTube link"); React waits on it (`sendBridgeWithTimeout` already exists). Don't clear input until confirmed. |
| 5 | Profile picker with keyboard / TV remote (A) | Nothing is focused (harness: initial `activeElement` = BODY). Tab goes to the Library behind the picker first (Admin 90x34), then picker. | No autofocus on first profile, no arrow keys, `outline:none` on tiles (`ProfilePicker.tsx:132`), picker `aria-modal` but background stays tabbable. | Autofocus first tile; roving arrow-key focus; visible 4px ring; `inert` the background. |
| 6 | Browse channels -> play (A) | Library grid / channel grid. | Channel and video cards are `div onClick` (`ChannelCard.tsx:106-108`, `VideoCard.tsx:110-112`). Harness Tab order on Library: Edit, profile chip, tabs, Sort + 3 invisible options, queue handle... **never a channel card**; on Channel: only Favorite hearts, never a video. Playback is mouse-only. | Cards become `<button>`/`<a>` with Enter/Space; 2-D arrow nav; Esc/Back = up one level. |
| 7 | Parent enters Settings from picker / Cmd+, (B) | Picker "Settings" -> PIN -> lands on Admin > Channels. Cmd+, in viewer: nothing happens. | `ProfilePicker.tsx:26-42` sets a PIN callback that `PINEntry.tsx:31-42` overwrites on mount (single slot in `store.ts`), so the post-PIN navigation never runs. `AppDelegate.openSettings` (`:198-203`) emits `navigateTo settings` ungated; React bounces it back (`App.tsx:151-153`) -> silent no-op. | Pending-intent in store (`pinIntent: 'settings'`), not a closure; Cmd+, triggers PIN prompt when locked. |
| 8 | Parent walks away in edit layer / admin (B/A) | Library with "Editing Maya's library" chip. | No timer (by design), session not cleared on profile switch (`handleSetActiveProfile` `:792-802` doesn't touch isEditing; EDITING_MODEL §9 says it should). Edit-layer "Admin" button promotes to Admin **without PIN** (`:492-496`). A child then has delete channel/video, relocation, settings. Also in edit layer: remove-channel-from-profile is one click, no confirm (`Library.tsx:133`). | Idle prompt ("Still editing? Exit in 30 s") after ~10 min without input; exit on screen lock/sleep/app deactivate; Cmd+L "Lock now"; PIN step-up for destructive Admin actions. |
| 9 | Failed download -> Retry / Delete (B) | Failed card in Admin shows error text + Retry. | Delete is an invisible (opacity 0) hover-only overlay (`VideoCard.tsx:437-474`), deletes file with **no confirmation and no undo**. It overlaps the top ~30% of Retry: harness click at 15% of Retry height sent `deleteVideo`. Tab reaches the invisible Delete (harness: 19th Tab) and Enter sent `deleteVideo`. | Remove overlay; explicit labelled Delete with confirm (or undo-toast + Trash); fix stacking. |
| 10 | Drive unplugged (A/B) | "Library folder not found ... this screen will go away by itself" (good copy, 5 s polling). | "Locate Library..." is reachable by a child with no PIN -> relocation modal (Move/Adopt/Switch). Bridge has no per-mode guard (`LocalTubeBridge.swift:508` is the only appMode check). | Gate "Locate Library..." behind PIN; keep Try Again open. |

Also noted: tools missing (Settings shows only "Missing", no Install: `Settings.tsx:296-316`; `installMissing` is only called from dead `DependencyCheckView.swift:65,94`) -> parent adds a channel, downloads fail with a raw yt-dlp error and no pointer to the cause. Update available: native Sparkle window (`AppDelegate.swift:22`, SUEnableAutomaticChecks `Scripts/package_app.sh:67`) interrupts viewing and is not PIN-gated (`suspected`).

---

## 2. Mode model

* Viewer -> Edit layer -> Admin exists as EDITING_MODEL specifies. The edit layer is clearly signalled: "Editing Maya's library" chip + Done (red) + dimmed hidden channels + remove/hide buttons visible without hover (harness screenshot `harness/shots/editing-layer-1280x800.png`, which I looked at). That part works.
* Weak points: (a) vocabulary: "Admin", "Edit", "Editor Mode" (View menu `AppDelegate.swift:289`, Cmd+E), "Editor PIN" (`PINSetup.tsx:229`, `Onboarding.tsx:240`), "Admin PIN" (`PINEntry.tsx:122`), spec "Parent PIN". Picker "Admin" and Library "Edit" use the same pencil glyph. (b) "Done" is styled as a destructive exit. (c) Edit layer's Feed tab still lets rows play (`Library.tsx:458-463`) contrary to EDITING_MODEL §4.1. (d) The entry point for a parent ("Edit", 34px, 13px type, next to the avatar) is discoverable but tiny; for a child it is equally visible - acceptable only because the PIN works and lockout persists (AUDIT H6).
* Walk-away: no timer, no reset on profile switch, Admin promotion without PIN. See friction #8. Child-reachable destructive actions in viewer: only "Locate Library..." (#10); everything else needs PIN in the UI, **but the bridge itself never checks mode** (cross-lane SEC note).

## 3. Feedback & async honesty

* H9 `handleAddVideos`: **still true** (`Channel.tsx:190-205`). The Admin path (`Editor.tsx:38-42`, `AddVideosModal`) closes immediately and validates only client-side substrings.
* Add Channel: modal closes instantly; "YouTube Source" accepted with a blank ID (`AddChannelModal.tsx` canSubmit = name only) -> channel never syncs and **Sync is a silent no-op** (`AppState.swift:419` `guard ... else { return }`).
* PIN error not announced (no live region; harness: `ariaLive: false`).
* Toasts: auto-dismiss timer is re-armed on every render because `onDismiss` is a fresh arrow per render (`ToastHost.tsx:30`); harness: toast still present >20 s while download progress events streamed (control: gone at 6 s). Live region mounts together with its content (`ToastHost.tsx:13` returns null when empty), which screen readers commonly miss. Error and info toasts both vanish in 6 s.
* Filters/search: list view ignores search and Favorites (`Channel.tsx:1039` maps `sortedVideos`; harness: 9 rows with search "Bluey" vs 1 in grid). Favorites filter with 0 favorites shows `No videos found / Nothing matches ""` and "Clear Search" does not clear the filter (`Channel.tsx:941-947`; harness confirmed; TODO "edge case" item still open).
* Library sort "Name/Recently updated" + drag reorder: drag commits to profile order but the sort overlay keeps the old visual order, so reorder appears to do nothing (`Library.tsx:57-76` vs `:163-177`).
* Failed downloads: kids see raw 11px yt-dlp error text (`VideoCard.tsx:250-267`); there is no parent-facing "needs attention" indicator outside Admin.

## 4. Undo / safety

* Spec §9 promises Cmd+Z for all editor operations. `LibraryStore` registers undo actions (`LibraryStore.swift:449-561`) but `appState.undoManager` is never assigned in `App/` or `Bridge/` (grep: zero hits), and the Edit menu Undo targets the responder chain (`AppDelegate.swift:275`). Result: **nothing is undoable** (confirmed statically; also, React is never told about an undo so the UI would desync). `suspected` runtime: Edit > Undo is greyed out.
* Confirm dialogs: delete channel (Channel + Admin), delete profile, clear queue have them. Missing: delete video (Admin), remove channel from profile, hide channel (reversible, fine), autoplay change.
* Copy drift: Admin dialog says "permanently deleted" (`Editor.tsx:473`), Channel page says "Downloaded files will also be deleted" (`Channel.tsx:1078`); reality: folder goes to Trash (AUDIT L1). Say "moved to the Trash".

## 5. Accessibility defect list (evidence)

| ID | Defect | Evidence |
|---|---|---|
| A1 | Channel/video cards are not focusable or exposed as controls | `ChannelCard.tsx:106-108`, `VideoCard.tsx:110-112`; harness Tab trace (Library, Channel); ARIA snapshot shows cards as bare text+img, no role/name |
| A2 | No `:focus-visible` anywhere; 12 inline `outline: 'none'` in 7 files (`ProfilePicker.tsx:132,185`, `Library.tsx:489,857`, `LtSelect.tsx:77`, ...); harness: picker tiles, Admin/Settings, Edit/Done, tabs, Sort all `outline-style:none`. Spec §3.2 wants a large tvOS ring | grep + harness |
| A3 | No arrow-key navigation (spec §3.3) in picker, grids, tabs; TODO a11y item still open | grep: no key handlers beyond Esc in LtSelect/Editor/Profiles |
| A4 | No focus trap / restore / Esc in any modal (Add Videos, delete confirms, New Profile, Relocate, PIN). Harness: after opening Add Videos focus stays on the trigger OUTSIDE, Tab walks into background invisible Delete buttons, Esc leaves it open; PIN Esc does not dismiss | probe5 output |
| A5 | Picker `aria-modal` but Library behind remains in Tab order and a11y tree (harness Tab trace; ARIA snapshot lists the whole Library after the dialog) | `ProfilePicker.tsx:45` |
| A6 | Closed popovers are still focusable: LtSelect listbox is only `opacity:0; pointer-events:none` (`LtSelect.tsx:121-124`), so Tab stops 3-6 times on invisible options per select; QueueTray is off-canvas but its Close button and content are tabbable and in the a11y tree (harness) | harness `<<INVISIBLE>>` rows |
| A7 | Icon-only buttons without names: Channel grid/list view toggles (harness: `button` with no name x2-3), modal close X (`Channel.tsx:1111`), Admin row actions only `title`; remove/hide buttons all named identically with no channel name | ARIA snapshot |
| A8 | SVGs not `aria-hidden` (every control shows an extra `img` node); no landmarks, no `<main>/<nav>`, Library has no `<h1>`; dialogs use `aria-label` not `aria-labelledby` | ARIA snapshot; TODO a11y items |
| A9 | PIN field: hidden text input with no label; error has no `role=alert`; digits are divs | `PINEntry.tsx:181-225` |
| A10 | Live regions: toast container mounts with content; progress/sync/"downloading" state has no announcement | `ToastHost.tsx:13` |
| A11 | `prefers-reduced-motion`: zero matches in `WebUI/src` (CSS or JS). Harness with reducedMotion on: spinner/ambient/enter animations still run. SwiftUI player honours it only for the controls fade (`VideoPlayerView.swift:443-446`); spring/scale effects on buttons are not gated | grep + harness |
| A12 | Targets far below spec (96pt): harness counts visible controls <44px: Library 6, Channel 21, Edit layer 20 (Edit 74x34, tabs 38px, Sort 36px, hearts 34px, remove/hide 32px) | probe4 |
| A13 | Hover-dependent affordances (spec §3.3 forbids): Admin video Delete overlay (opacity 0 until hover, no `:focus-within`), channel-list row Delete (`Channel.tsx:1378-1381`), play button reveal `.lt-play-btn` | `index.css:651-690`, `VideoCard.tsx:437-451` |
| A14 | Drag-only reorder (Library channels, queue tray) with no keyboard/pointer-click alternative (WCAG 2.5.7) | `Library.tsx:151-181`, `QueueTray.tsx` |
| A15 | SwiftUI player: Back, +/-10s and Play/Pause are `onTapGesture` views with no accessibility labels/traits (`VideoPlayerView.swift:196,237,343`); only Loop and Autoplay are labelled (`:466,497`). VoiceOver cannot operate them. Keys: Esc/Space/arrows only (`PlayerOverlayController.swift:299-316`); Return/media keys unhandled | static |
| A16 | `suspected`: WKWebView only tabs to buttons when macOS Full Keyboard Access is on; without it even the Tab traces above would not occur. JS focus management with explicit `tabindex` is the safe route | needs a Mac |

## 6. Spec vs reality (LocalTube_Parameters.md)

| Spec | Reality |
|---|---|
| Targets >= 96pt, focus rings big/high-contrast | 32-44px controls; ring missing or UA default |
| Arrow-key navigation between all major elements | none |
| No hover-dependent reveals | Admin Delete overlay, play button, channel-list delete |
| Max nav depth 2 | OK: Library -> Channel -> Player; Admin is a separate shell with 3 tabs; edit layer is lateral |
| PIN: Keychain, recovery phrase, 10-min auto-lock | UserDefaults hash (`PINService.swift:7-8`) while PINSetup copy says "macOS keychain" (`PINSetup.tsx:291`); phrase hidden; timer intentionally removed |
| Undo/Redo for editor ops | not wired |
| Reduce Motion, VoiceOver labels | largely absent |
| 28pt body / SF Rounded | (TYP lane) |

## 7. Player UX (SwiftUI, per PM correction)

* Controls: centre play 84pt, skip 66pt (good), but Back 88x36, loop 36pt, autoplay 36pt, volume slider 200pt wide. Auto-hide after 4 s only while playing; stays visible while paused (`PlayerState.swift:119-131`, a kid-friendly choice). Every key and any mouse move reveals them.
* Exit for a child: Esc or Back; one press, no confirm; resume position saved on stop unless within 2 s of the end.
* Resume: silent. Live path starts at saved position when > 10 s (`PlayerOverlayController.swift:80`) with no "Start Over"; the Resume/Start Over prompt exists only in dead `VideoPlayerView.swift:152-155`. Card shows "Resume at ..." and progress bar for > 5 s (`VideoCard.tsx:107`) so 5-10 s of progress is displayed but ignored. Watched-to-end resets to 0 with no "watched" marker.
* End of video: queue source auto-advances; channel source follows the profile's autoplay mode (`nextVideo`, `PlayerOverlayController.swift:~160-190`); `.exit` returns to channel. Sound.
* In-player autoplay cycle button changes the **persistent per-profile mode** with no PIN (`:96-102`, `VideoPlayerView.swift:477-498`), duplicating the edit-layer picker with different labels ("Off/Next/Repeat/Shuffle" vs "Off - back to channel/Play next/Repeat one/Shuffle") and overlapping the per-session Loop button. Decision needed (EDITING_MODEL open question 3 is unresolved).

## 8. Feature gap: planned vs built

| Item (TODO / EDITING_MODEL) | Status in code | Notes |
|---|---|---|
| Queue tray ("Up Next") | Built | Per-profile, DB-backed, drag reorder, remove, Clear w/ confirm (edit layer); kids read-only; queue autoplay in Swift |
| Named playlists | Partial (backend only) | create/rename/delete/setActive handlers exist (`LocalTubeBridge.swift:78-82`) but no React code sends them; Playlists tab = "coming soon" placeholder (`Library.tsx:607-640`) |
| Auto-playback modes | Built (needs PIN decision) | 4 modes, edit-layer picker + in-player cycle |
| Favorites + filter | Built, buggy edges | 0-favorite empty state, list view ignores filter |
| Refresh missing/failed on sync | Built | (AUDIT P5) + "Retry N failed" in Admin only |
| Sort videos | Mostly built | Channel: default/newest/oldest/title/longest/shortest (`Channel.tsx:151-161`), localStorage not per-profile; no "recently viewed/most watched"; TODO is stale |
| Channel sort in Library | Built | custom/name/recent |
| Search tags | Missing | title-only (`Channel.tsx:241`), no tags column |
| Watch tracking (`profile_watches`) | Missing | only `resumePositionSeconds`; no last-watched, count, completed |
| Continue Watching rail | Missing | data (resume position) exists |
| Hide a video | Missing | only per-profile hidden channels exist |
| Bulk ops | Missing | |
| PiP | Missing | (AV lane) |
| Global favorites shelf | Missing | |
| Active-download chip in Library bar | Built | `Library.tsx:242-258` (TODO item stale) |
| Volume persistence, reduce-motion | Missing | |
| Edit layer: Channels tab | Built | reorder, hide, remove |
| Edit layer: Channel page | Partial | only queue add; no reorder/hide videos |
| Edit layer: Playlists tab | Missing | |
| Dependency install in live UI | Missing | status-only |
| PIN change/recovery | Missing | |

## 9. Ranked UX fixes (effort / impact)

1. **Keyboard + focus foundation**: real `<button>` cards, roving-tabindex arrow navigation hook for picker/channel grid/video grid/tabs, global `:focus-visible` 4px ring, autofocus on screen entry, Esc/Backspace = back. (M / High) (UX-1)
2. **One `<Modal>` primitive**: `<dialog>`/inert background, focus trap + restore, Esc, `aria-labelledby`; `inert` for picker background, closed LtSelect and closed QueueTray. Also fixes TODO "modal exits pop". (M / High) (UX-8, A4-A6)
3. **Safety net**: Undo toast ("Video deleted - Undo", soft delete into Trash for ~10 s) replacing the hover Delete overlay; confirm for remove-from-profile; wire or drop Cmd+Z. (S-M / High) (UX-4)
4. **Parent session safety**: idle prompt + exit on sleep/lock/profile switch, "Lock now" Cmd+L, PIN step-up on edit-layer -> Admin and on relocation. (S-M / High) (UX-3)
5. **First-run wizard + PIN recovery/change** (tools check with Install [needs UPD], first profile, first channel auto-assigned; show phrase; Forgot PIN). Fix the "Keychain" copy. (M-L / High) (UX-2, UX-5)
6. **Result feedback for add videos / add channel / sync** (Swift result toast; validate source ID; remove 2 s fake timer). (S / High) (UX-6)
7. **Filter/search correctness**: list view uses `filteredVideos`; zero-favorites empty state "No favorites yet - tap the heart" with "Show all"; reorder disabled or sort snaps to Custom while editing. (S / Med) (UX-7)
8. **Playlists tab**: hide it until built; then ship create/rename/delete/switch + "save queue as playlist". (S now, M later / Med)
9. **Toast fixes** (stable `onDismiss`, persistent live region, errors persist until dismissed). (S / Med)
10. **Terminology + PIN-intent**: pick "Parent Mode" (or Admin) and use it everywhere incl. View menu; distinct icons for Edit vs Admin; pending-intent store for picker Settings; Cmd+, prompts PIN. (S / Med)
11. **TV scale**: "Large controls" mode honouring the 96pt spec; 44px minimum everywhere else; reduced-motion CSS + JS. (M / Med)
12. **Player a11y/resume**: labels/traits on SwiftUI controls, Return = play/pause, resume prompt or "Start over" chip, align the 5 s vs 10 s thresholds, PIN-gate or remove the in-player autoplay cycle. (S-M / Med)

Suggested sequence: 1+2 (foundation) -> 3+4 (safety) -> 6+7 (honesty quick wins, can run in parallel) -> 5 (onboarding) -> Continue Watching/watch tracking -> playlists UI -> new ideas.

## 10. Feature roadmap (value vs effort), including ideas not in TODO

1. Continue Watching rail + "watched" badge (light watch tracking: `last_watched_at`, `completed`) - M, very high kid + parent value; unlocks "Most watched" sort.
2. "Surprise me" tile (random ready video from visible channels / favourites) - S, high kid value.
3. Sleep timer / "stop after this video" in the player (15/30/45 min, fade out) - S-M, high parent value (bedtime).
4. Per-profile daily watch-time limit with a friendly "all done for today" screen; PIN override - M.
5. Parent "Needs attention" dot on the Admin button (failed downloads, missing tools, sync errors, update pending) - S.
6. Favourites shelf at the top of Library (TODO "global favorites") - S.
7. Per-profile hidden videos + "Show hidden" in edit layer - M.
8. Per-profile content filters (max duration, hide channels by tag) - M-L; tags search depends on capturing yt-dlp tags (migration).
9. Bulk select in Admin (hide/delete/move) - M.
10. Kid-safe error copy ("This video isn't available right now") with raw yt-dlp text parent-only - S.

## 11. Needs a real Mac to confirm
* Whether Tab reaches buttons in WKWebView with default Full Keyboard Access (A16); focus-ring appearance in WebKit.
* Edit > Undo state (greyed?) and whether any `undoManager` is attached by the window.
* Sparkle window appearing mid-viewing and whether a child can install.
* VoiceOver reading of the SwiftUI player and the web UI.
* PlayerPanel key handling after the panel loses key status.

## 12. Cross-lane notes
* SEC: bridge performs no mode/PIN authorization on mutating messages (only `handleRequestEditMode` checks appMode); `setPIN` has no `needsPINSetup` guard; recovery phrase stored in plaintext UserDefaults (`PINService.swift:49`).
* UPD: dependency install exists only in dead SwiftUI; live Settings is read-only. Silent no-op when a source channel has no YouTube ID.
* AV: volume not persisted; Loop vs autoplay Repeat overlap; two `AVPlayerItemDidPlayToEndTime` observers (PlayerState and PlayerOverlayController).
* ARC/QA: `Channel.tsx` re-implements Add Videos/Delete modals that `components/AddVideosModal.tsx` already provides; `WebUI/src/screens/PlayerScreen.tsx` + `main.tsx` player branch and `Views/**` are deletion candidates; `editorAutoLockMinutes` is still in AppSettings/Settings state though the timer is gone.
* UI/DSG: remove/hide buttons collide with the video-count badge on edit-layer cards; "Drag to reorder" pill covers card content (harness shot `editing-layer-1280x800.png`).
