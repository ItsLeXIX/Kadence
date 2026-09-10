# screenshots/p2-t02 — click-to-select defect, before and after

Task P2-T02. Two captures of the **same click on the same block**, differing
only in the one-line modifier ordering that was the defect. See STATUS.md §1.6.

Both were produced mechanically, not by hand: build → launch a fresh instance →
park the pointer off-window → move the window to a fixed origin (100, 60) and
size it 1500×900 → read "Datenmodellierung"'s rectangle from the accessibility
tree → post a real `CGEvent` mouseDown/mouseUp at its centre → screencapture the
window region. The accessibility `AXSelected` value was recorded at capture time
and is quoted below, so each image has a machine-checked claim attached to it.

Dataset: the fixed mock dataset (`Kadence/Mock/MockData.swift`), reseeded before
capture, so these are comparable with other phases' captures. Appearance: dark.
View: Week, showing 7–13 Sep 2026.

| file | state it shows |
|---|---|
| `before-click-block-does-nothing.png` | **The defect.** `.contentShape` applied *after* `.offset` in `DayColumnView.blockStack`. A click at the centre of "Datenmodellierung" (09:00–10:30, Fri 11). `AXSelected` for that block after the click: **`no`**. The block has no selection ring, and the inspector shows **"Late lab session" (22:30–23:30)** — a block thirteen hours away that was never clicked. The click could not land on the block it was aimed at, because every block's hit region had collapsed onto the day column's top-left corner. |
| `after-click-selects-block.png` | **Fixed.** `.contentShape` before `.offset`. The identical click on the identical block. `AXSelected` after the click: **`true`**. The selection ring renders around "Datenmodellierung", and the inspector shows Datenmodellierung — 09:00, 10:30, 1 h 30 min, FH B.2.09, imported. |

**What to compare.** Only two things differ between the images: the selection
ring, and the inspector's contents. Every block draws in exactly the same place
in both. That is the point, and it is why no screenshot review could ever have
caught this defect on its own — the rendering was never wrong. Only a real click
tells you anything, which is what `Scripts/check-block-click-selects.sh` now
does on every run.

## Known open at capture time

- **G-010** (`design/GAPS.md`) — interactions.md §6 does not say which block a
  click selects when the click point is inside two overlapping blocks. Visible
  here as the "Overlap 1–5" cascade on Sat 12; clicking into it selects the
  frontmost block, which is current behaviour rather than a specified rule.
- **A24** (`DEVIATIONS.md`) — one block ("Statistik übung", 10:45–11:45 Fri 11)
  reports `AXSelected = true` to accessibility even when nothing is selected.
  Not visible in either image — it has no visual effect, and it is not our
  trait — but it is live in both.
- **The block-overlap rendering defect** is untouched and visible in both images
  in the Sat 12 cascade. It is the next task and was deliberately out of scope
  for P2-T02.
- **B9** (`DEVIATIONS.md`) — selection still does not scroll into view on a view
  change. Not exercised by these captures.
- **A20b** — blocks reach the accessibility tree carrying the §3.4 hover-help
  string instead of the §11 label. That is why the tooling above matches blocks
  on `AXHelp`.
