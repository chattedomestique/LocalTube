# TYP — Typography and wireframe hierarchy audit (LocalTube v1.0.37)

Lane: type system, fonts, ten-foot legibility, hierarchy and spacing per screen. Evidence: source in
`/home/user/LocalTube/WebUI/src`, computed styles from the mock-bridge harness at 1920x1080 / 3840x2160,
screenshots in `/tmp/claude-0/-home-user-LocalTube/411d552b-4a76-5096-8a3a-c28d66f3586b/scratchpad/work-typ/shots/`.
**Revision note (PM correction):** the live player overlay is SwiftUI (`VideoPlayerView.swift:354`), not the React `PlayerScreen.tsx`; section 1.7 and the Player wireframes now use the SwiftUI source, TYP-5/TYP-4/TYP-8 and the cross-lane notes were rewritten, and the React-player harness screenshot was dropped.
Raw measurement: `.../work-typ/m1080.json` (every visible text node: size, weight, family, line-height, tracking, colour, box).

## 0. Verdict

LocalTube's type is a well-behaved but entirely desktop-scale system: one system font, no web-font risk, sensible
weights, a clear top-level ranking on the picker, library and player. It is not a ten-foot UI in its React screens: at 1080p, 77-100% of
text nodes on the viewer screens are 17 px or smaller (median 15-17 px), video titles are 17 px (spec: 28), labels
and chips are 12-13 px (spec: 24), and nothing in the app can be scaled (no rem, no zoom, no text-size setting).
The scale itself has no discipline (22 distinct font sizes, 12 line-heights, 8 tracking values, Tailwind loaded but
unused), and the long-title, tabular-number and error-text details are not handled. The live player is SwiftUI and is only half ten-foot (28 pt timecodes next to a 22 pt title and 14 pt / 36 pt secondary controls), so the app is inconsistent with itself, not just with the spec. The fix is small and mostly
mechanical: one scale dial (`WKWebView.pageZoom`) plus a role-token pass, not a rewrite.

## 1. (a) Type audit

### 1.1 Method
- Source grep of every `fontSize`, `fontWeight`, `lineHeight`, `letterSpacing`, `fontFamily` in `WebUI/src/**/*.tsx` and `index.css`.
- `page.evaluate` over every visible text node in the 18 harness scenarios at 1920x1080 (about 840 nodes). The harness `openPlayer()` React overlay
  (`PlayerScreen.tsx`) is **excluded: it never ships** (nothing in Swift sets `__playerMode`; the live overlay is SwiftUI, measured from source in section 1.7). Chromium maps `system-ui`/`-apple-system` to **Inter** on this Linux box (`fc-match system-ui` ->
  Inter-Regular.otf), so all screenshots are Inter, not SF. Sizes/weights are exact; glyph widths are approximate.
- Tailwind: `@import "tailwindcss"` is the first line of `index.css`, but `className` values are only `lt-*` custom
  classes, `spinner`, `reveal`, `screen-enter`, `line-clamp-2`. There are zero `text-*`, `font-*`, `leading-*`,
  `tracking-*` utilities and zero `rem` values in tsx. Every size is an absolute px literal.

### 1.2 Source-level inventory (confirmed)

| Property | What is actually used | Count / irregularity |
|---|---|---|
| font-size literals (inline) | 9, 10, 11, 12, 13, 14, 15, 16, 17, 18, 20, 22, 24, 26, 28, 30, 32, 34, 36, 40, 42, 48 | **22 distinct values**, about 207 inline declarations + about 13 in `index.css`. Eight consecutive 1-px steps (11-18). Most used: 13 (44x), 16 (31x), 12 (28x), 14 (18x), 11 (15x) |
| font-size in CSS | body 20 (`index.css:60`); `.lt-btn-*` and `.lt-input` 18 (`:159,186,214,240,267`); `.lt-label` 15 (`:287`); `.lt-editor-toggle` 16 (`:507`); `.lt-btn-xs` 14 (`:734`); `.lt-btn-retry` 15 (`:760`) | Components then override these inline with 16/13 (e.g. `Channel.tsx:520-629` buttons `fontSize: 16`), so the class defaults are not the real values |
| font-weight | 600 (32x), 700 (16x), 500 (10x), 800 (6x), plus default 400; h1-h6 forced to 600 (`index.css:80`) | Five weights; 800 is used for page titles on some screens (`Library.tsx:385`, `Channel.tsx:489`, `ProfilePicker.tsx:90`) and 600/700 on others |
| line-height | 1, 1.1, 1.2, 1.3, 1.35, 1.4, 1.45, 1.5, 1.6, 1.8, '28px', '36px' | 12 variants; body 1.5 (`index.css:61`) |
| letter-spacing | -0.03em, -0.02em (+ global h1-h6), -0.01em (6x), -0.005em, 0.02em, 0.04em, 0.06em (`.lt-label`), 0.2px, -0.3px | 9 values, mixed em and px |
| font-family | one sans stack (`index.css:59`) + `ui-monospace, monospace` (about 10 inline uses, 3 spellings) + two stray stacks: `-apple-system, BlinkMacSystemFont, sans-serif` (`App.tsx:51`), `-apple-system, system-ui, sans-serif` (`PlayerScreen.tsx`, dead code) | 1 UI family (good), 3 live stack spellings (bad) |
| font-variant-numeric | **none in the React UI** (the only hits are in dead `PlayerScreen.tsx:500,524`); the live SwiftUI player uses `.monospacedDigit()` (`VideoPlayerView.swift:301,305`) | Not used on durations, counts, percentages, stats |
| text-wrap / hyphens / overflow-wrap | none anywhere | `text-wrap: balance/pretty` unused; `overflow-wrap` unused |
| Truncation | `.line-clamp-2` on video titles (3 uses), nowrap+ellipsis on list rows; live player title `lineLimit(1)` (`VideoPlayerView.swift:390`) | No `title=` tooltip on any video title (grep `title={video.title}` = 0) |
| Spacing (gap) | 144 `gap:` declarations: 6 px x20, 10 px x21, 14 px x11 ... | **76 of 144 (53%) are not multiples of 4.** Grid gaps differ: channel video grid 22 (`Channel.tsx:954`), library channel grid 24 (`Library.tsx:397`) |

### 1.3 Computed sizes at 1920x1080 (measured, all scenarios, text nodes only)

| Size / weight | Nodes | Where (examples) |
|---|---|---|
| 10 / 700 | 32 | queue tray durations (`QueueTray.tsx:384`); plus 9 px list-view duration (`Channel.tsx:1308`, not in a scenario shot) |
| 11 / 400 | 47 | card error text (`VideoCard.tsx:254`), mono IDs, queue/tray meta |
| 12 / 400-700 | 68 | filter chips "All (14)" (`Channel.tsx:1429`), "Show in Finder", onboarding footer, queue |
| 13 / 400-600 | 145 | Admin/Settings/Edit, Sort, PIN subtitle, Settings descriptions, queue titles |
| 14 / 400-700 | 80 | tabs "Channels/Playlists/Feed", "Resume at 1:14", empty-state copy |
| 15 / 400-700 | 98 | duration badges (`VideoCard.tsx:407`), "Downloading...", Retry |
| 16 / 400-700 | 86 | count badge, "Up Next", Edit, pagination |
| 17 / 400-500 | about 180 | **video-card titles** (`VideoCard.tsx:480`), "12 of 14 ready" |
| 18 / 400-600 | 26 | buttons, "4 channels", Library back link |
| 20 / 400-600 | 5 | picker subtitle, PIN title |
| 22 / 600-700 | 5 | profile names (`ProfilePicker.tsx:145`), Editor profile header (`Profiles.tsx:277`) |
| 26 / 700 | 26 | channel-card names (`ChannelCard.tsx:422`) |
| 28 / 600-800 | 12 | wordmark, channel title (`Channel.tsx:488`), PIN setup |
| 30-34 / 800 | 2 | load-error / folder-missing titles |
| 36 / 600-800 | 6 | "Channels" (`Library.tsx:385`), "No channels yet" |
| 42 / 700 | 1 | onboarding wordmark |
| 48 / 800 | 1 | "Who's watching?" (`ProfilePicker.tsx:89`) |

Share of text at <=14 px / <=17 px / >=28 px (viewport 1920x1080, text on screen):

| Screen | Nodes | <=14 px | <=17 px | >=28 px | Max | Median |
|---|---|---|---|---|---|---|
| Library | 43 | 23% | 77% | 2 | 36 | 17 |
| Channel (grid) | 45 | 33% | 96% | 1 | 28 | 15 |
| Editor > Channels | 88 | 49% | 100% | 0 | 17 | 15 |
| Editor > Settings | 54 | 93% | 100% | 0 | 15 | 12 |
| Onboarding | 14 | 36% | 64% | 1 | 42 | 17 |
| Profile picker | 54* | 6% | 67% | 3 | 48 | 17 |
| PIN entry (over library) | 46* | 24% | 74% | 2 | 36 | 17 |

\* includes the Library that stays mounted underneath the picker/PIN overlay (see cross-lane note).

### 1.4 Spec drift (`LocalTube_Parameters.md:40-50`, `:274`)

| Spec rule | Reality | Verdict |
|---|---|---|
| Body >= 28 pt | body 20 px (`index.css:60`); real reading text 13-17 px | 0.46-0.61x of spec. **Drifted** |
| Labels >= 24 pt | `.lt-label` 15; chips 12; buttons 13-18; tabs 14 | 0.5-0.75x. **Drifted** |
| Titles 36-48 pt bold | page title 36/800 (Library), 28/800 (Channel), 26/700 (channel cards), **17/500 (video titles)** | Only the picker (48) and Library heading (36) comply |
| SF Rounded | `-apple-system, 'SF Pro Display', 'SF Pro Text', system-ui ...` (`index.css:59`) = SF Pro, not Rounded | **Not implemented** |
| 96x96 pt targets | heart/queue buttons 34x34 (`VideoCard.tsx:293,337`), view toggles 40x38 (`index.css:535`), row buttons 24x24 (`:703`) | UI lane; type-relevant because label sizes follow target sizes |
| No small print | 9-12 px used 100+ times per screen set | **Drifted** |
| Icons >= 40 pt | icons 10-22 px in cards/badges; live player symbols 16-34 pt | **Drifted** |
| Ten-foot scale as code | `Views/Shared/TenFootStyles.swift:31-44` encodes the spec literally: ltHero 48 / ltTitle 36 / ltHeadline 28 / ltBody 28 / ltCaption 24, all `design: .rounded`, plus `LT.minTargetSize = 96` (`:49`) | The spec exists as Swift tokens, but only dead views and the resume prompt use them. **Neither the React UI nor the live player uses these tokens** |
| Live player (SwiftUI) | Timecodes 28 pt (meets body), knob 24 pt, transport 66/84 pt; but title 22 pt, Back 15 pt in a 36 pt-high button, autoplay label 14 pt, loop/back targets 36 pt (details in 1.7) | **Half ten-foot: inconsistent with the rest of its own overlay and with the React UI** |

CSS px == pt in a WKWebView, so "28 pt" means 28 CSS px at the app's window scale.

### 1.5 Ten-foot legibility (calculation)

Geometry: 55" 16:9 TV = 0.685 m tall; at 1080 pt rows the pixel pitch is 0.634 mm; at 3 m one pt subtends
0.727 arcmin. Cap-height of SF/Inter = 0.727 em, so **cap-height (arcmin) = 0.529 x font-px** on that TV.
Reference points: 20/20 acuity limit = 5'; tvOS floor (23 pt) = 12'; tvOS body (29 pt) = 15.3'; print body from 40 cm = 20-21'.

| Setup | arcmin per px | Min font-px for cap 12' (glance) | 16' (comfortable) | 20' (sustained) |
|---|---|---|---|---|
| 55" TV, 1080p points, 3 m | 0.727 | **23** | **30** | 38 |
| 65" TV, 1080p points, 3 m | 0.859 | 19 | 26 | 32 |
| 100" projector, 1080p, 4 m | 0.991 | 17 | 22 | 28 |
| 55" TV driven at 3840x2160 @1x (CSS px = 4K px) | 0.363 | **45** | 61 | 76 |
| 27" desktop 1440p, 65 cm (for comparison) | 1.235 | 13 | 18 | 22 |

What the React UI actually shows at 55"/3 m (cap height): filter chips 12 px = 6.3'; labels 13 px = 6.9';
**video titles 17 px = 9.0'**; channel-card names 26 px = 13.7'; "Channels" 36 px = 19'; picker H1 48 px = 25'. The live SwiftUI player, same geometry (points):
timecodes 28 pt = 14.8' (meets the spec), title 22 pt = 11.6', Back label 15 pt = 7.9', autoplay label 14 pt at 55% white = 7.4', the "10" inside the skip symbol
(suspected 7-9 pt tall) = about 5-6.5'; transport 66 pt subtends 0.8 deg vs 1.16 deg for the spec's 96 pt, Back/loop (36 pt) 0.43 deg.
So only headings clear the 12' glance floor; everything a child must read to choose a video (titles, durations,
resume markers) is at 7-9'. On a 14" MacBook at 50 cm the same 13 px text is 11.7' and fine: the UI is calibrated for a desk.
The spec's 28/24 pt are correctly calibrated for a 55" TV at 3 m (28 px = 14.8').

If macOS drives the TV at 3840x2160 points (@1x) instead of 1920x1080 @2x, every size above halves
(17 px title = 4.5'); the picker is the only thing that survives. The app cannot detect the physical screen size.

### 1.6 Decision: TV app or desktop app?

**Today it is a desktop app with a TV-capable layout skeleton.** Evidence: default window 1280x800, min 900x600
(`Sources/LocalTube/Bridge/WebWindowController.swift:129-132`), all sizes px, no scale control anywhere
(grep of `Bridge/` and `App/` for `pageZoom|magnification|textZoom` = 0 hits), videos 17 px, admin UI 11-13 px. The product
statement ("mostly on a TV/projector") is not delivered by the type. Recommendation: stay desktop-first but add one
"Display size" dial (Computer 1.0 / Large 1.25 / TV 1.6 / Big 2.0 or 3.0 for 4K@1x), default Computer, offered during
onboarding and in Settings and via View menu Cmd+ / Cmd- / Cmd-0. Do not maintain two UIs.

### 1.7 Live player overlay (SwiftUI, measured from source in points)

Correction folded in from the PM: the shipped player controls are `PlayerControlsOverlay` (`Player/VideoPlayerView.swift:354`), hosted in an
`NSHostingView` above the `AVPlayerView` (`Bridge/PlayerOverlayController.swift:144`). The React `PlayerScreen.tsx` is dead code. Values are literals in
the Swift source (macOS has no Dynamic Type, so points are final); not run on a Mac.

| Element | Size / weight / frame (pt) | Source | Ten-foot reading |
|---|---|---|---|
| Title | 22 semibold, SF Pro (default design), `lineLimit(1)`, white | `:388-391` | 11.6' cap at 55"/3 m; spec 36-48 -> **below spec**; long titles cut at ~65 chars |
| Back button | 88 x 36, chevron 13 + "Back" 15 semibold, radius 10 | `:313-334` | 36 pt target (spec 96); label 7.9' -> **below spec** |
| Skip -10 / +10 | 66 pt circle, SF Symbol `gobackward.10` / `goforward.10` at 22 pt semibold | `:402,406` | 66 < 96; the built-in "10" numeral is small (suspected 7-9 pt) |
| Play / pause | 84 pt circle, symbol 34 pt semibold, spacing 44 | `:228,221,401` | 84 < 96, closest to spec |
| Timecodes | **28 medium, `.monospacedDigit()`**, white 95% | `:301,305` | 14.8' cap = **meets the spec body size**, tabular already |
| Scrub bar | track 6 pt (10 hover/drag), knob 24 pt (always visible, "10-ft UX"), hit height 32, gold `Color.ltAccent` fill | `:261-297` | Good; accent is gold #FFBE00 (`TenFootStyles.swift:14`) while the React UI is purple |
| Volume | speaker icons 18 pt at 60% white, `Slider` max 200 (native size) | `:418-432` | small; duplicates system volume |
| Autoplay button | icon 16 + label 14 semibold, height 36, pad 12, 55% white when "Off" | `:480-492` | 7.4' cap, **below spec** |
| Loop button | icon 18 medium in a 36 x 36 frame | `:458-466` | 36 pt target |
| Margins / scrims | 48 pt sides, 40 pt top/bottom; scrims 160 / 170 pt | `:394-395,438-439,370,377` | 2.5% of 1920 (TV title-safe ~5%) |
| Resume prompt (`ResumePromptOverlay`, `:125-163`) | title `ltHeadline` 28 rounded, body `ltBody` 28, buttons `LTButtonStyle` 28 / 96 pt min | uses `TenFootStyles` | The only ten-foot-compliant player UI, but only reachable via `VideoPlayerView` <- `ViewerRootView` (legacy), not the live `PlayerOverlayController` |

**Inconsistency to call out:** the Swift side already holds the ten-foot scale (`TenFootStyles.swift`: 48/36/28/28/24 rounded, 96 pt targets) and the live
overlay half-follows it (28 pt timecodes, always-visible knob), while the React UI ignores it (17 px titles, 12-13 px labels) and the player's own title and buttons
revert to desktop sizes (22 / 14-15 pt, 36 pt targets). Three surfaces, three scales, no shared token table.

## 2. Font loading and fidelity

- **What renders on the Mac (confirmed from source, rendering suspected):** `-apple-system` first in `index.css:59`
  -> SF Pro with automatic optical sizing (Text below ~20 pt, Display above). `'SF Pro Display'`/`'SF Pro Text'`
  by name are dead entries: Apple reserves SF Pro/Rounded/Mono for system use and exposes them only through generic
  keywords ([Apple docs](https://developer.apple.com/documentation/technologyoverviews/fonts.md)).
- **No web font, no `@font-face`, zero font bytes**: bundle is `index-*.css` 28 KB + `index-*.js` 528 KB. No FOUT/FOIT
  risk, no `file://` font-path risk (`loadFileURL` at `WebWindowController.swift:258`, `base: './'` in `vite.config.ts`).
  If a webfont is ever added: relative `url()` under `assets/`, `font-display: block` for the tiny UI subset,
  preload via `<link rel="preload" as="font" crossorigin>` is unnecessary on file://.
- **SF Rounded (spec) works in WKWebView on macOS 14:** `font-family: ui-rounded` is a Safari/WebKit generic
  (introduced with Safari 13.1; [caniuse](https://caniuse.com/mdn-css_properties_font-family_ui-rounded) shows no Chrome/Firefox support). It maps to
  SF Pro Rounded; it cannot be bundled (licence) and cannot be referenced by name. Fallback chain: `ui-rounded,
  system-ui, -apple-system, ...`. **The Chromium harness will ignore `ui-rounded` and render Inter**, so the rounded
  look can only be verified on a Mac.
- **Chromium vs WebKit differences to expect (suspected):** (1) `-webkit-font-smoothing: antialiased` (`index.css:62`)
  is honoured on macOS but ignored on Linux Chromium, so real macOS text is lighter and thinner than the harness shots,
  making 13 px `#8e8e99` secondary text less legible than it looks here; (2) Inter is not SF: widths differ by a few
  percent, so clamp/ellipsis points will move; (3) SF applies size-dependent tracking itself, so the explicit
  `-0.02em` on every h1-h6 (`index.css:81`) plus `-0.01em` inline on titles tightens twice at 26-48 px;
  (4) `text-rendering: optimizeLegibility` (`index.css:64`) is a no-op-to-small cost on WebKit.
- **rem vs px:** 0 rem in tsx/css; every size is px. WKWebView has no browser zoom UI and (suspected) Mac "Larger Text" does not
  reach web content on macOS 14, so users cannot enlarge text at all. Apple documents `WKWebView.pageZoom` (macOS 11+,
  "equivalent to setting the CSS zoom property on all page content",
  [Apple docs](https://developer.apple.com/documentation/webkit/wkwebview/pagezoom.md)); it is the right no-rewrite dial.
- **SF Rounded exists only in Swift tokens that are not live:** `design: .rounded` appears in `Views/Shared/TenFootStyles.swift:33-43` (dead views + resume prompt). The live overlay uses `.system(size:weight:)` = SF Pro (`VideoPlayerView.swift:301,388`) and the React UI uses `-apple-system`; **no live surface renders SF Rounded**.
- **Tabular figures:** SF has `tnum` (SwiftUI uses `.monospacedDigit()` for the player timecodes); whether SF Rounded keeps them through `font-variant-numeric: tabular-nums`
  needs a Mac check. Inter (harness) supports it.

## 3. Hierarchy per screen (what the eye hits, measured)

Screens: `shots/library-1920x1080.png`, `channel-1920x1080.png`, `profile-picker-1920x1080.png`,
`editor-*-1920x1080.png`, `pin-entry-1920x1080.png`, `onboarding-1920x1080.png`, `stress-*.png`.

- **Profile picker** (best TV screen): 1) three saturated 172 px avatars, 2) "Who's watching?" 48/800, 3) names 22/700.
  Ranking is right. Issues: names are 22 px at 78% alpha (`ProfilePicker.tsx:145-148`), 0.13x the avatar, no wrap/ellipsis
  for long names (grid `minmax(180px,1fr)`, `:103` - suspected overflow, untested); `outline: 'none'` on the tile (`:132`) leaves no
  focus ring; Admin/Settings corner pills 13/600 (`:182`).
- **Library:** 1) "Channels" 36/800 and the 28/700 wordmark compete (two H1-level items within 120 px), 2) cards with 26/700 names
  over gradient, 3) tabs 14/600. Alignment: left edges are 40 (logo) / 54 (tab text) / 44 (heading and cards); right edges
  1880 vs 1876. At 4 channels, 46% of the screen is empty while video text is tiny: the density is wrong in both directions.
- **Channel:** banner 300 px + header 80 px + search/filters ~105 px push the **first video row to y=529 (49% of 1080)**.
  Eye order: 1) banner art (no text), 2) thumbnails, 3) channel title. Smallest viewer text is here: chips 12 px, sort 13 px.
  Cards in a row have ragged heights (1-line vs 2-line vs "Resume" line; row 1 spans ~205-258 px). Resume is a 14 px blue
  text line; duration badges are 15/700 without tabular figures (`VideoCard.tsx:407`).
- **Channel list view:** titles 13/500, duration 9/700 (`Channel.tsx:1308,1320`), status 11 px, a ~1700 px empty gulf between title
  and the status icon, no 2-line clamp (a 200-char title is one 1380 px line at 1920). The least TV-suitable view.
- **Editor / Settings:** desk UI, internally consistent but 11-13 px (93% of Settings text <=14 px); the Download Quality select
  inherits `.lt-input` 18 px next to 13 px labels and its value is clipped ("Best Available (up to"), three button sizes in one card.
- **PIN entry / setup:** dialog 20/600 title, 13 px hint, 28 px digits, Cancel 18 px: OK for a parent at the keyboard, small on TV.
- **Onboarding:** wordmark 42/700 (third different wordmark size: 28 / 42 plus picker H1 48), step titles 15/600, hints 13, footer 12 px.
- **Queue tray:** header 16/700, meta 12, titles 13/500, duration 10/700, empty copy 14 px (`QueueTray.tsx:129,197,384,392`).
- **Player overlay (live SwiftUI, see 1.7):** 1) transport cluster 66/84/66 pt, 2) scrub bar + 28 pt timecodes, 3) title 22/600 one line. Order is right;
  the scale is mixed: big clock and knob, small title and secondary controls; margins 48/40 pt = 2.5% of 1920 (TV title-safe ~5%).
- **Long titles (stress test, `shots/stress-long-titles-1920x1080.png`):** 200-char title clamps cleanly at 2 lines; **unbroken
  strings (URL-like, single long word) are clipped mid-glyph with no ellipsis** (title box scrollWidth 680/555 vs clientWidth 257);
  CJK and emoji titles wrap fine. No full-title reveal exists in viewer mode (no tooltip; player is 1 line).
- **Empty/error copy:** empty states are kid-appropriate ("Ask a grown-up to add channels in Admin", 20 px in Library, but 14-16 px in the queue tray and Playlists/No-videos states);
  channel sync banner shows "Sync failed" + a raw monospace error string to viewers (`Channel.tsx:727-736`); the per-video error text
  is 11 px inside a card dimmed to opacity 0.4 (`VideoCard.tsx:121,254`) so both the message and the Retry button are nearly invisible
  (`shots/channel-error-1920x1080.png`, centre card).

## 4. (b) Recommended type system

### 4.1 Principles
1. **One dial, not two UIs.** Design roles once at 1x (desktop). TV = the same roles zoomed by `WKWebView.pageZoom`
   (1.6 recommended for a 55" TV at 3 m). Spacing, hit areas, icons and grid reflow scale with it for free; no px rewrite is needed in phase 1.
   The live player overlay is SwiftUI, so `pageZoom` does not reach it: it needs the same `uiScale` as a multiplier on its literals (4.5).
2. **Six roles + Numeric + Mono** replace 22 sizes. Floor at 1x: 14 px for anything a child reads (-> 22 px on TV, = tvOS floor 23);
   13 px only for admin mono/IDs.
3. **Four weights** (400/500/600/700) plus 800 for Display only. Hierarchy comes from size (4-6 px steps), then weight, then colour.
4. **Tokens in rem, scale applied by zoom.** Authoring in rem keeps a later CSS-only dial (`html { font-size: calc(16px * var(--ui-scale)) }`) possible; never apply both pageZoom and the CSS dial.
5. **Scale / ratio:** hand-set, roughly Major Third (1.25) from Body upward and Major Second (1.125) below, rounded to even pixels
   so TV values land on whole points: 14, 16, 18, 22, 30, 40. This is deliberate: a pure ratio would give 5 near-identical sizes
   between 13 and 18, which is today's problem.

### 4.2 Roles (1x = computer; TV = x1.6 = 55" at 3 m; cap-height arcmin on that TV in the last column)

| Role | Desktop size / weight / line-height / tracking | TV (x1.6) size | Cap' @55"/3 m | Use |
|---|---|---|---|---|
| **Display** | 40 / 800 / 1.1 / -0.015em | 64 | 34' | "Who's watching?", onboarding wordmark |
| **Title** | 30 / 700 / 1.15 / -0.01em | 48 | 25' | Screen titles ("Channels", channel name), empty/error titles |
| **Headline** | 22 / 700 / 1.2 / -0.005em | 35 | 19' | Channel-card name, profile name, modal title, section header, player title |
| **Body** | 18 / 500 (titles) or 400 (prose) / 1.35 or 1.5 / 0 | 29 | 15' | Video titles, list rows, paragraphs, input text |
| **Label** | 16 / 600 / 1.25 / +0.005em | 26 | 13.5' | Buttons, tabs, chips, nav, sort, field labels (all-caps variant: 14 / 600 / +0.06em) |
| **Caption** | 14 / 500 / 1.35 / +0.01em | 22 | 11.9' | Meta ("12 of 14 ready", "Resume at"), helper text, errors |
| **Numeric** | 16-18 / 600-700 / 1 / +0.01em, `tabular-nums` | 26-29 | 13.5-15' | Durations, counts, percentages, timecodes (an overlay of Label/Body) |
| **Mono** | 13 / 400 / 1.4 / 0 | (admin only) | - | IDs, paths, version; admin screens only |

Tracking note: remove the global `h1..h6 { letter-spacing: -0.02em }` (`index.css:81`) when switching to system fonts that already track by size.
Weight-contrast rule: adjacent tiers differ by >= 4 px or by >= 200 weight, never by 1 px.
Colour tiers (DSG owns values): primary / secondary / tertiary; do not use tertiary for text a child must read.

Resulting sizes at 1080p, TV 1.6: video titles 29 px (cap 15'), labels 26 px, caption 22 px - all above the 12' glance floor; the picker heading 64 px.

### 4.3 Font stack

```css
--font-ui:   ui-rounded, system-ui, -apple-system, "Helvetica Neue", "Apple Color Emoji", "Segoe UI Emoji", "Noto Color Emoji", sans-serif;
--font-mono: ui-monospace, "SF Mono", Menlo, monospace;
```
Rounded for the viewer surfaces (picker, library, channel, queue; in SwiftUI `design: .rounded` on the player title, labels and timecodes); optional plain `system-ui` for Editor/Settings
(`[data-mode="editor"] { --font-ui: system-ui, -apple-system, ... }`) if SF Rounded looks juvenile in dense admin tables - decide on a Mac.

### 4.4 Paste-ready CSS (replace `index.css:56-86`; keep the `lt-*` component classes and map their sizes to the tokens)

```css
:root {
  /* font stacks */
  --font-ui:   ui-rounded, system-ui, -apple-system, "Helvetica Neue", "Apple Color Emoji", "Segoe UI Emoji", "Noto Color Emoji", sans-serif;
  --font-mono: ui-monospace, "SF Mono", Menlo, monospace;

  /* role sizes (1x design values; TV is the same tokens under pageZoom 1.6) */
  --fs-display:  2.5rem;     /* 40 */
  --fs-title:    1.875rem;   /* 30 */
  --fs-headline: 1.375rem;   /* 22 */
  --fs-body:     1.125rem;   /* 18 */
  --fs-label:    1rem;       /* 16 */
  --fs-caption:  0.875rem;   /* 14 */
  --fs-mono:     0.8125rem;  /* 13 (admin only) */

  --lh-tight: 1.15;  --lh-snug: 1.25;  --lh-title: 1.35;  --lh-prose: 1.5;
  --ls-display: -0.015em;  --ls-title: -0.01em;  --ls-headline: -0.005em;  --ls-label: 0.005em;  --ls-caption: 0.01em;  --ls-caps: 0.06em;

  /* 4-pt spacing scale + one page gutter */
  --sp-1: 4px;  --sp-2: 8px;  --sp-3: 12px;  --sp-4: 16px;  --sp-5: 24px;  --sp-6: 32px;  --sp-7: 48px;
  --gutter: 40px;           /* wordmark, tabs, titles, grids all start here */
}

body {
  font-family: var(--font-ui);
  font-size: var(--fs-body);   /* was 20px */
  line-height: var(--lh-prose);
  font-synthesis: none;
  -webkit-font-smoothing: antialiased;
}
h1, h2, h3, h4, h5, h6 { font-weight: 700; letter-spacing: 0; }   /* roles set size/tracking */

/* role classes */
.t-display  { font-size: var(--fs-display);  font-weight: 800; line-height: 1.1;            letter-spacing: var(--ls-display); text-wrap: balance; }
.t-title    { font-size: var(--fs-title);    font-weight: 700; line-height: var(--lh-tight); letter-spacing: var(--ls-title);   text-wrap: balance; }
.t-headline { font-size: var(--fs-headline); font-weight: 700; line-height: 1.2;            letter-spacing: var(--ls-headline); }
.t-body     { font-size: var(--fs-body);     font-weight: 500; line-height: var(--lh-title); }
.t-prose    { font-size: var(--fs-body);     font-weight: 400; line-height: var(--lh-prose); max-width: 62ch; text-wrap: pretty; }
.t-label    { font-size: var(--fs-label);    font-weight: 600; line-height: var(--lh-snug);  letter-spacing: var(--ls-label); }
.t-caption  { font-size: var(--fs-caption);  font-weight: 500; line-height: var(--lh-title); letter-spacing: var(--ls-caption); }
.t-caps     { font-size: var(--fs-caption);  font-weight: 600; letter-spacing: var(--ls-caps); text-transform: uppercase; }
.t-mono     { font-family: var(--font-mono); font-size: var(--fs-mono); line-height: 1.4; }
.t-num      { font-variant-numeric: tabular-nums; font-weight: 700; letter-spacing: 0.01em; line-height: 1; }  /* durations, %, counts */

/* wrapping / truncation utility set (replaces .line-clamp-1/2 at index.css:449-461) */
.clamp-1 { display: block; min-width: 0; white-space: nowrap; overflow: hidden; text-overflow: ellipsis; }
.clamp-2, .clamp-3 { display: -webkit-box; -webkit-box-orient: vertical; overflow: hidden; min-width: 0; overflow-wrap: anywhere; }
.clamp-2 { -webkit-line-clamp: 2; }
.clamp-3 { -webkit-line-clamp: 3; }
.slot-2  { min-height: calc(2 * 1.35em); }          /* reserve two title lines so a grid row's cards align */
.t-balance { text-wrap: balance; }                   /* Safari 17.5+; harmless no-op on macOS 14.0-14.4 */
.t-pretty  { text-wrap: pretty; }                    /* Safari 26; progressive enhancement */
.t-wrap-anywhere { overflow-wrap: anywhere; }        /* long URLs / unbroken titles */
```

Usage examples: video card title `className="t-body clamp-2 slot-2"` (+ `title={video.title}` for pointer users); duration badge
`className="t-label t-num"`; channel-card name `className="t-headline clamp-2"`; list-row title `t-body clamp-2`.

### 4.5 Applying the TV scale (Swift side, static review only)

```swift
// WebWindowController: one UserDefaults value "uiScale" in {1.0, 1.25, 1.6, 2.0}
mainWebView.pageZoom = CGFloat(scale)        // macOS 11+, equivalent to CSS zoom on all page content

// PlayerOverlayController hosts SwiftUI (NSHostingView), not a WebView: pageZoom does not apply.
// Give PlayerControlsOverlay a metrics struct holding 1x values and multiply by the same uiScale:
struct PlayerMetrics {
    let s: CGFloat                                   // uiScale (1.0 desktop, 1.6 TV)
    var title: CGFloat       { 22 * s }              // Headline, lineLimit(2)
    var timecode: CGFloat    { 18 * s }              // Numeric (today 28 pt literal; 28 * 1.6 would balloon to 45)
    var transportSide: CGFloat { 66 * s }            // 106 pt on TV, play 84 * s = 134
    var skipSymbol: CGFloat  { 30 * s }              // today 22 pt -> the built-in "10" becomes legible
    var secondaryTarget: CGFloat { 40 * s }          // Back / autoplay / loop, today 36 pt
    var label: CGFloat       { 16 * s }              // Back, autoplay (today 15 / 14 pt)
    var margin: CGFloat      { 48 * s }
}
// usage: .font(.system(size: m.title, weight: .semibold, design: .rounded)) ... instead of literals at VideoPlayerView.swift:388,301,402,328,485
```
Guards: (1) cap so `window.innerWidth >= ~900 css px` (1280 pt window at 1.6 = 800 css px, narrower than the 900 pt design minimum;
only offer >1.25 in full screen or >= 1600 pt wide windows); (2) View menu items Cmd-+ / Cmd-- / Cmd-0 with a checkmarked
"Computer / Large / TV / Big" submenu; (3) first-run onboarding step "Is this a computer or a TV?"; (4) suggest TV when
`NSScreen` is an external display >= 1920 pt wide in full screen (physical size from `CGDisplayScreenSize` is unreliable on HDMI TVs;
suspected). 4K@1x needs about x3: tell the user to pick the 1920x1080 (HiDPI) display mode or offer a "Big TV x3" notch.
Phase 2 (M): codemod 207 inline `fontSize` and the 13 CSS sizes to role classes; this makes the zoom unnecessary for typography and lets TV use different values where x1.6 is not ideal.

## 5. (c) Wireframes (ASCII, 100 columns; 1 col = 19.6 px and 1 row = 38 px at 1920x1080; as-is values are measured (web) or read from source (SwiftUI player))

Legend: `size/weight` in CSS px at 1920x1080. In PROPOSED frames, role names are from section 4.2, sizes are 1x css px, TV points = x1.6, `(1)(2)(3)` = visual-weight order, `Num` = Numeric role.

### 5.1 Library

```text
┌ LIBRARY — AS-IS @1920x1080 (measured; 1 col = 19.6 px, 1 row = 38 px; sizes are px/weight) ──────┐
│ [>] LocalTube 28/700                                                  [Edit 13/600] [heart 36px] │
│                      (top bar 80px)                                                              │
├──────────────────────────────────────────────────────────────────────────────────────────────────┤
│ Channels 14/600   Playlists 14/600   Feed 14/600                          [Sort Custom 13/600 v] │
├──────────────────────────────────────────────────────────────────────────────────────────────────┤
│                                                                                                  │
│ Channels 36/800                                                        4 channels 18/400 #55555f │
│                                                                                                  │
│   ┌─────────────────────┐ ┌─────────────────────┐ ┌─────────────────────┐ ┌─────────────────────┐│
│   │       [14] 16/600   │ │       [10] 16/600   │ │        [8] 16/600   │ │       [12] 16/600   ││
│   │                     │ │                     │ │                     │ │                     ││
│   │                     │ │                     │ │                     │ │                     ││
│   │                     │ │                     │ │                     │ │                     ││
│   │Downloading... 63%   │ │                     │ │                     │ │                     ││
│   │Cocomelon 26/700     │ │Bluey Official 26/700│ │Nature Videos 26/700 │ │Songs 26/700         ││
│   │12 of 14 ready 17/400│ │9 of 10 ready 17/400 │ │8 of 8 ready 17/400  │ │12 of 12 ready 17/400││
│   └─────────────────────┘ └─────────────────────┘ └─────────────────────┘ └─────────────────────┘│
│   4 cards x 440x246 (auto-fill minmax(360px,1fr), gap 24); title:body ratio 26:17 = 1.5          │
│                                                                                                  │
│                                                                                                  │
│                                                                                                  │
│                                                                                                  │
│                      ( empty: y 500-1080 = 46% of the screen is unused at 4 channels )           │
│                                                                                                  │
│                                                                                                  │
│                                                                                                  │
│                                                                                                  │
│  left edges: logo x=40 | tab text x=54 | h2 x=44 | card x=44      right edges: 1880 | 1876 | 1876│
└──────────────────────────────────────────────────────────────────────────────────────────────────┘
```

```text
┌ LIBRARY — PROPOSED, TV scale 1.5x (1920x1080 pt = 1280x720 css; roles in css px, TV pt = x1.5) ──┐
│ [>] LocalTube  Label 16/600  (was 28/700)           [(M) Maya  Label 16/600]  [Edit  Caption 14] │
│                        top bar 64 css = 96 pt                                                (3) │
├──────────────────────────────────────────────────────────────────────────────────────────────────┤
│ Channels  Label 16/700 (active, 3px bar)    Playlists    Feed                 [Sort  Label 16 v] │
├──────────────────────────────────────────────────────────────────────────────────────────────────┤
│                                                                                                  │
│ Channels   TITLE 32/700 (2)                                           4 channels  Caption 14 (3) │
│                                                                                                  │
│   ┌────────────────────────────┐  ┌────────────────────────────┐  ┌────────────────────────────┐ │
│   │                            │  │                            │  │                            │ │
│   │              [14] Numeric  │  │              [10] Numeric  │  │               [8] Numeric  │ │
│   │                            │  │                            │  │                            │ │
│   │                            │  │                            │  │                            │ │
│   │Cocomelon   HEADLINE 22/700 │  │Bluey - Official Channel    │  │Nature Videos               │ │
│   │12 of 14 ready  Caption 14  │  │9 of 10 ready               │  │8 of 8 ready                │ │
│   └────────────────────────────┘  └────────────────────────────┘  └────────────────────────────┘ │
│   (1) channel art + name: 3 columns at TV scale, 16:9, 600x338 pt, gap 24 css                    │
│   ... second row of cards continues below the fold; nothing else competes with them              │
│                                                                                                  │
│  weight order: (1) card art+title  (2) page title  (3) chrome (wordmark, tabs, counts)           │
│  one left gutter (--gutter 40 css = 60 pt) for wordmark, tabs, title, cards; same on right       │
└──────────────────────────────────────────────────────────────────────────────────────────────────┘
```

**Library - rationale.** The as-is screen is a competent desktop home: a big heading, glassy cards, readable 26 px names. On a TV
it fails on proportion rather than style: the wordmark (28/700) and the page title (36/800) are rival H1s, the tab strip is 14 px,
the left gutter is 40/44/54 px depending on the row, and the cards stop at y=500 so almost half the screen is dark while the
text that remains is sized for a desk. The proposal demotes the chrome (wordmark to Label, Edit to Caption), makes the page title
the single type anchor (Title 30 -> 48 pt), puts channel art and Headline names first in the weight order (art 1, title 2, chrome 3),
unifies the gutter, and relies on the x1.6 dial so the grid reflows to 3 large columns instead of 4 small ones.

### 5.2 Channel (grid)

```text
┌ CHANNEL (grid) — AS-IS @1920x1080 (measured) ────────────────────────────────────────────────────┐
│                                                                                                  │
│ banner art: 300 px tall (28% of the screen), no text, scrolls away                               │
│                                                                                                  │
│                                                                                                  │
├──────────────────────────────────────────────────────────────────────────────────────────────────┤
│ < Library 18/500  Cocomelon 28/800 [12/14 16]                    [Edit 16/500] [grid|list 40x38] │
│                                          header 80px                                             │
├──────────────────────────────────────────────────────────────────────────────────────────────────┤
│ [Search videos... 16/400  480px]                                   [Sort Default order 13/600 v] │
│  [All (14) 12/600] [Favorites (2) 12/600]            <- chips: 12px, the smallest viewer text    │
├──────────────────────────────────────────────────────────────────────────────────────────────────┤
│  ┌─────────────┐ ┌─────────────┐ ┌─────────────┐ ┌─────────────┐ ┌─────────────┐ ┌─────────────┐ │
│  │             │ │             │ │             │ │             │ │             │ │             │ │
│  │         1:35│ │         3:07│ │         4:01│ │        10:03│ │        22:00│ │      1:00:00│ │
│  │Wheels on the│ │Bluey: The   │ │How Do Trains│ │Baby Shark   │ │The Very     │ │Counting 1 to│ │
│  │Bus | Sing...│ │Creek (Full..│ │Work? An...  │ │             │ │Hungry Cat...│ │20           │ │
│  │             │ │Resume 1:14  │ │             │ │             │ │             │ │             │ │
│  └─────────────┘ └─────────────┘ └─────────────┘ └─────────────┘ └─────────────┘ └─────────────┘ │
│  6 cols x 287 px (minmax(280px,1fr), gap 22); title 17/500 lh 23, clamp 2; ragged bottoms        │
│  first card row starts at y=529 = 49% of screen height (about 1.5 rows above the fold)           │
└──────────────────────────────────────────────────────────────────────────────────────────────────┘
```

```text
┌ CHANNEL (grid) — PROPOSED, TV scale 1.5x ────────────────────────────────────────────────────────┐
│ banner 120 css (180 pt) — collapses to 0 on first scroll; sits behind the title, no empty band   │
│                                                                                                  │
│ < Library  Label 16/600                                            [Edit]  [grid|list]  Label 16 │
│ Cocomelon   TITLE 32/700 (2)  2-line clamp, balance            12 of 14 ready  Caption 14 (3)    │
│ [ Search  Label 16 ]  [All 14]  [Favorites 2]  [Sort v]       <- chips Label 16 (TV 24 pt)       │
├──────────────────────────────────────────────────────────────────────────────────────────────────┤
│  ┌─────────────────────┐ ┌─────────────────────┐ ┌─────────────────────┐ ┌─────────────────────┐ │
│  │                     │ │                     │ │                     │ │                     │ │
│  │                     │ │                     │ │                     │ │                     │ │
│  │       [1:35] Num    │ │       [3:07] Num    │ │       [4:01] Num    │ │      [10:03] Num    │ │
│  │Wheels on the Bus |  │ │Bluey: The Creek     │ │How Do Trains Work?  │ │Baby Shark Dance     │ │
│  │Sing Along Nurser... │ │(Full Episode)       │ │An Animated Guide... │ │                     │ │
│  │Body 18/500 (1)      │ │[===---] Resume 1:14 │ │                     │ │                     │ │
│  └─────────────────────┘ └─────────────────────┘ └─────────────────────┘ └─────────────────────┘ │
│  4 cols at TV scale (min 280 css = 420 pt); every card = 16:9 thumb + 2-line title slot          │
│  weight order: (1) thumbs + titles  (2) channel title  (3) filters; chips/search Label 16, not 12│
└──────────────────────────────────────────────────────────────────────────────────────────────────┘
```

**Channel - rationale.** This is where a child chooses a video, and it is the most desktop-like screen: a 300 px content-free banner, an
80 px header and a search/filter band with 12-13 px controls push the first thumbnails to 49% of the screen height, and 17 px titles
get ragged card bottoms and silent truncation. The proposal shrinks the banner into the header (it can sit behind the title), keeps
one Title for the channel name, makes chips and search Label-sized, and designs the card as a fixed unit: 16:9 thumbnail, Numeric
duration, a reserved two-line Body title slot (`slot-2`), and a progress bar for resume instead of a blue 14 px sentence. Full title is
available via `title=` for pointer users and, on TV, via a 3-line clamp on focus (or the player title wrapping to two lines).

### 5.3 Profile picker

```text
┌ PROFILE PICKER — AS-IS @1920x1080 (measured) ────────────────────────────────────────────────────┐
│                                                                 [Admin 13/600] [Settings 13/600] │
│                                                                                                  │
│                                                                                                  │
│                                                                                                  │
│                                                                                                  │
│                                     48/800  Who's watching?                                      │
│                             Pick a profile to start  20/400 #8e8e99                              │
│                                                                                                  │
│                        ┌────────────┐      ┌────────────┐      ┌────────────┐                    │
│                        │   172px    │      │   172px    │      │   172px    │                    │
│                        │   (heart)  │      │  (rocket)  │      │  (flower)  │                    │
│                        └────────────┘      └────────────┘      └────────────┘                    │
│            Maya 22/700 @78%        Leo 22/700 @78%     Grandma & Grandpa 22/700 @78%             │
│                                                                                                  │
│                                                                                                  │
│                                                                                                  │
│                                                                                                  │
│                                                                                                  │
│  H1 48 : avatar 172 : name 22 -> name is 0.13x the avatar; 11.6' cap height @55in/3m             │
└──────────────────────────────────────────────────────────────────────────────────────────────────┘
```

```text
┌ PROFILE PICKER — PROPOSED, TV scale 1.5x ────────────────────────────────────────────────────────┐
│                                                          [Admin  Label 16]  [Settings  Label 16] │
│                                                                                                  │
│                                                                                                  │
│                                                                                                  │
│                               Who's watching?   DISPLAY 40/800 (2)                               │
│                                   Pick a profile  Body 18/400                                    │
│                                                                                                  │
│                       ┌──────────────┐   ┌──────────────┐   ┌──────────────┐                     │
│                       │              │   │              │   │              │                     │
│                       │  160 css (1) │   │    (rocket)  │   │   (flower)   │                     │
│                       │    (heart)   │   │              │   │              │                     │
│                       └──────────────┘   └──────────────┘   └──────────────┘                     │
│      Maya  HEADLINE 22/700 (3)    Leo                 Grandma & Grandpa  (wraps to 2 lines)      │
│                                                                                                  │
│                                                                                                  │
│  weight order: (1) avatars  (2) heading  (3) names; name 22 css = 33 pt, 100% alpha, 2-line clamp│
│  focus ring 4 css px accent + 1.08 scale (keyboard/remote); corner buttons Label 16 = 24 pt      │
└──────────────────────────────────────────────────────────────────────────────────────────────────┘
```

**Profile picker - rationale.** Already the best screen: three huge saturated avatars with a clear 48 px heading. Weak points are the
quiet 22 px names at 78% alpha (0.13x the avatar), a missing focus ring (`outline: none`), no wrap rule for long names and 13 px
parent buttons. The proposal keeps the layout, promotes names to Headline at full opacity with a 2-line clamp, adds a 4 px focus ring
and scale, and moves the two parent pills to Label size so they are still findable but visibly secondary (order: avatars 1, heading 2, names 3).

### 5.4 Player overlay

```text
┌ PLAYER OVERLAY — AS-IS, live SwiftUI (VideoPlayerView.swift:354-499), points ────────────────────┐
│ [< Back] 88x36  Wheels on the Bus | Sing Along Nursery Rhymes for Toddlers   22/600 lineLimit(1) │
│ 13+15/600 label  margins 48 pt side / 40 pt top      SF Pro (design .default), NOT Rounded       │
│  top scrim 160 pt                                                                                │
│                                                                                                  │
│                                                                                                  │
│                                                                                                  │
│                                                                                                  │
│                                  (<10)      (  ||  )      (10>)                                  │
│ 66 pt       84 pt        66 pt    icons 22 / 34 / 22 pt semibold; '10' is part of the SF Symbol  │
│                  (numeral size inside gobackward.10 at 22 pt: suspected 7-9 pt)                  │
│                                                                                                  │
│                                                                                                  │
│                                                                                                  │
│ ( ====gold fill====O---------------------------------------------------------------- )           │
│ track 6 pt (10 on hover/drag), knob 24 pt, hit 32 pt, fill gold #FFBE00 (React UI is purple)     │
│ 5:12  28/500 monospacedDigit                                                    14:05  28/500    │
│ [spk 18] [===Slider max 200===] [spk 18]                      [Off 14/600 @55%] [loop 18, 36x36] │
│ bottom scrim 170 pt; margins 48 / 40; 48 pt = 2.5% of 1920 (TV title-safe is about 5% = 96)      │
└──────────────────────────────────────────────────────────────────────────────────────────────────┘
```


```text
┌ PLAYER OVERLAY — PROPOSED, SwiftUI with a uiScale multiplier (1x values; TV = x1.6) ─────────────┐
│ [< Back] 96x40  Label 16   Wheels on the Bus | Sing Along Nursery Rhymes for Toddlers (clamp 2)  │
│ TV 154x64, label 26 pt     title Headline 22/600 -> 35 pt on TV (3)     margins 48 -> 77 pt on TV│
│                                                                                                  │
│                                                                                                  │
│                                                                                                  │
│                                                                                                  │
│                                                                                                  │
│                                 (<10)      (   ||   )      (10>)                                 │
│   66 pt         84 pt         66 pt   (x1.6 = 106 / 134 / 106 pt)  skip symbol 22 -> 30 pt (2)   │
│                    (numeral inside the symbol now >= 9 pt at 1x, 14 pt on TV)                    │
│                                                                                                  │
│                                                                                                  │
│                                                                                                  │
│ ( ====accent fill====O------------------------------------------------------------------- )      │
│ track 6/10 pt, knob 24, hit 40 pt (x1.6 on TV)            (1) transport + scrub = the focus      │
│ 5:12  Numeric 18/600 monospacedDigit (TV 29 pt)                                 14:05  Numeric 18│
│ [Volume: system keys; slider optional]                         [Off Label 16 @75%] [loop 40x40]  │
│ every SwiftUI literal becomes PlayerMetrics.x * uiScale (1x desktop, 1.6 TV); order (1)(2)(3)    │
└──────────────────────────────────────────────────────────────────────────────────────────────────┘
```


**Player overlay - rationale (live SwiftUI `PlayerControlsOverlay`, hosted in an `NSHostingView` above `AVPlayerView`, `PlayerOverlayController.swift:144`; the React `PlayerScreen.tsx` and its harness screenshot are not used because nothing in Swift sets `__playerMode`).** This is the only surface that already half-follows the ten-foot spec: 28 pt tabular timecodes, an always-visible 24 pt scrub knob, 66/84 pt transport circles. Around that it reverts to desktop sizes: a 22 pt single-line title, a 36 pt-high Back button with a 15 pt label, a 14 pt autoplay label at 55% white, 36 pt loop button, 18 pt volume icons, 48/40 pt margins, default-design SF Pro and a gold accent where the rest of the app is purple. Hierarchy order is right (transport and scrub first, timecodes second, title third), so the proposal keeps the layout and fixes scale: every literal becomes a 1x value times `uiScale` (`PlayerMetrics`), secondary controls reach 40 pt at 1x (64 pt on TV), the skip symbol grows 22 to 30 pt so its built-in "10" is legible, the title wraps to two Headline lines, and the timecodes are rebased to Numeric 18 at 1x so they land at 29 pt on TV (close to today's 28 pt) instead of ballooning to 45 pt under zoom.
## 6. (d) Ranked fixes

| Rank | ID | Sev | Status | What + evidence | User impact | Fix | Effort | Impact |
|---|---|---|---|---|---|---|---|---|
| 1 | TYP-1 | Major | confirmed | No scale dial; viewer text is desktop-sized: at 1080p, 77-100% of nodes <=17 px, median 15-17 px; video titles 17 px vs spec 28; labels 12-13 vs 24. All sizes px (0 rem); no `pageZoom` anywhere in `Bridge/`/`App/`; window 1280x800 default (`WebWindowController.swift:129-132`). 4K@1x halves everything again (`shots/channel-3840x2160.png`: 12 columns of ~9 px titles). | Kids cannot read titles from the couch; the product's stated use case is unsupported | `UserDefaults uiScale` {1.0, 1.25, 1.6, 2.0(, 3.0)} -> `pageZoom` on the WKWebView and a `PlayerMetrics` multiplier in the SwiftUI player overlay; Settings row, View menu Cmd+/-/0, onboarding question; guard `innerWidth >= 900 css` | S-M | High |
| 2 | TYP-3 | Major | confirmed | Functional text below any legible floor: list duration 9 px (`Channel.tsx:1308`), queue durations 10 (`QueueTray.tsx:384`), chips 12 (`Channel.tsx:1429`), card error 11 (`VideoCard.tsx:254`) inside a card at `opacity: .4` (`:121`) so message and Retry are ~invisible (`shots/channel-error-1920x1080.png`) | Parents cannot see why a download failed; kids cannot read chips | Floor 13 (admin) / 14 (viewer); render the error + Retry outside the dimmed wrapper (dim only the thumbnail/title) | S | High |
| 3 | TYP-4 | Major | confirmed | Long titles: unbroken strings clip mid-glyph with no ellipsis (title box scrollWidth 680/555 vs 257, `shots/stress-long-titles-1920x1080.png`); card heights ragged; no `title=` tooltip on any video title; live player title `lineLimit(1)` (`VideoPlayerView.swift:388-391`) so a 90+ char title is never fully readable | Truncated, ragged grid; full title unreachable | `.clamp-2 { overflow-wrap:anywhere }`, `.slot-2` min-height, grid `align-items: stretch`, `title={video.title}`, player title 2-line clamp | S | Med-High |
| 4 | TYP-2 | Major | confirmed | No discipline in the scale: 22 font sizes (eight 1-px steps 11-18), 12 line-heights, 9 tracking values, 5 weights, 4 font-stack spellings; Tailwind imported (`index.css:1`) but 0 utilities used | Every new screen invents sizes; TV scaling and QA are impossible to reason about | Role tokens + classes (section 4.4); codemod 207 inline `fontSize` + 13 CSS sizes -> roles; delete `@import "tailwindcss"` or actually use it (ARC to decide) | M | High (enabler) |
| 5 | TYP-7 | Major | confirmed | Hierarchy and layout: Library wordmark 28/700 vs title 36/800; gutters 40/44/54; right edges 1876/1880; Channel first video row at y=529 (49%) behind a 300 px banner + 80 px header + ~105 px filter band; Library leaves 46% of the screen empty; page titles 36/28/22/20 across screens; list view has a ~1700 px gulf and no clamp | Eye has nowhere to land; content below the fold; inconsistent screen headers | Wireframes 5.1-5.4: one `--gutter`, one Title per screen, banner folded into header, fixed card unit, 2-line list rows | M | Med-High |
| 6 | TYP-5 | Minor | confirmed (symbol size suspected) | The live SwiftUI player is half ten-foot: timecodes 28 pt `monospacedDigit` (`VideoPlayerView.swift:301,305`) and knob 24 pt meet the spec, but title 22 pt `lineLimit(1)` (`:388-391`), Back 15 pt in an 88x36 button (`:313-334`), autoplay label 14 pt at 55% white (`:485-487`), loop/Back targets 36 pt (`:465,489`), transport 66/84 pt (`:402,228`, spec 96) and skip symbol 22 pt (`:402,406`, small built-in "10"). SF Pro default design, gold accent, no scale input. React `PlayerScreen.tsx` (6.5-unit "10", 20-22 px) is dead code | Big clock, small controls: kids hit 36 pt targets from 3 m; the three surfaces use three different scales | `PlayerMetrics` (1x values x `uiScale`, see 4.5): title Headline 2 lines, secondary targets >= 40 pt at 1x, skip symbol 22 -> 30 pt, label 16 pt at 75% alpha, timecode Numeric 18 at 1x; delete `PlayerScreen.tsx` | S | Med |
| 7 | TYP-6 | Minor | confirmed (render suspected) | Spec says SF Rounded; code ships SF Pro (`index.css:59`), `'SF Pro Display/Text'` entries are dead names; global `-0.02em` h1-h6 tracking (`:81`) double-tightens with SF's own tracking (suspected); harness renders Inter so nothing here can be eyeballed | Brand/"friendly" look from the spec is absent; `design: .rounded` exists only in dead `TenFootStyles.swift:33-43`, so no live surface is Rounded | `font-family: ui-rounded, system-ui, ...` (and `design: .rounded` in the player); drop dead names and global tracking; verify weights 400-800 on a Mac | S | Med |
| 8 | TYP-10 | Minor | confirmed | Error/empty tone: viewer-facing sync banner shows "Sync failed" + raw monospace string (`Channel.tsx:727-736`); queue/Playlists/No-videos empties 14-16 px (`QueueTray.tsx:231`, `Library.tsx:634,679`) | Kids see developer text (banner is not gated on editor mode, `Channel.tsx:710`); small empties unreadable on TV | Viewer: one friendly sentence at Body size ("Couldn't check for new videos. Everything already here still works."); raw detail only in admin | S | Med |
| 9 | TYP-12 | Minor | suspected | `ProfileTile` has `outline: none` (`ProfilePicker.tsx:132`) and no wrap/ellipsis for long names in a `minmax(180px,1fr)` grid (`:103`) | No visible focus on keyboard/remote; long names may overflow | Focus ring + 2-line clamp (needs a Mac/long-name test) | S | Med |
| 10 | TYP-8 | Minor | confirmed | React UI has no `tabular-nums` (only the SwiftUI player uses `.monospacedDigit()`, `VideoPlayerView.swift:301,305`); absent on duration badges (`VideoCard.tsx:407`), progress % (`VideoCard.tsx:195`, `ChannelCard.tsx:402`), list durations (`Channel.tsx:1308`), Settings stats | Live percentages jitter; durations do not align | `.t-num` on all numeric text | S | Low |
| 11 | TYP-9 | Minor | confirmed | Settings: select inherits `.lt-input` 18 px beside 13 px labels and clips "Best Available (up to" (`shots/editor-settings-1920x1080.png`); three button sizes inside one card | Looks unfinished; value unreadable | Use Body/Label roles; widen or let select wrap its value | S | Low |
| 12 | TYP-11 | Minor | confirmed | 53% of 144 `gap:` values are not multiples of 4 (6 px x20, 10 px x21, 14 px x11); grid gaps 22 vs 24 | Subtle rhythm drift | `--sp-*` scale in the token pass | S-M | Low |

Effort total for the sequence 1, 2, 3 (+5 for Channel and Library only): about 4-6 days including Mac verification.

## 7. Top 3 highest-leverage improvements

1. **Functionality - Display-size dial (TYP-1).** Add the `uiScale` setting, apply with `pageZoom` on the WebView plus a `PlayerMetrics` multiplier in the SwiftUI player, surface it in onboarding, Settings and the View menu. One day of Swift/JS turns a desktop UI into one a child can read from 3 m, without touching 200 inline sizes.
2. **Reliability of rendering - role tokens, a 14 px floor and the long-title utilities (TYP-2/3/4).** Removes clipped strings, ragged rows, invisible error text and 9-12 px functional text in one pass, and gives QA a finite set of styles to snapshot.
3. **Features - rebuild Library and Channel headers/cards to the wireframes (TYP-7).** First thumbnails above the fold, one title per screen, a fixed card unit with Numeric duration and resume bar: the screens a child uses all day.

## 8. Needs a real Mac to confirm
- `ui-rounded` actually resolves to SF Pro Rounded in the app's WKWebView on macOS 14.x, with weights 400-800, and that `font-variant-numeric: tabular-nums` works with it.
- `WKWebView.pageZoom` on the main window: grid reflow, `100vh`/`innerWidth` behaviour, `localtube-thumb://` images unaffected, window-size guard.
- The SwiftUI player at 1.6 via `PlayerMetrics`: real height of the numeral inside `gobackward.10` at 22 pt vs 30 pt, title wrapping to 2 lines, SF Rounded weights/width on the player title, and that the 160/170 pt scrims still cover the larger controls.
- Real macOS text weight with `-webkit-font-smoothing: antialiased` (harness shows heavier Inter) - legibility of 13-14 px `#8e8e99` on the dark background.
- Whether SF's automatic tracking plus the explicit `-0.02em` double-tightens titles; compare with the global rule removed.
- `text-wrap: balance` on macOS 14.0-14.4 (Safari 17.0-17.4 lacks it; falls back silently) and `-webkit-line-clamp` plus `overflow-wrap: anywhere` ellipsis behaviour.
- Which display mode macOS picks for the user's TV (1920x1080 @2x vs 3840x2160 @1x): this decides whether CSS px are 0.634 mm or 0.317 mm.
- Profile-picker overflow with a long profile name and keyboard focus visibility.

## 9. Cross-lane notes
- UX: `ProfilePicker.tsx:132` `outline: 'none'`; 34x34 px favourite/queue buttons (`VideoCard.tsx:293,337`) vs the 96 pt spec; hover-only play button and delete overlay (`index.css:662-691`).
- DSG: the live player uses a gold accent (`Color.ltAccent` #FFBE00, `TenFootStyles.swift:14`; scrub fill `VideoPlayerView.swift:273`, volume tint `:428`) while the React UI is purple #9b5de5. Also `--text-tertiary #55555f` carries real information ("4 channels" 18 px, "Sort", stats, empty-state copy); 0.4 opacity on whole cards dims error text and Retry.
- ARC: `Views/Shared/TenFootStyles.swift` is not safe to delete with the dead `Views/**`: the live `PlayerControlsOverlay` depends on `Color.ltAccent` (`VideoPlayerView.swift:273,428,462,487`); move it first. The profile picker and PIN overlay leave the Library mounted underneath (Library text nodes appear in the picker scenario); Tailwind preflight is shipped with no utilities in use; about 420 inline `style` objects.
- UI: min window 900x600 vs any scale above 1.25 on a 1280 window; Settings select clips its value.
- QA: no snapshot test for long-title/CJK/emoji/URL titles; add the five stress titles from `.../work-typ/stress.cjs` to the harness fixtures.
- AV: the live overlay is SwiftUI (`VideoPlayerView.swift:354`); it needs the same `uiScale` and a title-safe margin of about 5%. The React `PlayerScreen.tsx` is dead code (nothing sets `__playerMode`): deletion candidate for ARC.
