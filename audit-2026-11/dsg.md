# DSG - Design & Color audit (LocalTube v1.0.37)

Evidence sources: `WebUI/src/**` (read), harness renders at 1920x1080 (`work-dsg/shots/*.png`, `work-dsg/cs/*.png`),
programmatic contrast scan of 451 rendered text runs (`work-dsg/scan.cjs` + `contrast.py` -> `work-dsg/rows.json`),
player-overlay renders over 5 video frames (`work-dsg/cs-player/*.png`), token maths (`work-dsg/tokens.py`, `proposed.py`).
Chromium != WebKit; AppKit items are static review only (labelled `suspected`).

## 0. Verdict
The visual system has a decent skeleton (CSS-variable tokens in `index.css:4-42`, warm pastel profile avatars, calm low-APL screens: 1-13% mean luminance)
but it is NOT a system in practice: ~50% of colour values are hard-coded literals, the single most-used text colour (`--text-tertiary`) fails
WCAG everywhere it is used (2.2-2.6:1), the primary button and accent text fail AA, the player controls become invisible on bright video,
and there is zero handling of Reduce Motion / Reduce Transparency / Increase Contrast / focus rings. Identity reads as "generic dark glass +
purple->blue gradient", not the spec's "warm, saturated, child-friendly". All fixable mostly in one stylesheet + a thin Swift->JS accessibility bridge.

## 1. Token audit (real numbers)
Architecture fact: **575 inline `style={{}}` blocks, 146 `className=` (23 distinct lt-* classes), 0 Tailwind utility classes**, although Tailwind 4 is imported
(`index.css:1`) with no `@theme`. So tokens must be plain CSS variables, and inline styles cannot express `:hover`, `:focus-visible` or `@media`.

| Metric | Count | Notes |
|---|---|---|
| Colour literals in TSX | 65 hex + 293 rgb/rgba = **358** | vs **321** `var(--*)` uses in TSX |
| Colour literals in index.css body (lines 43+) | 69 rgba | vs 100 `var(--)` |
| Total hard-coded vs tokenised | ~**430 vs ~420 (51% hard-coded)** | |
| Worst offenders (literals / var uses) | Channel.tsx 54/39, Library.tsx 38/27, VideoCard.tsx 33/11, ChannelCard.tsx 32/3, PlayerScreen.tsx 33/1, Settings.tsx 24/17, QueueTray.tsx 19/14, ToastHost.tsx 7/0 | PlayerScreen and ToastHost use no tokens at all |
| Distinct white-alpha values | **34** (`rgba(255,255,255,x)` from 0.02 to 0.95) | 16x 0.04, 12x 0.06, 10x 0.2, 8x each 0.08/0.1/0.10 ... |
| Distinct black-alpha values | **24** | |
| Distinct alphas of accent purple (155,93,229) | **17** | |
| Distinct alphas of red (248,113,113) | **23** | only `--destructive` token exists, no tint tokens |
| Token usage in TSX | text-secondary 54, text-tertiary 50, accent 50, text-primary 41, border 32, surface-el 17, surface 15, accent-dim 14, bg 13, success 11, destructive 10, border-strong 4, **--blue 1, --glass-* 4, --shadow-* 2** | glass/shadow tokens are defined but essentially unused |
| Border radii | tokens 8/12/18/22/30 used **7 times**; **92 inline numeric radii** in **20 distinct values** (1,2,3,4,6,7,8,9,10,12,14,16,18,20,21,22,26,28,36,99) + 5/3/14/10 in CSS | avatars use `size*0.32` (icon) vs `size*0.2` (emoji/initial) - `ProfileAvatar.tsx:25,45,64` |
| Box-shadows | **37** distinct declarations | 3 tokens used 1x each |
| z-index | 14 distinct values: 0,1,2,3,5,60,70,71,80,90,100,150,200,400 | no scale/tokens; toast=400, PIN=200, modal=100, queue=60-90 |
| backdrop-filter blur recipes | 14 distinct strings: blur(10/12/16/20/24/28/32px) x saturate(150/160/180/200%) | 15 rules in index.css + ~20 inline |
| Durations | 17 distinct (80,90,100,120,140,150,160,180,200,220,240,260,280,300,400ms, 0.15s, 0.3s...) | top: 160ms x34, 140ms x21, 180ms x20 |
| Easings | ease x69, cubic-bezier(.4,0,.2,1) x25, (.89,0,.14,1) x21, (.25,1,.5,1) x15, (.34,1.2,.64,1) x3, (.34,1.56,.64,1) x1, (.36,.07,.19,.97) x1, ease-in-out x4 | 7 curves |

### Near-duplicate colours (same intent, different literal)
Purples: `#9b5de5` (--accent), `#b06ff0` (--accent-hover), `#ad6df0` (fallback in Library.tsx:818), `#a264e8` (player scrub fill, PlayerScreen.tsx:169),
`#c084fc` (App.tsx:84 error-boundary button), `#a86ff0` (app icon, render_icon.py:21), `#863bff` (favicon.svg = Vite logo), plus profile `lavender #B39DDB` and `plum #CE93D8`.
Reds: `#f87171`, `#fca5a5` (11x), `#ff8a80` (coral profile). Greens `#34d399`/`#a7f3d0`. Ambers `#fbbf24`/`#fde68a`/`#ffe082`.
Blues: `#60a5fa` (--blue, "Resume at"), `#bfdbfe`, `#90caf9`. Toast palette `ToastHost.tsx:41-46` duplicates the semantic colours as rgb+hex pairs outside the token block.
Dark neutrals: `#0d0d0f`, `#1a1a1f`, `#222228`, `#1e1e28` (ChannelCard.tsx:158, VideoCard.tsx:151), `#0d0d22`, rgba(20,20,25), (26,26,31), (34,34,40), (22,22,27), (16,16,20) - five slightly different "surface" darks.

### Missing tokens
No focus ring, no control-border (input edge), no tint/ink tokens for status colours, no ink-on-accent, no overlay/scrim token, no z/duration/blur scales.

## 2. Contrast (WCAG 2.2 AA: 4.5:1 text, 3:1 large text/UI). Computed, not eyeballed.
Method: for every visible text node, computed `color` (+ cumulative opacity) from the DOM, background sampled from a screenshot with all text made transparent,
ratio = composite(fg over each bg pixel) vs bg pixel, median over the glyph box. 451 runs over 17 screens @1920x1080.
Result: **147 of 451 runs fail on median, 165 on 5th-percentile.**

### 2a. Token pairs (analytic)
| Pair | on --bg #0d0d0f | on --surface #1a1a1f | on --surface-el #222228 |
|---|---|---|---|
| text-primary #f0f0f4 | 17.1 | 15.3 | 13.9 (pure `white` used 20+x = 19.4) |
| text-secondary #8e8e99 | 6.0 | 5.4 | **4.9** (falls to 4.1-4.4 on ambient/hover surfaces) |
| **text-tertiary #55555f** | **2.64 FAIL** | **2.35 FAIL** | **2.15 FAIL** |
| accent #9b5de5 as text | 4.7 | **4.2 FAIL** | **3.8 FAIL** |
| accent text on accent-dim tint (chips) | | | **3.1 FAIL** |
| **white on --accent (primary button)** | **4.13 FAIL** (13-18px/600 is not "large") | | |
| white on accent-hover (button hover) | **3.29 FAIL** | | |
| success #34d399 / destructive #f87171 / blue #60a5fa as text | 10.1 / 7.0 / 7.6 pass | | |
| hairline border rgba(255,255,255,.08) / strong .14 | 1.20 / 1.45 | | decorative only |
| **input border rgba(255,255,255,.13) on surface** | **1.48 FAIL WCAG 1.4.11 (needs 3:1)** | | |

### 2b. Rendered failures (1920x1080, `work-dsg/rows.json`)
| Pair | Ratio | Where | Verdict |
|---|---|---|---|
| text-tertiary #55555f on ambient bg | **1.6** | Library.tsx:388 "4 channels" count (18px) | FAIL |
| text-tertiary on surface cards | 2.15-2.35 | Settings.tsx:50,351,447,453 hints, paths, timestamps, stat labels (11-12px); Editor channel meta `▶ Source`; Onboarding.tsx step-2 title & hint; PIN/Onboarding footers (2.64) | FAIL (82 runs) |
| text-tertiary "Sort" label | 2.15-2.28 | Library/Channel sort chip (13px) | FAIL |
| white@0.24 "Queued" label | **2.19** | VideoCard.tsx:161-175 | FAIL |
| error text "Video unavailable. This video is private..." fg #fca5a5 @0.40, 11px | **2.4** | VideoCard.tsx:121 (`opacity: hasIssue ? 0.4 : 1` applies to the whole card incl. its error string) | FAIL - error text is the one string that must stay readable |
| Retry button on failed card (red @0.4) | 1.84-1.92 | channel-error / syncing | FAIL (disabled-looking but it is the action) |
| white@0.40 disabled primary "Continue", "Set PIN" | 3.05 | Onboarding / PINSetup.tsx:273 | exempt as disabled, but unreadable in dim room |
| white on --accent button | 4.13 | Choose Folder, New Channel, Add Videos, Try Again, step "1" bubble | FAIL (8 distinct buttons) |
| accent #9b5de5 text | 3.26-3.99 | filter chip "All (14)" 12px, "Editing Maya's library" bar, Admin tab labels "Channels/Profiles/Settings", "Syncing..." | FAIL |
| white@0.70 "Downloading... 63%" on card | 2.9-3.5 (min 1.65 over bright banner) | ChannelCard.tsx:399-404 | FAIL |
| white@0.55 "12 of 14 ready" on card | 4.1 on yellow banner, **3.6 over white banner** | ChannelCard.tsx:431-436 | FAIL on bright banners |
| text-secondary #8e8e99 over translucent chrome | 4.1-4.4 (4.0-4.2 with bright banner) | Library tabs "Playlists/Feed", "Library" breadcrumb, "12 / 14" counts | FAIL (marginal) |
| toast text (#bfdbfe/#a7f3d0/#fde68a/#fca5a5 on rgba(20,20,25,.92)) | 9-14 | ToastHost.tsx:41-63 | pass (but 14px) |
| "Resume at 1:14" #60a5fa 14px | 7.0 | VideoCard | pass |
| Channel card title white 26px bold + text-shadow over WHITE banner (worst case) | >3 | ChannelCard.tsx:421-428 | pass (scrim .85 at bottom: needs alpha>=0.42 for 3:1, >=0.54 for 4.5:1; title row has ~0.51) |
| Video card titles | 11-15 | solid dark panel under thumbnail (not over image) | pass |

### 2c. Player overlay over arbitrary video (PlayerScreen.tsx, transparent WebView over AVPlayerView)
Renders over solid frames (`work-dsg/cs-player/player-*.png`):
| Frame | Title 22px (scrim) | Time 20px | Transport glyph vs its glass disc | Disc edge vs frame | Scrub track vs frame |
|---|---|---|---|---|---|
| white | 3.95 FAIL | 4.15 FAIL | **1.00 (invisible)** | 1.00 | 1.00 |
| light yellow | 4.8 | 4.9 | **1.22** | 1.04 | 1.10 |
| sky blue | 5.5 | 5.6 | **1.43** | 1.07 | 1.19 |
| mid-gray | 10.4 | 9.6 | 3.03 | 1.30 | 1.70 |
| black | 21 | 16.8 | 14.6 | 1.44 | 2.3 |
The three centre transport buttons sit where the top/bottom scrims do not reach (PlayerScreen.tsx:433,486 scrims only cover 160/170px), fill is `rgba(255,255,255,.16)` and glyph is
`fill="white"` (lines 42-79), so on any frame brighter than mid-gray (snow, white cartoon backgrounds, sky - very common in kids' content) the controls vanish.
Also: `backdrop-filter: blur(32px) saturate(200%)` on 4 buttons (PlayerScreen.tsx:218,270) **cannot sample the AVPlayerView** (separate native view beneath a transparent WKWebView), so the "glass" is just a
16%-white disc - `suspected`, confirm on a Mac.

### 2d. Comfort (dim room, 4K TV)
- Mean luminance (APL) at 1080p: profile picker 2.3%, library 5.7%, channel 12.5%, settings 0.9%. Comfortable. Pixels with L>0.8: <=0.5%.
- `--text-primary #f0f0f4` = 17:1, plain `white` = 19.4:1 on near-black: slightly harsh (halation) for long viewing; warm off-white at ~15-16:1 is easier.
- Ambient background: `AmbientBackground.tsx:119,135` stacks `blur(64px) saturate(200%) contrast(1.12)` + a second `hue-rotate(22deg) saturate(240%)` screen-blended copy under a 0.68 scrim. Real render
  gave `#393714` mustard-olive on the library (Bluey-yellow banner), `#804c45` maroon / `#077f5e` green on the channel header. The hue is whatever the banner is, pushed to 200% saturation then dimmed:
  muddy olive/brown tints behind every text run (text-secondary drops to 4.1 there). Channel banner hero (top 300px) is fully saturated with no top scrim.
- Hover/active glow shadows `0 0 20px rgba(155,93,229,.3)`, `0 0 12px rgba(155,93,229,.7)` (new-video dot, ChannelCard.tsx:349) are the "AI glow" look; fine at 1x, bloom-y on 4K.

## 3. Materials & performance
- **backdrop-filter**: 11 live elements on Library, **20 on Channel (16 video cards), 32 on a 400-video channel page** (`channel-large`, paginated), 11 under the PIN modal; plus every `.modal-backdrop` is a **full-viewport
  `blur(16px) saturate(150%)`** (index.css:373-384; 9 modal sites) and `.modal-panel` another `blur(28px) saturate(200%)` on top (index.css:391-400) = two stacked backdrop-filters over a page that already
  has a 4-layer ambient background. Visible blurred area summed with overlap: 14% (library) - 21% (channel) of viewport.
- **Ambient stack**: up to `MAX_LAYERS=4` layers x 2 `<img>` each = **8 full-viewport images scaled 1.3x with CSS blur(64px/40px)+saturate+mix-blend-mode:screen** (AmbientBackground.tsx:16,102-143). At 4K
  that is ~8 x (1.69 x 8.3 Mpx x 4 B) = **~450 MB of compositor surfaces** (`suspected` - confirm in Instruments/Metal HUD). It also never pauses (9s timer + 1.4s crossfade forever, including when the player is open or the window is occluded).
- `will-change: transform` on every `.lt-card` / `.lt-video-card` (index.css:133,646) + `.lt-card` also has backdrop-filter => each channel card is its own filtered GPU layer.
- **Reduce Motion / Reduce Transparency / Increase Contrast**: **zero handling** in WebUI (`grep prefers-` = 0 hits; no `forced-colors`). Swift: `NSWorkspace.shouldReduceMotion` exists only in
  `Utilities/AccessibilityHelpers.swift:6-10` and is referenced by nothing outside the dead SwiftUI tree (TODO.md:158 says "checked in one place (player controls)" - not true of current code). WebKit does **not** support
  `prefers-reduced-transparency` ([caniuse](https://caniuse.com/wf-prefers-reduced-transparency), [web-platform-dx](https://web-platform-dx.github.io/web-features-explorer/features/prefers-reduced-transparency/)), so CSS alone cannot fix it - the AppKit shell must
  forward `accessibilityDisplayShouldReduceTransparency` / `...ReduceMotion` / `...IncreaseContrast` (+ `NSWorkspace.accessibilityDisplayOptionsDidChangeNotification`) to JS as `data-` attributes on `<html>`.
- **Light mode**: none, dark-only by design (spec 3.4). But the shell never pins appearance: `WebWindowController.swift:119-135` creates a plain `NSWindow` (`.titled`), no `appearance = .darkAqua`,
  no `titlebarAppearsTransparent`, no `backgroundColor`, `drawsBackground=false` on the WKWebView, and `index.html`/CSS have no `color-scheme: dark`. `suspected`: in macOS Light mode the title bar is light grey over a near-black page
  (two-tone window), native controls/scrollbars/context menus render light, and a light flash shows on live-resize. No NSVisualEffectView / vibrancy anywhere in the live shell: all "glass" is simulated in CSS over the page's own content,
  so it never picks up the Mac desktop and the sidebar/titlebar material of a Mac app is absent (fine for a TV app, but then the glass buys nothing).
- Player NSPanel is opaque black (`PlayerOverlayController.swift:120-121`) - good.

## 4. Identity coherence vs spec 3.4
- "Warm, saturated, child-friendly": **no.** Chrome is cool neutral near-black (#0d0d0f = blue-tinted) + violet accent + purple->blue gradient mark. Warmth exists only in content (thumbnails) and in the 12 pastel profile tiles (`profileColors.ts`),
  which are the best-designed colour asset in the app (all 12 pass: dark glyph 5.6-8.1:1, tile vs bg 8.1-15:1).
- "Single accent per state, no rainbow": mostly honoured (violet = selected/progress/focus). Violations: **blue is a second progress colour** ("Resume at 1:14" `#60a5fa` text while the same card's progress bar is purple gradient, VideoCard.tsx:209);
  blue also = info toast; success/amber/red status colours are consistent in meaning. The accent collides with profile `lavender/plum` (default profile colour is lavender: `DEFAULT_PROFILE_COLOR`), so identity colour and UI state colour are indistinguishable for that profile.
- AI-slop flags (confirmed): purple->blue 135deg gradient tile as logo in 3 places (Library.tsx:221, Onboarding.tsx:58, icon), `.gradient-text` wordmark (index.css:441, Onboarding "LocalTube"), glow shadows, glass on every surface,
  hover-scale 1.03 + spring overshoot everywhere, **35 emoji glyphs used as UI icons** (Onboarding step icons 📁🔐 `Onboarding.tsx:159,234`; type badges `▶ Source` / `📂 Custom` `Editor.tsx:312`, `Profiles.tsx:333`, `AddChannelModal.tsx:186-187`;
  fallback 📺 x6; 📭 empty state `Library.tsx:677`; 🎬 `QueueTray.tsx:230`; 👤) next to a Phosphor icon set - inconsistent (emoji render as Apple Color Emoji, full-colour, outside the palette, ~3 different sizes).
- **App icon** (`Assets/AppIcon/AppIcon-1024.png`, rendered by `render_icon.py`): correct Apple grid and quality, but it is a generic purple->blue gradient squircle + white play triangle: no concept (offline/local/family),
  the triangle mimics every video app, and at 16-32px (preview) it reads as a smudge. The same mark is the in-app logo. `WebUI/public/favicon.svg` is the unmodified Vite bolt logo and `public/icons.svg` is the Vite template social sprite
  (bluesky/discord/github/x); both ship inside the app bundle (`Sources/LocalTube/Resources/WebUI/`), referenced only by `index.html:5` (`suspected` dead; irrelevant in WKWebView but a brand leak / dead weight).
- Consistency nits: three avatar shapes (`size*.32` vs `size*.2`), channel/video cards use `lt-card`/`lt-video-card` with different border/shadow recipes, destructive buttons come in 3 sizes/alphas (`lt-btn-destructive`, `lt-btn-retry`, `lt-row-btn.destructive`).

## 5. Motion inventory
- 11 `@keyframes` (screenFadeIn, screenSlideIn, shake, spin, pulse-glow, lt-eq, backdropIn, modalIn, reveal, lt-overlay-in, lt-panel-in); all animate **transform/opacity only** (good). Infinite: `spinner` x12 sites, `pulse-glow` (PIN dots), `lt-eq` bars.
- Non-composited transitions: `width` on progress bars (index.css:437, RelocateLibraryModal.tsx:97, PlayerScreen.tsx:160-170 height+width), `transition: all` x6 (index.css:510,545; PINEntry.tsx:161; Channel.tsx:666; PINSetup.tsx:29; Onboarding.tsx:145).
- JS-driven: AmbientBackground 9s `setInterval` + double-rAF fade (CSS-transition based, OK); IntersectionObservers in Channel.tsx replaced scroll handlers (the TODO.md:270-273 "header parallax" lesson **has been applied** - `Channel.tsx:92,141,296,327`; no scroll-driven style writes remain) - `fixed-already`.
- **Easing**: `--ease: cubic-bezier(.89,0,.14,1)` (index.css:28-30) is an easeInOutExpo: for the 140ms hover/focus transitions that use it (21x) it barely moves for the first third then snaps - feels laggy on a keyboard/remote focus move. `.lt-card` uses overshoot (.34,1.2,.64,1), modal (.34,1.56,.64,1) = springy, ok for kids but an unscripted 56% overshoot on a 600px modal is large.
- **Reduced motion: 0 coverage** (no `prefers-reduced-motion`; see section 3). Ambient crossfade, card scale, modal pop, shake, spinners all run regardless. (TODO.md:158 acknowledges.)

## 6. Proposed design system (paste-ready)
Rationale: warm charcoal base (hue ~25 deg) instead of blue-black; one violet accent **lifted to L~0.72** so the *same token* works as text/ring/fill on dark (6.3-8.4:1) and takes dark "ink" text on fills (7.9:1) - this removes the
white-on-purple 4.1:1 failure and the accent-as-text failure in one change; semantic status trio (ok/warn/bad) with their own ink and tint; blue dropped (resume = accent); glass reduced to ONE material; accent can be overridden per profile
(all 12 pastel profile colours pass as accent: >=6.0:1 as text on surface-3, >=7.5:1 ink-on-fill) which gives each child "their" colour, honouring "single accent per state". If the PM wants a literally warm accent instead (tangerine #FF9F5A), keep warn amber out of the UI or move warn to yellow-green; violet keeps the four status hues unambiguous.

All ratios below computed with `work-dsg/proposed.py`.

```css
:root {
  color-scheme: dark;

  /* ── Surfaces: warm charcoal; each step ~1.07-1.14:1, so rely on shadow+line, not just fill ── */
  --bg:         #110F0E;   /* canvas, 'lights-off' base */
  --surface-1:  #1A1715;   /* page sections, sidebars */
  --surface-2:  #231F1C;   /* cards, panels, inputs */
  --surface-3:  #2E2925;   /* raised/hover, modals, menus */
  --scrim:      rgba(10, 8, 7, 0.72);

  /* ── Lines ── */
  --line:          rgba(255, 240, 225, 0.12);  /* decorative hairline (1.4:1) */
  --line-strong:   rgba(255, 240, 225, 0.20);
  --control-edge:  #7A6F64;                    /* input/toggle/checkbox boundary: 3.3-3.9:1 on surfaces (WCAG 1.4.11) */

  /* ── Text (on --bg / s1 / s2 / s3) ── */
  --text-1: #F3EDE4;   /* 16.4 / 15.3 / 14.1 / 12.4  warm off-white, replaces #f0f0f4 and every literal 'white' */
  --text-2: #C2B8AC;   /*  9.8 /  9.1 /  8.4 /  7.4  secondary */
  --text-3: #9A9085;   /*  6.1 /  5.7 /  5.2 /  4.6  tertiary - AA everywhere; replaces #55555f (2.2-2.6) */

  /* ── Accent (violet, lifted). Use as text, icon, ring, progress, fill. ── */
  --accent:       #B79CFF;                              /* 8.4 / 7.8 / 7.2 / 6.3 as text */
  --accent-hi:    color-mix(in srgb, var(--accent) 78%, white);   /* hover; #CDB9FF = 10.9 */
  --accent-ink:   #1B1033;                              /* text/icon ON accent fills: 7.9:1 */
  --accent-tint:  color-mix(in srgb, var(--accent) 16%, transparent);  /* chip/selected bg */
  --accent-edge:  color-mix(in srgb, var(--accent) 45%, transparent);
  /* Per-profile override: <html style="--accent:#FF8A80"> (use colorHex(profile.color)); all 12 profile colours pass (>=6.0 text, >=7.5 ink). */

  /* ── Status: each has fill, ink-on-fill and tint ── */
  --ok:    #6EDBA5; --ok-ink:   #0B2418; --ok-tint:   color-mix(in srgb, var(--ok)   14%, transparent);  /* text 8.5-11.2, ink 9.6 */
  --warn:  #FFCB5C; --warn-ink: #2A1C00; --warn-tint: color-mix(in srgb, var(--warn) 14%, transparent);  /* text 9.6-12.7, ink 11.0 */
  --bad:   #FF7B72; --bad-ink:  #2D0A08; --bad-tint:  color-mix(in srgb, var(--bad)  14%, transparent);  /* text 5.7-7.6, ink 7.2 */
  /* 'info' and --blue are retired: info toast = neutral surface-3 + text-1; resume/progress = --accent. */

  /* ── Focus: two-tone ring works on any background incl. accent fills and thumbnails ── */
  --focus:       #FFF4DD;
  --focus-ring:  0 0 0 3px var(--bg), 0 0 0 6px var(--focus);       /* ring vs inner gap 17.5:1 */
  --focus-ring-lg: 0 0 0 4px var(--bg), 0 0 0 8px var(--focus);     /* cards / 10-foot */

  /* ── Radius: 5 steps replace 20 literals (map: <=8->r1, 9-12->r2, 14-20->r3, 21-36->r4, 99/50%->pill) ── */
  --r-1: 8px;  --r-2: 12px;  --r-3: 18px;  --r-4: 26px;  --r-pill: 999px;
  --r-avatar: 28%;               /* one avatar squircle (was .32 and .2) */

  /* ── Elevation: dark-UI elevation = lighter surface + soft shadow. No coloured glows. ── */
  --elev-0: none;
  --elev-1: inset 0 1px 0 rgba(255,240,225,.04), 0 2px 6px rgba(0,0,0,.35);              /* resting card */
  --elev-2: inset 0 1px 0 rgba(255,240,225,.06), 0 8px 20px rgba(0,0,0,.45), 0 2px 6px rgba(0,0,0,.35);  /* hover / focus lift */
  --elev-3: 0 20px 48px rgba(0,0,0,.55), 0 6px 14px rgba(0,0,0,.40);                     /* modal, menu */

  /* ── Materials: ONE blurred material + a scrim. Nothing else may use backdrop-filter. ── */
  --blur-chrome: 20px;           /* top nav / sticky bars only */
  --blur-scrim:  12px;           /* modal backdrop only (was 16px + 28px stacked) */
  --material-chrome: color-mix(in srgb, var(--surface-1) 80%, transparent);
  --overlay-dark: rgba(17, 15, 14, 0.62);   /* badges/controls ON imagery or video: solid, NO blur (5.4:1 glyph on white frame) */

  /* ── Motion ── */
  --dur-press: 90ms;  --dur-fast: 140ms;  --dur-base: 220ms;  --dur-slow: 360ms;  --dur-ambient: 1400ms;
  --ease-standard: cubic-bezier(.2, 0, 0, 1);      /* hover/focus/colour (replaces .89,0,.14,1 and .4,0,.2,1) */
  --ease-enter:    cubic-bezier(.25, 1, .5, 1);    /* enter/reveal (already used 15x) */
  --ease-pop:      cubic-bezier(.34, 1.3, .64, 1); /* card hover/modal, overshoot capped (was 1.56) */

  /* ── Z scale (replaces 0,1,2,3,5,60,70,71,80,90,100,150,200,400) ── */
  --z-raised: 1; --z-sticky: 10; --z-nav: 20; --z-tray: 40; --z-modal: 100; --z-pin: 200; --z-toast: 300;
}

/* Material helpers */
.material { background: var(--material-chrome); backdrop-filter: blur(var(--blur-chrome)) saturate(140%); -webkit-backdrop-filter: blur(var(--blur-chrome)) saturate(140%); border: 1px solid var(--line); }
.on-media { background: var(--overlay-dark); border: 1px solid rgba(255,255,255,.18); color: #fff; }   /* chips, play button, player transport */

/* Focus: one global rule instead of 13 `outline:none` */
:where(button, a, [role="button"], [tabindex], input, select, textarea):focus-visible { outline: none; box-shadow: var(--focus-ring); }
.lt-card:focus-visible, .lt-video-card:focus-visible { box-shadow: var(--focus-ring-lg), var(--elev-2); transform: scale(1.03); }

/* Accessibility switches: CSS media queries + Swift-forwarded data attributes (WebKit lacks prefers-reduced-transparency) */
@media (prefers-reduced-motion: reduce) { :root { --dur-fast: 1ms; --dur-base: 1ms; --dur-slow: 1ms; --dur-ambient: 1ms; } }
@media (prefers-reduced-motion: reduce) {
  *, *::before, *::after { animation-duration: 1ms !important; animation-delay: 0s !important; transition-duration: 1ms !important; scroll-behavior: auto !important; }
  .spinner { animation: spin 1.6s linear infinite !important; }          /* progress indicator is essential motion; slow it */
  .lt-card:hover, .lt-video-card:hover { transform: none; }
}
:root[data-reduce-motion="true"] *, :root[data-reduce-motion="true"] *::before, :root[data-reduce-motion="true"] *::after { animation-duration: 1ms !important; transition-duration: 1ms !important; }
@media (prefers-reduced-transparency: reduce) { .material, .modal-backdrop, .modal-panel, .lt-glass { -webkit-backdrop-filter: none !important; backdrop-filter: none !important; background: var(--surface-3) !important; } }
:root[data-reduce-transparency="true"] .material, :root[data-reduce-transparency="true"] .modal-backdrop, :root[data-reduce-transparency="true"] .modal-panel { -webkit-backdrop-filter: none !important; backdrop-filter: none !important; background: var(--surface-3) !important; }
@media (prefers-contrast: more) { :root { --text-3: var(--text-2); --line: var(--control-edge); --line-strong: var(--text-3); } }
:root[data-increase-contrast="true"] { --text-3: var(--text-2); --line: var(--control-edge); }
```

Swift side (static sketch, not built): in `WebWindowController` observe `NSWorkspace.accessibilityDisplayOptionsDidChangeNotification` and run
`document.documentElement.dataset.reduceMotion = "<NSWorkspace.shared.accessibilityDisplayShouldReduceMotion>"` (same for `reduceTransparency`, `increaseContrast`) at didFinishNavigation and on change; also
`window.appearance = NSAppearance(named: .darkAqua)` + `window.backgroundColor = NSColor(srgbRed: 0.067, green: 0.059, blue: 0.055, alpha: 1)` so the title bar/resize flash match the page.

Ambient background rules (replace the 8-image stack): max 2 layers x 1 image, `blur(48px) saturate(130%)`, no `hue-rotate`, no `mix-blend-mode`, a 0.78 `--bg` scrim on top;
pause the rotation when `document.hidden`, on reduce-motion/transparency, and while the player is open.

Scrim for text on imagery: channel card = `linear-gradient(to top, rgba(10,8,7,.88) 0%, rgba(10,8,7,.62) 45%, transparent 100%)` and subtitle `--text-2` (alpha>=0.54 needed for 4.5:1 over a pure-white banner; current title row sees ~0.51).
Player: top/bottom scrim stay; transport buttons -> `.on-media` (dark disc, white glyph) and add a 360px radial scrim behind the centre cluster; scrub track `rgba(255,255,255,.42)` + 1px `rgba(0,0,0,.35)` outline.

## 7. Ranked fixes (impact first)
1. **DSG-1 Replace `--text-tertiary` (#55555f) with `#9A9085`-class value** (1 line, `index.css:15`) - fixes 82 failing runs / 50+ uses. S, High.
2. **DSG-2 Fix accent pair**: filled buttons = `--accent` bg + `--accent-ink` text; accent text uses the lifted accent (single token change `index.css:10` + `.lt-btn-primary`, `.lt-btn-xs.primary`, `.lt-editor-toggle.active`, step bubble). S-M, High.
3. **DSG-3 Player controls invisible on bright video**: dark `.on-media` discs, remove the no-op `backdrop-filter` (4 elements), radial scrim behind the centre cluster. S, High (every bright scene).
4. **DSG-4 Reduce Motion / Transparency / Contrast + dark window pin**: CSS block above + Swift forwarding + `appearance = .darkAqua`. M, High (a11y + perf lever; also lets low-end Macs drop the blur).
5. **DSG-5 Add a real focus ring** (`:focus-visible` global rule, two-tone) - 0 exist today. S (CSS) but cards need to become focusable (UX lane). High.
6. **DSG-6 Don't dim error/status text with `opacity: .4`** (`VideoCard.tsx:121`, "Queued" at .24, Retry at .4): dim only thumbnail+title, keep status/action at full contrast. S, Med.
7. **DSG-7 Glass diet**: one `.material` for nav bars, solid `--surface-*` for cards/buttons/badges/inputs, one modal scrim; collapse 14 blur recipes -> 2; remove `will-change` + backdrop-filter combo on cards. M, Med-High (4K perf, 20-32 filter layers on channel page).
8. **DSG-8 Tokenise**: move 358 TSX literals onto semantic tokens (status tints, `--line*`, `--overlay-dark`, radii, z, durations); lint rule banning raw `#hex`/`rgba(` in TSX. L, Med (prevents recurrence).
9. **DSG-9 Ambient background**: 2 layers, 130% saturation, no hue-rotate/blend, pause when hidden/playing; today it produces `#393714` olive and up to ~450 MB surfaces at 4K (suspected). S-M, Med.
10. **DSG-10 Identity**: warm the neutrals (above), retire blue + gradient wordmark, replace 35 emoji-as-icons with Phosphor (type badges, onboarding, empty state), per-profile accent; new app icon with a concept (house/offline + play), delete Vite `favicon.svg`/`icons.svg` from `public/`. M, Med.
11. **DSG-11 Motion cleanup**: replace `--ease` (.89,0,.14,1) with `--ease-standard`, ban `transition: all` (6x), progress bars via `transform: scaleX` instead of `width`. S, Low-Med.
12. **DSG-12 Input boundaries**: `.lt-input` border -> `--control-edge` (1.48:1 -> 3.6:1), checkbox/toggle edges likewise. S, Med.

## 8. Needs a real Mac to confirm
- Whether CSS `backdrop-filter` in the transparent overlay WKWebView blurs the AVPlayerView at all (assumed no); real contrast of controls over real video.
- Light-mode titlebar mismatch / resize flash (no `darkAqua` pin, `drawsBackground=false`).
- GPU/memory cost of the 8-image ambient stack and 20-32 backdrop-filter layers at 4K@2x; frame pacing during card hover.
- `prefers-reduced-motion` / `prefers-contrast` actually reflecting System Settings inside WKWebView on macOS 14; 
- Real banner-derived ambient colours with actual YouTube channel art (harness uses gradient fixtures).

## 9. Cross-lane notes
- UI/UX: video cards are non-focusable `div`s (1 `tabIndex` in the whole WebUI) and `.lt-play-btn` appears only on hover (spec 3.3 "no hover-dependent reveals").
- TYP: real text is 11-20px (settings hints 11-12px, filter chips 12px) vs 28pt spec; body `font-size:20px` (`index.css:60`); SF Pro, not SF Rounded.
- ARC: 575 inline style objects defeat CSS cascade (pseudo-classes, media queries); candidate for extracting `.lt-*` classes.
- UPD/QA: committed bundle CSS is 24 KB - confirm it matches current source before trusting harness == shipped app.

## Addendum: live SwiftUI player
Static review of `Player/VideoPlayerView.swift` (`PlayerControlsOverlay`, :354+) and `Views/Shared/TenFootStyles.swift`; contrast maths in `work-dsg` (frames white/yellow/sky/black; material tint unknown, so disc figures are worst case, `suspected`).

**Which DSG-3 numbers still apply:** none (PlayerScreen.tsx is dead). Correction to DSG-4: `NSWorkspace.shouldReduceMotion` IS used live (`VideoPlayerView.swift:444`, controls fade only); my grep had excluded `Player/`. Hover springs/scale ignore it.

**Real findings**
- Scrims cover only top 160pt / bottom 170pt (:368-381); **nothing behind the centre controls**. Discs = `.ultraThinMaterial` + white 0.16 (:179-181, 217-219), glyph white. Glyph vs disc: white 1.00, yellow 1.23, sky 1.43, black 14.6.
- Back button 15pt white: 3.0 / 3.6 / 4.1 (fails 4.5). Time labels 28pt white .95: 1.75 / 2.18 / 2.56 (fail 3:1; bottom scrim is ~0.24 alpha at label height). Loop-off (.6): 2.6-3.2. Autoplay "Off" (.55): 2.2-2.7. Title 22pt passes (3.7/4.5/5.2).
- Scrub track (.28 white) vs frame 1.05-1.19; gold fill vs yellow frame 1.10.
- Player accent is gold `ltAccent #FFBE00` (TenFootStyles.swift:15) vs WebUI violet: two accents in one product.
- Reduce Transparency: no explicit handling (system materials adapt, suspected; the white overlay stays). Increase Contrast: none (`colorSchemeContrast` absent). Focus: circle/back buttons are `onTapGesture` views (not focusable); Loop/Autoplay are plain Buttons with no ring.

**Corrected fix (paste-ready)**
```swift
enum PlayerChrome {
    static let ink   = Color(red: 0.067, green: 0.059, blue: 0.055)   // #110F0E
    static let focus = Color(red: 1.0, green: 0.957, blue: 0.867)     // #FFF4DD
}
struct ChromeDisc<S: Shape>: ViewModifier {
    @Environment(\.accessibilityReduceTransparency) private var rt
    @Environment(\.colorSchemeContrast) private var contrast
    @Environment(\.accessibilityReduceMotion) private var rm
    let shape: S; var hovered = false; var pressed = false; var focused = false
    func body(content: Content) -> some View {
        content
            .background(shape.fill(PlayerChrome.ink.opacity(pressed ? 0.82 : hovered ? 0.72 : (rt || contrast == .increased) ? 0.88 : 0.62)))
            .overlay(shape.strokeBorder(Color.white.opacity(contrast == .increased ? 0.7 : 0.30), lineWidth: 1))
            .overlay(shape.stroke(PlayerChrome.focus, lineWidth: 3).padding(-5).opacity(focused ? 1 : 0))
            .scaleEffect(rm ? 1 : (pressed ? 0.92 : hovered ? 1.06 : 1))
    }
}
```
Replace the three `.ultraThinMaterial` + white-fill stacks with `.modifier(ChromeDisc(shape: Circle(), …))` (RoundedRectangle for Back); make them `Button`s with `@FocusState`. Add behind the centre HStack `RadialGradient(colors:[.black.opacity(0.35), .clear], center:.center, startRadius:0, endRadius:240)`. Bottom scrim stops `[.clear, .40, .62, .78]` over 220pt; labels `.shadow(color:.black.opacity(0.6), radius:3)`; secondary icons `.white.opacity(0.85)`; scrub track `.black.opacity(0.35)` 1pt outline. Result: glyph vs disc 5.4 / 6.3 / 7.0 / 19.9.
