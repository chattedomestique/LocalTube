# LocalTube proposed GUI mockups

Source of the design canvas ("LocalTube — Proposed GUI Mockups"). Eight artboards at 1200 x 675 px, which is
exactly a 1920 x 1080 TV at the proposed `pageZoom` 1.6, drawn with the 1x tokens from `/DESIGN.md`.

| File | Screen |
|---|---|
| `Main.dc.html` | Who's watching? |
| `Library.dc.html` | Library |
| `Channel.dc.html` | Channel |
| `Player.dc.html` | Player controls on a bright frame |
| `PlayerError.dc.html` | Video can't play |
| `Setup.dc.html` | First run: get downloads ready |
| `AddChannel.dc.html` | Add a channel |
| `Editing.dc.html` | Editing: idle prompt and undo |

`project/canvas.json` is the canvas index (artboard positions). The `.dc.html` files are design-canvas
components: they load a `support.js` runtime that the canvas supplies, so they are not standalone pages.
Thumbnails are gradients; the "Nunito" font stands in for SF Rounded (`ui-rounded` on a Mac).

## Consistency check

```bash
node audit-2026-11/mockups/lint.cjs audit-2026-11/mockups/project
```

Needs Playwright. Measures every control and avatar and fails on anything that breaks `/DESIGN.md`:
heights off the ruler (36/44/56/64/80), controls in a row with different heights, single-line controls that are
not pills, avatars below 96 px that are not circles. Exit code 1 on any problem.
