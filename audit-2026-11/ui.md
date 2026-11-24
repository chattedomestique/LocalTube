# UI audit (lane: UI) — LocalTube v1.0.37

Auditor: UI. Evidence = code (path:line read) + harness screenshots/probes.
Shots dir: `/tmp/claude-0/-home-user-LocalTube/411d552b-4a76-5096-8a3a-c28d66f3586b/scratchpad/work-ui/shots/` (all 19 scenarios x 1280x800, 1920x1080, 3840x2160, 900x600, plus `ui-*.png` probe shots).
Probe scripts: `.../work-ui/probe1.cjs` (target sizes + Tab), `probe2.cjs` (modals), `probe3.cjs` (hero/feed/focus/large), `probe4.cjs` (small window/4K), `scan.cjs` (button census).
Harness is Chromium, not WebKit; Swift is static review only (labelled `suspected`).

## 0. Headline corrections to the brief
* **`WebUI/src/screens/PlayerScreen.tsx` is dead code.** No Swift file sets `window.__playerMode` or `window.LocalTubePlayer` (grep over `Sources/` hits only the committed JS bundle). The live player controls are SwiftUI `PlayerControlsOverlay` (`Sources/LocalTube/Player/VideoPlayerView.swift:354`) hosted in an `NSHostingView` inside the AVPlayer panel (`Bridge/PlayerOverlayController.swift:9-12,145`). So `Player/**` is NOT dead (PlayerState, PlayerControlsOverlay, GlassCircleButton are live), and the harness `player-*.png` shots show UI that never ships.
* Lead (a) hero gradient: **refuted for missing `bannerPath`**, **confirmed for broken banner** (see UI-5).
* Lead (b) "10" glyph: true in dead code only (see UI-16).
* Lead (c) Feed tab: **real** (Library.tsx:646-770). The **Playlists** tab is the placeholder (Library.tsx:607).
* Lead (e) Edit menu: **exists** (AppDelegate.swift:269-281).

## 1. Prioritised findings

Severity key: Critical = blocks a core flow; Major = clearly wrong in a primary flow; Minor = polish/edge.

| ID | Sev | Status | Summary |
|---|---|---|---|
| UI-1 | Major | confirmed | ChannelCard and VideoCard are non-focusable `div`s — keyboard/remote users cannot open a channel or play a video |
| UI-2 | Major | confirmed | No visible keyboard focus indicator anywhere (0 `:focus-visible` rules, 16 inline `outline:none`) |
| UI-3 | Major | confirmed | Closed LtSelect menus and the closed Queue tray stay in the tab order (invisible focus targets) |
| UI-4 | Major | confirmed | 10 modal shells, 0 handle Esc, 0 trap focus, 0 restore focus; only 2 use MountWithExit |
| UI-5 | Major | confirmed | Channel screen: fixed 300px hero + 183px sticky chrome; zero thumbnails above the fold at 900x572; broken-banner leaves empty 300px |
| UI-6 | Major | suspected (Mac) | Dark-only web UI inside a system-appearance window: light title bar / first-paint flash / light native controls |
| UI-7 | Major | confirmed (menu) / suspected (undo) | Main-menu gaps: no ⌘W, no Help, no Services, static "Enter Editor Mode", Undo/Redo wired to the wrong selector |
| UI-8 | Major | suspected (Mac) | Main window never opts into `.fullScreenPrimary` — fullscreen (the TV use case) may not work |
| UI-9 | Major | confirmed | Design-system fragmentation: 575 inline style blocks, 0 Tailwind utilities used, 49/69 `lt-*` buttons carry inline overrides |
| UI-10 | Minor | confirmed | ChannelCard edit-layer × button covers the count badge; "Drag to reorder" pill covers the progress text |
| UI-11 | Minor | confirmed | Ragged video grid rows (card doesn't fill its grid cell) |
| UI-12 | Minor | confirmed | "Playlists coming soon" placeholder tab shipped in viewer; Feed column left-aligned with dead space |
| UI-13 | Minor | confirmed | Onboarding clips at the minimum window size (no scroll container) |
| UI-14 | Minor | confirmed | Settings uses a native `<select>` (truncated label) and native white checkboxes on the dark UI |
| UI-15 | Minor | confirmed | Duplicate Add-Videos modal and ambient-background stack inside the 1,450-line Channel.tsx |
| UI-16 | Minor | confirmed | PlayerScreen.tsx (536 lines) is dead; the "10" glyph renders at 5.6px there; live buttons are 66pt/84pt |
| UI-17 | Minor | confirmed | Primary controls are 34-44px, spec says 96pt; 43% of inline font sizes are <=13px |
| UI-18 | Minor | suspected (Mac) | Nothing scales at 4K @1x: 396px cards, ~55% dead width, 13px tab text |
| UI-19 | Minor | confirmed | Queue-tray handle is permanently fixed at right-centre and overlaps content edge/scrollbar/hover-scaled cards |
| UI-20 | Minor | suspected | Nested `backdrop-filter` makes modal panels see-through in Chromium; 54 backdrop-filter uses overall |
| UI-21 | Minor | confirmed | Missing yt-dlp/ffmpeg has no viewer-visible surface (only Settings) |
| UI-22 | Minor | confirmed | No `prefers-reduced-motion` handling anywhere |

### UI-1 Cards are not keyboard-operable (Major, confirmed)
* `components/ChannelCard.tsx:106-108` root is `<div className="lt-card" onClick=...>`; `components/VideoCard.tsx:110-112` root is `<div className={isReady ? "lt-video-card" : undefined} onClick={isReady ? onPlay : undefined}>`. `grep tabIndex|role="button"` across screens+components = 0 hits. The only `keydown` handlers in the UI are LtSelect, inline-rename inputs, PINEntry and the dead PlayerScreen.
* Harness probe (probe1.cjs): Library exposes 11 focusable elements and none is a channel card; Channel exposes 28 and none is a video card (only the heart buttons). Browsing and playing therefore need a mouse.
* Impact: keyboard-only users, switch users, and anyone driving the Mac from a keyboard on a TV. Also kills VoiceOver ("group" with no action).
* Fix: render the card roots as `<button>`/`<a role=link>` (or add `role=button tabIndex=0` + Enter/Space), then add arrow-key spatial navigation on the grids. Effort M, impact High. (Overlaps UX lane; the component change is UI-owned.)
* Suspected add-on (needs Mac): WKWebView does not Tab to controls unless `WKPreferences.tabFocusesLinks` / Full Keyboard Access is on; no Swift file sets `tabFocusesLinks` (grep).

### UI-2 No visible focus indicator (Major, confirmed)
* `index.css` has 0 `:focus-visible` rules; the only focus style is `.lt-input:focus` (index.css:281). 16 inline `outline: 'none'` (LtSelect.tsx:77, EditorShell.tsx:204/236, Editor.tsx:176, Library.tsx:489/857, Channel.tsx:785/1432, Profiles.tsx:191/391, ProfilePicker.tsx:132/185, ...).
* Evidence: `shots/ui-focus-feed-tab.png` (Tab x5 → focus on Feed: no ring), `shots/ui-focus-profile-tile.png` (focus on the "Maya" tile: identical to unfocused), computed `outline-style: none` for Edit, Channels, Playlists, Feed, Sort, all three profile tiles (probe1.cjs output).
* Hover is implemented by 54 JS `onMouseEnter/Leave` style mutations across 15 files, so there is no CSS hook for focus parity.
* Fix: one global rule `:focus-visible { outline: 3px solid var(--accent); outline-offset: 3px; border-radius: inherit }`, delete the inline `outline:none`, convert JS hover handlers to CSS `:hover, :focus-visible`. Effort S, impact High.

### UI-3 Invisible focus targets (Major, confirmed)
* `components/LtSelect.tsx:96-125`: closed menu is `opacity:0; pointerEvents:none` but still rendered and tabbable; options are `role=option` buttons with no arrow-key support. `components/QueueTray.tsx:160-175`: the tray panel (`role=dialog`) is always mounted and merely `translateX(360px)` when closed, so its "Close queue" button is tabbable while off-screen.
* Evidence: `shots/ui-library-focus-after-tabs.png` — after 8 Tabs focus sits on the hidden "Name (A-Z)" option and nothing is highlighted; probe2 pin-entry Tab sequence includes "Close queue" while the tray is closed.
* Fix: `visibility:hidden` (or `inert`) while closed; implement ArrowUp/Down/Home/End/Enter/Typeahead in LtSelect or use a native `<select>`. Effort S.

### UI-4 Modal behaviour (Major, confirmed; verifies the TODO.md claim)
* `MountWithExit` is used only in `App.tsx:224-229` (ProfilePicker, PINEntry) — claim confirmed. `grep modal-backdrop` = 10 dialog shells in 9 files: AddChannelModal:43, AddVideosModal:57, RelocateLibraryModal:59, QueueTray:293, Editor:453, PINEntry:87, Profiles:365+432, Channel:1058+1102.
* Esc: handled by none (the only `Escape` handlers are LtSelect and the inline-rename inputs). probe2.cjs: Esc left AddChannel, AddVideos, delete-confirm and PIN open.
* Focus trap: none. probe2: AddChannel Tab order = 3 controls then `BODY` then the background "Channels" tab; AddVideos Tab walks 14 background "Delete" buttons. Six dialogs declare `aria-modal="true"` while the background stays reachable.
* Initial focus: AddChannel and PIN focus their input; AddVideos, delete-channel confirm and the queue tray do not (focus stays on the opener or `BODY`; the destructive confirm needs 10+ Tabs to reach). Focus restore on close: none (`BODY`).
* Backdrop click closes only AddChannel and AddVideos (`onClick={onClose}`); every other dialog ignores it. Body scroll lock is moot (`html, body {overflow:hidden}`, index.css:55) and scroll containers are not ancestors of the backdrop.
* Fix: one `<Modal>` primitive on native `<dialog>` + `showModal()` (WebKit 15.4+ gives focus trap, Esc, inert background, focus restore for free) wrapped in MountWithExit. Effort M, impact High.

### UI-5 Channel hero + sticky chrome (Major, confirmed; lead (a))
* `Channel.tsx:29` `BANNER_HEIGHT = 300` fixed. `Channel.tsx:416-446`: hero renders only `hasBanner ? <div 300px> : null`.
  * No `bannerPath` → no hero (probe3: top bar at y=0; `shots/ui-hero-no-banner.png`). **PM lead refuted for that case.**
  * `bannerPath` set but unloadable (deleted/moved file, 404) → `onError` hides only the `<img>` (Channel.tsx:437); the 300px box and scrim stay (probe3: top bar at y=300; `shots/ui-hero-broken-banner.png`). **Confirmed variant.**
* Even with a valid banner: sticky top bar 80px (Channel.tsx:458) + search/filter bar ~103px = 183px of chrome. At 1280x800 the first video row starts at y=529 (`shots/channel-1280x800.png`, one row visible); at 900x572 no thumbnail is above the fold (`shots/channel-900x600.png`); scrolled, chrome covers 23% of the viewport (`shots/ui-large-scrolled.png`).
* Fix: `height: clamp(140px, 24vh, 300px)`, collapse the box on image error (state flag), merge search+sort into the 80px bar and hide the filter pills on scroll. Effort S, impact Med-High.

### UI-6 Dark UI in a system-appearance window (Major, suspected — needs Mac)
* No Swift sets `window.appearance`/`backgroundColor`/`isOpaque` (grep of WebWindowController.swift and AppDelegate.swift; no `darkAqua` anywhere outside legacy). Web side: no `color-scheme` in `index.css`/`index.html`, no `prefers-color-scheme`. The window style is plain `[.titled,.closable,.miniaturizable,.resizable]` (WebWindowController.swift:127), `webView.drawsBackground=false` via KVC (:120) so the window background shows through before first paint.
* Predicted in macOS Light mode: light-grey title bar over a black UI; light flash on launch; white native checkboxes/scrollbars/textarea (already visible in Chromium: `shots/editor-profiles-1280x800.png`, bright white unchecked boxes).
* Fix: `window.appearance = NSAppearance(named: .darkAqua)`, `window.backgroundColor = #0D0D0F`, `:root{color-scheme:dark}` + `<meta name="color-scheme" content="dark">`. Effort S, impact High (every launch).

### UI-7 Main-menu completeness (Major, confirmed except where noted; lead (e))
`AppDelegate.swift:239-322`. Present: App (About, Check for Updates, Settings… ⌘,, Hide ⌘H, Hide Others ⌥⌘H, Show All, Quit ⌘Q), Edit (Undo, Redo, Cut ⌘X, Copy ⌘C, Paste ⌘V, Select All ⌘A), View (Enter Editor Mode ⌘E, Enter Full Screen ⌃⌘F), Library (custom), Window (Minimize ⌘M, Zoom, Bring All to Front).
* Lead (e) refuted: the Edit menu exists and `cut:/copy:/paste:/selectAll:` resolve through the responder chain into WKWebView (suspected-OK; needs Mac to confirm in the PIN/search/URL fields).
* Gaps (confirmed by reading the file): no Close Window ⌘W (no File menu, no Close in Window menu); no Help menu; no Services submenu; no Find/Delete/Paste-and-Match in Edit.
* `Undo`/`Redo` use `#selector(UndoManager.undo)` / `redo` (:275-276) i.e. selectors `undo`/`redo`, not the responder-chain `undo:`/`redo:` — suspected permanently greyed (WebKit may still handle ⌘Z itself). Needs Mac.
* "Enter Editor Mode" title is static (:289); there is no `validateMenuItem`/`menuNeedsUpdate` in AppDelegate (grep), so it never flips to "Exit Editor Mode".
* `openSettings` (:194-198) comment says "Only allow settings access from editor mode" but navigates unconditionally and `App.tsx:199` has a viewer-mode `case 'settings'` fallback — a child can reach Settings with ⌘, (cross-lane: SEC/UX).
* Fix: add File-less "Close" ⌘W to Window menu, Help menu (`NSApp.helpMenu`), `NSApp.servicesMenu`, dynamic editor item via `NSMenuItemValidation`, use `Selector(("undo:"))`. Effort S.

### UI-8 Fullscreen opt-in (Major, suspected — needs Mac)
No `.fullScreenPrimary` anywhere in `Sources/` (grep); `WebWindowController.swift:~120-136` sets styleMask/minSize/autosave only. Programmatically-created NSWindows are generally not full-screen-capable unless `collectionBehavior` includes `.fullScreenPrimary`, so the green button and View → Enter Full Screen (AppDelegate.swift:292) may be disabled/zoom-only. For a projector/TV app this is the main use. The player panel already sets `.fullScreenAuxiliary` (PlayerOverlayController.swift:123), implying fullscreen was expected to work. Fix: `window.collectionBehavior.insert(.fullScreenPrimary)`. Effort S.
Related facts (confirmed): `window.minSize = 900x600` is a frame size (content ~900x572) (WebWindowController.swift:132); `setFrameAutosaveName("LocalTubeMainWindow")` after `center()` (:135) so restore wins; closing the window terminates the app (`windowWillClose`, :~288, plus `applicationShouldTerminateAfterLastWindowClosed` true); standard title bar (no `fullSizeContentView`) so traffic lights never overlap web content (good) but cost ~28pt vertical.

### UI-9 Design-system fragmentation (Major, confirmed) — see inventory section.
Quantified: 575 `style={{` blocks vs 146 `className=`; Tailwind 4 is imported (`index.css:1`, vite plugin) but **0 Tailwind utility tokens** appear in any className (scan.cjs) — it contributes only preflight; 100 `<button>`s: 71 use `lt-btn-*`/`lt-row-btn` classes, 29 are fully inline, and 49 of the 69 class users also carry an inline `style` override; ~19 distinct inline `borderRadius` values vs 5 radius tokens; 207 inline `fontSize` declarations over 22 distinct sizes; 293 inline `rgba()` + 53 hex colours vs 318 `var(--…)`; 102 inline `<svg>` while `@phosphor-icons/react` is imported only by `lib/profileIcons.ts`; z-index scale ad hoc (0-5, 60, 70, 71, 80, 90, 100, 150, 200, 400); 5 dead CSS classes (`lt-icon-btn`, `lt-glass-panel`, `lt-surface`, `lt-glass`, `lt-editor-toggle`: 0 TSX uses). Fix: shared primitives below. Effort L (incremental), impact High on maintainability and on fixing UI-2/3/4 once.

### UI-10 ChannelCard edit-layer collisions (Minor, confirmed)
`ChannelCard.tsx:233-236` (× and eye stack, top:12/right:12) sits on the count badge (`:354-358`, top:14/right:14); the centred "Drag to reorder" pill overlaps "Downloading… 63%". `shots/editing-layer-1280x800.png`. Fix: move the badge to bottom-right or the buttons to top-left. Effort S.

### UI-11 Ragged grid (Minor, confirmed)
`Channel.tsx:951-955` grid cells stretch (wrapper 234px) but VideoCard's root doesn't fill them: inner heights at 1920x1080 row 1 = 230/234/230/207/230/207 (probe4). `shots/channel-large-1920x1080.png`, `shots/ui-large-scrolled.png`. Fix: `height:100%` + flex column with a fixed 2-line title block. Effort S.

### UI-12 Playlists placeholder / Feed layout (Minor, confirmed; lead (c))
* Feed = chronological cross-channel list of ready videos (Library.tsx:646-770), `maxWidth: 920`, left-aligned (`shots/ui-library-feed-tab.png`: ~320px dead right at 1280, ~1000px at 1920). Works; channel name/time text is tertiary grey (#55555f on dark ≈ low contrast — DSG lane).
* Playlists tab renders "Playlists coming soon" (`Library.tsx:607-640`, `shots/ui-library-playlists-tab.png`) in a shipped build, while the Up-Next queue tray already exists. Fix: hide the tab until built or fold into queue; centre/cap Feed. Effort S.

### UI-13 Onboarding clips at min size (Minor, confirmed)
At 900x572 content: "Continue →" bottom = 576 > 572, logo cropped at top, 0 scroll containers (probe4; `shots/ui-onboarding-900x572.png`, `shots/onboarding-900x600.png`); fine at 1280x720. Cause: `html, body, #root {overflow:hidden}` (index.css:55-75) and a centred non-scrolling column. Fix: `overflow-y:auto` + `justify-content:safe center`. Effort S.

### UI-14 Native controls (Minor, confirmed)
`Settings.tsx` has the only native `<select>` (Download Quality): label truncates to "Best Available (up to" (`shots/editor-settings-1280x800.png`), while three other pickers use LtSelect. Native checkboxes (Settings, Profiles) render white on the dark UI (`shots/editor-profiles-1280x800.png`). Fix: LtSelect + a shared Checkbox/Switch; `color-scheme:dark`. Effort S.

### UI-15 Channel.tsx decomposition (Minor, confirmed; lead (d))
`Channel()` is a single 1,130-line function (L40-1170) with ~50 hooks and 89 inline style blocks. Extractable now:
1. `ChannelTopBar` (L448-707: back, title, count chip, edit toggle, sync, page-size, view toggle) ~260 lines
2. `SyncErrorBanner` (L709-745)
3. `VideoSearchBar` + sort + `FavoritesFilterPill` (L746-850; pill already separate at L1396)
4. `VideoGrid`/`VideoList` + `Pager` (L851-1056; `VideoListRow` already at L1236)
5. `useChannelVideos(channelId)` hook: sort/filter/page/readyCount/favoriteIds (L69-260)
6. `useAmbientBackground` hook (L263-372) — and merge with `components/AmbientBackground.tsx` (Library) whose header comment says "Same visual stack as the channel page"; today there are two implementations plus `BgBlurLayer` (L1170)
7. Replace the inline delete-confirm (L1057-1100) and inline Add-Videos modal (L1101-1160) with the shared `AddVideosModal` (components/AddVideosModal.tsx, already used by Editor) and `<ConfirmDialog>`
Effort M, impact Med.

### UI-16 PlayerScreen.tsx dead (Minor, confirmed; lead (b))
`PlayerScreen.tsx:60-75`: skip icons use `viewBox 0 0 28 28` rendered at 24px, `<text fontSize="6.5">` → 6.5 x 24/28 = **5.6px** on screen. Real, but unreachable (see section 0). Live: `GlassCircleButton(icon:"gobackward.10", fontSize:22, size:66)` (VideoPlayerView.swift:402-406), play/pause 84pt (:228), scrub knob etc. — all below the spec's 96pt. Action: delete `PlayerScreen.tsx` + the `isPlayerMode` branch in `main.tsx:10-14` (-536 lines, -16 inline styles) and the harness `player` scenario. (ARC/AV to confirm.)

### UI-17 Target sizes and text size vs spec (Minor, confirmed)
Measured with getBoundingClientRect (probe1): Library — Edit 74x34, tabs 92/84/61 x 38, Sort 170x36, profile chip 44x44, queue handle 45x76; Channel — Back 107x39, view toggles 40x38, search 425x23 (input), heart 34x34, filter pills 66x28; Editor — rename/delete 24x24, tabs 32px tall; 9/11 Library controls and 27/28 Channel controls are <44px, none of the buttons reach 96px (only cards, profile tiles 248x259, PIN boxes). Inline font sizes: 89 of 207 declarations are <=13px; tab buttons compute to 13px; `body` is 20px (index.css:62) vs the spec's 28pt. Spec drift is ~2.5-3x. Fix: "TV scale" (root font-size / `zoom` driven by window width or a setting) and bump primary controls to >=56px in viewer mode. Effort M.

### UI-18 4K @1x does not scale (Minor, suspected — depends on macOS scaling)
At 3840x2160 dpr 1: 4 channel cards at 396px occupy ~23% of the width, rest is dead (`shots/library-3840x2160.png`); h1 36px, tabs 13px. If a 4K TV is driven at 1x (common for generic HDMI TVs), the UI is tiny. At 1920x1080 it is fine (`shots/library-1920x1080.png`). Fix: fluid root scale (`html{font-size:clamp(16px, 0.9vw, 28px)}` + rem units) or WKWebView `pageZoom`. Effort M.

### UI-19 Queue-tray handle overlap (Minor, confirmed)
`QueueTray.tsx:~100-125` fixed `right:0; top:50%; z-index:60`, 45x76, shown on every viewer screen even when the queue is empty. It overlaps the sync-error banner edge (`shots/channel-error-1280x800.png`), the native scrollbar track, and the 1.03x hover-scaled right-column cards (`.lt-card:hover` index.css:~125). Fix: show only when count>0 or move into the top bar; leave a safe gutter. Effort S.

### UI-20 Nested backdrop-filter (Minor, suspected)
`.modal-backdrop` (index.css:373) and `.modal-panel` (:391) both use `backdrop-filter`; in Chromium the inner blur is a no-op so background text shows through the panel (`shots/ui-modal-addvideos.png`: "Wheels on the Bus" visible behind "YOUTUBE URLS"; `shots/pin-entry-1280x800.png`). WebKit behaviour unconfirmed. 54 `backdrop-filter` uses in total (ARC lane: cost at 4K). Fix: raise panel alpha to >=0.94 and drop the inner blur. Effort S.

### UI-21 Missing-tools state (Minor, confirmed)
`dependencyStatus` is consumed only at `Settings.tsx:301,312`; `shots/deps-missing-1280x800.png` is indistinguishable from a healthy library. Downloads fail silently for the family; the parent must find Admin → Settings. Cross-lane (UX/UPD).

### UI-22 Reduced motion (Minor, confirmed)
Zero `prefers-reduced-motion` handling (grep) despite hover scale 1.03, modalIn spring, 1.4s ambient cross-fades, `.reveal`, `.shake`. Fix: one `@media (prefers-reduced-motion: reduce)` block. Effort S.

## 2. State coverage (harness-proven)
| Component | hover | focus-visible | active | disabled | loading | empty | error |
|---|---|---|---|---|---|---|---|
| lt-btn-* | CSS yes | NO (UI-2) | transform | inline only, no `:disabled` rule in index.css | `.spinner` ad hoc (11 refs) | n/a | n/a |
| LtSelect / TopBarButton / TabBtn | JS style handlers | NO (outline:none) | no | n/a | n/a | n/a | n/a |
| ChannelCard / VideoCard | CSS scale 1.03 + JS | NO, not focusable (UI-1) | scale .97 | `isReady` gating | progress ring/bar | Library empty state OK (`library-empty-1280x800.png`) | error badge + retry |
| Inputs (.lt-input) | no | `:focus` ring OK | n/a | n/a | n/a | placeholder | PIN shake |
| Modals | n/a | no trap (UI-4) | n/a | submit disabled | n/a | n/a | n/a |
| Toast | click-dismiss | not focusable | n/a | n/a | n/a | n/a | error kind, 6s auto-dismiss |

## 3. Component inventory (distinct kinds, where defined, duplication)
| Kind | Defined / lives in | Instances | One-off re-implementations / notes |
|---|---|---|---|
| Buttons | `index.css:155-259` `.lt-btn-{primary,secondary,ghost,destructive}`, `.lt-btn-xs` (:733), `.lt-btn-retry` (:759), `.lt-row-btn` (:702), `.lt-view-toggle-btn` (:534) | 100 `<button>` | 29 fully inline; 49/69 class users override with inline style; icon buttons re-built ad hoc: TopBarButton (Library:801), EditCornerButton (ChannelCard), heart (VideoCard:~300), QueueTray close, ColorPicker/IconPicker swatches, page-size segmented (Channel:~650) |
| Modal / dialog | `.modal-backdrop`/`.modal-panel` (index.css:373-413) | 10 | 3 are components (AddChannel, AddVideos, RelocateLibrary); 7 inline (Channel x2, Editor, Profiles x2, QueueTray clear, PINEntry); each re-declares width/padding/title/button row |
| Select / dropdown | `components/LtSelect.tsx` | 3 uses (Library sort, Library autoplay, Channel sort) | native `<select>` in Settings; segmented page-size in Channel |
| Text input | `.lt-input` (index.css:260) | 5 of 14 inputs | search input (Channel:~780) and inline-rename inputs (Editor, Profiles) hand-styled; checkboxes native |
| Card | `.lt-card` (index.css:124), `ChannelCard.tsx`, `VideoCard.tsx` | ChannelCard (Library, Editor), VideoCard (Channel, Editor, QueueTray) | VideoListRow (Channel:1236), FeedRow (Library:696), Editor sidebar row, Profiles row, ProfilePicker tile each separate |
| Chip / pill / badge | none shared | ~10 | FavoritesFilterPill (Channel:1396), ProfileChip (Library:895), count chip (Channel header), count badge (ChannelCard:354), Source/Custom tag (Editor/Profiles), DepStatus (Settings), EditingBanner pill (Library:868) |
| Tab bar | `TabBtn` Library:471; `EditorShell.tsx` | 2 | two unrelated implementations (3 tabs each); no `role=tablist` |
| Search + sort | Channel inline (L746-850) + LtSelect | 1 | Library has sort only; no shared SearchField |
| Tray / drawer | `QueueTray.tsx` (417 lines) | 1 | always mounted (UI-3) |
| Toast | `ToastHost.tsx` | 1 | fine; `role=status`, 6s |
| Banner | Channel SyncError (:709), Library EditingBanner (:868) | 2 | inline each |
| Empty state | Library EmptyChannelsState (:562), PlaylistsPlaceholder (:607), Feed empty (:664), Channel no-results (:~935), Editor/Profiles empties | >=5 | same icon-tile + h2 + p composition re-typed |
| Avatar / pickers | `ProfileAvatar`, `ColorPicker`, `IconPicker` | shared | the good examples |
| Ambient background | `AmbientBackground.tsx` (Library) + Channel inline stack + `BgBlurLayer` | 2 impls | UI-15 |
| Progress | `.progress-bar-*` (index.css:427) | + inline bars in ChannelCard/VideoCard/QueueTray | |
| Icons | 102 inline `<svg>` | | Phosphor only in lib/profileIcons.ts |

## 4. Proposed minimal shared-component set (removes the most duplication)
1. `Button` — `variant: 'primary'|'secondary'|'ghost'|'destructive'`, `size: 'sm'|'md'|'lg'|'tv'`, `icon?`, `loading?`, `disabled?`; owns `:hover/:focus-visible/:disabled` in CSS (kills ~100 button sites + 54 JS hover handlers + UI-2).
2. `IconButton` — `label` (required → aria-label), `icon`, `tone: 'neutral'|'destructive'|'accent'`, `size`; replaces TopBarButton, EditCornerButton, close X's, heart.
3. `Modal` — `open`, `onClose`, `title`, `size: 'sm'|'md'|'lg'`, `dismissOnBackdrop?`, `initialFocusRef?`, children; built on `<dialog>` + MountWithExit; gives Esc, trap, restore, scrim (replaces 10 shells; fixes UI-4/20).
4. `ConfirmDialog` — `title`, `body`, `confirmLabel`, `tone`, `onConfirm`; replaces 4 destructive-confirm copies (Editor, Profiles x2, QueueTray, Channel).
5. `Select` (evolve `LtSelect`) — add `visibility:hidden` when closed, arrow-key/typeahead, `aria-activedescendant`; use for Settings quality and page-size.
6. `TextField` / `SearchField` — `label`, `value`, `onChange`, `leadingIcon?`, `error?`; `.lt-input` + focus ring; replaces search + inline rename inputs.
7. `Checkbox`/`Switch` — dark-themed, label-bound.
8. `Card` (focusable) — renders `<button>`/`<a>` root with `onActivate`, shared hover/focus/active styles; ChannelCard/VideoCard/FeedRow/VideoListRow compose it (fixes UI-1).
9. `Chip` — `tone`, `icon?`, `count?`, `selected?`, `onClick?` (pill, badge, tag, filter).
10. `Tabs` — `items`, `value`, `onChange`, proper `role=tablist/tab`; replaces TabBtn + EditorShell nav.
11. `EmptyState` / `Banner` — `icon`, `title`, `body`, `action?` and `tone`, `message`, `action?`.
12. `Gradients/tokens` — add `--focus-ring`, `--tap-min` (44/56/96 by `data-scale`), `--z-{tray,modal,toast}`, radius scale; delete 5 dead classes.
Order of work: tokens + `:focus-visible` (S) → Button/IconButton (M) → Modal/ConfirmDialog (M) → Card/Chip/Tabs (M) → Channel.tsx split (M).

## 5. Native chrome review (static)
| Item | Finding | Ref |
|---|---|---|
| Window style | titled/closable/miniaturizable/resizable; standard title bar, traffic lights never overlap web content; no vibrancy; title "LocalTube" | WebWindowController.swift:125-131 |
| Size | initial content 1280x800; `minSize` 900x600 (frame, ~572 content) | :132 |
| Frame autosave | `LocalTubeMainWindow`, set after `center()` | :135 |
| Fullscreen | no `.fullScreenPrimary` (suspected non-functional) | UI-8 |
| Spaces | main window default; player panel `.canJoinAllSpaces,.fullScreenAuxiliary` | PlayerOverlayController.swift:123 |
| Appearance | follows system, web UI dark-only | UI-6 |
| Close behaviour | red button quits app and cancels downloads | WebWindowController.swift:288; AppDelegate.swift:169,179-185 |
| Menu | App/Edit/View/Library/Window; no File/Help/Services; no ⌘W | UI-7 |
| Context menu | default WKWebView menu (no `contextmenu` handling in WebUI) | grep |
| Inspector | no `isInspectable` set (fine for release; no debug path) | grep |

## 6. Large-library (channel-large, 400 videos) — confirmed
Paged, not virtualised: 24 per page (17 pages), 33 `<img>`, 489 DOM nodes, one scroll container (`scrollHeight 2204`), sticky top bar + search bar. Prev/Next pager at page bottom (`shots/ui-large-scrolled.png`). DOM cost is fine; UX cost is paging (list jumps back to top on page change; no "N of 400" jump). Editor page-size options 16/24/36/48 (Channel.tsx:~650). Scroll container and sticky behave correctly; chrome height is the issue (UI-5).

## 7. Needs a real Mac to confirm
* UI-6 light-mode title bar/flash and native control colours.
* UI-8 whether the green button / ⌃⌘F enter fullscreen without `.fullScreenPrimary`.
* UI-7 Undo/Redo enabled state; ⌘C/⌘V/⌘A/⌘X inside WKWebView text fields (PIN, search, URLs).
* UI-1/2 whether Tab reaches buttons at all in WKWebView without Full Keyboard Access / `tabFocusesLinks`.
* UI-20 nested backdrop-filter rendering in WebKit; blur cost at 4K.
* UI-18 whether a 4K TV runs at dpr 1.

## 8. Cross-lane notes
* AV: `PlayerScreen.tsx` is dead; the live player is SwiftUI `PlayerControlsOverlay` (VideoPlayerView.swift:354) — brief's "Player/** dead" is wrong for this file.
* SEC/UX: ⌘, opens Settings in Viewer mode (AppDelegate.swift:194 vs its comment); Settings has a viewer fallback route (App.tsx).
* ARC: Tailwind 4 imported with 0 utility classes; `@phosphor-icons/react` used by one file; 54 backdrop-filters; `will-change: transform` on every `.lt-card`.
* DSG: tertiary text (#55555f) on tinted ambient backgrounds (Feed meta, "4 channels", Sort label) is ~2.3:1; no light theme.
* UX: no arrow-key navigation anywhere in browsing screens; missing-tools state invisible to viewers.
