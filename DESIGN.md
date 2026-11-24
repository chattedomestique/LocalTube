# LocalTube — Design Rules

> **This file is the single source of truth for sizes, shapes and spacing.** If a screen, mockup or component contradicts it, the screen is wrong, not the file.
> Colour tokens come from [`audit-2026-11/dsg.md`](audit-2026-11/dsg.md) §6 and type roles from [`audit-2026-11/typography.md`](audit-2026-11/typography.md) §4; this file adds the part those two leave open: **how big things are, how round they are, and how they nest.**
> Mockups that follow it: [`audit-2026-11/mockups/`](audit-2026-11/mockups/). A consistency checker for them: [`audit-2026-11/mockups/lint.cjs`](audit-2026-11/mockups/lint.cjs).
>
> **Revision 2 (2026-11-24).** Controls are **10 px rounded rectangles, not pills.** This was the owner's decision, made by editing the Channel board; the rest of the system was derived from it (§3).

All numbers are **1× design px**. The TV view is the same layout under `pageZoom` 1.6 (see §9), so nothing here is written twice.

---

## 0. The five rules (these prevent almost every inconsistency)

1. **One ruler for heights: 28 · 36 · 44 · 56 · 64 · 80.** No other height is allowed on anything a person can press, type into or read as a chip. (§2)
2. **One row, one height.** Every control that shares a row or toolbar uses the same height token. A search field, its filter chips and the Sort menu are all 44. (§6)
3. **One corner radius for everything small: 10.** Buttons, icon buttons, chips, fields, selects, the segmented control, badges and option rows are all `border-radius: 10px`. Cards are 18, dialogs 26. (§3)
4. **Corners nest concentrically.** Whatever touches a rounded corner of its container has `inner radius = outer radius − inset`; a container built around a control has `outer = control radius + inset`. **Small avatars are rounded squares with that concentric radius (6).** (§3, §4)
5. **Height is set by `height`, never by padding.** `box-sizing: border-box`, borders live *inside* the height, padding only moves content sideways. (`min-height` plus padding is how a "44" button became 46.) (§8)

---

## 1. Foundations

| Thing | Rule |
|---|---|
| Base unit | **4 px.** Spacing scale: `4 · 8 · 12 · 16 · 24 · 32 · 48`. Nothing else. |
| Page gutter | **40 px** left and right on every screen (wordmark, tabs, titles, grids all start at 40). |
| Gap between controls in a row | **12** (inside a tight group such as a segmented control: **8**; between groups: **16–24**). |
| Section rhythm | Title → content **12**; section → section **24**; dialog sections **16–20**. |
| Alignment | Rows use `align-items: center`. Never align controls by baseline, and never nudge with margins. |
| Borders | **1 px**, always counted *inside* the box. Focus uses `box-shadow`, so it never changes layout. A container never gets a decorative border by accident: check the properties panel after editing. |
| Min window | 900 px wide. TV mode is capped so the CSS viewport stays ≥ 900 px (see typography §4.5). |

---

## 2. The height ruler

| Token | px | Name | Use | Label type | Icon | Padding-x | At TV ×1.6 |
|---|---|---|---|---|---|---|---|
| `--h-xs` | **28** | Badge | **Display only**, never pressable: duration, count, status | 14/700 | 14 | 10 | 45 |
| `--h-sm` | **36** | Small | **Grown-up screens only** (Settings tables, dense admin rows). Never on a viewer screen. | 14/600 | 16 | 14 | 58 |
| `--h-md` | **44** | Medium | **The default.** Every button, input, select, chip, segmented control, icon button and overlay button. | 16/600 | 20 | 20 | 70 |
| `--h-lg` | **56** | Large | One hero action per screen or dialog, TV-first flows (error recovery, onboarding). Also banner bars and the toast. | 18/700 | 24 | 28 | 90 |
| `--h-xl` | **64** | XL | Secondary player transport; the player's bottom bar | – | 32 | – | 102 |
| `--h-2xl` | **80** | 2XL | Primary play/pause | – | 40 | – | 128 |

Notes that settle the usual arguments:

- **Viewer screens never go below 44.** A child's target is `md` or bigger. `sm` is for the parent doing admin work with a mouse.
- **The 96 pt ten-foot target in the original spec** is met by `xl`/`2xl` at ×1.6 and by `lg` at the "Big" ×2.0 setting (112). `md` at ×1.6 is 70 px, comfortable for a pointer, tight for a remote. Put the one action a child must hit on `lg` or bigger.
- **Pairs match.** Two buttons side by side are the same token. Cancel + Primary are both `md`; a recovery screen's two buttons are both `lg`. Never `md` + `lg` in a pair.
- **Icon-only buttons are square:** `width = height`.
- **Bars** are not controls but follow the same ruler: header **72**, tab bar **56** (`lg`), toolbar row **68** (= `md` 44 + 12 above and below), edit banner **56** (`lg`), channel banner **104**.
- **Progress bars** are 4 (thin, on imagery / inside chips), 6 (lists), 8 (the scrub bar). They are not controls.
- **Native inputs:** checkbox and radio are **20 × 20**, `accent-color: var(--accent)`.

---

## 3. Shape and radius

### 3.1 Radius tokens

| Token | Value | Used by |
|---|---|---|
| `--r-1` | 8 | Menus, tooltips, tiny inset images |
| `--r-ctl` | **10** | **Every control and every small thing:** button, icon button, chip, search field, URL field, select, segmented control (outer), status chip, profile chip, **28 px badges**, option rows, brand logo tiles (36 / 40). Same value at `sm`, `md` and `lg`. |
| `--r-3` | 18 | **Cards, thumbnails, panels**, anything that holds a picture |
| `--r-4` | 26 | **Dialogs and sheets** |
| `--r-tile` | `28%` | **Profile / icon tiles ≥ 96 px**, standalone only (§4) |
| derived | see §3.2 | Segmented inner buttons (6), small avatars (6), a toast (16), the player bar (20) |
| checkbox | 6 | Checkbox only; radio is a circle |

**Fields use the same 10** as the buttons beside them, so a toolbar is one shape language. (Multi-line text areas also 10.) The old `--r-2` (12) is retired: use 10.

**What stays round (and why it is not a contradiction):**

- **Play / transport controls of 64 px and up** (skip, play-pause, the play button on a focused card) are **circles**. They are the one place a child looks for.
- **Indicators that are not pressable**: stepper numbers, status icons (check, spinner), the warning badge on an icon tile. They sit alone, never in a rounded container's corner.
- **Progress tracks and the scrub knob** (a fill, not a control).

### 3.2 Concentric corners

When something sits against a rounded corner of its container, the radii differ by the inset:

```
child radius     = max(container radius − inset, 0)        when the child is the smaller thing
container radius = child radius + inset                    when the container is built around a control
inset            = padding + border on that side, measured from the container's outer edge
```

Worked cases (all appear in the mockups; the checker verifies each):

| Container | Inset | Child | Result |
|---|---|---|---|
| Segmented control, 44, r **10** | 4 (3 padding + 1 border) | inner button | **36 tall**, r **6** |
| Profile chip, 44, r **10** | 4 | avatar | **36 × 36**, r **6** |
| "Show it to" chip, 44, r **10** | 4 | avatar | **36 × 36**, r **6** |
| Card, r **18** | **8** | any 44 overlay control (heart, handle, remove) | r **10** (= 18 − 8) |
| Card, r **18**, padding 11 + border 1 | 12 | avatar 56 | r **6** (= 18 − 12) |
| Toast, **56** | 6 | Undo button, r 10 | toast r **16** (= 10 + 6) |
| Player bottom bar, **64** | 10 | 44 icon buttons, r 10 | bar r **20** (= 10 + 10) |
| Dialog, r **26** | 28 | fields and buttons | not at the corner: no rule applies |

An element that is **a full radius away from the corner** does not need to follow the rule. The test: *does its edge run parallel to the container's curve?* If yes, make it concentric. **Overlays on a card sit at inset 8**, not 12, precisely so a 10 px control is concentric with the card's 18 px corner.

---

## 4. Avatars

| Size token | px | Used for |
|---|---|---|
| `xs` | 24 | Inline mentions, dense lists |
| `sm` | 32 | Dense admin lists |
| **chip** | **36** | **Inside a 44 chip** (profile chip, "Show it to" chips): `44 − 2 × 4` |
| `md` | 40 | List rows |
| `lg` | **56** | Preview cards (a found channel), settings rows |
| `xl` | 96 | Profile editor header |
| `tile` | **152** | The "Who's watching?" picker |

**Shape (this is the rule that stops avatars clashing with their container):**

- **Below 96 px an avatar is a rounded square with the concentric radius**, which in both standard containers works out to **6** (chip: 10 − 4; card: 18 − 12). It is never a circle and never a 28 % squircle inside a rounded container.
- **96 px and up is a squircle** (`border-radius: 28%`), **standalone only**: it is never inside a rounded container.
- **Inside a chip, avatar size = chip height − 2 × inset**, inset 4 → `44 − 8 = 36`. The offset from the chip's outer edge is **4 on every side** (padding-left 3 + 1 px border), which is what keeps the curves parallel.
- Glyph or initials are **50 %** of the avatar, centred, ink `#17120F` on the profile colour. Initials use Label type at weight 700.
- Mark every avatar element `data-avatar` so the checker finds it.
- The focus ring is a `box-shadow` on the avatar element itself, so its curve always matches.

---

## 5. Component specs

`H` = a height token from §2. All controls: `display:inline-flex; align-items:center; gap:8px; box-sizing:border-box; height:H; border-radius:10px`.

| Component | Height | Radius | Padding-x | Type | Notes |
|---|---|---|---|---|---|
| **Button — primary** | md / lg | 10 | 20 / 28 | 16/600, 18/700 | `--accent` fill, `--accent-ink` text. One per row. |
| **Button — secondary** | md / lg | 10 | 20 / 28 | same | Transparent, 1 px `--control-edge`, text `--text-1`. |
| **Button — ghost** | md | 10 | 20 | 16/600 | No border; text `--text-2`. |
| **Button — on media** | md | 10 | 20 | 16/600 | `rgba(17,15,14,.62)` + 1 px `rgba(255,255,255,.18)`, white text. Never blurred. |
| **Icon button** | md (square 44 × 44) | 10 | 0 | – | 20 px icon. On a card: **inset 8** from the thumbnail edge. |
| **Leading-icon button** | md | 10 | **14** start, 20 end | 16/600 | Icon 20, gap 8. |
| **Filter chip** | md | 10 | 20 | 16/600 | Selected: `--accent-tint` fill, 1 px `--accent-edge`, text `--accent`. Not selected: like secondary. Same height as the search field beside it. |
| **Search / text field** | md | 10 | 14 (20 end with an icon at 16) | 16/500 | Icon 20 at 16 from the edge → text starts at **44**. Fill `--surface-2`, 1 px `--control-edge`. Placeholder `--text-3`. Always has a `<label>` or `aria-label`. |
| **Select (Sort)** | md | 10 | 20 / chevron 20 at 14 from the edge | 16/600 | Same fill and edge as the search field. |
| **Segmented control** | md outer | 10 | – | 16/600 | Padding 3 + border 1; inner buttons **36 × 48, r 6**. Selected = `--accent` fill + `--accent-ink`. Both inner buttons get the same radius, selected or not. |
| **Tabs (underline)** | **56** bar | none | 2 | 16/600 | The only controls with no radius. Active tab: 3 px `--accent` underline. Controls on the right of the same bar are `md`, vertically centred. |
| **Profile chip** | md | 10 | 3 start, 14 end | 16/600 | 36 avatar (r 6), name, 20 px chevron. |
| **Status chip** (header download) | md | 10 | 16 | 14/600 | Lives in a row with `md` controls, so it is `md` too. |
| **Badge** (duration, count, status) | **xs 28** | 10 | 10 | 14/700, tabular | Display only. On imagery: `rgba(17,15,14,.62)`, **inset 8**. A badge inside a button keeps ≥ 14 from the button's end so it is clear of the corner. |
| **Checkbox / radio** | 20 | 6 / circle | – | – | Native; the whole label row is the target (`md`). |
| **Option row** (radio card) | 50 | 10 | 14 | 16/600 + 14/500 | Two lines. Selected: `--accent-tint` + `--accent-edge`. |
| **Card (video / channel)** | – | 18 | – | – | 16:9 thumbnail, title slot of two lines, one meta line. Overlays **inset 8**. |
| **Toast** | **56 (lg)** | **16** | 5 end, 22 start | 16/500 | Action button inside is `md` (r 10), inset 6. |
| **Dialog** | auto | 26 | 28 | – | Title row **44** (title + close icon button). Sections 16–20 apart. Footer: right-aligned, gap 12, buttons `md`. |
| **Banner (edit / hero)** | 56 / 104 | none | 40 | – | Controls inside are `md`, centred. |
| **Player transport** | 64 / **80** / 64 | **circle** | – | – | Skip · play-pause · skip. Dark disc `rgba(17,15,14,.62)`; glyph 32 / 40. |
| **Player bottom bar** | **64 (xl)** | **20** | 28 start, 9 end (+1 border) | 18/700 numeric | Time, scrub (8), volume + sleep `md` icon buttons (r 10) at inset 10. |

**States.** Hover: one surface step lighter (`--surface-2 → 3`) or accent tint. Pressed: `scale(.98)` in 90 ms. Focus: `--focus-ring` (`0 0 0 3px bg, 0 0 0 6px #FFF4DD`), `--focus-ring-lg` (4 / 8) on cards. **Disabled: `--surface-3` fill with `--text-2` text, never `opacity`** (opacity fails contrast). Every hover affordance must also show on focus; nothing important appears on hover only.

---

## 6. Layout recipes

**One row, one height.** The recipes below are the only row shapes. If a design needs something else, change the design.

| Recipe | Container | Contents (all share one height) |
|---|---|---|
| **Header** | height **72**, gutter 40 | Wordmark · status chip `md` · profile chip `md` |
| **Tab bar** | height **56**, gutter 40 | Tabs (56, underline) · right: `md` buttons / selects, gap 12 |
| **Toolbar** | height **68** (44 + 12 + 12), gutter 40 | Search `md` · filter chips `md` · (spacer) · Sort `md` |
| **Banner header** | height **104**, gutter 40 | Back `md` · title 30/700 · badge `xs` · (spacer) · segmented `md` · button `md` |
| **Edit banner** | height **56**, gutter 40 | Label · (spacer) · Done `md` |
| **Dialog footer** | top margin 20 | Cancel `md` · Primary `md`, right-aligned, gap 12 |
| **Hero (recovery / onboarding)** | centred column | Icon tile 120 · title 30/700 · body 18 · buttons `lg` pair, gap 16 |
| **Video grid** | 4 columns, gap **20**, gutter 40 | Thumbnail 16:9 · 2-line title slot (`2.7em`) · one 14/500 meta line |

---

## 7. Colour, type, motion (pointers only)

Don't redefine these here; use them as defined.

- **Colour:** `--bg #110F0E`, `--surface-1…3 #1A1715 / #231F1C / #2E2925`, `--text-1…3 #F3EDE4 / #C2B8AC / #9A9085`, `--accent #B79CFF`, `--accent-ink #1B1033`, `--control-edge #7A6F64`, status `--ok #6EDBA5 / --warn #FFCB5C / --bad #FF7B72`, `--focus #FFF4DD`. Full set and contrast ratios: dsg.md §6.
- **Type:** Display 40/800 · Title 30/700 · Headline 22/700 · Body 18/500 · Label 16/600 · Caption 14/500. Numbers (durations, counts, percentages) use `tabular-nums`. Font stack `ui-rounded, system-ui, …`. Full table: typography.md §4.2.
- **Motion:** press 90 ms, hover/focus 140 ms, enter 220 ms, `cubic-bezier(.2,0,0,1)`. All motion collapses under Reduce Motion.
- **Icons:** one stroke family, **stroke 2.2**, round caps and joins, sized by control (14 / 16 / 20 / 24 / 32 / 40). No emoji as UI icons.

---

## 8. Implementation (paste-ready)

```css
:root {
  --h-xs: 28px; --h-sm: 36px; --h-md: 44px; --h-lg: 56px; --h-xl: 64px; --h-2xl: 80px;
  --r-1: 8px; --r-ctl: 10px; --r-3: 18px; --r-4: 26px; --r-tile: 28%;
  --sp-1: 4px; --sp-2: 8px; --sp-3: 12px; --sp-4: 16px; --sp-5: 24px; --sp-6: 32px; --sp-7: 48px;
  --gutter: 40px;
}

/* every single-line control. Height is set, never derived from padding. */
.lt-ctl {
  --h: var(--h-md);
  box-sizing: border-box; display: inline-flex; align-items: center; justify-content: center; gap: 8px;
  height: var(--h); padding: 0 20px; border: 1px solid transparent; border-radius: var(--r-ctl);
  font: 600 16px/1 var(--font-ui); white-space: nowrap;
}
.lt-ctl--sm   { --h: var(--h-sm); padding: 0 14px; font-size: 14px; }          /* grown-up screens only */
.lt-ctl--lg   { --h: var(--h-lg); padding: 0 28px; font-size: 18px; font-weight: 700; }   /* same 10px radius */
.lt-ctl--icon { width: var(--h); padding: 0; }                                  /* icon-only = square */
.lt-ctl--lead { padding-inline-start: 14px; }                                   /* leading 20px icon */

.lt-btn-primary   { background: var(--accent); color: var(--accent-ink); }
.lt-btn-secondary { background: transparent; border-color: var(--control-edge); color: var(--text-1); }
.lt-btn-ghost     { background: transparent; color: var(--text-2); }
.lt-on-media      { background: var(--overlay-dark); border-color: rgba(255,255,255,.18); color: #fff; }
.lt-btn-primary:disabled, .lt-btn-secondary:disabled { background: var(--surface-3); border-color: var(--line); color: var(--text-2); }

/* text fields share the control height and radius */
.lt-field { --h: var(--h-md); box-sizing: border-box; height: var(--h); width: 100%; padding: 0 14px; border-radius: var(--r-ctl);
  background: var(--surface-2); border: 1px solid var(--control-edge); color: var(--text-1); font: 500 16px/1 var(--font-ui); }
.lt-field--search { padding-inline-start: 44px; }   /* 16 + 20 icon + 8 */

/* segmented: inner = outer - 2 x (padding 3 + border 1); inner radius = 10 - 4 = 6 */
.lt-seg { --h: var(--h-md); --inset: 4px; box-sizing: border-box; display: inline-flex; height: var(--h); padding: 3px;
  border: 1px solid var(--control-edge); border-radius: var(--r-ctl); }
.lt-seg > button { height: calc(var(--h) - 2 * var(--inset)); width: 48px; border: 0; border-radius: calc(var(--r-ctl) - var(--inset)); }

/* avatars: concentric rounded square below 96, 28% squircle tile at 96+ and never nested */
.lt-avatar { --size: 36px; --parent-r: var(--r-ctl); --inset: 4px;
  width: var(--size); height: var(--size); border-radius: calc(var(--parent-r) - var(--inset)); display: grid; place-items: center; flex: none; }
.lt-avatar--tile { --size: 152px; border-radius: var(--r-tile); }
.lt-chip--avatar { --inset: 4px; padding-inline-start: calc(var(--inset) - 1px); }      /* −1 for the border */
.lt-chip--avatar .lt-avatar { --size: calc(var(--h) - 2 * var(--inset)); }               /* 44 − 8 = 36, radius 10 − 4 = 6 */
.lt-card .lt-avatar { --parent-r: var(--r-3); --inset: 12px; --size: 56px; }             /* 18 − 12 = 6 */

.lt-badge { box-sizing: border-box; display: inline-flex; align-items: center; height: var(--h-xs); padding: 0 10px; border-radius: var(--r-ctl);
  font: 700 14px/1 var(--font-ui); font-variant-numeric: tabular-nums; }
.lt-card .lt-overlay { position: absolute; inset-block-start: 8px; }                     /* overlays sit at 8 so a 10px control is concentric with r18 */

/* a container built around a control derives its radius from it */
.lt-toast  { box-sizing: border-box; height: var(--h-lg); padding: 0 5px 0 22px; border-radius: calc(var(--r-ctl) + 6px); }   /* 16 */
.lt-player-bar { box-sizing: border-box; height: var(--h-xl); padding: 0 9px 0 28px; border-radius: calc(var(--r-ctl) + 10px); } /* 20 */

/* focus never changes layout */
:where(button, a, [tabindex], input, select):focus-visible { outline: none; box-shadow: var(--focus-ring); }
```

SwiftUI (the player overlay) uses the same numbers, so the two UIs cannot drift:

```swift
enum LT {
    enum H { static let xs: CGFloat = 28, sm = 36, md = 44, lg = 56, xl = 64, xxl = 80 }
    enum R { static let r1: CGFloat = 8, ctl = 10, card = 18, dialog = 26 }
    static let tile: CGFloat = 0.28          // fraction of side, 96pt and up only
}
// a control: fixed height, 10pt continuous rounded rectangle, border counted inside
Button(action: back) { Label("Back", systemImage: "chevron.left") }
    .frame(height: LT.H.md)
    .background(RoundedRectangle(cornerRadius: LT.R.ctl, style: .continuous).fill(Color.black.opacity(0.62)))
    .overlay(RoundedRectangle(cornerRadius: LT.R.ctl, style: .continuous).strokeBorder(Color.white.opacity(0.18), lineWidth: 1))
// player transport (64pt and up) is the one Circle(); everything else uses LT.R.ctl.
// multiply by uiScale only through a metrics struct; do not write literal sizes in views (typography.md §4.5)
```

---

## 9. TV scale

The TV is **the same layout under `pageZoom`**, not a second set of sizes. At ×1.6 a 1920 × 1080 screen has a 1200 × 675 CSS viewport, which is how the mockups are drawn. Because every rule above is expressed in the 1× ruler, scaling keeps all heights, radii and nesting intact (44 → 70, radius 10 → 16, avatar 36 → 58, inset 4 → 6.4 all stay concentric). The SwiftUI player multiplies the same `LT` constants by `uiScale`.

---

## 10. Review checklist and the linter

Before merging any UI change, check:

- [ ] Every control's height is on the ruler; none is 38, 40, 42, 46, 48 or 52.
- [ ] Controls in one row share a height; pairs share a token.
- [ ] Every control, badge and option row has radius **10**; nothing small is a pill or 12.
- [ ] Anything touching a container's curve is concentric (inner = outer − inset); a toast is 16, the player bar 20.
- [ ] Small avatars are rounded squares with the concentric radius (6); tiles ≥ 96 are 28 % squircles, standalone. Every avatar is marked `data-avatar`.
- [ ] Only 64 px+ transport / play controls and non-pressable indicators are circles.
- [ ] Heights come from `height`, not `min-height` + padding; borders are inside.
- [ ] No container has a stray border or border-radius left behind by the editor.
- [ ] Disabled uses the surface fill, not `opacity`.
- [ ] Viewer screens use `md` or larger; `sm` appears only on admin screens.
- [ ] Nothing important is hover-only; every control shows a focus ring.

`audit-2026-11/mockups/lint.cjs` runs these checks on the mockup sources. It measures every button, input, status chip, 28 px badge and `data-avatar` element, and fails on: a height off the ruler; a row that mixes heights; a control radius other than 10 (a container around a control must be inner radius + inset; the segmented inner buttons 10 − inset; 64 px+ transport circles are allowed); a badge radius other than 10; an avatar that is not concentric with its parent, or a 96 px+ tile that is not a 28 % squircle or sits in a rounded parent. A version that runs the same measurements against the live app through the mock-bridge harness is part of the test plan (gameplan item 19).

```bash
node audit-2026-11/mockups/lint.cjs audit-2026-11/mockups/project
```

---

## 11. Decisions

**Made.**

1. **Controls are 10 px rounded rectangles, not pills** (owner, on the Channel board, 2026-11-24). Everything else in §3–§5 follows from it.
2. **Two assumptions I made while applying it, easy to flip:** icon-only buttons and the overlay buttons on thumbnails are 10 px rounded squares (not circles); 28 px badges use the same 10.

**Still open.**

1. **Filter chips at 44 instead of 36.** More consistent and TV-safe, but heavier next to dense lists. Recommendation: accept in viewer screens; use `sm` for the whole row on admin screens.
2. **Small avatars as 6 px rounded squares.** The real app's `ProfileAvatar` draws squircles at every size (radius .20–.32), so adopting §4 changes the profile chip, the picker thumbnails and the profile editor. Recommendation: adopt it; it is the only way avatars fit a 10 px chip.
3. **Transport 64 / 80** instead of the current 66 / 84, so the player also sits on the ruler.
4. **Tab bar 56** (was 48) so 44 controls fit on the same bar with 6 px above and below.
5. **The same 10 px radius on the 56 px `lg` buttons.** A single radius is simplest, but 56 px buttons may read as slightly tighter than 44 px ones. If it looks off on a TV, the alternative is a proportional scale (8 / 10 / 12).
