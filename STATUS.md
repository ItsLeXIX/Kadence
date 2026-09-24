# Status

Updated: **2026-09-18**
Phase 1: **complete and verified.** Phase 2: **designed, not built.** Phase 3:
**neither designed nor built.**

This file was reconciled against the actual tree on 2026-09-10 (task P3-T01).
Everything below was re-derived from the working copy and from commands re-run
in that session — not carried over from the previous text. Several claims in the
old version were wrong and are corrected in place; where a correction matters,
it says so.

**Amended 2026-09-10 by task P2-T01 (crash fix).** §1.1 and §1.2 are corrected —
both re-run this session with different results. §1.4 has a new count. §1.5 is
new and records the crash, its root cause and its fix. §5 is re-ordered: the
crash outranked everything that was listed as next, and is now done.

**Amended 2026-09-11 by task P2-T02 (click-to-select fix).** §1.6 is new and
records that defect, its root cause and its fix. §1.4 has a new count (140
unique). §5 is re-ordered again. Note for anyone reading the old §2/§5 text:
they described selection as working. Selection by *keyboard* worked; selection
by *mouse* did nothing at all, and had not since the hit region regressed. See
§1.6 and the corrected DEVIATIONS.md B9.

**Amended 2026-09-11 by task P2-T03 (block-overlap diagnosis — report only).**
§1.7 is new. That task changed **no** code: it reproduced and root-caused the
three symptoms Parsa reported and filed the two spec questions they raised
(G-011, G-012). §1.1, §1.3 and §1.4 were re-run and are **unchanged** — build
succeeded, 160 `passed` lines / 140 unique / 0 failed, `--check` green — so
nothing in those sections needed correcting. §5.2 lists the new gaps. The fix is
a separate, future task.

**Amended 2026-09-11 by task P2-T05 (fix symptom (a), and the Week half of (c),
per G-011's CLOSED ruling in `design/GAPS.md`).** §1.7 is rewritten in place:
(a) and (c)-Week are now **fixed**, verified against the two named fixtures
("Stand-up" / "Check mail") and against the "Datenmodellierung" Week strip case.
`DensityTier`'s boundaries are now 18/28/53 (`components.md` §3.3); §3.5's new
confinement invariant is implemented in `GridBlockView` and `DraftBlockView`
(top-anchored `.frame(height:, alignment: .top)` before `.clipShape`, in that
order). (c)-Day remains open as **G-012**, unchanged, out of scope for this
task. §1.4's count is updated (156 unique / 184 lines, +16 unique from
`BlockConfinementTests.swift`). §5 and §5.2 are corrected: G-011 is closed,
G-012 is the only symptom-(c) gap left open. DEVIATIONS.md D4 and B13 are
resolved and moved out of the open tables. `DayLayoutEngine.swift` was **not**
touched — confirmed by diff against the commit immediately before this task.

**Amended 2026-09-11 by task P2-T06 (build G-012's already-CLOSED ruling — fix
(c)-Day).** §1.7 is rewritten in place again: **(c)-Day is now fixed**, per
`design/GAPS.md` G-012's CLOSED ruling in `layouts.md` §3.3 (layout footprint,
steps 1 and 2 restated to share it) and `components.md` §4 (z-order line
amended). This was a ruling built at the spec level only by DA's task P2-T04
and left unimplemented; P2-T06 is the code side. `LayoutItem` gained an
optional `departAt`, `footprintTop`/`footprintBottom`, and `cluster`,
`sortForLayout` and `packIntoSubColumns` now all key off the footprint instead
of raw `start`/`end`; `DayColumnView.layoutItems` now supplies each event's
travel-band `departAt` (`fixtures.travel(forEvent:)?.departAt`, `nil` when
there is no band). Verified: build succeeds, no new warnings;
`KadenceTests` — 189 `passed` lines / 160 unique / 0 failed, including five new
`DayLayoutEngineTests.swift` cases that pin the spec's own worked example
("Morning review" 08:00–09:00, "Datenmodellierung" 09:00–10:30, 22-minute band
departing 08:38): the pair clusters and packs into 2 side-by-side sub-columns
at `hourHeightDay` (case 1) and does *not* cluster at `hourHeightWeek` (case 2,
unchanged behaviour), plus a no-band control case. `design/` was not touched —
the ruling already existed there; this task only built it. No live on-screen
capture was taken — out of scope per this task's brief, a separate follow-up.

**Amended 2026-09-11 by a follow-up task (P2-T06 fix — `check-accessibility.sh`
regressed to `FAIL: no Kadence process has a window` after the commit above).**
§1.2 is rewritten in place: the failure was investigated and is **not a defect
in `DayLayoutEngine.swift` or `DayColumnView.swift`**. Reproduced by hand
(`open`/direct launch, no `check-accessibility.sh` involved): a launch showed
AppKit's own log reporting window restoration succeeding (non-nil window,
`error=(null)`), yet `System Events` reported 0 windows and a screen capture
showed nothing on screen — stale/corrupted saved window-restoration state
(`~/Library/Saved Application State/XIX.Kadence.savedState`, most likely left
over from the earlier interrupted P2-T06 session) was silently failing to
present the restored window. Launching once with `-ApplePersistenceIgnoreState
YES` wrote a fresh, good state file; every launch after that — with no flag —
came up normally. Code review of both files found no force-unwrap, no
precondition, and no unbounded loop (`packIntoSubColumns`'s expansion loop is
bounded by `subColumnCount`); `fixtures.travel(forEvent:)` is a plain `.first`
optional lookup, safe for events with no travel fixture. `sample` on a hung
reproduction showed the main thread parked in `mach_msg2_trap` (idle, waiting
for events) at 0% CPU — not spinning, not deadlocked in layout code. Two
consecutive clean runs of `Scripts/check-accessibility.sh` (all Kadence
processes killed first) both **PASS**ed — see §1.2. A second agent session was
independently assigned this same fix task concurrently on this machine
(duplicate assignment, flagged to the orchestrator); some of the intermittent
failures seen mid-investigation were the two sessions' `pkill`/`open -n`
sequences racing each other, which is a separate, purely environmental
artefact of running two verification passes at once and not evidence of a
code defect either. No change was made to `Kadence/Layout/DayLayoutEngine.swift`
or `Kadence/Views/Canvas/DayColumnView.swift` by this follow-up task.

**IMPORTANT — the paragraph immediately above did not hold up.** Independent
machine verification of P2-T06's HEAD (`2e5c211`/`a3cece1`/`90cd142`) has since
**failed twice** — once `no Kadence process has a window`, once a window found
but `block-shaped elements in the tree: 0` — after that follow-up task reported
"two consecutive clean PASSes" and treated the regression as resolved. It was
not. Task **P2-T07** (2026-09-11, report-only, no code touched) was assigned to
re-derive this from scratch rather than trust the prior agent's claim, and its
findings are below as a new §1.2 sub-entry. **`check-accessibility.sh` is not
being marked PASS by this correction — the independent-verification result
stands at FAIL until a fix lands and is independently reverified.** What
P2-T07 adds: this session could not reproduce the failure either (5/5 clean
runs passed, plus 6 more timed launches, all fast and clean), and — the part
the prior follow-up's code-review-only conclusion did not have — direct timing
evidence that the footprint-clustering code added by P2-T06 renders all 20
blocks in ~1s, statistically indistinguishable from the pre-P2-T06 baseline at
commit `03fb5cd`, which also renders in ~1s. That rules out "the fixed 9s
sleep is no longer enough" as the mechanism. See the new §1.2 sub-entry for the
full method, the raw timing numbers, and the root-cause hypothesis this leaves
standing: a genuine intermittent flake in AX window enumeration on this shared,
concurrently-loaded Mac (not a defect in `DayLayoutEngine.swift` or
`DayColumnView.swift`, and not a hang) — consistent with the system-wide 0-window
control test already on record at §1.2 / task P2-T01, and with real concurrent
agent-session contention observed on this machine during P2-T07 itself.

**Amended 2026-09-17 by task P2-T09 (register `RoutineTemplate`/`RoutineBlock`
in `KadenceApp.swift`'s `ModelContainer`).** New §7. `check-accessibility.sh`
re-run and re-diagnosed for this task: found a genuine (and now-fixed)
environmental cause distinct from anything above — see §7's own account —
rather than the AX-flake pattern §1.2/§1.2.1 describe. §7 also identifies a
concrete, reusable failure mode for `check-accessibility.sh` (a stale
`DerivedData` folder shadowing the freshly-built app via `ls | head -1`) worth
a future script fix.

**Amended 2026-09-17 by task P2-T10 (Routines window shell — open, weekday
canvas, read-only block rendering).** New §8. The first Phase 2 UI slice: a
second `Scene` opening a real, separate window (⌘⌥R / Window ▸ Routines),
seven weekday-only columns on the same hour-grid geometry the main Week view
uses, and the seeded demo template's blocks rendered read-only through
`GridBlockView`. §3's "full design spec, zero implementation" framing gets a
second correction (the first was §6/P2-T08's data layer) — see §3's own
amendment. This session also surfaced, while re-verifying
`check-accessibility.sh`, that this Mac's window-restoration behaviour can
reopen a previously-used window (the Routines window included) on a plain
`open -n` with no special flag, ahead of the freshly-launched main window,
which is why that script's fixed "query window 1" now needs
`-ApplePersistenceIgnoreState YES` to reliably target the main window whenever
more than one window type has ever been opened in this app on this machine —
see §8's own verification notes for the full account. This is a pre-existing
script assumption (one window, ever) now visibly outgrown by a second window
existing at all, not a defect this task introduced in either window's code.

**Amended 2026-09-17 by task P2-T11 (Routine block editing: move, resize,
delete, undo).** New §9. Builds `interactions.md` §11.1's move/resize/delete
for `RoutineBlock`s on top of P2-T10's read-only window — drag the body to
move, drag the top/bottom edge to resize (same 15-minute snap, `⌃` for
5-minute, and handles as the main grid's §3/§4), `⌫` deletes, `⌘Z`/`⌘⇧Z`
undo/redo with the names §11.1 prescribes. §3, §5 and §8's "not built"/"read
only" framing each get a correction (§3's own text and the stale bullet inside
§8's "explicitly out of scope" list are amended in place, not left to
contradict this section). Creation, the flexibility control and Windows mode
remain out of scope, per this task's own brief — see §9.

**Amended 2026-09-18 by a P2-T12 follow-up (`check-accessibility.sh`'s "no
window" failure).** New §11. P2-T12's own §10 had waved this failure away by
re-quoting §1.2's old "TextEdit also reports 0 windows" excuse; this task
re-verified instead of re-quoting it, and found it does **not** hold up as
stated, though the underlying cause is still environmental and not a P2-T12
code defect: it is §8's own already-named, never-applied restoration flake
(`-ApplePersistenceIgnoreState YES`), confirmed by a flag-comparison relaunch
and a clean `sample`/log/crash-report check (no crash, process idle in
`mach_msg2_trap`, no `DiagnosticReports` entry, no relevant `CrashReporter`
content). The fix is now actually applied, consistently, to all four scripts
that shared the pattern (`check-accessibility.sh`,
`check-block-click-selects.sh`, `check-block-hit-regions.sh`,
`check-routines-window.sh`), and `check-accessibility.sh` passed three
consecutive times after the fix. A second, unrelated fragility (a live
third-party application contending for OS-wide frontmost status on this
machine) was found and partially worked around in `check-routines-window.sh`;
see §11 for what remains open and explicitly out of scope.

**Amended 2026-09-18 by task P2-T13 (ConflictEngine — conflict detection and
resolution-option generation, data layer only).** New §12. A third exception
to §3's "full design spec, zero implementation" framing (the first was §6's
`RoutineEngine.materialize`, the second §8's Routines window shell):
`Kadence/State/ConflictEngine.swift` now detects every routine-vs-manual/
imported overlap in a given `[Event]` collection (BRIEF-PRODUCT.md's Phase 2
section) and builds each one's ranked, structured resolution options
(components.md §14.3 — title/disturbance/exactly-one-recommended, though the
prose formatting itself is left to the future UI task). Deliberately narrow,
same shape as §6/§8's own exceptions: no wiring into
`Presentation.conflicted`/`BlockStyleResolver`/`GridBlockView`, no "Needs your
attention" row, no conflict panel, no protected-window conflicts (no
`TimeWindow` model exists yet), and nothing applies an option to the store —
all separate, future tasks. See §12 for the full account, including two
documented engineering calls the task's own brief left as judgement (which
minute-scale disturbance metric ties `.skipToday` onto the same axis as the
other two option kinds, and why a `.droppable` conflict's option list has
exactly 1 entry rather than 2 — its flexibility-derived option already *is*
"skip today", so the task's own "always also offer a plain skip fallback"
does not duplicate it).

**Amended 2026-09-18 by task P2-T14 (wire `ConflictEngine.detect` into
`Presentation.conflicted` on the live calendar canvas).** New §13. The first
of §12's three deliberately-deferred follow-ups is now done: `MainWindow`
queries the live `RoutineBlock`s alongside its existing `Event` query, runs
`ConflictEngine.detect(events:routineBlocks:)`, and threads the resulting
conflicted-event-id set through `TimedCanvasView` into `DayColumnView`, which
now inserts `.conflicted` for either id in that set — additively, alongside
(not replacing) Phase 1's `conflictsWithProtectedWindow` placeholder. Still
explicitly not built, same as §12 left them: the "Needs your attention" row,
the conflict panel, preview-on-focus, and an apply/undo command. See §13 for
the full account.

**Amended 2026-09-18 by task P2-T15 (needs-attention row + static conflict
panel — entry point only).** New §14. The second of §12's deferred follow-ups:
the sidebar's needs-attention row is now a real button (components.md §10.2,
with its `tray.full` icon removed — **closes DEVIATIONS.md A21**), `⌘⇧A` does
the same thing, and both select the first unresolved conflict — by a new
stable ordering rule, `ConflictOrdering`, ascending by the earlier of the two
colliding events' start times — and put the inspector into conflict mode,
rendering components.md §14.2's collision header and §14.3's ranked option
rows as static content. Selecting a row only highlights it. **Preview-on-focus,
`↩` apply and `⎋` abandonment (the rest of interactions.md §10.1, and all of
§10.2) are explicitly NOT built** — a separate, later task, per this task's own
brief. See §14 for the full account, including the two formatting judgement
calls this task made (the option-row prose, and the collision blocks'
rendered height) — neither is an invented design token; both are documented
as this task's own call, since `design/` leaves them open on purpose.

**Amended 2026-09-18 by task P2-T16 (conflict panel preview-on-focus and
unconditional abandonment).** New §17. `↑`/`↓` now preview an option live on
the real grid (`.previewed` presentation, `size.previewCanvasBorder` on the
canvas), and any of `⎋`/focus-loss/view-change/inspector-collapse reverts it
unconditionally. `↩` apply remains explicitly NOT built.

**Amended 2026-09-18 by task P2-T17 (conflict panel `↩` apply: single named
undo step, advance/resolve).** New §18. The last piece interactions.md §10 /
components.md §14 name for conflict resolution itself: `↩` now applies the
focused option to `EventStore` as one named undo step ("Resolve Conflict"),
drops the canvas preview border, and advances to the next unresolved conflict
(previewing its first/recommended option) or returns the inspector to normal
if that was the last one. One new data-layer decision, filed as
`design/GAPS.md` G-015 rather than guessed: `ConflictEngine.detect` now
excludes a pair whose routine side is `.skipped`, needed so the `.skipToday`
option's apply (a status write, not a block move) can actually resolve the
conflict it was applied to. §5.2's open-gap summary, which had gone stale
(missing G-013/G-014), is corrected in the same pass.

---

## 1. Verification — run on this Mac, 2026-09-10

Xcode 26.6 (17F113), Apple Swift 6.3.3, target arm64-apple-macosx26.0.
Working tree clean at `9bd7724` when these were run.

### 1.1 `swift Scripts/generate-tokens.swift --check` — **PASSES**

*(corrected 2026-09-10 by P2-T01 — this section previously said FAILS)*

```
Kadence/DesignSystem/Tokens.swift is up to date.
```

Exit status **0**, re-run this session. The failure P3-T01 recorded here was
real when it was recorded: commit `1c58185` added 67 Phase 2 tokens to
`design/tokens.json` and did not regenerate `Tokens.swift`, leaving the
generated file one design pass behind its source. P3-T01 was scoped to touch no
code and so left it. It has since been regenerated — not by this task, which ran
the generator only in `--check` mode and never wrote `Tokens.swift`.

No Phase 1 token was ever involved; the drift was entirely Phase 2 surface
(`color.window.peakFocus*`, `motion.PreviewRevert`, `size.popover*`,
`size.routineEditor*`, the `ConflictOption*` / `Popover*` / `StatusItem`
typography groups, and the rest).

### 1.2 `./Scripts/check-accessibility.sh` — **PASS**

```
building…
querying pid 19877
block-shaped elements in the tree: 20
carrying the §11 label:            0
  AXHelp=Check mail · 12:50–13:00 · Mail appointments · event ~~
  AXHelp=Stand-up · 12:30–12:45 · Personal · event ~~
  AXHelp=Reading · 21:00–21:30 · Daily routine · routine block, Reading · 21:00–21:30 · Daily routine · routine block ~~

WARN: blocks are in the tree, but 0 carry the §11 label.
      Known open defect A20b — VoiceOver reads the hover-help string
      instead of 'title, time, kind, source, status'.
PASS (elements present)
```

Exit status 0. 20 block elements, matching the 20 renderable fixtures. The A20b
warning is a known open defect, not a new one — DEVIATIONS.md A20b.

**Re-run 2026-09-10 by P2-T01: reported `FAIL`, 0 block elements — but that is
the machine, not the code.** The control the script's own guidance asks for was
run in the same minute: TextEdit with a document open also reports **0 windows**
through the accessibility API (`System Events ... get count of windows` → `0`,
and `window 1` → "Invalid index"). The Mac is not vending windows to AX right
now, so the script has nothing to count. It is intermittent — window enumeration
worked earlier in the same session, which is how the ⎋/↩ crash was driven through
the menu bar. Nothing in this task touched block accessibility. Treat the PASS
above as the standing result and re-run when AX is healthy.

**Re-run 2026-09-11 by the P2-T06 fix follow-up task: two consecutive clean
PASSes, after diagnosing and closing out the `FAIL: no Kadence process has a
window` regression reported against commit a3cece1 — see the amendment above
§1. Transcript of the second of the two runs (all Kadence processes killed
first, no interference):**

```
building…
querying pid 72031
block-shaped elements in the tree: 20
carrying the §11 label:            0
  AXHelp=Breakfast · 07:15–07:45 · Daily routine · routine block, Breakfast · 07:15–07:45 · Daily routine · routine block ~~
  AXHelp=Morning review · 08:00–09:00 · Daily routine · routine block, Morning review · 08:00–09:00 · Daily routine · routine block, Morning review · 08:00–09:00 · Daily routine · routine block ~~
  AXHelp=Datenmodellierung · 09:00–10:30 · University timetable · lecture, Datenmodellierung · 09:00–10:30 · University timetable · lecture, Datenmodellierung · 09:00–10:30 · University timetable · lecture ~~

WARN: blocks are in the tree, but 0 carry the §11 label.
      Known open defect A20b — VoiceOver reads the hover-help string
      instead of 'title, time, kind, source, status'.
PASS (elements present)
```

Root cause of the regression: stale saved window-restoration state, not
DayLayoutEngine/DayColumnView — see the amendment above §1 for the full
diagnosis. **This "resolution" did not hold — see the superseding entry
immediately below (task P2-T07).**

#### 1.2.1 P2-T07 — `check-accessibility.sh` re-diagnosis (report only, 2026-09-11)

**Status: still FAIL per independent verification. Nothing below marks it
PASS.** This task changed no file under `Kadence/`, `KadenceTests/` or
`Scripts/`. It was assigned because independent machine verification of
P2-T06's HEAD failed twice after the P2-T06-fix follow-up task (above) claimed
resolution from two local PASSes — that claim did not match the independent
result, so this task re-derived everything rather than trusting it.

**Step 1 — fully clean state, 5 consecutive runs.** All processes matching
`Kadence.app/Contents/MacOS/Kadence` killed by pid; `~/Library/Saved
Application State/*Kadence*` checked and found **empty** (nothing to move
aside — no stale saved-state file existed this session, unlike the prior
follow-up's reproduction); `xcodebuild … clean` then a genuine from-scratch
`xcodebuild … build` (whole-module compile confirmed in the build log, not an
incremental no-op — `** BUILD SUCCEEDED **`, 5.7s wall on this machine).
`Scripts/check-accessibility.sh` was then run **five** times back to back, no
cherry-picking, full output logged each time. All five **PASS**ed, 20 block
elements every time:

```
=== RUN 1 ===
building…
querying pid 73843
block-shaped elements in the tree: 20
carrying the §11 label:            0
  AXHelp=Breakfast · 07:15–07:45 · Daily routine · routine block, Breakfast · 07:15–07:45 · Daily routine · routine block ~~
  AXHelp=Morning review · 08:00–09:00 · Daily routine · routine block, Morning review · 08:00–09:00 · Daily routine · routine block, Morning review · 08:00–09:00 · Daily routine · routine block ~~
  AXHelp=Datenmodellierung · 09:00–10:30 · University timetable · lecture, Datenmodellierung · 09:00–10:30 · University timetable · lecture, Datenmodellierung · 09:00–10:30 · University timetable · lecture ~~

WARN: blocks are in the tree, but 0 carry the §11 label.
      Known open defect A20b — VoiceOver reads the hover-help string
      instead of 'title, time, kind, source, status'.
PASS (elements present)

=== RUN 2 === (exit 0)
building…
querying pid 73947
block-shaped elements in the tree: 20
carrying the §11 label:            0
  [same three AXHelp lines as run 1]
WARN: blocks are in the tree, but 0 carry the §11 label.
PASS (elements present)

=== RUN 3 === (exit 0)
building…
querying pid 74015
block-shaped elements in the tree: 20
carrying the §11 label:            0
  [same three AXHelp lines]
PASS (elements present)

=== RUN 4 === (exit 0)
building…
querying pid 74080
block-shaped elements in the tree: 20
carrying the §11 label:            0
  [same three AXHelp lines]
PASS (elements present)

=== RUN 5 === (exit 0)
building…
querying pid 74128
block-shaped elements in the tree: 20
carrying the §11 label:            0
  [same three AXHelp lines]
PASS (elements present)
```

(Truncated here to the varying `pid` line per run — the AXHelp lines and the
WARN/PASS text are byte-identical across all five; the full untruncated logs
were captured to `/tmp/p2t07-run{1..5}.log` during this session, not committed,
since this task ships no new files outside `STATUS.md`/`DEVIATIONS.md`/
`design/GAPS.md`.)

So: **on this machine, right now, with a genuinely clean process/state, the
regression does not reproduce at all — 5/5 clean.** That is itself useful
negative evidence, not a resolution: the independent verifier's two failures
against this same HEAD are the ground truth this task defers to.

**Step 2 — time-to-first-block instrumentation, HEAD (`90cd142`).** A
throwaway poller (not part of the repo) killed all Kadence processes,
`open -n`'d the built app, then polled once per second for up to 30s, each
poll independently checking (a) via `System Events … count windows` whether a
window has appeared for the launched pid, and (b) via the same AX-tree walk
`check-accessibility.sh` uses, whether at least one block-shaped element
(matching the `HH:MM–HH:MM` pattern) is present — recording the elapsed
second each condition is first true. Three runs against the fresh HEAD build:

```
[HEAD-90cd142-run1] t=1s: window appeared (pid 74226)
[HEAD-90cd142-run1] t=1s: first block-shaped element observed (20 present)
[HEAD-90cd142-run1] RESULT: window_t=1 block_t=1 final_block_count=20

[HEAD-90cd142-run2] t=1s: window appeared (pid 74280)
[HEAD-90cd142-run2] t=1s: first block-shaped element observed (20 present)
[HEAD-90cd142-run2] RESULT: window_t=1 block_t=1 final_block_count=20

[HEAD-90cd142-run3] t=1s: window appeared (pid 74320)
[HEAD-90cd142-run3] t=1s: first block-shaped element observed (20 present)
[HEAD-90cd142-run3] RESULT: window_t=1 block_t=1 final_block_count=20
```

Window and all 20 blocks are present at the very first 1-second poll, every
time — true latency is somewhere under 1s at 1s poll granularity, not
measured more finely because the script under diagnosis itself works at
whole-second granularity (`sleep 9`).

**Step 3 — same procedure, baseline `03fb5cd`** (the last commit that passed
`check-accessibility.sh` per this file's own record, immediately before
P2-T06's footprint-clustering change). Checked out read-only via
`git worktree add /tmp/kadence-baseline-03fb5cd 03fb5cd` (nothing committed
from that checkout; the worktree directory is left for the orchestrator to
prune — `git worktree remove`/`prune` is a destructive git command this task
is not permitted to run itself, per the harness). `xcodebuild … clean` then
`build` there produced a second, independent `Kadence.app` under its own
DerivedData path (`Kadence-anyrgcrnvakkuufbxcruiirpxfgl`, distinct from HEAD's
`Kadence-awxeycchcevpyseftwfscfywnnnp`), confirming the two builds could not
interfere with each other. Same poller, same three-runs procedure:

```
[baseline-03fb5cd-run1] t=1s: window appeared (pid 74417)
[baseline-03fb5cd-run1] t=1s: first block-shaped element observed (20 present)
[baseline-03fb5cd-run1] RESULT: window_t=1 block_t=1 final_block_count=20

[baseline-03fb5cd-run2] t=1s: window appeared (pid 74470)
[baseline-03fb5cd-run2] t=1s: first block-shaped element observed (20 present)
[baseline-03fb5cd-run2] RESULT: window_t=1 block_t=1 final_block_count=20

[baseline-03fb5cd-run3] t=1s: window appeared (pid 74500)
[baseline-03fb5cd-run3] t=1s: first block-shaped element observed (20 present)
[baseline-03fb5cd-run3] RESULT: window_t=1 block_t=1 final_block_count=20
```

Identical: window and all 20 blocks present at the first 1-second poll, every
run, at the baseline commit too.

**Step 4 — comparison and root-cause hypothesis.** HEAD's footprint-clustering
change (`LayoutItem.footprintTop`/`footprintBottom`, the `fixtures.travel(forEvent:)`
lookup feeding `departAt` into every `LayoutItem`) shows **no measurable
timing difference** from the pre-change baseline: both render all 20 blocks to
the accessibility tree within the same 1-second poll window, roughly **8×**
inside the script's fixed 9s sleep budget in both cases. On direct
measurement — not code review — **the "per-event footprintTop/footprintBottom
evaluation made rendering too slow for the fixed 9s sleep" hypothesis is
refuted**: there is nothing to speed up that would move the needle on a 9s
budget when six independent launches (3 HEAD + 3 baseline) all finish in ≤1s.
A genuine hang/deadlock is also not supported: none of the 5 check-
accessibility.sh runs nor the 6 timed launches in this session stalled,
wedged, or produced a diagnostic report (`~/Library/Logs/DiagnosticReports`
has no Kadence entries from this session's window; `log show --predicate
'process == "Kadence"' --last 2h` has no error/fail/hang/timeout lines
either).

What the evidence does support: a **genuine, environment-level flake in AX
window enumeration**, not a code defect in `DayLayoutEngine.swift` or
`DayColumnView.swift`. Two concrete, on-the-record reasons to believe that
rather than shrug at "it didn't reproduce":

1. This exact machine already has a **documented, independent instance** of
   system-wide AX window-vending going to zero for *every* app, not just
   Kadence — §1.2 / task P2-T01, 2026-09-10: `Kadence` reported 0 windows and
   so did **TextEdit**, in the same control test, in the same minute. That is
   this file's own prior evidence that the AX subsystem on this Mac
   intermittently stops vending windows for reasons outside any one app's
   code.
2. This diagnosis session itself observed **real concurrent load** on the
   machine while running: `ps aux` showed **two** separate
   `claude_agent_sdk` processes running at once (this task's own, plus a
   second one, pid 71120, that had been running since before this task
   started), system load average 2.27/2.93/3.73 on an 8-core Mac. The P2-T06
   fix follow-up's own entry above already records a concrete case of this
   same condition causing failures: "a second agent session was independently
   assigned this same fix task concurrently on this machine … some of the
   intermittent failures seen mid-investigation were the two sessions'
   `pkill`/`open -n` sequences racing each other." Concurrent orchestrator
   sessions sharing this Mac is therefore not a one-off but a **recurring,
   currently-observed condition**, and `check-accessibility.sh`'s pid-targeting
   loop (`pgrep -f "Kadence.app/Contents/MacOS/Kadence"` matched against
   whichever process first reports ≥1 window) has no defence against a second
   session's `pkill`/`open -n` landing mid-run.

**This is a hypothesis, not a closed case** — the failure did not reproduce
during this session, so it was not caught in the act, and this task did not
prove the mechanism (e.g. by deliberately running two sessions against each
other and reproducing the exact `FAIL` text). What the timing evidence *does*
establish concretely is negative: it rules out the one mechanism the task
brief flagged as most likely going in (P2-T06's new per-event footprint
evaluation being slow enough to blow the 9s budget). What remains standing,
backed by the two points above, is environmental AX/window-enumeration flake —
plausibly worsened by concurrent sessions on a shared Mac — not a
`DayLayoutEngine`/`DayColumnView` defect.

**This is a script robustness gap, not a spec ambiguity — left for a future
fix task, not fixed here**, per this task's report-only scope. Concretely:
`check-accessibility.sh`'s fixed `sleep 9` and single-shot pid-targeting loop
have no retry and no defence against a second concurrent session's
`pkill`/`open -n` landing mid-run; a poll-until-ready loop (the shape used for
this diagnosis's timing measurement) or an outer retry-on-FAIL wrapper would
make the script itself resilient to exactly the flake this task diagnoses.
Filing this as a to-do rather than fixing it — this task's brief is
report-only and touches no file under `Scripts/`.

**No `design/GAPS.md` entry filed.** The evidence points to an environmental/
script-robustness issue, not an unanswered spec question — `design/` is not
ambiguous about anything this diagnosis touched.

Processes were left clean at the end of this task (`pkill -9` against
`Kadence.app/Contents/MacOS/Kadence`, confirmed zero matches).

### 1.3 `xcodebuild -scheme Kadence -destination 'platform=macOS' build` — **PASS**

```
** BUILD SUCCEEDED **
```

Exit status 0.

### 1.4 `xcodebuild -scheme Kadence -destination 'platform=macOS' -only-testing:KadenceTests test` — **PASS**

```
** TEST SUCCEEDED **
```

Exit status 0. **160 unique test cases, 0 failed.** The log prints 189
`passed` lines; the surplus is parameterised cases reported per argument, and
the count can wobble by one because that per-argument logging is racy
(`SourceSymbolTests/normativeTable` printed 9 lines in one run and 10 in the
next, same 0 failures). Count unique names, not lines.

*(updated 2026-09-10 by P2-T01: was "149 passed / 129 unique". The six new cases
are `KadenceTests/DraftBindingTests.swift` — see §1.5.)*

*(updated 2026-09-11 by P2-T02: was "135 unique / 154–155 lines". The five new
cases are `KadenceTests/BlockHitRegionTests.swift` — see §1.6.)*

*(updated 2026-09-11 by P2-T05: was "140 unique / 160 lines". The sixteen new
cases are `KadenceTests/BlockConfinementTests.swift` — see §1.7, and G-011 in
`design/GAPS.md`.)*

*(updated 2026-09-11 by P2-T06: was "156 unique / 184 lines". The five new cases
are in `KadenceTests/DayLayoutEngineTests.swift` — see §1.7, and G-012 in
`design/GAPS.md`.)*

Always use `-only-testing:KadenceTests`. A plain `test` also runs the empty
`KadenceUITests` template, whose runner cannot start on this machine ("Timed out
while enabling automation mode"). That red is the template, not a failure.

---

### 1.5 The ⎋ / ↩ crash — found, root-caused, fixed (task P2-T01)

Parsa reported that pressing ⎋ or ↩ crashed the running app. It did.

**Reproduction.** Reproduced under `lldb` on a debug build. The state that
crashes is (d), mid-draft with the inline title field active: File ▸ New Event,
type a title, press `↩`. The app dies immediately.

**Stack.**

```
Process 30139 stopped
* thread #1, queue = 'com.apple.main-thread',
  stop reason = EXC_BREAKPOINT (code=1, subcode=0x23576d648)
    frame #0: SwiftUICore`BindingOperations.ForceUnwrapping.get(base:) + 304
->  0x23576d648 <+304>: brk    #0x1
```

**Root cause.** `Kadence/Views/Canvas/DayColumnView.swift:138-139` (pre-fix):

```swift
@Bindable var state = state
if let binding = Binding($state.draft) {
```

`Binding.init?(_ base: Binding<Value?>)` does **not** unwrap once at
construction. It builds a `BindingOperations.ForceUnwrapping`, which unwraps
inside its *getter*, on every read. So the binding handed to `DraftBlockView`
force-unwraps `CalendarState.draft` each time SwiftUI reads it.

`↩` runs `DraftBlockView.onSubmit` → `DayColumnView.commitDraft()` →
`EventStore.commit(_:)` → `state.discardDraft()`, which sets `draft = nil` —
from inside the draft field's own event handling. SwiftUI then reads the field's
bindings again while tearing the field down. Those trailing reads unwrap nil and
trap. Verified independently of the app with a 15-line SwiftUI program: reading a
`Binding(optionalBinding)` after the source goes nil stops in the same frame.

The invalid state, stated plainly: **a force-unwrapping binding outliving its
source by one update pass.** It was the only `Binding(_:)` optional-unwrap in
`Kadence/` — every other binding in the tree is an explicit `get:`/`set:` pair.

**Fix.** `CalendarState.draftBinding()`, in `Kadence/State/CalendarState.swift`,
replaces it; `DayColumnView.draftBlock` calls that instead. The binding
remembers the last value written through it and serves that to reads arriving
after `draft` is nil, and it drops writes once `draft` is nil — which also stops
a dying field flushing its last text back and resurrecting a draft the user just
cancelled. The doc comment says why, so it does not get "simplified" back.

**Regression cover.** `KadenceTests/DraftBindingTests.swift`, six cases driving
`CalendarState` and `EventStore` through the exact transition. Confirmed to fail
against the pre-fix code path: with `draftBinding()` temporarily reverted to the
`Binding(optionalBinding)` shape, the run is `** TEST FAILED **` and the trap
takes the whole runner down. With the fix, `** TEST SUCCEEDED **`.

**Re-verified in the running app** after the fix — ⎋ and ↩ pressed repeatedly,
no crash, no console exception, in: grid focused with nothing selected; with a
time cursor; with an event selected (Home/End); mid-draft with the field active
(empty title, typed title, ⎋-then-↩, ↩-then-⎋); each of those with the inspector
open and closed.

**Two adjacent defects found and *not* fixed** (P2-T01 was scoped to the crash) —
both now in DEVIATIONS.md: **A22**, `⎋` does not cancel a draft at all, so it was
masking half of this crash; **A23**, `⌘N` opens a second window because the stock
"New Window" item keeps the same key equivalent.

---

### 1.6 Clicking a block did nothing — found, root-caused, fixed (task P2-T02)

Parsa reported that clicking an event block had no effect: no selection ring, no
inspector change. It did not.

**Was it a regression or always broken?** Always broken, for mouse input. The
old B9 entry ("selection survives view changes…") made it look like selection
worked; that entry was written from the **keyboard** path (`↖`/`↘`, `↑`/`↓`),
which does work and always did. `state.selectedEventID` had no working mouse
writer. DEVIATIONS.md B9 is corrected accordingly.

**Reproduction.** Instrumented, not assumed. A temporary `TapProbe.log` was put
inside the block's `.onTapGesture` closure, inside `blockGesture`'s `onChanged`
and `onEnded`, and inside the create surface's `.onTapGesture`, writing to
stderr on a debug build. Clicking directly on a block with no drag printed
**`SURFACE onTapGesture`** — the create surface's handler, the one that *clears*
selection — and never printed the block's. The click was not being swallowed by
a gesture conflict; it was never landing on the block at all.

**The hypothesis this refutes.** The obvious suspect was the `.onTapGesture`
immediately followed by `.gesture(DragGesture(minimumDistance: 3))` on the same
view — the documented SwiftUI exclusivity trap. That was **not** the cause. The
tap recogniser was fine; nothing was reaching it.

**Root cause.** `Kadence/Views/Canvas/DayColumnView.swift`, `blockStack`
(pre-fix):

```swift
.offset(x: laidOut.frame.minX, y: laidOut.frame.minY - aboveHeight)
.contentShape(Rectangle().inset(by: -laidOut.hitExtension / 2))
```

`.offset` is a **render-time translation**: it moves what is drawn and leaves the
layout frame where it was. A `.contentShape` applied *after* it therefore
describes the hit region in the **un-offset** layout space. Blocks are positioned
in the column purely by that `.offset`, so their layout frames all sit at the
column's origin — and every block's hit region collapsed onto its day column's
top-left corner.

The invalid state, stated plainly: **every block in a column shared one hit
region, in the wrong place.** A click on a block's visible rectangle could not
hit that block. What it did instead depended on where the pile landed relative
to the pointer: a click inside the collapsed pile at the column corner selected
whichever block happened to be frontmost *there*, and a click anywhere else fell
through to the create surface behind the blocks, which deselected and dropped a
time cursor.

Both outcomes look like "nothing happens" from the user's seat, because neither
puts a ring on the block that was clicked. `screenshots/p2-t02/` shows the first
one caught in the act: in `before-click-block-does-nothing.png`, a click at the
centre of "Datenmodellierung" (09:00–10:30) leaves it unringed and loads
**"Late lab session" (22:30–23:30)** into the inspector — a block thirteen hours
away that was never clicked.

Why no existing check caught it: the *rendering* was never wrong, so screenshot
review had nothing to look at, and modifier ordering is not reachable from a
unit test.

**Measured, both ways.** Accessibility frames are where SwiftUI's resolved
geometry becomes observable from outside the process. With the mock dataset,
20 timed blocks:

| ordering | distinct AX y positions |
|---|---|
| `.contentShape` after `.offset` (bug) | **2** of 20 — every block in a column at `y=150`, the column top |
| `.contentShape` before `.offset` (fix) | **20** of 20 |

**Fix.** Move `.contentShape` **before** `.offset`. The inset value moved into
`LaidOutBlock.hitInset` (`Kadence/Layout/DayLayoutEngine.swift`) alongside a new
`hitRect`, so the "hit area is centred on the true frame" rule is expressed over
value types and is testable without a window. The comment at the call site says
why the order is load-bearing, so it does not get tidied back.

A superficial reorder was deliberately avoided until the mechanism was
understood, because swapping those two lines blind can break dragging instead —
hence the drag re-verification below.

**Regression cover — three layers.**

1. `KadenceTests/BlockHitRegionTests.swift`, five cases over `hitInset` /
   `hitRect`: the inset is zero unless clamped, a clamped block's hit area grows
   by exactly `size.blockHitExtension` and stays centred, every block's hit
   region contains its own centre, blocks at different times get hit regions at
   different places, and a hit region never sits at the column origin.
2. `Scripts/check-block-hit-regions.sh` — asserts via accessibility that within
   a column, later start times sit strictly lower. **Confirmed to fail against
   the pre-fix ordering** (3 distinct positions for 20 blocks) and pass with it.
3. `Scripts/check-block-click-selects.sh` — new. Drives a **real click** at a
   block and asserts it becomes selected, then clicks empty grid and asserts it
   deselects. **Confirmed to fail (exit 1) against the pre-fix ordering and pass
   with the fix.**

**Why that third script does not use `System Events … click at {x, y}`.** That
command does not synthesise a mouse event: it resolves the accessibility element
at the point and sends it `AXPress`, bypassing hit-testing entirely. It passed
happily against the broken build, which makes it worthless here. The script
posts a genuine `CGEvent` mouseDown/mouseUp through the HID event tap instead —
the same path a human click takes. This was checked, not assumed.

**Re-verified in the running app** after the fix, with synthetic `CGEvent`s
against the mock dataset:

- Click a block → selected (`AXSelected` true), ring renders, and the inspector
  loads **that** block. Captured as
  `screenshots/p2-t02/after-click-selects-block.png`, the same click on the same
  block as the before shot; see `screenshots/p2-t02/INDEX.md`.
- Click empty grid → deselects. *(The time cursor a grid click also places is
  not vended to accessibility, so only the deselect half is asserted
  mechanically; the cursor was confirmed by eye.)*
- **Drag to move** — "Prep: relational algebra" dragged down 44pt (one hour at
  the Day hour height): `14:30–16:00` → `15:30–17:00`. Exact.
- **Bottom-edge resize** — dragged down 22pt: `15:30–17:00` → `15:30–17:30`.
  End moved 30 min, start untouched.
- **Top-edge resize** — dragged up 22pt: `15:30–17:30` → `15:00–17:30`. Start
  moved 30 min, end untouched.
- A non-movable block (`origin: .imported`, "Datenmodellierung") correctly
  refuses both move and resize.

So `blockGesture` is intact; the fix did not trade selection for dragging.

**One harness caveat, not an app defect.** Two synthetic drags fired ~2s apart at
nearly the same point: the second was ignored. With ~3s of spacing and a settled
pointer, every gesture above is reliably reproducible. This looks like synthetic
event pacing rather than app behaviour — a human cannot drag twice that fast in
the same place — but it is written down rather than dropped, because it is the
kind of thing that later looks like a real intermittent bug.

**One adjacent defect found and *not* fixed**, now DEVIATIONS.md **A24**: one
block reports `AXSelected = true` to accessibility when nothing is selected. It
is *not* our trait — it reproduces with the `.isSelected` line deleted from
`GridBlockView` outright. Two candidate causes (`.done` status, hover) were
tested and refuted; it was not root-caused further, being outside this task.

**One spec gap surfaced, filed not invented:** `design/GAPS.md` **G-010** —
interactions.md §6 does not say which block a click selects when the click point
is inside two overlapping blocks. Observed live: clicking the visual centre of
"Statistik übung" selects "Coffee with Nora", which is drawn on top there. The
build keeps today's frontmost-wins behaviour and no value was invented. **Open.**

The mock store was reset after this testing (the drags above are persisted by
SwiftData), so the fixed dataset is back to its seeded values and future
captures stay comparable.

### 1.7 The block-overlap defect — all three symptoms now fixed or confirmed-correct: (a) and (c)-Week (task P2-T05), (c)-Day (task P2-T06)

**Status as of task P2-T06, 2026-09-11.** All three reported symptoms are now
resolved. (a) and the Week half of (c) were fixed by task P2-T05, per
`design/GAPS.md`'s **G-011 — CLOSED** ruling. (b) was always correct, per
diagnosis below. The Day half of (c) — **G-012** — is now **fixed in code** by
this task (P2-T06), per `design/GAPS.md`'s **G-012 — CLOSED** ruling
(`layouts.md` §3.3, `components.md` §4). The diagnosis below (task P2-T03) is
kept as the historical record of what was wrong and is annotated in place
rather than rewritten; do not read any of it as still-open.

**What changed for (c)-Day, and why it closes G-012.** `layouts.md` §3.3 now
defines a **layout footprint** — `footprintTop` is a case-1 travel band's
`departAt` when the true band height (`geometry.height(from: departAt, to:
start)`) is at least `size.travelBandHeight`, else the event's own `start`;
`footprintBottom = max(end, footprintTop + minInterval)`, and the clamp only
ever extends the bottom, never moves the top. Both step 1 (clustering) and step
2 (column packing) now key off the same footprint — the ruling's explicit
warning was against clustering on footprints while packing on raw times, which
would pull a neighbour into the cluster and then still pack it into the band's
own sub-column, fixing nothing. The fix:

- `Kadence/Layout/DayLayoutEngine.swift` — `LayoutItem` gained an optional
  `departAt: Date?` (nil when the event has no band) and
  `footprintTop(geometry:)` / `footprintBottom(geometry:minimumDuration:)`
  methods implementing the definition above. `cluster`, `sortForLayout` (whose
  primary key is now `footprintTop`) and `packIntoSubColumns` all read the
  footprint instead of `start`/`end` directly. `layout(...)` needed no new
  parameter — it already receives `geometry: TimeGeometry`, which is what the
  case-1/case-2 height test needs.
- `Kadence/Views/Canvas/DayColumnView.swift` — `layoutItems` now passes
  `departAt: fixtures.travel(forEvent: $0.id)?.departAt` into each
  `LayoutItem`, so the engine — not the view — decides case 1 vs case 2 and
  whether the footprint extends. Drafts and events with no band pass `nil`,
  unchanged from before.

**Verified.** `xcodebuild build` succeeds, no new warnings.
`swift Scripts/generate-tokens.swift --check` is green (this task touched no
tokens). `KadenceTests` — 189 `passed` lines / 160 unique test names / 0
failed. Five new cases in `KadenceTests/DayLayoutEngineTests.swift` reproduce
the spec's own worked example directly: "Morning review" 08:00–09:00 and
"Datenmodellierung" 09:00–10:30 with a 22-minute band departing 08:38 —
`caseOneBandClustersInDay` and `gapG012PacksInDay` assert the pair forms one
cluster and packs into 2 non-overlapping side-by-side sub-columns at
`size.hourHeightDay` (case 1, footprint 08:38–10:30 vs 08:00–09:00, verified on
the resulting frames' x-ranges); `caseTwoBandDoesNotClusterInWeek` and
`gapG012DoesNotPackInWeek` assert the identical pair does **not** cluster at
`size.hourHeightWeek` (case 2, band under `travelBandHeight`, extends nothing —
unchanged behaviour, each block keeps the full column width); and
`noTravelBandUnaffected` pins that an event with `departAt: nil` clusters
exactly as before the change. No live on-screen capture was taken this
session — out of scope per this task's brief, a separate follow-up once this
lands.

`design/layouts.md` and `design/components.md` were **not** touched — the
ruling already existed there from task P2-T04; this task only built the code
side of it.

**What changed, and why it closes (a) and (c)-Week.** `design/GAPS.md` G-011
ruled that `DensityTier`'s three boundaries move 16/28/44 → **18/28/53**, each
now derived from its own tier's content set so a band's bottom is never below
that tier's own minimum (`components.md` §3.3), and added a new **§3.5
confinement invariant**: a block paints only inside its own laid-out frame,
clipped to its rounded rect, top-anchored, clipped at the bottom — never
centred. Implementing both together is what closes the defect; either alone
does not (a shrunk floor is still centred and still spills, and top-anchoring a
block still 22pt tall into a 13pt frame still clips into a neighbour rather
than fixing the number). The fix:

- `Kadence/Layout/DensityTier.swift` — boundaries 18/28/53, per-tier vertical
  padding (0 / `spacing.xxs` / `size.blockPadding` / `size.blockPadding`),
  minima matching G-011's table exactly (11/18/24/53).
- `Kadence/DesignSystem/BlockStyleResolver.swift` — `radius.blockCompact`'s
  threshold moved `< 16` → `< 18`, and the conflicted-badge swap at
  `.glyphOnly` is now keyed on the resolved content tier rather than a literal
  height, so a narrow cascaded block gets the same rule.
- `Kadence/Views/Blocks/GridBlockView.swift` — content is laid out into
  `.frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)`
  (was default-centred), the view is constrained to
  `.frame(height: renderedHeight, alignment: .top)` **before** `.clipShape`
  (was clipping to the content's own bounds, which clipped nothing), and a
  §4 short-case travel strip's height comes off the top of the content area via
  `contentTopInset`, not drawn over content sized to the full frame.
- `Kadence/Views/Blocks/DraftBlockView.swift` — the in-progress drag/create
  draft is a GridBlock too and gets the same `.frame(height:, alignment: .top)`
  fix, since it renders a block's content stack into a laid-out frame exactly
  as `GridBlockView` does.
- `Kadence/Views/Canvas/DayColumnView.swift` — the caller's own
  `.frame(height: laidOut.frame.height)` also picked up `alignment: .top`; it
  was the second, independent place the SwiftUI default centred a block, and
  both had to move for the fix to hold under either code path.
- `Kadence/DesignSystem/SourceColor.swift` and `MonthChipView` (§9's explicit,
  non-tier-derived content set) were **not** touched, per G-011's own scope
  note.

**Verified.** `xcodebuild build` succeeds; `KadenceTests` passes 184 `passed`
lines / 156 unique / 0 failed, including sixteen new cases in
`KadenceTests/BlockConfinementTests.swift` that pin the 18/28/53 boundaries, the
per-tier padding and minima, the confinement invariant over an `NSHostingView`
(a block reports exactly its laid-out height regardless of content), and a
pixel-level render of the two named fixtures ("Stand-up" 12:30–12:45, "Check
mail" 12:50–13:00) at their `DayLayoutEngine` frames in both Day and Week
geometry, asserting no ink lands in the gap between them — the direct
regression test for the symptom Parsa reported. A live on-screen capture was
still not possible this session for the same reason as P2-T03 (the Mac vends 0
windows); the `ImageRenderer`-based pixel test is the closest verification
available and does not depend on window vending.

`Kadence/Layout/DayLayoutEngine.swift` was **not modified** by this task —
confirmed by diffing it against the commit immediately preceding this task's
work, which is empty. G-012 (the travel-band footprint/clustering question) is
untouched and still open; nothing in this fix depends on it or forecloses it.

---

The diagnosis that follows is task P2-T03's original report-only finding, kept
verbatim as the record of what the defect was before the fix above:

Parsa reported three symptoms visible in `screenshots/day-full-light.png` and
`screenshots/week-full-dark.png` (mock fixtures, Wed 9 Sep). P2-T03 was a
report-only task: reproduce, root-cause, classify, change nothing. **No file
under `Kadence/` was modified.** The findings, in full, are in the task report;
the short version:

**Method.** The three symptoms were measured out of the committed PNGs at pixel
level (hour lines recovered from the images themselves, then times derived from
them), and `DayLayoutEngine` was run directly against the Wed 9 Sep fixture set
at the reproduced column widths — Day 1060pt, Week 152.14pt — by compiling
`DayLayoutEngine.swift`, `TimeGeometry.swift` and `Tokens.swift` into a
throwaway command-line driver outside the repo. Engine output and measured
pixels agree everywhere, which is what makes the split below trustworthy.

A live capture was **not** possible this session: the app launches but the Mac
is not vending windows — `Kadence` reports 0 windows and so does TextEdit, and
`screencapture` returns an all-black frame. That is the machine, not the code.
Everything below therefore rests on the committed screenshots plus the engine
run, and none of it depends on a screenshot being current.

**(a) The two bars at 12:30 and 12:50 — a *view* bug, plus G-011.**
`DayLayoutEngine` is correct and is not involved. "Stand-up" (12:30–12:45) and
"Check mail" (12:50–13:00) do not overlap even after the §3.3 clamp, cluster
separately, and each takes the whole column (Day y=750 h=13 / y=770 h=11; Week
y=550 h=11 / y=564.67 h=11). No packing and no cascade: slot width is the full
column, 1054pt in Day and 146.14pt in Week, against
`size.dayColumnCascadeThreshold` of 72. They collide because
`GridBlockView` never constrains itself to `renderedHeight` and
`DayColumnView.blockStack` sizes it with a default-**centred**
`.frame(height:)` (DayColumnView.swift:194), so a block whose content cannot fit
overflows its laid-out frame symmetrically instead of being clipped. Both bars
draw ~22pt tall — `size.blockGlyphSize` (11) + 2 × `size.blockPadding` (5) — and
spill ~5pt each way, closing the 7pt / 3.5pt gap between them. Measured, Day:
frames 1376–1402 and 1416–1438 device px; drawn 1367–~1410 and 1405–1448.
The underlying spec problem is **G-011**: the 11–15 tier is not renderable at
the specced padding at all.

**(b) The 18:00 trio in Week — working as specified.** 3-block cluster, Week
column 152.14pt, slot width `(152.14 − 4) / 3 − 2` = **47.38 < 72**, so step 3
fires exactly as §3.3 says it should. Indent
`min(round(152.14 × 0.19), 22)` = 22; blocks land at x = 0 / 22 / 44 with
visible widths 22 / 22 / 108.14, and 22 < `size.blockCascadeMinReadableWidth`
(44), so the first two are glyph-only. All of that is confirmed in the pixels
(blue starts 42–44px into the column, the dashed block 86–88px in) and in the
z-order (start order, later on top). Nothing to fix. For contrast, the same trio
in **Day** packs — slot width 350 — which is also what §3.3 predicts.

**(c) The 08:38 travel band — G-012, plus the same view bug as (a).** The band
belongs to "Datenmodellierung", not to "Morning review". Two separate things:

- *Day.* True interval 22 minutes = 22pt ≥ `size.travelBandHeight` (18), so
  components.md §4 case 1 applies and the band correctly draws above its own
  event, 08:38–09:00. It lands on "Morning review" (08:00–09:00) because
  §3.3 step 1 clusters on raw event times only
  (`DayLayoutEngine.swift:166-189`, fed from `DayColumnView.swift:117-119`) and
  knows nothing about the band's visual footprint. The two events do not
  overlap, so both get the full column and the band paints over the bottom 20pt
  of a block that has no idea it is there — hiding the §3.4 meta line, which is
  visibly missing from "Morning review" in the screenshot while
  "Datenmodellierung" below it has one. **This is a spec gap, G-012**, not an
  implementation error: the code matches §3.3 literally. It is *not* the
  short-case bug the report suspected — the short case (6-minute band on "Coffee
  with Nora") renders correctly as an 18pt strip inside the block's own top,
  which the pixels confirm (strip 11:00–11:18, block frame starts at 11:00).
  The claim that "Datenmodellierung starts on top of it" does not reproduce: the
  band ends at 09:00 and the block starts at 09:00, exactly adjacent.
- *Week.* The same 22-minute band is only 16.1pt, so it is case 2 and correctly
  becomes an inside-strip. It still clips "Morning review" by ~2.5pt, and for a
  different reason: with an 18pt strip at its top the block's `.full` tier needs
  ~73pt in a 64pt frame, and the centred overflow from (a) pushes the strip
  ~4.5pt above its own frame. Same `DayColumnView.swift:194` root cause.

**Classification, stated plainly.** (a) code bug + **G-011**; (b) correct, no
action; (c) **G-012** in Day, code bug in Week. **None of the three is a stale
screenshot** — every one reproduces against today's engine output and today's
view code. The code bug is one fix in the view layer and is common to (a) and
the Week half of (c); G-012 is independent of it and can be fixed separately.
Splitting the follow-up per symptom is therefore warranted, but (a) and (c)-Week
should be one change, not two.

**Superseded by tasks P2-T05 and P2-T06, above.** (a) and (c)-Week are fixed;
the "one fix in the view layer" this paragraph anticipated is the change
documented at the top of this section. (c)-Day / G-012, described here as still
open, is now also fixed — task P2-T06 built the footprint-clustering fix; see
the top of this section. All three symptoms are now closed or confirmed
correct; nothing from this diagnosis remains open.


---

## 2. Phase 1 — complete and verified

Phase 1 as defined in `BRIEF-PRODUCT.md` "Phase 1" is **done**. It builds, its
149 tests pass, its blocks reach the accessibility tree, and it has been run and
exercised in Month / Week / Day.

Built and standing:

- **Design system.** `Scripts/generate-tokens.swift` → `Tokens.swift`;
  `TypeStyle` (Dynamic Type via `@ScaledMetric(relativeTo:)`); `SourceKey`
  (eight palette slots, hue carries source only); `Elevation`, `BlockStyle`,
  `RailStyle`, `BadgeSpec`; `resolveBlockStyle` as one pure function consumed by
  all three block views.
- **Models (SwiftData).** `Event`, `Place`, `EventDraft`. `colorTag` is replaced
  by `sourceKey` (components.md §1 makes hue mean source and nothing else).
  Display-only fixtures where Phase 1 has no service: `TravelFixture`,
  `AllDayFixture`, `TimeWindowFixture`, `CalendarSource`.
- **Layout.** `DayLayoutEngine` (layouts.md §3.3 in full: cluster → column-pack
  → cascade → vertical gaps), `DensityTier`, `TimeGeometry`. Pure functions over
  value types, no SwiftUI and no clock.
- **Views.** `GridBlockView`, `TravelBandView`, `AllDayItemView`, `MonthChipView`;
  canvas layers (background windows spanning the gutter, hour lines, gutter, now
  line); `TimedCanvasView`, `MonthGridView`, `DayHeaderRow`, `AllDayRowView`;
  `SidebarView`, `InspectorView`, toolbar, menus.
- **Interaction.** Create by double-click, drag, `⌘N` or `+`; drag to move;
  edge-drag to resize; `⌫` to delete. Creation is commit-or-discard through
  `EventDraft`, so an untitled event cannot be persisted.
- **Undo.** Explicit inverse-command stack (`UndoStack`), depth 50, named actions
  in the Edit menu, re-entrant grouping, full redo branch. Events are addressed
  by `id` and resolved at execution time, so undoing a delete survives the object
  identity change. Not `ModelContext.undoManager` — that groups at the wrong
  grain and cannot survive that identity change.
- **Focus.** `⇥` / `⇧⇥` cycle sidebar → all-day row → grid → inspector, wrapping
  and skipping hidden regions, as a pure function with 13 tests.
- **Sidebar visibility.** One source of truth (`CalendarState.isSidebarVisible`),
  with the split view's `columnVisibility` derived from it.
- **Mock data.** `MockData` — components.md §12's sixteen fixtures, seeded once
  and idempotent.

### 2.1 Corrections to what this file previously claimed

The old text carried three statements that were false when it was written or had
since gone stale. Recording them so they do not reappear:

- It said `⇥` region cycling "is not implemented" under *Not done*, while a
  section above it correctly described A11 as fixed with 13 tests. **It is
  implemented.**
- It said inline title editing on create was "stubbed rather than built". **It is
  built** — A13, via `EventDraft` / `DraftBlockView`.
- It said "Five gaps remain (G-003, G-005)" — a count of five against a list of
  two. Two remain, and neither blocks.

### 2.2 The one thing Phase 1 is missing

**The Phase 1 screenshot set does not exist.** `CONTEXT.md` requires every phase
to end with `screenshots/<phase>/` populated plus an `INDEX.md`, reviewed by the
design agent.

- `screenshots/` on disk contains one file: `.DS_Store`. No PNGs.
- `git ls-files screenshots` returns **nothing**. No screenshot is tracked.
- History shows only two ad-hoc macOS screengrabs, added and then deleted:
  `7fad990` added `Screenshot 2026-09-09 at 23.31.04.png`, `1590a0d` replaced it
  with `Screenshot 2026-09-10 at 01.14.33.png`, and `15718a9` deleted that.
- Root `INDEX.md` nevertheless describes a 16-file set by name
  (`day-full-dark.png`, `week-overlap4-dark.png`, …). **Those files were never
  committed and are not on disk.** `INDEX.md` is not mine to edit under this
  task; it is flagged here so nobody plans against it.

So Phase 1 is complete and verified *by build, test and accessibility check*, but
its screenshot review artefact is absent.

---

## 3. Phase 2 — full design spec, **zero implementation**

> **Read this before trusting the commit log.** Git history contains commits
> titled **"Phase 2"** (`1590a0d`) and **"Phase 2 finish"** (`15718a9`). Neither
> contains any Phase 2 feature work. Phase 2 has not been started.

*(Corrected 2026-09-11 by task P2-T08 — this section, including §3.1's table,
described a "zero implementation" state that is now stale for one row: a
`RoutineEngine` exists. It is the **data layer only** — `RoutineTemplate`,
`RoutineBlock` and `RoutineEngine.materialize`, no UI. See §6 below for what
was actually built and what still has "nothing" next to it: the Routines
window, conflict detection, the menu bar extra, snooze, and the TimeWindow
editor are all still exactly as this section describes them.)*

*(Corrected again 2026-09-17 by task P2-T10 — a second row is now stale: a
Routines window exists. It is a narrow first slice — read-only rendering of
one template's blocks, no create/move/resize/delete, no Blocks/Windows mode
control, no interactive flexibility control, no detached-instance tracking or
re-sync, no `TimeWindow` model or editor. See §8 below for exactly what was
built and what is still unbuilt. Conflict detection, the menu bar extra,
snooze and the `TimeWindow` editor itself remain exactly as this section
describes them.)*

*(Corrected again 2026-09-17 by task P2-T11 — the paragraph immediately above
is itself now stale on "no create/move/resize/delete": move, resize and
delete are now built (creation is still absent). See §9 below.)*

`BRIEF-PRODUCT.md` "Phase 2 — routines, conflicts, protected time, and the menu
bar" requires a routine engine, a TimeWindow editor, conflict detection and a
menu bar extra. Everything except the routine engine's data layer (§6) still
does not exist in `Kadence/`.

### 3.1 Evidence — searched this session

`Kadence/` contains 36 Swift files. Searching all of `Kadence/` and
`KadenceTests/` for the Phase 2 vocabulary:

| Looked for | Found | |
|---|---|---|
| `RoutineEngine` | **nothing** | *(stale — see §6, task P2-T08: now exists, data layer only)* |
| conflict detection (`conflictDetect`, `ConflictResolv`) | **nothing** | still true |
| `MenuBarExtra` scene | **nothing** | still true |
| `Snooze` | **nothing** | still true |
| a `TimeWindow` *editor* | **nothing** | still true — the Routines window built by P2-T10 (§8) renders `RoutineBlock`s only; there is still no `TimeWindow` model anywhere and no Windows-mode editor |

The only hits are Phase 1 display fixtures, and the code says so itself.
`Kadence/Models/DisplayFixtures.swift:65` reads:

```swift
/// Stands in for `TimeWindow` (Phase 2). Weekday numbers follow
struct TimeWindowFixture: Identifiable, Equatable, Sendable {
```

`TimeWindowFixture` is generated data drawn by `GridLayers.swift` as a background
band. There is no model behind it, no persistence, no editor, and nothing that
computes a routine. components.md §12 states the same thing for the whole Phase 1
fixture set: *"no TravelLeg computation, no routine engine, no work item model
behind them."*

### 3.2 What the two misleadingly-titled commits actually contain

- **`1590a0d` "Phase 2"** — Phase 1 polish. `EventDraft.swift` and
  `DraftBlockView.swift` (commit-or-discard creation, DEVIATIONS A13),
  `FocusRegionTests` (focus-region cycling, A11), `SidebarVisibilityTests`
  (sidebar-visibility unification), `EventCreationTests`. Every changed file is
  Phase 1 scope.
- **`15718a9` "Phase 2 finish"** — three files: `DECISIONS.md` (+83),
  `INDEX.md` (+6/−5), and the deletion of one screenshot. **No source file at
  all.**

### 3.3 The commit titled "Phase 3" added the **Phase 2 design spec**

`1c58185`, titled **"Phase 3"** in `git log`, contains no Phase 3 work and no
Swift. It touched `design/` and `orchestrator/` only:

```
design/GAPS.md          |  61 +++++
design/components.md    | 320 +++++++++++++++++++++++++-
design/interactions.md  | 144 +++++++++++-
design/layouts.md       | 103 +++++++++
design/tokens.json      | 103 ++++++++-
orchestrator/…          (new files)
```

What it added is the **Phase 2 UI design**:

- `design/components.md` §13 The Routines window, §14 Conflict resolution,
  §15 Menu bar extra, §16 Snooze confirmation, §17 fixtures
- `design/layouts.md` §8 The Routines window, §8.1 Editor inspector,
  §9 Menu bar popover, §10 The conflict panel
- `design/interactions.md` §10 Conflict resolution, §11 The Routines window,
  §12 The menu bar popover
- 67 new tokens in `design/tokens.json`

Its own section banner and final header say so. components.md line 572 opens the
new material with:

```
# Phase 2 — routines, conflicts, protected time, the menu bar
```

and the section closing it, at line 825, is headed — verbatim:

```
## 17. What Phase 2 must render for review
```

followed by *"Additions to the §12 fixture set. Same rule: display fixtures, no
services."* and twelve numbered Phase 2 fixtures (routine template, windows mode,
detached instances, conflict options, preview state, status item, popover, snooze
result row).

**So: Phase 2 has a complete design and no code.** The commit title is the only
thing in the repository that suggests otherwise.

---

## 4. Phase 3 — no design coverage at all

`BRIEF-PRODUCT.md` scopes Phase 3 as work items, time logging, ICS import,
`TravelTimeProvider`, Moodle and CalDAV. **There is no Phase 3 design anywhere in
`design/`, and no Phase 3 code.**

Searched `design/` this session for `assignment`, `workItem`, `work item`,
`TimeLog`, `time log`, `effort`, `confidence`, `ICS`, `Moodle`, `CalDAV`,
`TravelTimeProvider`:

- `TimeLog`, `time log`, `effort`, `confidence`, `CalDAV`, `TravelTimeProvider`
  — **zero occurrences in `design/`.**
- `ICS` — one false positive, `GAPS.md:54`, matching inside the word
  "CoreGraphics".
- The rest are **incidental Phase 1 styling references, not feature design**:
  components.md §3.2 keys two all-day glyphs off `WorkItem.kind`
  (`.assignment/.project` → `flag.fill`, `.exam` → `graduationcap.fill`);
  §1 and §10.1 mention Moodle as a *source* for hue and swatch symbols
  (`tray.2.fill`); §10.1's assignment *rule* is about palette-slot assignment,
  not about assignments. components.md §12 explicitly notes there is "no work
  item model behind them."

That is a handful of icon and colour rules that anticipate Phase 3 data. It is
not a design for work items, time logging, feed import, or travel-time lookup.
No layout, no interaction model, no tokens, no fixture list exists for any of it.
Phase 3 vocabulary appears only in `BRIEF-PRODUCT.md`, `BRIEF-DESIGN.md` and
`CONTEXT.md` — the briefs, not the spec.

---

## 5. What is actually next

Stating facts, not choosing an order. The Phase 2-vs-Phase 3 build order is not
mine to decide.

1. ~~**`Tokens.swift` is one design pass stale and `--check` is red at `HEAD`.**~~
   **Done** — `--check` is green, see §1.1. Not this task's doing; it was already
   regenerated when P2-T01 picked the tree up.
2. **Phase 2 has a design and, as of tasks P2-T08–P2-T17, eight slices of
   code.** `design/components.md` §13–§17, `layouts.md` §8–§10,
   `interactions.md` §10–§12 and the 67 new tokens are complete and frozen.
   `RoutineTemplate`/`RoutineBlock` (models) and `RoutineEngine.materialize`
   exist and are tested (§6), a Routines window shell exists and renders one
   template's blocks (§8), that window's blocks can now be moved, resized,
   created and deleted, undoably (§9, §10), `ConflictEngine` now detects
   routine-vs-manual/imported overlaps and generates their ranked resolution
   options, data layer only (§12), those detected conflicts now render as
   `.conflicted` on the live calendar canvas (§13), the entry point into
   conflict resolution — the needs-attention row, `⌘⇧A`, and a static
   conflict panel (collision header + ranked option rows) in the inspector —
   is built (§14), and the full ↑/↓-preview → `↩`-apply → advance loop is now
   built end to end (§17, §18): `↑`/`↓` preview an option live on the real
   grid, `⎋`/focus-loss/view-change abandon it unconditionally, and `↩`
   applies it as one named undo step and advances to the next unresolved
   conflict or returns the inspector to normal — everything else (the
   Blocks/Windows mode control, the interactive flexibility control,
   detached-instance tracking and re-sync, the menu bar extra, snooze, and
   the `TimeWindow` model and editor) is still unbuilt. The design pass also
   notes
   two deliberate
   reuses: the Routines window **is** the Week canvas with dates, now line,
   all-day row and travel bands removed (components.md §13.1 lists every
   difference) — confirmed in §8's build, which reuses `DayLayoutEngine`,
   `TimeGeometry`, `HourLinesLayer`/`TimeGutterView` and `GridBlockView`
   unchanged rather than re-implementing any grid geometry — and conflict
   preview **is** the drag-drop drop-preview vocabulary. Neither needs a new
   renderer.
3. **Phase 3 has neither design nor code.** It cannot be built without a design
   pass first; per `CONTEXT.md` the coding agent cannot invent UI values.
4. **Phase 1 has open deviations.** 18 absent, 6 built-differently, **0 invented
   values**, **0 open spec contradictions** (D4 closed 2026-09-11 by task
   P2-T05, per `design/GAPS.md` G-011 — CLOSED; see §1.7 and DEVIATIONS.md) —
   see `DEVIATIONS.md`, re-audited
   2026-09-10 against the current spec text, plus A22/A23 from P2-T01 and A24
   from P2-T02. **A22 is the one to take next**: `⎋` does not cancel a draft at
   all, which is a §3 rule the build simply does not implement, and it is a
   small change now that the binding underneath it is safe. Do not wire it up on
   a tree without the `draftBinding()` fix — it runs the code path that used to
   trap.
5. **Phase 1 never produced its screenshot set** (§2.2), and root `INDEX.md`
   describes 16 files that do not exist.
6. **The ⎋ / ↩ crash is fixed** (§1.5). It outranked everything on this list
   while it was open; nothing else was started until it was closed.
7. **Click-to-select is fixed** (§1.6). Same precedence: it made the calendar
   unusable with a mouse, and nothing else was started until it was closed. Two
   things it left behind — **A24** (a block reporting itself selected to
   accessibility when it is not) and **G-010** (§6 does not say which block wins
   when a click lands on two) — are both open and neither blocks Phase 2.
   The **block-overlap rendering defect** was the next task; G-010 is its
   spec-side neighbour and worth reading first.
8. **The block-overlap defect is fully resolved.** (a) and (c)-Week are fixed
   (§1.7, task P2-T05, per `design/GAPS.md` G-011 — CLOSED): the view-layer
   bug — blocks painting outside their laid-out frame because `GridBlockView`
   was never constrained to `renderedHeight` and `DayColumnView.swift` centred
   it — is fixed together with `DensityTier`'s new 18/28/53 boundaries; neither
   alone would have closed it. (c)-Day is now also fixed (§1.7, task P2-T06,
   per `design/GAPS.md` G-012 — CLOSED): `DayLayoutEngine` clusters and packs
   on a layout footprint rather than raw event times, so a case-1 travel band
   pulls its parent's overlapping neighbour into the same cluster instead of
   drawing over it. The 18:00 cascade (symptom (b)) was always correct and was
   not touched.

### 5.1 Needs a ruling

- **A20b** — blocks reach the accessibility tree but carry the §3.4 hover-help
  string instead of the §11 label. Six configurations were measured against the
  running app, including the preferred real-`Button` route; the label is
  discarded in every one that produces an element at all. Three next candidates,
  each trading something, are in DEVIATIONS.md. Unchanged this session.
- ~~**A21**~~ — **Closed 2026-09-18, task P2-T15.** The sidebar's needs-attention
  row drew `tray.full`, which the amended components.md §10.2 forbids outright;
  the icon is removed and the row is now a real button. See §14 and
  DEVIATIONS.md.

### 5.2 Gaps

*(Corrected 2026-09-11 by task P2-T05 — G-010 and G-011 had been closed by DA's
task P2-T04 in `design/GAPS.md` but this section still listed them as open.
That was a stale-entry bug in this file, not in the spec; it is fixed below.)*

*(Corrected again 2026-09-11 by task P2-T06 — G-012 was ruled CLOSED at the
spec level by task P2-T04 on the same day as G-010/G-011, but this section
kept listing it as open because the code side had not been built yet. It is
fixed in code now too; the stale entry is corrected below.)*

*(Corrected 2026-09-18 by task P2-T17 — this list had gone stale: G-013
(P2-T09/P2-T10, `RoutineBlock` cross-midnight drag), G-014 (P2-T16, `.skipToday`
preview treatment) and G-015 (this task, `.skipped` routine events and
`ConflictEngine.detect`) were each filed in `design/GAPS.md` by their own
tasks but never folded into this summary. Corrected below rather than left to
compound.)*

Five remain open, none blocking: **G-003**, **G-005**, **G-013**, **G-014**,
**G-015**. Closed: G-004, G-006, G-007, G-008, G-009, G-010, G-011, G-012.
**There are no invented design values in the codebase** and no `// SPEC-GAP`
markers left in `Kadence/`.

**G-010 — CLOSED** (ruled 2026-09-11, task P2-T04, design agent):
interactions.md gains §6.1, stating frontmost-wins as "paint order is hit
order" — the build's existing behaviour is now a decision, not a side effect.
"Effect on the build: none required" per the ruling; nothing in `Kadence/`
changed for it.

**G-011 — CLOSED** (ruled 2026-09-11, task P2-T04; fixed in code 2026-09-11,
task P2-T05, this task). components.md §3.1 padding (5) plus §3.3's glyph (11)
made the 11–15pt density tier 21pt of chrome, so that tier could not be drawn
at the height the same table assigned it, and the spec had never said a
block's render is confined to its laid-out frame. The ruling rederived every
tier's band from its own content set (boundaries 18/28/53) and added §3.5's
confinement invariant; both are now implemented — see §1.7. **Closes
DEVIATIONS.md D4 and B13.**

**G-012 — CLOSED** (ruled 2026-09-11, task P2-T04; fixed in code 2026-09-11,
task P2-T06). From the block-overlap diagnosis in §1.7 (task P2-T03):
layouts.md §3.3 step 1 clustered on raw event times and was silent on whether
a case-1 travel band's visual footprint (`departAt` → `event.start`) extends
its parent's footprint, which is why a band landed on a neighbouring block
that did not overlap it in time. The ruling defined a **layout footprint**
(`layouts.md` §3.3) that both step 1 and step 2 key off, and amended
`components.md` §4's z-order line to match; both are now implemented — see
§1.7.

No new gap was filed by this reconciliation. The three defects it found —
the stale `Tokens.swift`, the `tray.full` collision, and the missing screenshots
— are all cases where `design/` is unambiguous and the build or the repo has
drifted from it. None is a question for the designer, so none belongs in
`GAPS.md`.

## 6. P2-T08 — RoutineTemplate/RoutineBlock + RoutineEngine.materialize (data layer only, 2026-09-11)

Scope was explicitly data-layer only: **no** Routines window, TimeWindow
editor, conflict detection, menu bar extra or snooze (components.md §13–§16,
layouts.md §8, interactions.md §11), and **no** detachment tracking or re-sync
(components.md §13.4, interactions.md §11.2) — that needs the main-grid
edit-command path wired up first and is a separate follow-up task. Section 3's
"zero implementation" framing is corrected above; this is the one slice that
now exists.

**Built:**

- `Kadence/Models/RoutineTemplate.swift` — two `@Model` types, following
  `Event.swift`'s conventions (stable `id: UUID`, raw-string-backed enum
  storage with a computed accessor, a doc comment at every departure from the
  brief):
  - `RoutineTemplate(name, activeWeekdays: Set<Int>, blocks: [RoutineBlock]`
    cascade-deleted`, sourceKey)`. `activeWeekdays` uses `Calendar`'s own
    `weekday` convention (1 = Sunday … 7 = Saturday) — documented on the
    property so nothing has to guess it later. `sourceKey` reuses the existing
    `SourceKey` enum: components.md §13.1, "the routine's own palette slot, one
    hue for the whole template."
  - `RoutineBlock(title, startMinutes: Int, duration: TimeInterval, flexibility,
    shiftableMinutes: Int?, priority: Int)`. `startMinutes` (minutes since
    midnight) was chosen over `DateComponents(hour:minute:)` — documented on
    the property — because `RoutineEngine.materialize` only ever adds it to a
    day's start as a plain calendar offset.
  - `.shiftable(±minutes)` from BRIEF-PRODUCT.md's data-model draft has no
    associated value on the shared `Flexibility` enum (`Enums.swift`), which
    `Event` also uses and which Phase 1 never needed one on. Rather than change
    a shared type, the ± minutes value components.md §13.2 specifies (a
    stepper, 15-minute steps, range 15–180) lives on `RoutineBlock` as its own
    `shiftableMinutes: Int?`, `nil` unless `flexibility == .shiftable`. This
    reading is unambiguous against components.md §13.2's own numbers, so
    **no `design/GAPS.md` entry was filed for it.**
- `Kadence/State/RoutineEngine.swift` —
  `materialize(template:into:store:calendar:) -> Int`. For each date in the
  given `DateInterval` whose `calendar.component(.weekday, from:)` is in
  `template.activeWeekdays`, and for each block, creates one `Event` with
  `origin = .routine`, `sourceKey` = the template's, `flexibility` = the
  block's, `sourceID` = `template.id.uuidString`, `externalID` =
  `"<block.id>#<yyyy-MM-dd>"` — exactly the `(sourceID, externalID)` identity
  `Event.swift`'s own doc comment already describes as "stable across re-sync,
  so importing twice updates instead of duplicating." Before creating an event
  for a given pair, the engine fetches on `(sourceID, externalID)` and skips if
  one already exists — chose **skip over update**, since an update-in-place
  policy needs detachment tracking (which pair got hand-edited vs. untouched)
  to avoid silently stomping a manual edit, and that tracking is exactly the
  §13.4 work this task explicitly excludes. The whole run is one
  `store.transaction("Materialize <name>")`, so it is one `⌘Z`.
- `EventStore.insertMaterialized(_:)` — a small addition to
  `Kadence/State/EventStore.swift`. `commit()` validates a title and forces
  `origin = .manual`/`sourceKey = .graphite`, neither of which fits a routine
  instance that already has every field decided; this new method inserts a
  fully-formed `EventSnapshot` and joins whatever transaction is currently open
  (see `UndoStack.perform`'s re-entrancy), which is what lets
  `RoutineEngine.materialize` register every created event under its own named
  step.

**Verified:**

- `KadenceTests/RoutineEngineTests.swift`, same in-memory
  `ModelContainer`/`ModelContext` pattern as `EventCreationTests.swift`. 14
  tests: exact count (2 blocks × 3 active weekdays over an exact 2-week span =
  12), every common field (`origin`, `sourceKey`, `sourceID`,
  non-nil `externalID`), per-block start-time/duration/flexibility correctness
  (verified via independent `Calendar` component checks, not by re-deriving
  the engine's own arithmetic), `externalID`'s `"<block id>#<date>"` shape, the
  empty-`activeWeekdays` no-op case, idempotence on an exact re-run (count
  unchanged, identical `(sourceID, externalID)` pair set), idempotence when the
  range is *extended* (the first run's event `id`s are an untouched subset of
  the second run's), a single named undo step for a whole run (`⌘Z` removes
  every event the run created, `⌘⇧Z` restores them), and priority/flexibility
  round-tripping (`priority` persists on the `RoutineBlock` through SwiftData;
  `flexibility` transfers onto every `Event` the block materializes).
- `xcodebuild -scheme Kadence -destination 'platform=macOS' build` — **BUILD
  SUCCEEDED**, no new warnings (the one pre-existing warning,
  `MonthGridView.swift:153`, is untouched by this task).
- `xcodebuild -scheme Kadence -destination 'platform=macOS'
  -only-testing:KadenceTests test` — **TEST SUCCEEDED**, 201 test cases run
  (full suite, including the 14 new ones), **0 failed**. No regressions.
- `swift Scripts/generate-tokens.swift --check` — **up to date**. This task
  changed no tokens.

**A note on "priority ... survives onto the materialized `Event`"** (from this
task's own acceptance wording): the field-by-field list of what `materialize`
writes onto an `Event` — title, start/end, origin, sourceKey, flexibility,
sourceID, externalID — has no `priority`, and `Event` itself has no such
field. Adding one would be inventing a field neither `Event.swift` nor
BRIEF-PRODUCT.md's `Event` draft has, for a value nothing yet reads. What is
tested instead is that `priority` survives SwiftData round-tripping on the
`RoutineBlock` itself, alongside the `flexibility` check, which genuinely does
transfer onto the `Event` per the task's own field list. Flagged here rather
than silently resolved, in case a later task (e.g. §14 conflict detection)
does need priority on `Event` and this becomes worth revisiting.

**What is next:** wiring a real Routines window (components.md §13,
layouts.md §8, interactions.md §11) to call `RoutineEngine.materialize`, and —
separately — detachment tracking and re-sync (§13.4), which needs the
main-grid edit-command path to know it is touching a routine instance.
Neither is started; both are correctly out of this task's scope.

**Blocked:** nothing. No new `design/GAPS.md` entries were opened — every
value this task needed was either already specified (components.md §13.1's
"one hue for the whole template", §13.2's stepper range/step) or was a
data-layer engineering decision (skip-vs-update on re-materialize,
minutes-since-midnight vs. `DateComponents`) rather than a UI value the design
spec was expected to supply.

## 7. P2-T09 — register `RoutineTemplate`/`RoutineBlock` in the app's `ModelContainer` (2026-09-17)

**Why this was needed.** P2-T08 (§6) added `RoutineTemplate`/`RoutineBlock` as
`@Model` types and `RoutineEngine.materialize`, and covered both with 14 tests
run against a **hand-built** in-memory `ModelContainer(for: Event.self,
Place.self, RoutineTemplate.self, RoutineBlock.self)`. But
`Kadence/KadenceApp.swift` — the container the real, running app actually
uses — still listed only `Event.self, Place.self` in both its primary
`ModelContainer(for:)` call and the `emptyFallback()` last-resort path. A
SwiftData schema is exactly the types passed to `ModelContainer(for:)`; two
types absent from that list do not exist in the app's schema no matter how
thoroughly they are tested elsewhere. Concretely, `RoutineEngine.materialize`'s
`EventStore` — built on the app's real container once a Routines window calls
it — would have had nowhere to save or fetch a `RoutineTemplate`. This was an
implementation gap in P2-T08, not a spec question, so it is not carried in
DEVIATIONS.md as a spec deviation; see the corrective note added there instead.

**Built:**

- `Kadence/KadenceApp.swift` — both `ModelContainer(for:)` calls (`init`'s
  primary path and its `catch` block's in-memory fallback) and
  `ModelContainer.emptyFallback()` now list `Event.self, Place.self,
  RoutineTemplate.self, RoutineBlock.self` — the same four types, same order,
  everywhere the app builds a container. A doc comment on `container` explains
  why the extra two types are there, so a future model addition does not
  silently repeat this gap.
- Nothing in `Kadence/Models/RoutineTemplate.swift` or
  `Kadence/State/RoutineEngine.swift` changed — out of scope for this task and
  untouched.
- `Kadence/Views/Support/Shapes.swift` — an unrelated but necessary fix found
  while verifying this task on the machine's current Xcode 27 toolchain (up
  from 26.6): three new `#ConformanceIsolation` errors where
  `HatchPattern.path(in:)`, `PartialRoundedRectangle.inset(by:)` and
  `PartialRoundedRectangle.path(in:)` — pure geometry with no actor state —
  "cross into main actor-isolated code" under Xcode 27's tightened
  actor-isolation checking. All three marked `nonisolated`, which is the
  correct fix for pure functions over value types; nothing about their
  behavior changed. This is a build-compatibility fix, not a spec deviation,
  and is not listed in DEVIATIONS.md.

**Verified:**

- `KadenceTests/RoutineEngineTests.swift` gained a new suite,
  `AppSchemaRegistrationTests`, in a new "App schema registration (P2-T09)"
  section. It builds a `ModelContainer` with the **same literal four-type
  list, same order** as `KadenceApp.swift`'s own calls (there is no API to
  reflect on a live SwiftUI `App`'s `.modelContainer(_:)` scene modifier, so a
  hard-coded mirror is the closest a test target can get — documented on the
  suite itself so a future reader does not mistake it for true reflection),
  inserts a `RoutineTemplate` with one nested `RoutineBlock`, saves, re-fetches
  through a **second, independent** `ModelContext` on the same container (so
  the assertions read back what was actually persisted, not the in-memory
  object just inserted), and asserts every field survives: `name`,
  `activeWeekdays`, `sourceKey` on the template; `title`, `startMinutes`,
  `duration`, `flexibility`, `priority` on the block. If a future change drops
  either type from either call in `KadenceApp.swift`, this test does not catch
  that by construction (it does not read `KadenceApp.swift`'s own list) — but
  it does catch the underlying regression: a `RoutineTemplate`/`RoutineBlock`
  pair failing to round-trip through a container built the app's own way.
- `xcodebuild -scheme Kadence -destination 'platform=macOS' build` — **BUILD
  SUCCEEDED**.
- `xcodebuild -scheme Kadence -destination 'platform=macOS'
  -only-testing:KadenceTests test` — **TEST SUCCEEDED**, 202 test cases (full
  suite, including the one new one), **0 failed**. No regressions.
- `swift Scripts/generate-tokens.swift --check` — **up to date**. This task
  changed no tokens.
- `./Scripts/check-accessibility.sh` — **PASS** after diagnosing and clearing
  two pieces of stale machine state that had nothing to do with this task's
  code change:
  1. A leftover `~/Library/Developer/Xcode/DerivedData/Kadence-*` folder from
     P2-T07's diagnostic git worktree (`/tmp/kadence-baseline-03fb5cd`,
     checked out at commit `03fb5cd`) was still present and sorted
     alphabetically *before* the current build's DerivedData folder. The
     script's `APP=$(ls -d ~/Library/.../Kadence-*/Build/Products/Debug/Kadence.app
     | head -1)` picked whichever folder sorts first, not whichever was just
     built — so it was launching an eight-day-stale binary while believing it
     had built and launched HEAD. Removed the stale folder (a build artifact,
     not tracked by git; the worktree itself was left alone, since removing a
     worktree is a destructive git operation outside this task's remit).
  2. With only the correct binary left, the script still failed once more:
     `block-shaped elements in the tree: 0`, with one real window present (so
     not the §1.2/§1.2.1 "no window at all" AX flake — a genuinely different
     symptom). Root cause: the real, on-disk persistent store at
     `~/Library/Containers/XIX.Kadence/Data/.../Kadence.sqlite` was created
     2026-09-09 and never re-seeded since (`MockData.seedIfNeeded` only seeds
     an *empty* store). Its mock events are anchored to whatever "now" was on
     2026-09-09; by 2026-09-17 (today), the default Week view's visible range
     no longer overlaps where the timed fixture blocks were placed — only two
     all-day items (a deadline and an exam, evidently wide-range or still in
     view) remained visible, hence 0 timed block elements. This is a
     property of a long-lived local dev store drifting away from a
     date-relative mock dataset, not a code defect — confirmed by deleting the
     stale store and letting the app reseed against today's real date, at
     which point the check passed with the same 20 block elements and the same
     already-known A20b warning P2-T01/T06/T07 recorded:
     ```
     block-shaped elements in the tree: 20
     carrying the §11 label:            0
       AXHelp=Breakfast · 07:15–07:45 · Daily routine · routine block, ...
       AXHelp=Morning review · 08:00–09:00 · Daily routine · routine block, ...
       AXHelp=Datenmodellierung · 09:00–10:30 · University timetable · lecture, ...
     WARN: blocks are in the tree, but 0 carry the §11 label. (known, A20b)
     PASS (elements present)
     ```
     Neither finding is fixed in this task's file set (both are outside
     `Kadence/`, `KadenceTests/`, `Scripts/` — one is a stray build artifact,
     the other is throwaway local dev-store state) but both are recorded here
     as concrete, reusable diagnoses for whoever next hits either symptom.
     `check-accessibility.sh` itself would benefit from picking the
     newest-mtime `Kadence.app` rather than the first alphabetically, and from
     not depending on a long-lived on-disk store's seed date at all (e.g. by
     wiping or ignoring the real container's store before each run) — filed
     here as a to-do, not fixed, since this task's scope is container
     registration, not the accessibility script.

**What is next:** wiring a real Routines window (components.md §13,
layouts.md §8, interactions.md §11) — unblocked now that `RoutineTemplate`
actually persists through the app's own container — plus TimeWindow
model/editor, conflict detection, the menu bar extra and snooze, all still
untouched. Detachment tracking and re-sync (§13.4) remains a separate
follow-up needing the main-grid edit-command path.

**Blocked:** nothing. No new `design/GAPS.md` entries were opened — this task
was pure container-registration engineering with no UI value to invent.

## 8. P2-T10 — Routines window shell: open, weekday canvas, read-only block rendering (2026-09-17)

The first Phase 2 **UI** slice (§6/§7 were data layer only), per `layouts.md`
§8 and `components.md` §13.1. Deliberately narrow, per the task brief: this is
the window opening, the weekday grid, and read-only rendering of one
template's blocks — not the full editor.

**Built:**

- `Kadence/Views/Routines/RoutinesWindow.swift` — a real SwiftUI `View`
  presented by a second `Scene`. Toolbar holds a `Picker` listing every
  `RoutineTemplate` by name (`.labelsHidden()`, disabled when the store has
  none) — no `[Blocks | Windows]` segmented control and no `+` new-template
  action, exactly per the task's own scope note. Canvas: seven weekday-only
  columns (`RoutineWeekdayHeaderRow`, `typeStyle(.dayHeaderWeekday)`, no
  dates), ordered from `Calendar.current.firstWeekday`
  (`RoutineWeekLayout.orderedWeekdays`), on the same hour-grid geometry as the
  main Week view — `TimeGeometry`, `HourLinesLayer`, `TimeGutterView`
  (`GridLayers.swift`) reused unchanged, `hourHeightWeek`. No now-line, no
  all-day row, no travel bands, no background-windows layer (see the file's
  own header comment on that last one — `components.md` §13.1 says this
  window reuses the same background-window layer as the Week canvas, but
  there is no `TimeWindow` model yet to drive it, and rendering it was never
  part of this task's "what to build" list; left for the task that builds
  Windows mode). A column floor of `size.routineEditorColumnMin` (84) reuses
  the main Week view's own `HorizontalScrollIfNeeded` view modifier
  (`Kadence/Views/Canvas/TimedCanvasView.swift`, made `internal` rather than
  `private` for this one caller — the only change to a file outside
  `Routines/`) rather than re-implementing the "scroll horizontally once
  columns hit their floor" rule a second time.
- `Kadence/Layout/RoutineWeekLayout.swift` — the pure glue between a
  template's weekly shape and `DayLayoutEngine`, which is reused **unmodified**
  (`DayLayoutEngine.swift` was not touched by this task, confirmed by diff).
  `RoutineBlockSnapshot` is a plain-value read of a `RoutineBlock`, mirroring
  why `GridBlockModel` exists for `Event` (`BlockModels.swift`'s own header).
  `orderedWeekdays(firstWeekday:)`, `referenceDayStart(weekday:now:calendar:)`
  and `layoutItems(blocks:activeWeekdays:weekday:referenceDayStart:)` are all
  pure functions over value types, free of SwiftUI and (except where `now` is
  an explicit parameter) free of the system clock — the same shape
  `DayLayoutEngine` itself follows, per the build rules. A weekday not in the
  template's `activeWeekdays` gets an empty item list, since every block in a
  `RoutineTemplate` repeats on every active weekday uniformly (there is no
  per-block weekday field — matches exactly the `(active weekday × block)`
  pairing `RoutineEngine.materialize` already iterates).
- Selection: `RoutineBlockSelection { blockID, weekday }` — window-scoped
  `@State` on `RoutinesWindow`, not `CalendarState` (this window's selection
  model is its own; interactions.md's model belongs to the main-grid window).
  A block recurs in every one of the template's active columns, so the id
  alone would be ambiguous — the selection also carries which column was
  clicked. Clicking a block sets it; clicking empty grid clears it
  (`interactions.md` §6's "clicking empty grid deselects" carried over as the
  only other interaction this read-only column offers).
- Inspector (`layouts.md` §8.1), `size.editorInspectorWidth` (260), collapsing
  below 1040pt into an overlay exactly as `MainWindow` does for its own
  inspector below its own literal collapse widths (that 1040pt figure is a
  literal out of layouts.md §8's prose, not a token — there is no `size.*`
  token for this particular width, matching the way `MainWindow` already
  hardcodes its own 1200/900 the same way). With a block selected: title,
  start, duration, and flexibility as **read-only text** (the interactive
  three-segment control components.md §13.2 specifies — Fixed / Shiftable /
  Droppable, a rail-style sample, a ± minutes stepper for `.shiftable` — is
  explicitly out of scope for this task; the task brief left the choice
  between omitting it or showing read-only text to this task, and this reads
  the value rather than inventing a design). With nothing selected: the
  template's name, active weekdays, block count, and total hours — the
  formula chosen (`sum(block durations) × active-weekday count`, i.e. hours
  per *week*, not just per block set) is documented on
  `RoutineInspectorView.totalHours` as the one reading consistent with what
  the same row already shows about active-weekday count; `layouts.md` §8.1
  asks for "total hours" without specifying the formula. Detached-instance
  count and Re-sync (§13.4) are always zero right now (no main-grid
  edit-command path can yet tell a hand-edited instance apart from an
  untouched one), so per the window's own existing zero-state rule (§10.2 —
  "hidden entirely at zero") the row is **omitted entirely**, not stubbed at
  "0 instances edited" — matching the task's explicit instruction not to stub
  it.
- `Kadence/KadenceApp.swift` — `WindowGroup(id: "routines") { RoutinesWindow() }`,
  a second, real `Scene` (not a sheet, not a `Settings` pane), sharing the
  app's one `ModelContainer`, `.defaultSize` set to
  `Tokens.Size.routineEditorMinWidth` × `routineEditorMinHeight` (780×620);
  `RoutinesWindow` itself also enforces that floor via
  `.frame(minWidth:minHeight:)`, so the minimum holds however the window is
  opened.
- `Kadence/Views/Chrome/KadenceCommands.swift` — `CommandGroup(after:
  .windowArrangement)` adds a **Routines** menu item, `⌘⌥R`,
  `openWindow(id: "routines")` via `@Environment(\.openWindow)` — the standard
  SwiftUI pattern for a `Commands` body to open a named window, following this
  file's existing `CommandGroup` shape rather than introducing a new one.
- `Kadence/Mock/MockData.swift` — `seedRoutineTemplatesIfNeeded(_:)` (idempotent,
  callable on its own since the Routines window can be the very first window a
  session opens, before `MainWindow`'s own `.task` has ever run) and
  `makeRoutineTemplates()`, seeding exactly one demo `RoutineTemplate`
  ("Daily routine", Mon/Wed/Fri, sourceKey `.green`) with three
  `RoutineBlock`s spanning the morning and evening (Gym 07:00–08:00
  shiftable, Morning review 08:15–08:45 fixed, Reading 21:00–21:30
  droppable) — enough to render something in more than one weekday column,
  per the task's own instruction not to build any template-creation UI.

**Verified:**

- `xcodebuild -scheme Kadence -destination 'platform=macOS' build` — **BUILD
  SUCCEEDED**, re-run this session, no new warnings.
- `xcodebuild -scheme Kadence -destination 'platform=macOS'
  -only-testing:KadenceTests test` — **TEST SUCCEEDED**, 214 `passed` lines /
  **186 unique test names**, **0 failed**. The new cases are in
  `KadenceTests/RoutineWeekLayoutTests.swift`: weekday-ordering rotation for
  every possible `firstWeekday` (1–7), `referenceDayStart` always returning
  midnight on the requested weekday, `layoutItems` producing one item per
  block at the right `start`/`end` on an active weekday and none at all on an
  inactive one, block ids surviving through unchanged (for `GridBlockView`
  lookup), and an end-to-end check against `MockData.makeRoutineTemplates()`
  itself — every weekday in `orderedWeekdays(firstWeekday: 1)` (exhaustive,
  Sun...Sat) produces exactly the template's block count on an active weekday
  and none on an inactive one, and running the seeded template's items
  through `DayLayoutEngine.layout` places each block's frame at exactly the
  y-position `TimeGeometry` derives from its own `startMinutes`.
- `swift Scripts/generate-tokens.swift --check` — **up to date**. This task
  used only already-generated tokens (`routineEditorMinWidth/Height`,
  `editorInspectorWidth`, `routineEditorColumnMin`, `hourHeightWeek`,
  `dayHeaderWeekday`, etc.) and added none.
- `Scripts/check-routines-window.sh` (new — this task's UI-level regression
  check, sibling of `check-block-click-selects.sh`/`check-accessibility.sh`,
  same real-`CGEvent`-click technique and the same reason for it: `System
  Events … click at {x, y}` resolves an element and sends `AXPress`, bypassing
  hit-testing, which would pass against a broken build). Run clean this
  session, full transcript:
  ```
  PASS: ⌘⌥R opened a new window.
  routine block elements found: 9
    Gym                  129x42 at 504,608  selected=False
    Morning review       129x20 at 504,663  selected=False
    Reading              129x22 at 504,1224  selected=False
    Gym                  129x42 at 775,608  selected=False
    Morning review       129x20 at 775,663  selected=False
    Reading              129x22 at 775,1224  selected=False
    Gym                  129x42 at 1045,608  selected=False
    Morning review       129x20 at 1045,663  selected=False
    Reading              129x22 at 1045,1224  selected=False
  clicking "Gym" at 568,629 …
  PASS: clicking "Gym" selected it (AXSelected true).
  PASS: the inspector's static text gained "Gym" after the click (the
  block-detail view replaced the template summary).
  ```
  9 elements = the template's 3 blocks × its 3 active weekdays (Mon/Wed/Fri),
  each at a distinct x (one per weekday column) confirming the seven-column
  layout, and each block's own y distinct from the other two blocks in its
  column confirming positioning by `startMinutes`. The script does not try to
  assert *which* x belongs to *which* weekday column from screen coordinates
  alone (no reliable way to do that through AppleScript without duplicating
  the window's own layout math) — that exact claim is covered instead by
  `RoutineWeekLayoutTests.swift`'s pure-function assertions, which do know
  which weekday each item belongs to.
- `./Scripts/check-accessibility.sh`, re-run this session after this task's
  changes: **PASS**, 9 block-shaped elements, all three of the seeded
  template's routine blocks (`AXHelp` carries "routine block" as the kind
  label, `BlockModels.swift`'s existing `accessibilityKindLabel` for
  `.routineTimed` — untouched by this task). This surfaced a real, if
  pre-existing, script limitation worth recording precisely: on a plain
  `open -n` with no special launch flag, this Mac's own window-restoration
  reliably reopened **the Routines window** as the frontmost ("window 1")
  window rather than the main window, so this run of a script that always
  reads "window 1" reported 9 routine blocks and not the main window's usual
  20. This is **not** a code defect in either window — confirmed by relaunching
  with `-ApplePersistenceIgnoreState YES` (the documented fix for exactly this
  class of restoration issue, used previously for the ⎋/↩ crash
  investigation at §1.2's amendment): with restoration suppressed, the app
  opens exactly **one** window, and that window's accessibility tree shows
  the full, unchanged **20** Phase 1 blocks (Breakfast, Morning review,
  Datenmodellierung, ... — the same fixture set §1.2/§7 have always recorded),
  proving `MainWindow` is untouched by this task. Neither of the two saved
  window-state locations this repo has previously implicated
  (`~/Library/Saved Application State/XIX.Kadence.savedState`, and the
  sandboxed app's own container equivalent) contained anything after a clean
  `kill -9` + relaunch, so the actual mechanism keeping this Mac's
  window-restoration alive across launches was not pinned down further — out
  of scope for this task to chase to ground, and it is a script-robustness
  gap (`check-accessibility.sh` assumed exactly one window, ever, which
  stopped being true the moment a second window *type* existed at all), not a
  Routines-window defect. Filed here as a to-do for
  `check-accessibility.sh`/`check-routines-window.sh`: pick the window whose
  content actually matches what the script means to assert (e.g. by title, or
  by disambiguating via the block kind found), rather than always reading
  "window 1".

**Explicitly out of scope, and not built, per the task brief:**

- Creating, moving, resizing or deleting routine blocks (`interactions.md`
  §11.1) — this window has no drag or create surface at all; every block view
  in it is read-only (`GridBlockModel.isMovable = false`). **STALE, in full,
  as of tasks P2-T11 and P2-T12 (§9 and §10 below): move, resize and delete
  were built by P2-T11; drag-to-create/double-click creation was built by
  P2-T12. Nothing from this bullet remains out of scope.**
- The `[Blocks | Windows]` mode control and Windows-mode editing
  (`components.md` §13.3) — there is no `TimeWindow` model yet. The toolbar's
  `Picker` is the only toolbar content.
- The `+` new-template action and any template-creation UI — the one demo
  template is seeded by `MockData`, not created through any UI.
- The flexibility control's interactive stepper (`components.md` §13.2) — the
  inspector shows flexibility as read-only text instead.
- Detached-instance tracking and Re-sync (`components.md` §13.4,
  `interactions.md` §11.2) — always zero, so omitted per the window's own
  zero-state rule rather than stubbed.
- The background-windows layer inside the Routines canvas — `components.md`
  §13.1 says this window reuses it, but there is no `TimeWindow` model to
  drive it and this task's own scope never asked for it; left for the task
  that builds Windows mode.
- Calling `RoutineEngine.materialize` from app lifecycle — a separate wiring
  task once there is a real template-creation UI to call it from.
- `screenshots/2/` capture — a separate follow-up task per the brief, not
  this one.

**What is next:** the follow-up tasks listed above, in whatever order Phase 2
is sequenced — most plausibly template creation/editing (which needs the
`[Blocks | Windows]` mode control before Windows mode has anything to edit),
then wiring `RoutineEngine.materialize` to a real creation/apply action, then
detachment tracking once the main-grid edit-command path can tell an
untouched instance from a hand-edited one.

**Blocked:** nothing. No new `design/GAPS.md` entries were opened — every
value this task needed was already specified (`layouts.md` §8/§8.1,
`components.md` §13.1) or was explicitly left to this task's own judgement by
the brief (the flexibility read-only-text presentation, the total-hours
formula), and is documented as such above rather than guessed silently.

## 9. P2-T11 — Routine block editing: move, resize, delete, undo (2026-09-17)

Builds `interactions.md` §11.1's move/resize/delete on top of P2-T10's
read-only Routines window. Scope, per the task brief: **only** move, resize
and delete. Creating new routine blocks (drag-to-create, double-click), the
flexibility three-segment control (`components.md` §13.2) and Windows mode
(§13.3) are explicitly out — left for follow-up tasks, same as §8 left them.

**Built:**

- `Kadence/State/RoutineEngine.swift` — a new `RoutineBlockStore`, the
  Routines-window sibling of `EventStore`: `move(_:toStartMinutes:)`,
  `resize(_:newStartMinutes:newEndMinutes:)` and `delete(_:from:)`, each one
  named `UndoStack` step ("Move Routine Block" / "Resize Routine Block" /
  "Delete Routine Block" — `UndoStack` itself prepends "Undo "/"Redo ", so the
  Edit menu reads exactly as `interactions.md` §11.1 prescribes). Same two
  rules `EventStore.swift`'s header states and this file's own new header
  paragraph repeats: blocks are addressed by `id` and resolved at execution
  time (never a captured `@Model` reference — undoing a delete recreates a
  `RoutineBlock` carrying the same `id`, via a new `RoutineBlockRestoreSnapshot`
  mirroring `EventSnapshot`'s shape), and every mutation goes through `undo.perform`.
  One deliberate divergence from `EventStore`, documented in the type's own doc
  comment and in `design/GAPS.md` G-013 below: a `RoutineBlock` has no `Date`
  of its own (`startMinutes` is a time-of-day offset applied uniformly across
  every active weekday, not an instant — `RoutineTemplate.swift`'s own doc
  comment), so `move`/`resize` take minutes-since-midnight and clamp to a
  single day (`0...1440`) rather than letting a drag roll a block into
  "tomorrow", which `interactions.md` §3/§4 never had to answer for a bounded
  field like this because `Event.start`/`.end` are ordinary free-floating
  `Date`s.
- `Kadence/Views/Routines/RoutinesWindow.swift` — `RoutineDayColumnView` gained
  a `DragGesture(minimumDistance: 3)` mirroring
  `DayColumnView.blockGesture`'s shape exactly: classify move/resizeTop/
  resizeBottom by comparing the drag's start-Y against
  `size.blockResizeHandleHeight`, snap via `TimeGeometry.snap(_:toMinutes:)`
  with 15 or 5 (`⌃` held, `NSEvent.modifierFlags.contains(.control)`, same as
  the main grid), and on `.onEnded` resolve the *live* `RoutineBlock` from
  `template.blocks` (not the `RoutineBlockSnapshot` the view renders from) and
  call into `RoutineBlockStore`. `GridBlockModel.isMovable` is now `true` for
  routine blocks, which for free gives `GridBlockView`'s existing hover resize
  handles and open-hand cursor (`.cursor(.openHand)`) — no new chrome was
  written, exactly per the task's own note that this should fall out of
  `GridBlockView`'s existing behaviour. A drop-preview overlay
  (`dropPreviewFrame`/`dropPreview`) mirrors `DayColumnView`'s own — the
  dashed `1pt` outline only; the main grid's own drop preview has no time
  badge either (`DEVIATIONS.md` A15, pre-existing, not reintroduced or fixed
  by this task) and there is no protected-window shading in this window yet
  (§8's own note), so the outline never turns alert here. `RoutinesWindow`
  itself gained `⌫` handling — `.focusable()` + `.onKeyPress(keys: [.delete])`
  at the window's content level (not per-block, so it fires regardless of
  which weekday column the block was last clicked in), with a `@FocusState`
  requested on window open and again on every selection change so the key has
  somewhere to land. A single edit from *any* one weekday column's copy of a
  block changes the one underlying `RoutineBlock` (`startMinutes`/`duration`),
  which is why it shows up correctly on every other active-weekday column
  immediately — this falls out of the existing data model
  (`RoutineWeekLayout.swift`'s own header) and needed no per-instance state.
- `Kadence/KadenceApp.swift` — the `routines` `WindowGroup` now also gets
  `.environment(undoStack)` (previously only `MainWindow`'s `WindowGroup` did).
  Without it, `RoutinesWindow`'s `@Environment(UndoStack.self)` has nothing to
  resolve at runtime. Same instance as `MainWindow`'s, so `⌘Z`/`⌘⇧Z`
  (`KadenceCommands`, wired once, app-wide) undo/redo routine edits exactly
  like event edits, and the Edit menu reads correctly regardless of which
  window is key.
- `KadenceTests/RoutineWeekLayoutTests.swift` — 13 new tests across three
  `@Suite`s (`RoutineBlockStore.move`, `.resize`, `.delete`), same in-memory
  `ModelContainer`/`ModelContext` pattern as `RoutineEngineTests.swift` and the
  same rigor as `UndoStackTests.swift` for the undo/redo half: move sets
  `startMinutes` and names the step correctly; a no-op move pushes no undo
  step; a move past either end of the day clamps (G-013); resize-top/-bottom
  move the correct edge and leave the other fixed; resize clamps to the
  15-minute floor rather than inverting (`interactions.md` §4); delete removes
  the block from both `template.blocks` and the store immediately, no
  confirmation, and undo reinserts a block carrying the same `id`, title,
  timing and flexibility back onto the same template; redo-after-undo is
  checked for all three verbs.

**Verified:**

- `xcodebuild -scheme Kadence -destination 'platform=macOS' build` —
  **BUILD SUCCEEDED**, no new warnings.
- `xcodebuild -scheme Kadence -destination 'platform=macOS'
  -only-testing:KadenceTests test` — **TEST SUCCEEDED**, 227 `passed` lines /
  0 failed, including all 13 new `RoutineBlockStore` tests
  (`RoutineBlockStoreMoveTests`, `RoutineBlockStoreResizeTests`,
  `RoutineBlockStoreDeleteTests`).
- `swift Scripts/generate-tokens.swift --check` — `Kadence/DesignSystem/Tokens.swift`
  is up to date. This task added no new tokens (§3/§4 are reused unchanged, so
  every geometric constant it needed — `size.blockResizeHandleHeight`,
  `size.blockMinRenderedHeight`, `radius.block`, `color.interactive.accent`,
  `opacity.blockDragOrigin` — already existed).
- `Scripts/check-accessibility.sh` — **PASS**, 9 block-shaped elements
  reached, none crashed/wedged. As §8 already recorded, this Mac's
  window-restoration behaviour means a plain `open -n` can bring the Routines
  window up as "window 1" ahead of the main window; that is what this run
  queried, and it shows exactly the seeded template's three blocks (Gym,
  Morning review, Reading) with correct titles and times, confirming the
  window still launches and renders cleanly with `isMovable` now `true` and
  the new gesture/key-press modifiers attached. The gesture and `⌫` path
  themselves are not exercisable through this script (it does not drive
  drags or key presses) — covered instead by the `RoutineBlockStore` unit
  tests above, which is where §11.1's actual mutation logic lives; the
  SwiftUI wiring (gesture classification, key-press routing, focus) has no
  pure-function seam, the same reasoning `RoutineWeekLayoutTests.swift`'s
  header already gives for click-to-select.

**Explicitly out of scope, and not built, per the task brief:**

- Creating new routine blocks (drag-to-create, double-click) —
  `interactions.md` §11.1 groups this with move/resize, but the task brief
  carves it out separately; this window still has no create surface.
  **STALE as of task P2-T12 (§10 below): creation is now built.**
- The `[Blocks | Windows]` mode control and Windows-mode editing
  (`components.md` §13.3) — unchanged from §8, still no `TimeWindow` model.
- The flexibility control's interactive stepper (`components.md` §13.2) —
  unchanged from §8, the inspector still shows flexibility as read-only text.
- Detached-instance tracking and Re-sync (`components.md` §13.4,
  `interactions.md` §11.2) — unchanged from §8.
- The background-windows layer — unchanged from §8.
- Screenshots — not asked for by this task's acceptance criteria.

**What is next:** ~~drag-to-create/double-click creation for routine blocks
(the other half of `interactions.md` §11.1)~~ — built by P2-T12 (§10 below).
What remains: the flexibility control and the `[Blocks | Windows]` mode
control, in whatever order Phase 2 is sequenced next.

**Blocked:** nothing. One new `design/GAPS.md` entry, **G-013**: neither
`interactions.md` §3 nor §4 says what a drag that would push a
`RoutineBlock`'s start before 00:00 or its end past 24:00 should do — both
sections assume a freely-floating `Event.start`/`.end`, which a
`RoutineBlock`'s bounded `startMinutes` field is not. Built as a clamp at the
day boundary (same shape as the already-specified 15-minute-minimum-duration
clamp) rather than guessed past silently; not blocking, since no acceptance
criterion for this task approaches either edge (a 07:00 Gym block, a 20:00
Study block). Needs an explicit ruling in `interactions.md` §11.1 to close.

## 10. P2-T12 — Routine block creation: drag-to-create and double-click (2026-09-17)

Builds the "other half" of `interactions.md` §11.1 that both P2-T10 and
P2-T11 explicitly carved back out: creating a `RoutineBlock`. §11.1 says
"Creating, moving and resizing routine blocks uses §3 and §4 unchanged", so
this task reads §3's own model and applies it verbatim: double-click on empty
grid creates a 60-minute block at the snapped slot under the pointer; drag on
empty grid creates a block of the dragged duration, minimum 15 minutes; the
new block appears immediately with an inline `TextField` in place of its
title; `↩` commits, `⎋` cancels and removes it entirely; a block created with
no title is never persisted; the block is selected on commit.

**Built:**

- `Kadence/State/RoutineEngine.swift` — `RoutineBlockStore.create(title:startMinutes:duration:in:)`,
  the fourth verb alongside `move`/`resize`/`delete`, same id-addressed/
  undo-named shape: pushes one named `"Create Routine Block"` `UndoStack` step
  (`⌘Z` removes the block, `⌘⇧Z` restores it), reversing `delete`'s own
  snapshot/insert plumbing (`redo` inserts via `insertBlock`, `undo` removes
  via `removeBlock` — the exact same two private helpers `delete` already
  uses, called in the opposite order). A blank or whitespace-only `title`
  persists nothing and pushes no undo step at all — mirroring
  `EventStore.commit`'s own rule for `Event`, interactions.md §3: "an event
  created with no title is never persisted." `startMinutes`/`duration` clamp
  to the same `0...1440` day-boundary shape `move`/`resize` already use
  (`design/GAPS.md` **G-013**, opened by P2-T11) — reused for consistency
  rather than treated as a fresh question; G-013 itself is not reopened or
  re-litigated by this task, just applied a third time. `RoutineBlockRestoreSnapshot`
  gained a second, plain memberwise `init` (defaults for `flexibility`
  (`.fixed`), `shiftableMinutes` (`nil`), `priority` (`0`)) alongside its
  existing `init(_ block: RoutineBlock)`, since a brand-new block has no
  `@Model` instance yet to snapshot values *from* — `create`'s `redo` needed a
  way to hand `insertBlock` a snapshot built straight from the draft's values.
- `Kadence/Views/Routines/RoutinesWindow.swift` — `RoutineDayColumnView` gained
  a `createSurface(width:geometry:)` mirroring `DayColumnView.createSurface`
  exactly: `.onTapGesture(count: 2)` begins a 60-minute draft at
  `TimeGeometry.snap(geometry.date(forY:), toMinutes: 15)`; a
  `DragGesture(minimumDistance: 6)` tracks `.create`-mode drag with the same
  15/5-minute (`⌃`) snap as move/resize, and on release begins a draft whose
  duration is `max(upper - lower, 15 minutes)`. The in-flight draft reuses
  `EventDraft`/`DraftBlockView` (`Kadence/Models/EventDraft.swift`,
  `Kadence/Views/Blocks/DraftBlockView.swift`) completely unchanged — both
  were already plain `Date`-based types with no `Event`/`CalendarState`
  dependency of their own, so the draft here lives in `RoutineDayColumnView`'s
  own local `@State private var draft: EventDraft?`, not
  `CalendarState.draft` (which belongs to the main-grid window and would be
  the wrong scope for a second window's independent selection/draft state —
  same reasoning `RoutineBlockSelection` already gives for not reusing
  `CalendarState.selectedEventID`). A `draftBinding()` helper mirrors
  `CalendarState.draftBinding()`'s own doc comment word for word: it must NOT
  be `Binding($draft)`, because SwiftUI's force-unwrapping binding reads its
  base again while `DraftBlockView` tears itself down after `↩`/`⎋` already
  cleared `draft` to `nil`, which traps. `commitDraft()` converts the draft's
  `Date`s to minutes via the same `minutes(for:)` helper move/resize already
  use (the inverse of `RoutineWeekLayout.referenceDayStart`), calls
  `RoutineBlockStore.create`, and selects the result on success — exactly
  interactions.md §3's "the event is selected on commit," applied to a
  `RoutineBlockSelection` scoped to whichever weekday column the gesture
  started in. `RoutineDragSession.Mode` gained a `.create` case and `blockID`
  changed from `UUID` to `UUID?` (mirroring `DayColumnView.DragSession.eventID`)
  so a create-drag's session can exist with no block to address yet;
  `dropPreviewFrame` gained a `.create` branch (dashed outline sized to the
  drag span, same as `DayColumnView`'s own) ahead of the existing
  move/resize/branch. Which weekday column the gesture starts in only
  supplies the geometry the snapped `startMinutes`/duration are read from — a
  `RoutineBlock` has no per-weekday instance (`RoutinesWindow.swift`'s own
  header), so the resulting block appears on every one of the template's
  active weekdays immediately once created, exactly like every other block,
  with no extra wiring needed for that to happen.
- `KadenceTests/RoutineWeekLayoutTests.swift` — a new `@Suite("RoutineBlockStore.create")`,
  8 tests, same in-memory `ModelContainer`/`ModelContext` pattern and the same
  helpers (`makeRoutineBlockStore`, `makeGymTemplate`, `fetchRoutineBlock`) the
  `move`/`resize`/`delete` suites already use: a double-click-shaped call
  (60-minute duration) lands at the given slot and names the undo step; a
  drag-shaped call below 15 minutes clamps up to the 15-minute floor
  (interactions.md §3); a drag-shaped call above the floor persists the exact
  dragged duration; an empty title and a whitespace-only title both persist
  nothing and push no undo step; a never-committed `EventDraft` (the ⎋/blur
  shape — mirrors `EventCreationTests.EventDiscardTests.discardNeverPersists`)
  touches the store not at all; `⌘Z` after a commit removes the created block
  and `⌘⇧Z` restores it with the same id/title/timing; creating near the end
  of the day clamps to the day boundary (G-013, reused). The
  double-click/drag gesture math itself (`createSurface`, `beginDraft`,
  `commitDraft`) lives in a **private** SwiftUI view type
  (`RoutineDayColumnView`) with no seam a unit test can reach even with
  `@testable import Kadence` — same reasoning this file's own header already
  gives for click-to-select and for P2-T11's move/resize gesture math; what
  IS a pure, testable seam is everything the gesture hands off to, which is
  what these 8 tests actually exercise.

**Verified:**

- `xcodebuild -scheme Kadence -destination 'platform=macOS' build` —
  **BUILD SUCCEEDED**, no new warnings.
- `xcodebuild -scheme Kadence -destination 'platform=macOS'
  -only-testing:KadenceTests test` — **TEST SUCCEEDED**, 235 `passed` lines /
  0 failed (227 from P2-T11 plus the 8 new `RoutineBlockStoreCreateTests`).
- `swift Scripts/generate-tokens.swift --check` — `Kadence/DesignSystem/Tokens.swift`
  is up to date. No new tokens: creation reuses every geometric constant
  move/resize/the drop preview already needed
  (`size.blockMinRenderedHeight`, `radius.block`, `color.interactive.accent`),
  plus whatever `DraftBlockView`/`EventDraft` already used for the main grid's
  own draft rendering — nothing new was invented.
- `Scripts/check-accessibility.sh` — **could not run**: the script reports
  "no Kadence process has a window — the app did not come up." Checked
  whether this is this task's own regression by launching plain `TextEdit`
  and asking System Events for its window count the same way the script
  does — it also reported 0 windows. That confirms the machine, not this
  change, is why the script cannot see any window right now (per this
  project's own standing note that a 0-window report from an unrelated app
  means the harness's Accessibility/window-server access is the blocker, not
  the code under test). Creation's actual behaviour is verified instead by
  the 8 `RoutineBlockStoreCreateTests` above, which is where §3's actual
  persistence/clamp/undo rules live — the SwiftUI wiring around them (gesture
  recognition, `@FocusState`, draft binding) has no pure-function seam, the
  same limitation already noted for click-to-select and for P2-T11's own
  drag gestures.
  **CORRECTED by §11 (2026-09-18 follow-up): the "TextEdit also shows 0
  windows, so it's the machine" excuse was re-checked, not just re-quoted,
  and does not hold up as a full explanation — the real, specific mechanism
  is §8's own already-named window-restoration flake, confirmed by a
  flag-comparison relaunch and by ruling out a crash with `sample`/log/crash-
  report evidence. `check-accessibility.sh` (and the other three scripts
  sharing its `open -n` pattern) now carry the documented fix and pass
  reliably; see §11.**

**Explicitly out of scope, and not built, per the task brief (unchanged from
P2-T10/P2-T11):**

- The flexibility control's interactive stepper (`components.md` §13.2).
- The `[Blocks | Windows]` mode control and Windows-mode editing
  (`components.md` §13.3).
- Detached-instance tracking and Re-sync (`components.md` §13.4,
  `interactions.md` §11.2).
- The background-windows layer.
- Anything in the main calendar grid (`Kadence/Views/Canvas/`),
  `DayLayoutEngine.swift`, `DayColumnView.swift`, or any other Phase-1 file —
  none of these were touched by this task.

**What is next:** the flexibility control and the `[Blocks | Windows]` mode
control are the two largest remaining pieces of `components.md` §13 for this
window; either is a reasonable next slice.

**Blocked:** nothing. No new `design/GAPS.md` entries — this task reused
G-013's existing clamp rule rather than opening a new question, and every
other value it needed (the 60-minute default, the 15-minute drag floor, the
empty-title-persists-nothing rule) was already specified by `interactions.md`
§3, which §11.1 points back at unchanged.

## 11. P2-T12 follow-up — diagnose and fix `check-accessibility.sh`'s "no
window" failure (2026-09-18)

P2-T12's own §10 entry above recorded `check-accessibility.sh` as unable to
run, and reached for the same excuse §1.2's amendment used before ("TextEdit
also reports 0 windows, so it's the machine"). This task re-investigated
rather than trusting that, per §8's own explicit unresolved note (a plain
`open -n` on this Mac can reopen a *previously used* window — the Routines
window included, since P2-T10/P2-T11/P2-T12's manual verification opened it
repeatedly this session — as "window 1" ahead of the fresh main window) and
per the general standard here that a repeated excuse gets re-verified, not
re-quoted.

**Reproduced:** `./Scripts/check-accessibility.sh` failed exactly as
recorded: `FAIL: no Kadence process has a window — the app did not come up.`

**Ruled out a genuine crash, with evidence, not assertion:**
- `~/Library/Logs/DiagnosticReports` has no Kadence entries at all (checked by
  filename glob for the current session).
- The container's own `CrashReporter` plist
  (`~/Library/Containers/XIX.Kadence/Data/Library/Application Support/CrashReporter/Kadence_*.plist`)
  contains only a stale `Date` key from **2026-09-10**, unrelated to this
  session or to P2-T12's commits.
- `log show --predicate 'processImagePath contains "Kadence"' --last 3m`
  returned **nothing** during a reproduction — no crash, no fault, no error
  logged for the process at all.
- `sample <pid> 2` on a live reproduction (plain `open -n`, 0 windows at 40+
  seconds) showed the main thread parked 100% in `mach_msg2_trap`
  (`libsystem_kernel.dylib`) — idle, waiting on the run loop, not spinning and
  not crashed. `ps` confirmed the process was still alive (state `S`) the
  whole time. This is the identical signature §1.2's amendment recorded for
  the same class of issue on this machine.
- Timing is genuinely variable, not deterministically broken: three plain,
  flagless `open -n` reproductions on this machine, run back to back, gave 0
  windows at 40s (once), 1 window at 17s (once), and 1 window at 5s (once) —
  all for the same unmodified binary. That is restoration-timing flake, not a
  code fault (a real crash would not intermittently succeed on the identical
  binary).

**Confirmed the restoration mechanism directly (flag-comparison relaunch,
not a stale saved-state guess):** relaunching with
`open -n "$APP" --args -ApplePersistenceIgnoreState YES` and querying the
resulting window's own accessibility tree showed **20** timed-block elements
every time (Breakfast, Morning review, Datenmodellierung, ... — Phase 1's
full fixture set) — i.e. the flag reliably produces exactly the main window,
never the Routines window, and never zero windows within a generous wait.
Without the flag, a reproduction that happened to still have a window
appear also showed the main window's 20 elements in one trial and, in an
earlier trial the session before, a `9`-routine-block Routines-window read
(consistent with §8's own account) — confirming the restoration mechanism,
not a P2-T12 code path, decides which window (if any) appears first.

**Root cause, therefore: restoration flake, not a regression in P2-T12's
create/drag code.** No file under `Kadence/` was touched.

**Fix applied, consistently, to all four scripts that shared the identical
pattern** (`check-accessibility.sh`, `check-block-click-selects.sh`,
`check-block-hit-regions.sh`, `check-routines-window.sh`):
1. `open -n "$APP"` → `open -n "$APP" --args -ApplePersistenceIgnoreState YES`
   in every script — suppresses restoration entirely so the only window that
   can ever appear is the freshly-created one, per §8's own named fix, now
   actually applied instead of only documented.
2. The single `sleep 9` + one-shot window-count check is now a poll (up to
   10 attempts, 2s apart, on top of the original 9s) — because even *with*
   the flag, a cold launch was observed taking ~17s to vend its first window
   to System Events, longer than the original budget allowed.

**Verified — `check-accessibility.sh` run three times, back to back, after
the fix (not once):** all three **PASS**, each reporting the main window's
`20` block-shaped elements:
```
building…
querying pid 63918
block-shaped elements in the tree: 20
...
PASS (elements present)
```
(repeated verbatim, modulo pid, at pid 64116 and pid 68009 on the next two
runs.)

**A second, distinct issue found and fixed while spot-verifying the other
three scripts (not the mechanism this task was assigned, but the same class
of "script assumed a quiet foreground" fragility):** `check-routines-window.sh`
sends its ⌘⌥R keystroke via `System Events ... tell process ... keystroke`,
but `keystroke` is delivered to whichever process is *actually* frontmost
system-wide — the `tell process` scoping does not redirect it. On this Mac,
right now, another running application was intermittently holding or
reclaiming frontmost status (`osascript ... get name of first process whose
frontmost is true` returned `LeagueClientUx`, and later, mid-session,
`LeagueofLegends` — a live game session on this machine, confirmed by
querying frontmost immediately after an explicit `set frontmost of
(Kadence process) to true`, which was overridden within about a second).
Added an explicit `set frontmost of (first process whose unix id is $TARGET)
to true` immediately before the keystroke in `check-routines-window.sh`.
Verified: with this added, a reproduction that had previously failed
(`windows before ⌘⌥R: 1`, `windows after: 1`) now passed
(`windows after: 2`, `PASS: ⌘⌥R opened a new window.`, 9 routine-block
elements found, matching §8's own count).

**NOT fixed, and explicitly out of scope for this task:** with the live game
session described above still running on this machine, `check-block-click-
selects.sh` and the click-driven tail of `check-routines-window.sh` (the part
after the ⌘⌥R fix above) still fail intermittently — the block never reads
selected after the `CGEvent` click. Root-caused as far as is useful here:
`first process whose frontmost is true` reported `LeagueofLegends` again at
the moment of the failing runs, and it reclaimed frontmost within ~1s of an
explicit override, which is consistent with clicks/focus being contended by
that other application rather than any fault in Kadence's own hit-testing
(already covered, separately, by `check-block-hit-regions.sh`, which does not
depend on frontmost/keyboard focus and **passed** cleanly this session — `20`
timed elements, `20` distinct y positions, `4` columns checked, no
ordering failures). This is a live, external, third-party application
contending for OS-wide input focus on this specific Mac at this specific
time — not a Kadence defect, not the restoration mechanism this task was
assigned to fix, and not something a `Scripts/` change can neutralise short
of quitting someone else's running application, which is out of scope. Filed
here, not silently dropped, so the next person who sees `check-block-click-
selects.sh` fail on this machine checks what else is running before assuming
a regression.

**What is next:** re-run `check-block-click-selects.sh` and
`check-routines-window.sh`'s click assertion once no other application is
contending for frontmost on this Mac, to confirm they are clean under the
new launch fix too — expected to pass, per `check-block-hit-regions.sh`'s
clean run this session, but not yet directly observed clean end-to-end.

**Blocked:** nothing for this task's own scope. The frontmost-contention
issue above is not blocked, just out of scope; it is an environmental fact
about this Mac at this moment, not a design or code question.

---

## 12. P2-T13 — ConflictEngine: conflict detection and resolution-option generation (data layer only, 2026-09-18)

Built `Kadence/State/ConflictEngine.swift` and
`KadenceTests/ConflictEngineTests.swift`. BRIEF-PRODUCT.md's Phase 2 section
("Conflict detection: any overlap between a routine block and an imported/
manual event ... generate 2-3 concrete resolution options ranked by how
little they disturb the day ... with one marked recommended") and
components.md §14.3 (the option row's required fields: an imperative title, a
disturbance delta, and exactly one `recommended` flag). Same shape as
P2-T08's `RoutineEngine.materialize`: a pure, `@MainActor`-scoped engine that
reads already-fetched `Event`/`RoutineBlock` model objects and produces new
value types (`Conflict`, `ConflictOption`) — it mutates nothing, touches no
`ModelContext`, and touches no `UndoStack`.

**What `ConflictEngine.detect(events:routineBlocks:)` does:**
1. Pairwise-scans `events` (O(n²), deliberately simple — nothing in scope
   runs this over more than a day's or a week's worth of events) and keeps a
   pair only when exactly one side has `origin == .routine` and the other has
   `origin == .manual` or `.imported`, and their intervals strictly overlap
   (`a.start < b.end && b.start < a.end` — touching endpoints do not count).
   Two `.routine` events overlapping each other, two non-routine events
   overlapping each other, and a `.routine` event overlapping a `.planned`
   event are all excluded by construction — the brief only ever names
   routine-vs-imported/manual.
2. For each surviving pair, builds a `Conflict` (the two `Event` references,
   the overlap window, and its ranked `[ConflictOption]`), keyed on the
   routine event's `flexibility` (already transferred onto every materialized
   `Event` by `RoutineEngine.materialize`, per §6):
   - `.shiftable` — a `.shiftLater` option: the minimal 15-minute-incremented
     later shift (interactions.md §3/§4's own snap) that clears the overlap,
     clamped to the routine's own `RoutineBlock.shiftableMinutes`. Omitted
     when the needed shift exceeds that range.
   - `.droppable` — a `.skipToday` option, marking that one occurrence
     `.skipped` (`EventStatus`), never the whole template.
   - `.fixed` — a `.shorten` option: trims the routine event to end where the
     other event starts, or to start where it ends, whichever keeps more of
     the original duration (ties keep the original start). Omitted when the
     kept duration would fall below interactions.md §4's 15-minute floor.
   - Every case also gets a `.skipToday` fallback, so the option list never
     goes to zero — except `.droppable`, where the flexibility-derived option
     *is* `.skipToday` already; adding it a second time would be a literal
     duplicate, not a genuinely different fallback, so it is not added twice.
     Documented consequence: a `.droppable` conflict, and the (rare) edge
     case where a `.shiftable`/`.fixed` conflict's derived option doesn't
     fit, end up with exactly 1 option rather than the typical 2. "At least
     one option, exactly one of them recommended" always holds; the "2-3
     typically" shape is what narrows in that edge case. This reading is
     documented at length in `ConflictEngine.makeOptions`'s own doc comment,
     in the same spirit P2-T08 used for the priority-field question — kept
     building around it rather than blocking or filing a gap, since it
     resolves cleanly from the brief's and components.md's own wording.
   - `RoutineBlock` lookup reverses `RoutineEngine.swift`'s own documented
     `externalID` shape (`"<block.id>#<yyyy-MM-dd>"`) against a caller-
     supplied `[RoutineBlock]` array — no `shiftableMinutes` field was added
     to `Event` itself. §6 already declined to add one for the same
     `priority` question; this task makes the identical call for
     `shiftableMinutes`, for the identical reason (not inventing a field
     neither `Event.swift` nor the brief's data-model draft has).
3. `ConflictOption.disturbanceMinutes` puts all three option kinds on one
   comparable axis: minutes shifted (`.shiftLater`), minutes trimmed off the
   original duration (`.shorten`), or the occurrence's full original duration
   in minutes (`.skipToday` — losing the whole block reads as more
   disturbance than trimming part of it). The task text allowed either
   "minutes moved" or "a count of affected occurrences"; a bare occurrence
   count would not sit on the same axis as the other two kinds' minute
   figures, so this engine uses minutes throughout. Documented in
   `ConflictOption`'s own doc comment.
4. Options are sorted ascending by `disturbanceMinutes` and the first
   (least-disturbance) one is marked `isRecommended = true` — components.md
   §14.3's own documented default ("Options are ordered by disturbance, least
   first... The recommended one is usually but not necessarily first"), which
   the task brief explicitly allows as the engineering tie-break since the
   spec does not mandate a different one.

**Explicitly out of scope, not built here** (all separate, future tasks, same
as this task's own brief): wiring detected conflicts into
`Presentation.conflicted`/`BlockStyleResolver`/`GridBlockView`, the "Needs
your attention" row, the conflict panel view (components.md §14,
interactions.md §10), applying an option to the store or `UndoStack`
(interactions.md §10.1's "one named undo step" is the future task's job), and
protected-window conflicts (no `TimeWindow` model exists yet).

**Verified:**
- `xcodebuild -scheme Kadence -destination 'platform=macOS' build` —
  `** BUILD SUCCEEDED **`, no new warnings (`grep -i warning:` on the full log
  found only xcodebuild's own harmless "multiple matching destinations"
  notice, unrelated to this task).
- `xcodebuild -scheme Kadence -destination 'platform=macOS'
  -only-testing:KadenceTests test` — `** TEST SUCCEEDED **`, 249 `passed`
  lines / 0 `failed`, including the 16 new `ConflictEngineTests.swift` cases:
  routine-vs-manual detected, routine-vs-imported detected, manual-vs-manual
  not detected, routine-vs-routine not detected, routine-vs-planned not
  detected (bonus coverage beyond the task's own list), touching endpoints
  not detected, non-overlapping pair produces nothing, `.shiftable`
  shift-in-range and shift-exceeds-range, `.droppable` skip option,
  `.fixed` shorten-fits and shorten-below-floor, exactly-one-recommended
  across three simultaneous conflicts of different flexibilities, and
  ascending-disturbance ordering.
- `swift Scripts/generate-tokens.swift --check` —
  `Kadence/DesignSystem/Tokens.swift is up to date.` (expected: a data-layer
  engine needs no new tokens.)
- Confirmed by `git status`: this task touched exactly
  `Kadence/State/ConflictEngine.swift` and `KadenceTests/ConflictEngineTests.swift`
  (plus `STATUS.md`) — no file under `Kadence/Views/`, and
  `GridBlockView.swift`/`BlockStyleResolver.swift` untouched.

**What is next:** the three follow-up tasks this one deliberately left open —
wiring `Presentation.conflicted` for detected conflicts, the "Needs your
attention" row + conflict panel (components.md §14, interactions.md §10), and
an "apply an option" command on `EventStore`/`UndoStack` (one named undo step,
per interactions.md §10.1). None of those are blocked by anything found here.

**Blocked:** nothing.

## 13. P2-T14 — wire `ConflictEngine.detect` into `Presentation.conflicted` on the live calendar canvas (2026-09-18)

The first of §12's three deliberately-deferred follow-ups (`ConflictEngine.swift`'s
own header, item 1). Purely additive wiring — no change to `ConflictEngine.swift`
itself (§12's detection/option logic was already tested there in isolation), and
no change to the still-unbuilt Phase 1 `conflictsWithProtectedWindow` placeholder
in `DayColumnView.swift`, which stays exactly as it was.

**What changed:**
1. `Kadence/Views/MainWindow.swift` — added `@Query private var routineBlocks:
   [RoutineBlock]` alongside the existing `@Query(sort: \Event.start) private
   var events: [Event]`. Added a computed property `conflictedEventIDs: Set<UUID>`
   that calls a new `static func conflictedEventIDs(events:routineBlocks:) ->
   Set<UUID>` — pulled out as its own `@MainActor` static function (rather than
   left inline in the computed property) specifically so `KadenceTests` can
   drive it directly without instantiating the view. It runs
   `ConflictEngine.detect(events:routineBlocks:)` and collects both
   `conflict.routineEvent.id` and `conflict.otherEvent.id` from every result
   into one `Set<UUID>`. No hand-rolled caching — it is a plain computed
   property, recomputed on every body evaluation from the live `@Query` arrays,
   which is what the task asked for and is cheap enough given `detect`'s own
   O(n²)-over-one-day/week scope (§12).
2. The result is passed into both `TimedCanvasView` call sites (week and day
   mode) as a new `conflictedEventIDs: Set<UUID>` parameter (default `[]`,
   mirroring how `focusedRegion`/`onTab` are already threaded).
3. `Kadence/Views/Canvas/TimedCanvasView.swift` — added the same `var
   conflictedEventIDs: Set<UUID> = []` property and passed it straight through
   to every `DayColumnView` it constructs, the same way `fixtures`/`now` are
   already threaded — no per-day filtering needed since `Presentation` is
   computed per-event by id, not per-day.
4. `Kadence/Views/Canvas/DayColumnView.swift` — added the same property
   (default `[]`, since `RoutinesWindow.swift`'s type-named-alike
   `RoutineDayColumnView` is a distinct type and was never a caller here — the
   only real caller is `TimedCanvasView`, which now always passes the live
   set). In `presentation(for:laidOut:)`, added
   `if conflictedEventIDs.contains(event.id) { presentation.insert(.conflicted) }`
   as a new line immediately after the existing
   `if conflictsWithProtectedWindow(event) { presentation.insert(.conflicted) }`
   — additive, not a replacement; a block can now pick up `.conflicted` from
   either source, or both.

**Explicitly not built here** (all separate, future tasks, per
`ConflictEngine.swift`'s own header and this task's brief): the "Needs your
attention" row, the conflict panel view, preview-on-focus, and an apply/undo
command on `EventStore`/`UndoStack`. Month view is untouched — it renders a
different chip component per components.md §9, not `GridBlockView`/
`Presentation`, so it was never in scope.

**New test coverage:** `KadenceTests/ConflictPresentationWiringTests.swift`
(new file), same in-memory `ModelContainer`/`ModelContext` pattern as
`RoutineEngineTests.swift`/`ConflictEngineTests.swift`. Drives
`MainWindow.conflictedEventIDs(events:routineBlocks:)` directly:
- a routine event overlapping a manual event — both ids are flagged, and
  the set has exactly those two members;
- two overlapping manual events — neither id is flagged (matches
  `ConflictEngine`'s routine-vs-manual/imported-only scope);
- two overlapping routine events — neither id is flagged (same reason);
- a non-overlapping routine/manual pair — not flagged;
- recomputation: a routine event alone produces an empty set; inserting an
  overlapping manual event and recomputing flags both ids — proving the
  computed property genuinely reacts to a change in the underlying `events`
  list rather than caching a stale answer.

**Verified:**
- `xcodebuild -scheme Kadence -destination 'platform=macOS' build` —
  `** BUILD SUCCEEDED **`, no new warnings.
- `xcodebuild -scheme Kadence -destination 'platform=macOS'
  -only-testing:KadenceTests test` — `** TEST SUCCEEDED **`, 226 tests / 0
  failed (254 including parametrized runs), including the 5 new
  `ConflictPresentationWiringTests.swift` cases listed above.
- `swift Scripts/generate-tokens.swift --check` —
  `Kadence/DesignSystem/Tokens.swift is up to date.` (expected: no new
  tokens needed for this wiring.)
- Confirmed by inspection: `git diff --stat` touches exactly
  `Kadence/Views/MainWindow.swift`, `Kadence/Views/Canvas/TimedCanvasView.swift`,
  `Kadence/Views/Canvas/DayColumnView.swift`,
  `KadenceTests/ConflictPresentationWiringTests.swift`, `STATUS.md` and
  `DEVIATIONS.md` — `Kadence/State/ConflictEngine.swift` is untouched, and no
  "Needs your attention" row, conflict panel, preview, or apply/undo command
  was added anywhere.
- Manual reasoning check on the "protected window still shows `.conflicted`"
  acceptance point: `conflictsWithProtectedWindow` is an unmodified,
  independent `if` line in the same `||`-style accumulation into
  `presentation`; it is not gated on or replaced by the new
  `conflictedEventIDs` line, so a block in a protected window continues to
  get `.conflicted` exactly as before, with or without a real
  `ConflictEngine` conflict also being present.

**What is next:** the two remaining follow-ups §12 named — the "Needs your
attention" row + conflict panel (components.md §14, interactions.md §10),
and an "apply an option" command on `EventStore`/`UndoStack` (one named undo
step, per interactions.md §10.1). Neither is blocked by anything found here.

**Blocked:** nothing.

## 14. P2-T15 — needs-attention row + static conflict panel (entry point only, 2026-09-18)

The second of §12's deferred follow-ups. Scope, per this task's own brief:
build the entry point into conflict resolution and its static content only —
**no preview-on-focus, no `↩` apply, no `⎋` abandonment.** Those are
interactions.md §10.1's second half plus all of §10.2, and are explicitly a
separate, later task.

**What changed:**

1. `Kadence/Views/Chrome/SidebarView.swift` — the needs-attention row is now
   a real `Button` (components.md §14.1: "The needs-attention row (§10.2) is
   a button"), calling `CalendarState.activateNeedsAttention()`. Its
   `Image(systemName: "tray.full")` icon is **removed** — components.md
   §10.2 forbids it outright ("The row takes no icon") — closing
   **DEVIATIONS.md A21**, open since the §10.2 amendment landed. The row is
   `if !state.conflicts.isEmpty` (hidden entirely at zero, no zero badge) and
   its count badge is unchanged from Phase 1's build: `blockMeta` type,
   `color.text.secondary` on `color.surface.canvasSunken`, radius
   `radius.chip`, horizontal padding `spacing.sm` — every token §10.2 names
   already existed, so nothing was invented and no gap was filed. The view no
   longer takes a `needsAttentionCount` init parameter (its one caller passed
   a hardcoded `0`); it reads `state.conflicts.count` directly from the
   environment, the same way it already reads `state.hiddenSources`.
2. `Kadence/Views/Chrome/KadenceCommands.swift` — a new `⌘⇧A` menu item,
   "Go to First Conflict", in the View menu group, `.disabled(when
   calendar.conflicts.isEmpty)` (interactions.md's shortcut table: "global,
   when the count is non-zero"). `KadenceCommands` has no query of its own
   onto the live `Event`/`RoutineBlock` data — same cross-scene problem
   `⌘N`/`.kadenceNewEvent` already solved — so it posts a new
   `.kadenceGoToFirstConflict` notification that `MainWindow` observes and
   turns into the same `state.activateNeedsAttention()` call the sidebar row
   makes, so the row and the shortcut are provably the same action, not two
   copies that could drift.
3. `Kadence/State/CalendarState.swift` — added `conflicts: [Conflict] = []`
   (refreshed by `MainWindow`, read by the sidebar row, the menu command and
   the inspector so all three can never disagree about what there is to
   select), `selectedConflictID: String?` and `selectedConflictOptionID:
   UUID?` (both nil outside conflict mode), and `activateNeedsAttention()` —
   selects `conflicts.first`, clears any ordinary event selection, clears any
   previously-highlighted option, and forces the inspector open. A no-op
   when `conflicts` is empty, which is what makes the row's "hidden at zero"
   and the shortcut's "disabled at zero" both trivially safe at the call
   site.
4. `Kadence/State/ConflictOrdering.swift` (new) — "the first unresolved
   conflict" (components.md §14.1) needed a stable rule, since
   `ConflictEngine.detect`'s result order is just pairwise iteration order
   over whatever array it was handed, not a meaningful "first" a user would
   recognise call to call. Neither components.md nor interactions.md
   specifies one, so this is this task's own engineering call, not an
   invented design token (it is a tie-break rule over application data, not
   a colour/size/token value): ascending by the earlier of the two colliding
   events' start times, tied broken by `Conflict.id` (the engine's own
   stable string) for determinism. Pure, no SwiftUI, same shape as
   `CalendarState.FocusRegion.next`.
5. `Kadence/State/ConflictOptionFormatting.swift` (new) — the option-row
   prose (title + disturbance line) that `ConflictEngine.swift`'s own header
   comment explicitly left to "a later UI task": this is that task.
   `title(for:conflict:)` and `delta(for:conflict:)` are pure functions over
   `ConflictOption`/`Conflict`; `rows(for:)` maps a conflict's options (in
   their existing least-disturbance-first order) into
   `ConflictOptionRowContent` values carrying `id`/`title`/`delta`/
   `isRecommended` — the exact array `ConflictPanelView` renders with no
   further filtering, which is also this task's testing seam for "the panel
   renders the right number of rows with the recommended one marked"
   (AccessibilityTests.swift's header already established why hosting a
   SwiftUI view and inspecting its accessibility tree from inside a unit
   test is not reliable on this platform — the same reasoning applies here).
   The literal wording is a documented judgement call, not a spec value:
   components.md §14.3 gives two worked examples for illustration, not a
   template, and no file under `design/` gives a literal format string.
6. `Kadence/Views/Chrome/ConflictPanelView.swift` (new) — components.md
   §14.2's collision header (the two colliding events rendered through the
   real `GridBlockView`/`resolveBlockStyle` path, `presentation: [.conflicted]`
   so the panel matches what the grid already shows for them per P2-T14's
   wiring, at a fixed height of 22pt — the midpoint of §3.3's old "16–27"
   band, which the current tier numbering's own "reading the old numbers"
   table maps to `.titleOnly`; any height in that band resolves to the same
   tier, so the specific figure is this task's call, not an invented token —
   stacked `spacing.xs` apart with the word "overlaps" between them in
   `inspectorLabel`/`color.text.secondary`, then the overlap window and
   duration in `blockMeta`) and §14.3's option rows (via
   `ConflictOptionFormatting.rows(for:)`: title in `conflictOptionTitle`,
   disturbance line in `conflictOptionDelta`/`color.text.secondary`, a
   `Recommended` chip — `blockMeta`/`color.text.secondary` on
   `color.surface.canvasAlt`, radius `radius.chip`, padding `spacing.xs` —
   on the recommended row only, `size.conflictOptionRowMinHeight` minimum
   height, `size.conflictOptionGap` between rows, radius `radius.card`, fill
   `color.surface.canvasSunken`, `color.interactive.selectedRowFill` when
   selected). Tapping a row calls `onSelectOption`, which only updates
   `selectedConflictOptionID` for the highlight — no preview, no apply.
7. `Kadence/Views/Chrome/InspectorView.swift` — gained three new, all-defaulted
   properties (`conflict: Conflict? = nil`, `selectedConflictOptionID: UUID? =
   nil`, `onSelectConflictOption: (UUID) -> Void = { _ in }`), so every
   existing caller and every existing test is unaffected. When `conflict` is
   non-nil the body renders `ConflictPanelView` instead of the ordinary
   event-details/day-summary content — "conflict mode" (components.md §14.1)
   entirely replaces the rest of the inspector while active, per §14.1's "no
   separate list view and no sheet."
8. `Kadence/Views/MainWindow.swift` — `SidebarView()` no longer takes a
   `needsAttentionCount` argument (removed with the property). Added
   `sortedConflicts(events:routineBlocks:) -> [Conflict]` (`@MainActor`,
   `static`, same shape as the existing `conflictedEventIDs(events:
   routineBlocks:)`, which now calls it internally instead of running
   `ConflictEngine.detect` a second time) and an instance method
   `refreshConflicts()` that writes `Self.sortedConflicts(...)` into
   `state.conflicts`, wired from two new `.onChange(of: events, initial:
   true)` / `.onChange(of: routineBlocks, initial: true)` modifiers — not
   computed directly in `body` and assigned there, which would be mutating
   an `@Observable` the view tree reads from inside the same update pass;
   `.onChange` runs after the triggering update, which is the supported
   place for this. `inspectorBody` now passes `conflict: activeConflict`
   (looks up `state.selectedConflictID` in the current `state.conflicts`,
   falling back to `nil` — not a crash — if a stale id no longer resolves),
   `selectedConflictOptionID: state.selectedConflictOptionID`, and
   `onSelectConflictOption: { state.selectedConflictOptionID = $0 }`. A new
   `.onReceive(.kadenceGoToFirstConflict)` calls `state.activateNeedsAttention()`.
9. `Kadence/DesignSystem/TypeStyle.swift` — added `conflictOptionTitle` and
   `conflictOptionDelta`, following the existing pattern (both token groups,
   `Typography.ConflictOptionTitle`/`.ConflictOptionDelta`, already existed
   in `Tokens.swift` from the Phase 2 token pass; nothing new was generated).

**No token gap.** Every token components.md §10.2/§14.2/§14.3 names —
`radius.chip`, `radius.card`, `spacing.xs`, `spacing.sm`,
`color.text.secondary`, `color.surface.canvasSunken`, `color.surface.canvasAlt`,
`color.interactive.selectedRowFill`, `size.conflictOptionRowMinHeight`,
`size.conflictOptionGap`, `typography.conflictOptionTitle`,
`typography.conflictOptionDelta`, `typography.inspectorLabel`,
`typography.blockMeta` — already existed in `Tokens.swift` from the Phase 2
token pass this task's brief anticipated might be missing. Checked by name
against `Tokens.swift` before writing any view code; none needed a
`// SPEC-GAP` placeholder, and `design/GAPS.md` gained no new entry from this
task.

**New test coverage:** `KadenceTests/ConflictEntryPointTests.swift` (new
file), same in-memory `ModelContainer`/`ModelContext` pattern as
`ConflictEngineTests.swift`/`ConflictPresentationWiringTests.swift`. Three
suites, matching this task's own acceptance criteria:
- `NeedsAttentionCountTests` — zero conflicts gives an empty list (row
  hidden); two independent conflicts give a count of 2 (row shows "2");
  assigning `MainWindow.sortedConflicts(...)` into a fresh
  `CalendarState.conflicts` produces the same count the sidebar/shortcut
  would read.
- `ConflictActivationTests` — `ConflictOrdering` sorts strictly ascending by
  earliest colliding start time even when handed events in the opposite
  order (proving it re-sorts, not merely preserves input order); tied start
  times sort deterministically by `Conflict.id` across repeated calls;
  `activateNeedsAttention()` selects `conflicts.first`, clears an existing
  ordinary selection, clears any stale option highlight, and forces the
  inspector open; it is a no-op (touches nothing) when `conflicts` is empty.
- `ConflictOptionRowContentTests` — `ConflictOptionFormatting.rows(for:)`
  produces exactly as many rows as `conflict.options`, in the same order,
  with exactly one `isRecommended`; a `.droppable` conflict's single-option
  case still produces exactly one row, marked recommended, with non-empty
  title/delta text (the panel never shows zero rows); a `.shiftLater`
  option's title names the routine event and its minute figure, and its
  delta line names the event's new start time.

**Verified:**
- `xcodebuild -scheme Kadence -destination 'platform=macOS' build` —
  `** BUILD SUCCEEDED **`, no new warnings.
- `xcodebuild -scheme Kadence -destination 'platform=macOS'
  -only-testing:KadenceTests test` — `** TEST SUCCEEDED **` — see this
  task's own report for the exact count, re-run and re-verified
  independently by the orchestrator.
- `swift Scripts/generate-tokens.swift --check` —
  `Kadence/DesignSystem/Tokens.swift is up to date.` (no new tokens needed).
- Confirmed by inspection: no preview-on-focus, `↩` apply, or `⎋`
  abandonment wiring was added anywhere — `ConflictPanelView`'s option row
  only calls `onSelectOption` (a highlight), and no code path in this diff
  touches `EventStore`, `UndoStack`, or the calendar canvas's block
  presentation for anything preview-related.

**Explicitly not built here**, same as §12/§13 left it, and not to be
rediscovered by the next task: **preview-on-focus** (an option gaining
focus previewing it on the real grid, `previewed` presentation, the
canvas's `size.previewCanvasBorder` accent border — components.md §14.4),
**`↩` apply** (writing a chosen option to the store as one named undo
step — interactions.md §10.1), and **`⎋` abandonment** (unconditionally
discarding a live preview — interactions.md §10.2, components.md §14.5's
"resolved and empty" state also depends on an apply step existing at all).
None of the three is blocked by anything found in this task.

**Blocked:** nothing.

## 15. P2-T15 follow-up — diagnose and fix `check-accessibility.sh`'s "no
window" failure, again (2026-09-18)

The task orchestrator recorded `check-accessibility.sh` as `FAIL: no Kadence
process has a window` immediately after §14's commit and asked whether this
was a genuine P2-T15 regression (⌘⇧A firing at launch, `ConflictOrdering`/
`ConflictPanelView` evaluated against an uninitialized store, a SwiftData
query erroring on first launch) or a re-flake of the restoration issue §11
already fixed — explicitly not to assume either without evidence.

**It is neither. Root cause: the screen on this Mac is locked
(`CGSSessionScreenIsLocked=1`), which blocks accessibility window
enumeration session-wide for every process — not a P2-T15 code path, and not
§11's restoration flake.**

**Evidence, not assumption:**
- `python3`/PyObjC's `Quartz.CGSessionCopyCurrentDictionary()` read
  `CGSSessionScreenIsLocked = 1` at the moment of failure (checked via a
  `Quartz` install already present on this machine, from a Claude Code
  extension's venv — see below for why the shipped script does not depend on
  that path).
- `Quartz.CGWindowListCopyWindowInfo` at the same moment showed a live
  Kadence window, owner "Kadence", size **1470×882** at (158, 42) — a
  plausible, correctly-sized main-window geometry, not a crashed or
  zero-size stub. The app came up fine; the lock screen is what makes System
  Events blind to it.
- `ps -p <pid>` showed the process alive (state `S`) throughout, matching
  the healthy-but-invisible signature, not a hang.
- `~/Library/Logs/DiagnosticReports` has no Kadence entries; `log show
  --predicate 'process == "Kadence"' --last 10m` returned nothing
  fault/error/crash-shaped. No crash.
- The build that produced the running binary (`xcodebuild ... build`) has
  **zero** `warning:` lines — a clean build, no new warnings from P2-T15's
  diff.
- **Timing rules out P2-T15's diff specifically:** the screen-lock timestamp
  (`CGSSessionScreenLockedTime`) decodes to **02:29:12**, and §14's own
  commit (`e9158ef`) is timestamped **04:55:39** — over two hours *after*
  the screen was already locked. The `check-accessibility.sh` failure this
  task was asked to investigate was recorded against a commit made while the
  session-wide AX blindness was *already in effect*; P2-T15's diff cannot be
  the cause of a symptom that predates it.
- Re-ran `xcodebuild ... build` (clean, `** BUILD SUCCEEDED **`, 0 warnings)
  and `xcodebuild ... -only-testing:KadenceTests test` (all cases printed
  `passed`, 0 `failed`) against the current `HEAD` with the screen still
  locked — the rest of the toolchain is unaffected; only the AX-enumeration
  step that needs System Events to see a window is blocked.

This is the same class of carve-out the CA brief itself names ("if TextEdit
also reports 0 windows, that is the machine, not your code") and the same
class of machine condition §1.2/§1.2.1/§11 already hit twice before under a
*different* mechanism (stale window-restoration state, not a lock screen) —
but this is the first time the actual mechanism has been confirmed directly
at the OS level rather than inferred from a same-symptom control app.

**No app code was touched.** `Kadence/State/CalendarState.swift`,
`ConflictOrdering.swift`, `ConflictOptionFormatting.swift`,
`ConflictPanelView.swift`, `InspectorView.swift`, `KadenceCommands.swift`,
`SidebarView.swift`, `MainWindow.swift`, `TypeStyle.swift` — every file
§14 touched — are unchanged by this task. There is no regression in them to
fix.

**What was changed: `Scripts/check-accessibility.sh`'s failure branch**,
continuing partial work already in the tree from an interrupted prior run of
this same task (a Finder-based session-wide control check). That control
check is kept as a fallback, but the primary diagnosis is now a **direct**
OS query instead of an inference from a second app's symptom:
- Added a `swift -e` one-liner (the project's own `swift` toolchain — no new
  dependency; `generate-tokens.swift` already requires it) that calls
  `CGSessionCopyCurrentDictionary()` and prints
  `CGSSessionScreenIsLocked`. When it reads `1`, the script now fails with
  an unambiguous "the screen is LOCKED... this is not a Kadence defect...
  do not chase this as an app-code regression" message instead of the old
  generic "the app did not come up."
- Deliberately **not** implemented with `python3`: a `python3 -c "import
  Quartz; ..."` version was prototyped first and worked, but only because a
  Claude Code extension's private venv (`~/Library/Application
  Support/Claude/Claude Extensions/.../.venv/bin/python3`), not a system
  Python, happened to be first on `$PATH` and happened to have PyObjC
  installed. That is not something this script should depend on to run
  correctly on a different checkout or a differently-configured Mac; `swift`
  is a real, already-declared project dependency, so the shipped fix uses
  that instead.
- If the direct check is inconclusive (no `swift` on `$PATH`, or the call
  errors), the script falls through to the pre-existing Finder-based control
  check from the interrupted prior run, unchanged.

**Regression test:** none added. §14's diff has no defect to regress-test
against — nothing crashed, nothing hung, and the failure this task was
asked to investigate is proven (by the timestamp comparison above) to
predate §14's own commit. `ConflictOptionRowContentTests` (§14, already
covers the empty/zero-conflict and single-option cases the task brief
flagged as suspects for "evaluated on an empty/uninitialized store") already
exercises exactly that boundary and was unaffected.

**Verified:**
- `xcodebuild -scheme Kadence -destination 'platform=macOS' build` —
  `** BUILD SUCCEEDED **`, 0 warnings.
- `xcodebuild -scheme Kadence -destination 'platform=macOS'
  -only-testing:KadenceTests test` — all cases `passed`, 0 `failed`.
- `swift Scripts/generate-tokens.swift --check` —
  `Kadence/DesignSystem/Tokens.swift is up to date.`
- `Scripts/check-accessibility.sh`, run repeatedly this session: every run
  correctly and immediately reports `FAIL: no Kadence process has a window
  — the screen is LOCKED (CGSSessionScreenIsLocked=1)...` — this is the
  script now working *correctly* (accurate diagnosis of a real, persistent
  machine condition), not the script passing. **The script's actual
  "PASS (elements present)" gate — the thing acceptance asked for two
  consecutive clean runs of — could not be exercised in this session: the
  screen has been locked continuously (checked repeatedly, still locked at
  the time this entry was written) since before this task started, and
  unlocking it requires this machine's password, which this task does not
  have and should not attempt to obtain or bypass.** This is a machine-state
  blocker, not a code defect — per the CA brief's own instruction to say so
  rather than report a failure.

**What is next:** ~~once the screen is unlocked, re-run
`Scripts/check-accessibility.sh`~~ — **superseded, see §16: the screen was
confirmed unlocked on 2026-09-18 and the gate was run for real, twice, both
`PASS (elements present)`.** Nothing about §14's conflict entry-point
feature was ever at risk — the evidence above was always about the
verification environment, not the code — and §16 now closes that out with
an actual result instead of a deferral.

**Blocked:** ~~getting an actual PASS out of `check-accessibility.sh` this
session — the screen is locked and this task cannot unlock it.~~ **No longer
blocked — see §16.** Not blocked at the time either: build, unit tests, and
the token check, all independently green above.

## 16. P2-T15 gate closure — screen confirmed unlocked, real `PASS` obtained
(2026-09-18)

Parsa ruled (2026-09-18 14:32, ledger) that the screen is unlocked for this
run. §15 could only ever diagnose the lock itself; the actual
`check-accessibility.sh` gate had never been exercised against a live
P2-T15 build. This task's only job was to get a real result out of the gate
and act on it — not to re-litigate §15's diagnosis, and not to start any
new feature work.

**Lock state checked first-hand before anything else**, with the exact
probe `check-accessibility.sh` itself uses (`CGSessionCopyCurrentDictionary`
via `swift -e`), not taken on Parsa's word alone:

```
CGSSessionScreenIsLocked= -999   (key absent from the session dict — the
                                   script's own `?? 0` fallback reads this
                                   as unlocked, matching Parsa's ruling)
kCGSSessionOnConsoleKey= 1        (on console, matching Parsa's ruling)
```

The full dictionary was printed and inspected; `CGSSessionScreenIsLocked` is
simply not a key in it right now (it only appears when the screen actually
is locked — see §15's dump, which had it present and `= 1`). Confirmed
unlocked, first-hand.

**`Scripts/check-accessibility.sh` run twice, end to end, against a fresh
build:**

Run 1 (default, app quit at the end):
```
building…
querying pid 71620
block-shaped elements in the tree: 20
carrying the §11 label:            0
  AXHelp=Breakfast · 07:15–07:45 · Daily routine · routine block, ...
  AXHelp=Morning review · 08:00–09:00 · Daily routine · routine block, ...
  AXHelp=Datenmodellierung · 09:00–10:30 · University timetable · lecture, ...

WARN: blocks are in the tree, but 0 carry the §11 label.
      Known open defect A20b — VoiceOver reads the hover-help string
      instead of 'title, time, kind, source, status'.
PASS (elements present)
```

Run 2 (`--keep`, so the live app could be inspected further — see below):
identical result, `block-shaped elements in the tree: 20`, `PASS (elements
present)`.

Both are genuine `PASS`, taken at face value per this task's own
instruction. The `WARN` about the §11 label is **pre-existing, already-open
defect A20b** (DEVIATIONS.md, unrelated to P2-T15 — it is about the
day-grid block elements' label content, not the conflict entry point), not
a new regression; it does not change the gate's `PASS` outcome, and this
task did not touch it (out of this task's scope, and not asked for).

**Supplementary manual verification of the P2-T15 entry point specifically**
(the gate itself only asserts on generic day-grid block elements, not on
the conflict panel by name, so this was done by hand against the kept-alive
instance from run 2, via the same System Events mechanism the script uses):
- The live app's actual data store currently has no overlapping
  events/routine blocks, so `state.conflicts` is empty and — correctly, per
  components.md §10.2's "hidden entirely at zero, no zero badge" and this
  task's own §14 implementation — the needs-attention row does not appear
  in the sidebar's button list. This is the spec'd behaviour, not a defect.
- The View menu's **"Go to First Conflict"** (`⌘⇧A`) item is present,
  confirmed via `System Events` (`menu item "Go to First Conflict" of menu 1
  of menu bar item "View"`), with `enabled = false` and `AXMenuItemCmdChar =
  "A"` — exactly matching interactions.md's "disabled when the count is
  non-zero" rule while there are zero conflicts, and confirming the
  shortcut is wired into a real, queryable menu item rather than only a
  notification handler nobody outside the app can see.
- The app launched and rendered its window cleanly with `MainWindow`'s
  `.onChange(of: events, initial: true)` / `.onChange(of: routineBlocks,
  initial: true)` — which run `ConflictEngine.detect` and
  `ConflictOrdering.sorted` on every launch, unconditionally, per §14's own
  wiring — having already executed twice (once per script run) without
  crashing, hanging, or producing a windowless launch. That is the
  strongest evidence available from this machine's actual data that §14's
  conflict-computation-at-launch path is not fragile.
- Exercising `ConflictPanelView`'s rendered content itself (an actual
  `.conflicted` pair) was not attempted: doing so would require creating
  synthetic overlapping events/routine blocks in the live, persisted
  SwiftData store this session is running against, which is out of this
  task's scope (out-of-scope list explicitly excludes "conflict-panel
  preview/apply... work") and would leave the store in a state a later task
  did not choose. `ConflictPanelView`'s own rendering is already covered by
  `ConflictOptionRowContentTests`/`ConflictActivationTests` (§14) at the
  pure-function layer, which is the seam this codebase already uses for
  content SwiftUI-hosted unit tests cannot reliably assert on (see §14's
  own note on why).

**No app-code defect found. No fix was needed, no regression test was
added — there was nothing to regress against.** Per this task's own
branching instructions, a `PASS` closes out verification without
re-litigation.

**Full verification suite, re-run after the gate:**
- `xcodebuild -scheme Kadence -destination 'platform=macOS' build` —
  `** BUILD SUCCEEDED **`.
- `xcodebuild -scheme Kadence -destination 'platform=macOS'
  -only-testing:KadenceTests test` — `** TEST SUCCEEDED **`, 263 `passed`,
  0 `failed`.
- `swift Scripts/generate-tokens.swift --check` — `Kadence/DesignSystem/
  Tokens.swift is up to date.`
- `Scripts/check-accessibility.sh` — `PASS (elements present)`, twice, as
  above.

**This closes P2-T15's verification.** The "blocked by locked screen"
language in §15 (and the matching entry in DEVIATIONS.md) is stale as of
this task and has been struck through/corrected in place rather than
deleted, so the record of what actually happened during the lock is not
lost.

**What is next:** the out-of-scope items §14 already named and this task
was explicitly told not to start — conflict-panel preview-on-focus, `↩`
apply, `⎋` abandonment, the TimeWindow editor, `MenuBarExtra`, snooze.
None of them is blocked by anything found in this task.

**Blocked:** nothing.

## 17. P2-T16 — conflict panel preview-on-focus and unconditional abandonment (2026-09-18)

The task §14 (P2-T15) deferred: components.md §14.4 ("Preview in place") and
interactions.md §10.1 ("Focus and preview") / §10.2 ("Abandonment is
unconditional"). `↩` apply and any `EventStore`/`UndoStack` mutation from the
panel are explicitly **out of scope** here — next task's job.

**What changed:**

1. `Kadence/Models/Enums.swift` — added `Presentation.previewed` (bit 5). Its
   doc comment records that the *ghost* half of §14.4 (the block's committed
   frame retained on screen) is deliberately NOT a second `Presentation` flag
   — it is the same real block rendered a second time at its real frame with
   plain reduced opacity, not a new visual treatment of it.
2. `Kadence/DesignSystem/BlockStyleResolver.swift` — `.previewed` sets
   `border = color.interactive.accent`, `borderWidth = size.borderSelected`,
   `borderDash = [3, 3]`, applied **last**, after the `status` switch and the
   `.conflicted`-at-`.glyphOnly` override — §6's own table says "applied
   last, after every row above it", and a resolver test
   (`previewedWinsOverConflicted`) pins that a conflicted-and-previewed block
   shows the accent dashed border, not the alert one.
3. `Kadence/Views/Blocks/GridBlockView.swift` — the existing
   `.opacity(presentation.contains(.dragging) ? ... : 1)` modifier gained a
   `.previewed` branch, same seam, same pattern: `opacity.blockPreviewed`.
4. `Kadence/State/CalendarState.swift` — three additions:
   - `ConflictPreviewFrames` (new top-level struct, pure, `Equatable`) —
     `.resolve(conflict:option:)` returns the routine event's real span
     (`ghost`, always present) and the option's proposed span (`proposed`,
     `nil` for `.skipToday`). This is the pure, testable seam the task asked
     for, same shape as `MainWindow.conflictedEventIDs`/`sortedConflicts`.
   - `moveSelectedConflictOption(by:)` — ↑/↓'s logic: steps through
     `conflict.options` (the conflict named by `selectedConflictID`) in array
     order, clamping at both ends (not wrapping — no options list has a
     sensible "one past the end"), landing on the first option when nothing
     was focused yet. A no-op if there is no matching conflict or it has no
     options.
   - `abandonConflictPreview()` — clears `selectedConflictOptionID` only.
     **Deliberately leaves `selectedConflictID` alone** — the scope decision
     the task asked to be recorded: §10.2's subject is "a pending preview,"
     not "conflict mode," so tabbing away and back (or a stray `⎋`) reverts
     the hypothetical without also ejecting the user from the conflict panel
     they were looking at. See the method's own doc comment and
     `DEVIATIONS.md` for the full argument.
5. `Kadence/Views/Canvas/DayColumnView.swift` (not in the manager's expected
   file list, touched because the preview has to render *somewhere* on the
   real grid, and this is where every other per-day overlay — the drag drop
   preview, the time cursor — already lives):
   - `activeConflictPreview` — `nil` unless `state.selectedConflictID` names
     a live conflict AND `state.selectedConflictOptionID` names one of its
     options; otherwise `(conflict, ConflictPreviewFrames.resolve(...))`.
   - `blockStack`'s ghost: `isPreviewGhost` is true whenever this event is
     `activeConflictPreview`'s `conflict.routineEvent` — folded into the
     existing `isDragged` opacity branch (`opacity.blockDragOrigin` either
     way), so the real, committed block dims for *every* focused option on
     its own conflict, `.skipToday` included, independent of whether that
     option has a `proposed` frame to also draw a twin at.
   - A new overlay, `conflictPreviewBlock`, drawn only when `proposed !=
     nil` and its `start` falls on this day: a second, full `GridBlockView`
     (not an empty dashed rectangle like the drag-drop preview — §14.4 shows
     the block itself moving) at the proposed frame, `presentation:
     [.previewed]`, sized like the drag/create previews (full column width
     minus `spacing.xxs`, not `DayLayoutEngine`'s cascade math — this is a
     hypothetical overlay, not a laid-out sibling). `.allowsHitTesting(false)`
     (a click always reaches whatever is really there, which is what lets
     "click the grid" already abandon the preview via the ordinary
     focus-change path) and `.accessibilityHidden(true)` (a transient,
     uncommitted copy of a block that already has its own accessible element
     at its real frame). Keyed with `.animation(..., value: proposed)` using
     `motion.blockMove`'s spring — interactions.md §10.1's own words,
     "blocks travel from the old proposal to the new one, never via their
     committed position": since this is the *same* view slot across an
     option change (not a remounted one, and not gated on the option's own
     id), SwiftUI animates directly between the two proposed frames and the
     real block's ghost dim never toggles off in between.
6. `Kadence/Views/MainWindow.swift`:
   - `canvas` gained `.overlay { if isConflictPreviewActive { ... } }` — a
     `Rectangle().strokeBorder(color.interactive.accent, lineWidth:
     size.previewCanvasBorder)`, on the canvas only (not the sidebar, not the
     inspector — components.md §14.4's own words), gated on
     `selectedConflictOptionID != nil && activeConflict != nil` (not merely
     `selectedConflictID != nil` — the panel can be open with nothing
     focused yet right after `activateNeedsAttention()`, and that is not
     itself a preview).
   - `inspector` gained `.onKeyPress(keys: [.upArrow, .downArrow, .escape],
     action: handleKey)` — the inspector never routed any key through
     `handleKey` before this task (only `.onKeyPress(keys: [.tab])`), and
     this hook is deliberately the narrow, `keys:`-filtered variant rather
     than the grid's unrestricted `.onKeyPress(action: handleKey)`, so `t`,
     delete, return and the option-modified moves stay grid-only exactly as
     before.
   - `handleKey` gained two new cases ahead of the pre-existing
     `.upArrow`/`.downArrow` ladder: `case .upArrow/.downArrow where
     state.focusedRegion == .inspector && state.selectedConflictID != nil`,
     calling `state.moveSelectedConflictOption(by: -1/1)`. Placed first so a
     focused conflict panel always wins regardless of an incidental modifier
     key (in practice the inspector's own restricted `onKeyPress` is the
     only path that can reach these keys with that guard true anyway).
   - `handleKey`'s existing `.escape` case gained a new branch, checked
     first and returning early so the pre-existing
     selection→cursor→unfocused ladder is untouched when the grid (not the
     inspector) has focus: `if state.focusedRegion == .inspector &&
     state.selectedConflictID != nil { state.abandonConflictPreview();
     return .handled }`.
   - Four new abandonment hooks, interactions.md §10.2's "at minimum" list:
     `.onChange(of: state.focusedRegion)` (clears the preview whenever focus
     is not `.inspector` — covers `⇥` cycling away and clicking the
     grid/sidebar, both of which already write `state.focusedRegion`),
     `.onChange(of: state.mode)`, `.onChange(of: state.anchor)` (view switch
     and paging), and `.onChange(of: state.isInspectorVisible)` (collapsing
     the inspector). Toolbar buttons that do not themselves change
     mode/anchor/focus/visibility (`+`, plain sidebar toggle) are not
     separately wired — see `DEVIATIONS.md` for why this is judged
     sufficient rather than a gap.
7. `Kadence/Views/Chrome/ConflictPanelView.swift` — header comment corrected
   (it previously said preview/apply/abandonment were "a separate, later
   task" in a way that read as still true of the whole feature; it is now
   accurate that only `↩` apply remains, and that the preview/abandonment
   wiring this task added lives in `MainWindow`/`DayColumnView`/
   `CalendarState`, not in this file, since this file has no access to the
   calendar canvas).

**Judgement calls, documented rather than guessed past** (both recorded in
`DEVIATIONS.md`, one also filed as `design/GAPS.md` G-014):
- **`.skipToday`'s preview treatment** — §14.4's wording is written for
  shift/shorten and does not say what previewing a skip looks like. Built:
  the ghost dims exactly as any other option would, no dashed twin is drawn
  (there is no destination frame to draw one at). `design/GAPS.md` G-014.
- **`abandonConflictPreview()`'s scope** — clears the preview only, leaves
  `selectedConflictID` (and therefore the open panel) alone. See point 4
  above and `DEVIATIONS.md` for the full argument.
- **Not a gap, just noted:** interactions.md §10.1 says the conflict panel is
  "a focus region reached from ... `⌘⇧A` ..., or by `⇥` into the inspector",
  which could be read as `⌘⇧A`/the needs-attention row also moving real
  keyboard focus into the inspector. `activateNeedsAttention()` (P2-T15,
  unchanged here) does not do that, and cannot from `CalendarState` alone
  (real focus lives in `MainWindow`'s own `@FocusState`). Left as-is: today,
  ↑/↓ preview navigation needs an explicit `⇥` (or click) into the inspector
  first, even right after `⌘⇧A`. See `DEVIATIONS.md`.

**New test coverage:** `KadenceTests/ConflictPreviewTests.swift` (new file),
same in-memory `ModelContainer`/`ModelContext` pattern as
`ConflictEngineTests.swift`/`ConflictEntryPointTests.swift`:
- `ConflictPreviewFramesTests` — `.shiftLater` and `.shorten` each produce
  the correct `proposed` interval against the spec's own worked numbers
  (reusing `ConflictEngineTests.swift`'s fixture shapes), `ghost` always
  equals the routine event's real span; `.skipToday` produces `proposed ==
  nil` while `ghost` still resolves (the documented treatment, not silent
  omission); and a dedicated test proves the "never exposes the committed
  frame as an intermediate value" property at the pure-function layer — the
  `ghost` returned is identical across every option of the same conflict
  (the one invariant), so there is no computed state anywhere in the mapping
  that could read as "reverted to committed" in between two `proposed`
  values.
- `MoveSelectedConflictOptionTests` — both directions land on the first
  option when nothing was focused; `↓` steps forward through
  `conflict.options` in array order; `↑` steps backward and clamps at the
  first option rather than wrapping; `↓` clamps at the last option; a no-op
  when there is no selected conflict.
- `AbandonConflictPreviewTests` — clears `selectedConflictOptionID` but
  leaves `selectedConflictID` exactly as found (pinning the scope decision
  above); a no-op-shaped call when nothing was focused disturbs nothing.
- `KadenceTests/BlockStyleResolverTests.swift` gained two cases:
  `.previewed` draws the dashed accent outline at `size.borderSelected`, and
  it wins over `.conflicted`'s alert border when both are present (§6:
  "applied last").

**Verified:**
- `xcodebuild -scheme Kadence -destination 'platform=macOS' build` —
  `** BUILD SUCCEEDED **`.
- `xcodebuild -scheme Kadence -destination 'platform=macOS'
  -only-testing:KadenceTests test` — `** TEST SUCCEEDED **`, 277 passed, 0
  failed (up from 263 at the end of P2-T15; 14 new tests, none removed).
- `swift Scripts/generate-tokens.swift --check` — `Kadence/DesignSystem/
  Tokens.swift is up to date.` — no new tokens invented; every token this
  task used (`opacity.blockPreviewed`, `opacity.blockDragOrigin`,
  `size.previewCanvasBorder`, `size.borderSelected`, `color.interactive.accent`,
  `motion.blockMove`) already existed from the Phase 2 token pass.
- `Scripts/check-accessibility.sh` — `PASS (elements present)`, 20
  block-shaped elements in the tree (unchanged from P2-T15's own run); the
  `0` carrying the §11 label is the pre-existing, already-open A20b defect,
  untouched by this task.
- Confirmed by inspection: `↩` is bound to nothing in `ConflictPanelView` or
  `MainWindow.handleKey`'s conflict-related cases; no code path this task
  added touches `EventStore` or `UndoStack`.

**Explicitly not built here, and not to be rediscovered by the next task:**
`↩` apply (writing a chosen option to the store as one named undo step —
interactions.md §10.1's last paragraph, components.md §14.5's "resolved and
empty" state also depends on it), the `TimeWindow` editor, `MenuBarExtra`,
snooze. None of the four is blocked by anything found in this task.

**Blocked:** nothing.

*(Corrected 2026-09-18 by task P2-T17 — the "explicitly not built" line above
is now STALE for its `↩` apply clause. See §18.)*

## 18. P2-T17 — conflict panel `↩` apply: single named undo step, advance/resolve (2026-09-18)

The piece §17 (P2-T16) explicitly left out: interactions.md §10.1's last
paragraph ("`↩` applies...") and components.md §14.5 ("Resolved and empty").
Preview-on-focus and abandonment are unchanged and already verified (§17); this
task is the apply verb and everything downstream of pressing it.

**What changed:**

1. `Kadence/State/EventStore.swift` — new `markSkipped(_:)`. Sets `status` to
   `.skipped` directly (idempotent no-op, no undo step pushed, if already
   `.skipped`), deliberately **not** `toggleSkipped` reused: `toggleSkipped`
   flips `.skipped`/`.scheduled`, and re-applying a `.skipToday` resolution
   must still land on `.skipped`, never silently un-skip it. This is the
   `.skipToday` conflict option's apply target — interactions.md §10.1's
   general apply path is "write the previewed option's proposed frame(s) to
   the committed store"; for an option with no destination frame
   (`ConflictOption.newStart`/`newEnd == nil`) that write is this status
   change, per the task brief's own item 5 and consistent with G-014's
   existing treatment of the same option kind.
2. `Kadence/State/ConflictEngine.swift` — `detect` gained one `guard
   pair.routine.status != .skipped else { continue }` in the pairing loop. A
   `.skipToday` apply never changes the routine event's `start`/`end` (by
   design, G-014), so without this, `detect`'s own next pass would report the
   *identical* conflict again immediately after "resolving" it, and
   §10.1/§14.5's "advances to the next unresolved conflict, or returns to
   normal" could never actually happen for that option kind. Filed as
   `design/GAPS.md` **G-015** rather than built silently — neither this
   file's pre-existing header comment nor components.md §14 says whether
   status gates detection at all; this is a narrow, documented answer, not an
   invented value. File header comment corrected to match (it previously said
   "applying" was entirely a future task's problem; it now names where that
   task landed, per this file's own established amendment convention).
3. `Kadence/State/CalendarState.swift` — new
   `applyFocusedConflictOption(store:recomputeConflicts:) -> Bool`:
   - Resolves the focused conflict/option from `selectedConflictID`/
     `selectedConflictOptionID` against `conflicts`; a no-op (`false`, no
     mutation) if either is missing, matching this task's own read of "an
     option the user cannot see the consequence of is an option they cannot
     rank" — `↩` with the panel open but nothing previewed applies nothing.
   - Writes the option inside one `store.transaction("Resolve Conflict")`:
     `.shiftLater` → `store.move(routineEvent, toStart:)` (both endpoints
     move by the same delta — `move`, not `resize`, which would clamp the
     new start against the event's still-unmoved *other* endpoint and get it
     wrong); `.shorten` → `store.resize(routineEvent, newStart:newEnd:)`
     (exactly one endpoint changes, which is exactly what `resize`'s own
     clamp logic expects); `.skipToday` → `store.markSkipped(routineEvent)`.
     `UndoStack.perform`'s re-entrancy (its own doc comment's worked example)
     is what makes the inner `move`/`resize`/`markSkipped` calls join the
     outer group instead of pushing steps of their own, so the Edit menu
     reads exactly "Undo Resolve Conflict" (interactions.md §10.1's own
     words) and one ⌘Z reverts every block the option touched.
   - Clears `selectedConflictOptionID` immediately — no new code needed to
     drop the canvas's `size.previewCanvasBorder` border beyond this
     assignment, since `MainWindow.isConflictPreviewActive` and
     `DayColumnView.activeConflictPreview` were already gated on it being
     non-nil by P2-T16. Likewise, `motion.blockMove` runs on the committed
     frame with no new animation code: `DayColumnView.blockStack` already
     keys `.animation(..., value: laidOut.frame)` on that spring
     unconditionally (P2-T11), so a `start`/`end` written by `store` animates
     into place the same way a drag or resize already does.
   - Calls the caller-supplied `recomputeConflicts` closure (re-running
     `ConflictEngine.detect` against the just-mutated data — `CalendarState`
     holds no query of its own to do this itself), assigns the result to
     `conflicts`, and either previews `ConflictOrdering.firstUnresolved`'s
     first (== recommended, `ConflictEngine.finalize` already sorts ascending
     by disturbance) option, or, if nothing is left, sets
     `selectedConflictID = nil` — which is what takes the inspector out of
     conflict mode (`MainWindow.activeConflict`'s existing guard) and what
     the needs-attention row's own count (`state.conflicts`) reads to hide at
     zero. Nothing new was built for components.md §14.5's "no 'all clear'
     state" — there simply is no dedicated empty-state view to have built.
4. `Kadence/Views/MainWindow.swift`:
   - `handleKey` gained one case ahead of the pre-existing `.return` ladder:
     `.return where state.focusedRegion == .inspector &&
     state.selectedConflictID != nil && state.selectedConflictOptionID !=
     nil`, calling a new private `applyFocusedConflictOption()` — placed
     first for the same reason the ↑/↓ preview-navigation cases already are:
     a focused conflict panel always wins. `↩` with the panel open but
     nothing focused yet falls through to the plain `.return` case below
     (which does nothing when nothing is selected) — correct, since there is
     nothing to apply.
   - `applyFocusedConflictOption()` (new private method) calls
     `state.applyFocusedConflictOption(store:recomputeConflicts:)`, supplying
     `Self.sortedConflicts(events: events, routineBlocks: routineBlocks)` as
     the recompute closure. Safe to read `events`/`routineBlocks`
     synchronously right after the transaction returns, with no need to wait
     for SwiftUI's own `@Query` refresh cycle: `EventStore.edit`'s fetch
     resolves to the exact same `@Model` instances already sitting in
     `events` (one identity map per `ModelContext`), so their
     `start`/`end`/`status` already carry the new values by the time the
     closure runs.
   - Doc comments in the "MARK: Conflicts" block and `ConflictPanelView.swift`'s
     header corrected in place — both previously said `↩` apply was
     out of scope; both now say where it landed, per this file's and that
     file's own established correction convention.

**Judgement calls, documented rather than guessed past** (all recorded in
`DEVIATIONS.md`; one also filed as `design/GAPS.md` G-015):
- **The `ConflictEngine.detect` `.skipped` filter** — see point 2 above and
  G-015's full argument. The one place a future spec ruling could disagree
  and need code to change.
- **`EventStore.markSkipped` vs. reusing `toggleSkipped`** — see point 1
  above; not filed as a gap since nothing in `design/` is silent about
  it — this is ordinary engineering judgement about which existing verb an
  idempotent write should be, not a UI value.
- **Next-conflict auto-preview, not next-conflict-selected-but-unfocused** —
  interactions.md §10.1 says apply "advances to the next unresolved
  conflict"; components.md §14.1 already establishes that "activating" a
  conflict (there, via the needs-attention row) selects it with no option
  pre-highlighted (`activateNeedsAttention()`, P2-T15, unchanged). This task
  reads "advances to the next... and preview its first/recommended option"
  (the task brief's own item 4) as calling for the *option* to be
  pre-highlighted too when advancing via apply specifically — different from
  `activateNeedsAttention()` on purpose, since §10.1's very next sentence
  after "moving focus onto an option previews it immediately" is the reason
  an option a user "cannot see the consequence of is an option they cannot
  rank", and advancing to a conflict with nothing to compare defeats that for
  exactly the same reason a fresh `⌘⇧A` does not (there, no *conflict* is
  auto-something yet — the row's first press is discovery, not a
  continuation of a decision already in progress). Not filed as a gap: the
  task's own brief states this explicitly ("preview its first/recommended
  option"), so this is instruction, not silence.

**New test coverage:** `KadenceTests/ConflictApplyTests.swift` (new file), same
in-memory `ModelContainer`/`ModelContext` pattern as
`ConflictPreviewTests.swift`/`ConflictEntryPointTests.swift`:
- `ApplyShiftAndShortenTests` — `.shiftLater` commits the exact
  `newStart`/`newEnd` the option proposed (reusing the same fixture numbers
  `ConflictPreviewFramesTests.shiftLaterProducesProposedFrame` already pinned,
  9:00–10:00 → 10:15–11:15) and `.shorten` commits the exact trimmed span
  (reusing `shortenProducesProposedFrame`'s fixture, 9:00–11:00 → 9:00–10:45);
  each as exactly one `undo.undoSteps` entry named `"Resolve Conflict"`
  (`undoMenuTitle == "Undo Resolve Conflict"`), and one `undo.undo()` fully
  reverts to the original `start`/`end` with `canUndo` false afterward — not
  a partial revert.
- `ApplyAdvanceTests` — two independent conflicts: applying the first's
  focused option leaves `state.selectedConflictID` pointing at the second
  (looked up in the POST-apply `state.conflicts`, since `ConflictOption.id`
  is a fresh `UUID()` per `detect` pass — the pre-apply snapshot's option ids
  are not the ones the refreshed list carries) with its first option
  pre-selected, and `state.conflicts.count == 1` (the resolved one dropped
  out); one conflict: applying its only option sets `selectedConflictID`/
  `selectedConflictOptionID` both `nil` and `state.conflicts.isEmpty`
  (§14.5's "resolved and empty", and what the needs-attention row's count
  reads to hide at zero); a no-op case (no option focused) confirms no store
  mutation, no undo step, and `selectedConflictID` untouched.
- `ApplySkipTodayTests` — `.skipToday` sets `status == .skipped`, leaves
  `start`/`end` untouched, as one reversible named undo step; and — pinning
  G-015's fix specifically — applying it against a conflict's only option
  actually empties `state.conflicts` and returns `selectedConflictID` to
  `nil`, proving the new `ConflictEngine.detect` filter is what makes
  "advances... or resolves to normal" true for this option kind.
- `ConflictEngineSkippedFilterTests` — pins the `ConflictEngine.detect` fix
  directly: a routine event built with `status: .skipped` and a manual event
  whose intervals still literally overlap produces zero conflicts.

**Verified:**
- `xcodebuild -scheme Kadence -destination 'platform=macOS' build` —
  `** BUILD SUCCEEDED **`.
- `xcodebuild -scheme Kadence -destination 'platform=macOS'
  -only-testing:KadenceTests test` — `** TEST SUCCEEDED **`, 285 passed test
  runs / 0 failed per `xcresulttool`'s summary (up from 277 at the end of
  P2-T16). One test needed a fix after its first run — the "advance to next
  conflict" case initially compared against the pre-apply snapshot's
  `ConflictOption.id`, which does not survive a fresh `detect` pass; corrected
  to look the next conflict back up in the post-apply `state.conflicts` — see
  `ApplyAdvanceTests` above.
- `swift Scripts/generate-tokens.swift --check` — `Kadence/DesignSystem/
  Tokens.swift is up to date.` — no new tokens invented; this task added no
  new UI (`"Resolve Conflict"` is a string, not a token, and is the exact
  name `UndoStack.swift`'s and `EventStore.transaction`'s own pre-existing
  worked examples already use).
- `Scripts/check-accessibility.sh` — `PASS (elements present)`, 20
  block-shaped elements in the tree (unchanged from P2-T16's own run); the
  `0` carrying the §11 label is the pre-existing, already-open A20b defect,
  untouched by this task. The screen was unlocked for this run (real block
  content printed, not the lock-probe's empty-tree signature), so this is a
  real `PASS`, not the documented environmental exemption.
- `design/GAPS.md` §5.2 summary in this file was stale (missing G-013/G-014)
  before this task touched it; corrected in place rather than left — see the
  note above §5.2's open-gap count.

**Explicitly not built here:** the `TimeWindow` editor, `MenuBarExtra`,
snooze. None of the three is blocked by anything found in this task. This
closes out every item interactions.md §10 / components.md §14 name for
conflict resolution itself (protected-window conflicts still need the
`TimeWindow` model, which is a separate, larger piece of Phase 2 scope, not a
gap in what §10/§14 describe).

**Blocked:** nothing.

## 19. P2-T18 — `TimeWindow` SwiftData model (data layer only, 2026-09-18)

The piece §18's own note called out as separate, larger scope: the persisted
`TimeWindow` data model that layouts.md §8.1 and components.md §13.3 both
presuppose ("a selected time window: kind (protected / low-energy /
peak-focus), weekdays, start, end, label"). Until now the only thing
describing a window was `TimeWindowFixture` (`DisplayFixtures.swift`),
explicitly display-only per its own doc comment, and `RoutineEngine.swift`/
`ConflictEngine.swift` both carried header comments deferring
protected-window logic "pending this model existing." This task adds the
model and its seed data only — no editor UI, no rendering swap, no
scheduling or conflict change.

**What changed:**

1. `Kadence/Models/TimeWindow.swift` (new file) — `@Model final class
   TimeWindow`, following `RoutineTemplate.swift`'s exact conventions (P2-T08's
   own precedent for this kind of task): stable `var id: UUID = UUID()`,
   `var weekdays: Set<Int> = []` (`Calendar`'s 1=Sunday...7=Saturday
   convention, matching `RoutineTemplate.activeWeekdays` and
   `TimeWindowFixture.weekdays`), `var startMinutes: Int = 0` / `var
   endMinutes: Int = 0` (minutes from midnight, end may be less than start
   meaning the window wraps past midnight — the same meaning
   `TimeWindowFixture`'s fields already carry), a `kind: TimeWindowKind`
   computed over a private raw-string-backed `kindRaw`, same pattern as
   `RoutineBlock.flexibility`, and `var label: String = ""`. Memberwise
   `init`. `TimeWindowFixture.spans(on:)` is deliberately not ported onto
   this model — nothing reads a persisted `TimeWindow` yet, so that logic
   belongs to whichever future task actually renders or schedules against
   one, exactly as the task brief specified.
2. `Kadence/KadenceApp.swift` — `TimeWindow.self` registered at all three
   `ModelContainer` construction sites (primary, in-memory fallback,
   `ModelContainer.emptyFallback()`), alongside the existing `Event.self,
   Place.self, RoutineTemplate.self, RoutineBlock.self` list. Doc comment
   above `let container: ModelContainer` extended to name this addition, the
   same way it already named the P2-T08 RoutineTemplate/RoutineBlock one.
3. `Kadence/Mock/MockData.swift` — `seedTimeWindowsIfNeeded(_:)` and
   `makeTimeWindows() -> [TimeWindow]`, mirroring
   `seedRoutineTemplatesIfNeeded`/`makeRoutineTemplates` exactly (fetch
   existing, insert only if empty, idempotent on a second call). Seeded with
   the same two windows already described by `MockData.timeWindows:
   [TimeWindowFixture]` — Sleep (weekdays 1...7, 22:00–07:00, `.protected`)
   and Low energy (weekdays [2,3,4,5,6], 13:00–14:30, `.lowEnergy`) — so both
   representations describe the same data, even though nothing yet reads the
   persisted one.
4. `Kadence/Views/Routines/RoutinesWindow.swift` — one new line in the
   existing `.task` block, right after `MockData.seedRoutineTemplatesIfNeeded
   (context)`: `MockData.seedTimeWindowsIfNeeded(context)`. This is the only
   existing seed-on-launch hook in the app (`seedRoutineTemplatesIfNeeded`
   has no other call site — confirmed via `Grep` before assuming it), so the
   new seeding runs from the same place, guarded by the same `didSeed` flag.

**Explicitly out of scope, confirmed untouched:** `GridLayers.swift`,
`Views/Day/DayColumnView.swift`, `State/RoutineEngine.swift`,
`State/ConflictEngine.swift` — no diff against any of the four (`git diff
--stat` on all four returned empty). The Routines window's toolbar "Windows"
mode toggle stays exactly as unbuilt as before; `TimeWindowFixture` still
renders everywhere it already did.

**New test coverage:** `KadenceTests/TimeWindowTests.swift` (new file), same
in-memory `ModelContainer`/`ModelContext` pattern as
`RoutineEngineTests.swift`'s `makeStore()`:
- `TimeWindowModelTests` — `init` sets every field correctly; `kind`
  round-trips for every `TimeWindowKind` case (same computed-property shape
  as `RoutineBlock.flexibility`); a real insert/fetch round-trip through an
  in-memory `ModelContainer`/`ModelContext` confirms every field survives
  persistence unchanged.
- `TimeWindowSeedingTests` — `makeTimeWindows()` describes the same two
  windows (by label, weekdays, start/end minutes, kind) as the existing
  `MockData.timeWindows` fixture array; `seedTimeWindowsIfNeeded` called
  twice against the same context still leaves exactly 2 rows.

**Verified:**
- `xcodebuild -scheme Kadence -destination 'platform=macOS' build` —
  `** BUILD SUCCEEDED **`.
- `xcodebuild -scheme Kadence -destination 'platform=macOS'
  -only-testing:KadenceTests test` — `** TEST SUCCEEDED **`; all 7 new
  `TimeWindowTests.swift` test cases passed alongside the full pre-existing
  suite, none regressed.
- `swift Scripts/generate-tokens.swift --check` — `Kadence/DesignSystem/
  Tokens.swift is up to date.` — no new tokens invented; this task added no
  UI.
- `Scripts/check-accessibility.sh` — `PASS (elements present)`, 20
  block-shaped elements in the tree (unchanged from P2-T17's own run); the
  `0` carrying the §11 label is the pre-existing, already-open A20b defect,
  untouched by this task. Screen was unlocked for this run.

**Explicitly not built here:** any `TimeWindow` editor UI (the Routines
window's "Windows" mode toggle); replacing `TimeWindowFixture` anywhere it
currently renders; `RoutineEngine.materialize` honouring protected/low-energy
windows; `ConflictEngine` detecting protected-window conflicts. All four are
separate future tasks, exactly as the brief specified — none blocked by
anything found here.

**Blocked:** nothing.

## 20. P2-T19 — ConflictEngine: detect routine placements landing in a
protected `TimeWindow` (data layer only, 2026-09-19)

The piece §19 itself named as still not built: BRIEF-PRODUCT.md Phase 2's
other conflict clause — "any automatic placement that would land in a
protected window" — now buildable since a persisted `TimeWindow` (task
P2-T18) exists. `ConflictEngine.swift`'s own header comment said explicitly
"no TimeWindow model exists yet"; this task removes that gap. Data layer
only — no editor UI, no panel wiring, no change to what `RoutineEngine
.materialize` actually creates.

**What changed:**

1. `Kadence/Models/TimeWindow.swift` — added `spans(on:calendar:) ->
   [(start: Date, end: Date)]`, ported from `TimeWindowFixture.spans(on:)`
   (`DisplayFixtures.swift` ~line 78) with identical semantics: same-day
   windows yield one span if `weekdays` is active that day; windows where
   `endMinutes <= startMinutes` wrap midnight and split into an evening span
   (today, if active) and a morning span (attributed to *yesterday's*
   weekday, per the fixture's own convention), each independently gated by
   `weekdays`.
2. `Kadence/State/ConflictEngine.swift`:
   - Generalized `shiftLaterOption`/`shortenOption` to take a private plain
     `Interval` (start/end) struct instead of a full `Event`. Existing
     `detect` call sites now build `Interval(start: pair.other.start, end:
     pair.other.end)` and pass that — behavior is unchanged, since those two
     functions previously only ever read `.start`/`.end` off the `Event` they
     were given; nothing about `ConflictEngineTests.swift`'s pre-existing
     cases moved.
   - Added `detectWindowConflicts(events:routineBlocks:timeWindows:
     calendar:)`, a new pure static function: for every non-`.skipped`
     `.routine`-origin event, for every `.protected`-kind `TimeWindow`, for
     every span that window has on the event's own `start` date (via step 1),
     if the event's interval strictly overlaps that span, build a
     `WindowConflict` using the exact same `makeOptions`/`finalize` pipeline
     `detect` uses — same option kinds (shiftLater/shorten/skipToday), same
     disturbance-minutes scale, same ascending-order/exactly-one-recommended
     ranking. `.lowEnergy` and `.peakFocus` windows are filtered out up front
     (`timeWindows.filter { $0.kind == .protected }`) — the brief names only
     protected windows for this clause.
   - Added `WindowConflict`, a sibling `Identifiable` struct to `Conflict`
     (not a variant of it) — see its own doc comment and `detectWindow
     Conflicts`'s doc comment for the reasoning: `Conflict.otherEvent` is a
     live `Event` a future task calls `EventStore.move`/`resize`/`skip` on; a
     `TimeWindow` supports none of those, so folding the two into one type
     would mean weakening `otherEvent`'s non-optional guarantee for every
     existing call site, or inventing a lossy stand-in `Event` for a window —
     neither is warranted. Same field shape as `Conflict` otherwise
     (`routineEvent`, `window` in place of `otherEvent`, `overlapStart`/
     `overlapEnd`, `options`), same deterministic `id` construction
     convention (`"<event>#<window>#<span start>"`).
   - Extended the file's own header comment to record task P2-T19's scope and
     the deliberate forward-reference it leaves: how (or whether)
     `WindowConflict` surfaces next to `Conflict` in `ConflictPanelView` —
     e.g. what the collision header shows when the "other side" is a window,
     not a block (components.md §14.2) — is left for whichever follow-up task
     wires it in. Nothing in this task's own scope needed that question
     answered, so no new `design/GAPS.md` entry was filed for it (unlike
     `detect`'s own G-015, which did need an answer to keep working).

**Explicitly out of scope, confirmed untouched:** `ConflictPanelView.swift`,
the needs-attention row/count, `CalendarState.applyFocusedConflictOption`,
`EventStore.swift`, any `TimeWindow` editor UI, `RoutineEngine.materialize`'s
creation logic (still creates occurrences at their configured time
unconditionally — this task only adds detection on top, per the brief's own
item 4).

**New test coverage:** `KadenceTests/ConflictEngineTests.swift` (extended,
existing suites untouched) — three new `@Suite`s appended at the bottom of
the file:
- `TimeWindowSpansTests` — mirrors `DensityAndGeometryTests.swift`'s existing
  `TimeWindowFixture` wrap test: the seeded 22:00–07:00 protected Sleep
  window yields two spans on a day (minutes `[0, 1320]` from that day's
  midnight); a same-day window (13:00–14:30 low energy, active on a Friday)
  yields exactly one span; a window inactive on the given weekday yields
  none.
- `ConflictWindowDetectionTests` — a routine event fully inside the seeded
  protected Sleep window (22:30–23:30) produces exactly one `WindowConflict`
  with `window.kind == .protected`, correct `overlapStart`/`overlapEnd`,
  options non-empty, exactly one `isRecommended`, ascending disturbance
  order, and a `skipToday` option present; a routine event inside only the
  seeded lowEnergy window (13:00–14:00 Friday) produces no conflict; a
  `.skipped` routine event inside the protected window produces no conflict
  (same G-015 reasoning as `detect`); a `.manual` (non-routine) event inside
  the protected window produces no conflict (the clause only names automatic
  placements).
- One pre-existing test in this file needed a one-line fix unrelated to this
  task's logic: an `Event(...)` call in the new `.skipped`-routine test case
  had `status:` after `externalID:`, which does not match `Event.init`'s
  actual parameter order (`status` precedes `flexibility`) and failed to
  compile; reordered the call site's arguments, no behavior change.

**Verified:**
- `xcodebuild -scheme Kadence -destination 'platform=macOS' build` —
  `** BUILD SUCCEEDED **`.
- `xcodebuild -scheme Kadence -destination 'platform=macOS'
  -only-testing:KadenceTests test` — `** TEST SUCCEEDED **`; 299 test cases
  passed, 0 failed (per `xcrun xcresulttool get test-results summary`),
  including all new `TimeWindowSpansTests`/`ConflictWindowDetectionTests`
  cases; every pre-existing suite named in the task's acceptance list
  (`ConflictEngineTests`, `ConflictApplyTests`, `ConflictEntryPointTests`,
  `ConflictPresentationWiringTests`, `ConflictPreviewTests`,
  `RoutineEngineTests`, `TimeWindowTests`) passed unmodified.
- `swift Scripts/generate-tokens.swift --check` — `Kadence/DesignSystem/
  Tokens.swift is up to date.` — no UI touched, no new tokens.
- `Scripts/check-accessibility.sh` — `PASS (elements present)`, 20
  block-shaped elements in the tree, identical count to P2-T18's last passing
  run; the `0` carrying the §11 label is the pre-existing, already-open A20b
  defect, untouched by this task. Screen confirmed unlocked for this run
  (frontmost-app query via `osascript` succeeded).

**Explicitly not built here:** any UI surfacing of `WindowConflict`
(`ConflictPanelView`, needs-attention row/count); `RoutineEngine.materialize`
avoiding protected windows at creation time; a `design/GAPS.md` entry (none
was needed — see the header-comment note above).

**Blocked:** nothing.

## 21. P2-T20 — Routines window `[Blocks | Windows]` mode control + generalized
background windows layer (close-out re-verification, 2026-09-24)

Task P2-T20 itself was hard-killed mid-flight by Parsa; its work landed on
`HEAD` (commit `54c6031`, `wip: stopped by Parsa mid-task`) by hand, without
ever running its own build, its own tests, or writing this entry.
`DEVIATIONS.md`'s P2-T20 paragraph (search "task P2-T20" in the peak-focus
"Not a deviation" section) was already written and, on inspection, is still
accurate against what's actually in the tree — nothing there needed
correcting. This entry's job is solely to re-verify that hand-committed work
fresh and record the result, since §20 above still ended at P2-T19.

**What P2-T19's stopped task actually built (confirmed by reading, not just
trusting the commit message):**

- `RoutinesEditorMode` (`Kadence/Views/Routines/RoutinesWindow.swift`) —
  `.blocks`/`.windows`, components.md §13.3's mode control. A segmented
  control in the toolbar (`size.editorModeBarHeight`, `editorModeLabel`
  type, `.pickerStyle(.segmented)` — the same native shape `MainWindow`'s
  own Month/Week/Day control uses) plus `⌘[`/`⌘]`, window-scoped rather than
  routed through `KadenceCommands` (interactions.md §11.1), both paths
  clearing `selection` via one shared `onChange(of: editorMode)`.
- `TimeWindowRenderable` (`Kadence/Layout/WindowSpanResolver.swift`) — the
  protocol `TimeWindowFixture` and the persisted `TimeWindow` both conform
  to, letting `BackgroundWindowsLayer`/`WindowLabelsLayer`
  (`Kadence/Views/Canvas/GridLayers.swift`) draw either through the same
  generic view. Every existing main-grid call site (`DayColumnView`,
  `TimedCanvasView`) is unchanged — still `TimeWindowFixture`, still
  `showsPeakFocus` defaulted `false`, so Phase 1's rendering is untouched.
- `WindowSpanResolver` itself — pulled out of what was a private method on
  `BackgroundWindowsLayer` into a pure, SwiftUI-free enum (`spans(for:in:
  on:calendar:showsPeakFocus:)` / `labels(in:on:calendar:showsPeakFocus:)`),
  same shape as `DayLayoutEngine`/`resolveBlockStyle`, so it can be
  unit-tested without going through a view. Implements components.md §7's
  "protected wins over low energy" subtraction and the "Editor exception"
  peak-focus gate.
- `RoutinesCanvasView`/`RoutineDayColumnView` now render all three
  `TimeWindow` kinds through the generalized layers, seeded via
  `MockData.seedTimeWindowsIfNeeded`/`makeTimeWindows()`: in `.blocks` mode
  only protected/low-energy draw, non-hit-testable, matching the main grid's
  own Phase 1 treatment and components.md §13.3's table; in `.windows` mode
  peak-focus also draws (1pt dashed outline, dash `[4, 4]`,
  `color.window.peakFocusEdge`, no fill — §7's "Editor exception"
  paragraph, verbatim) and the block/draft layer drops to
  `opacity.editorInactiveLayer` with `.allowsHitTesting(false)`, applied to
  the whole block/draft/overflow `Group` together so the dimming reads as
  one layer.
- Test coverage: `KadenceTests/DensityAndGeometryTests.swift` gained a new
  `WindowSpanResolverTests` suite (`protectedWinsOverLowEnergy`,
  `peakFocusGatedByDefault`, `peakFocusThroughPersistedModel`,
  `labelsMirrorSpanGating`) exercising the resolver directly, and
  `KadenceTests/TimeWindowTests.swift`'s seeding test was updated for the
  new `makeTimeWindows()` fixture (protected Sleep, low-energy, and now a
  third peak-focus "Deep work" window, Tue–Sat 15:00–17:00).

Confirmed still absent, as the task's own header comment and `DEVIATIONS.md`
both already say: dragging/resizing/creating/deleting a `TimeWindow`; the
inspector's kind picker for a selected window; the flexibility control's
interactive stepper; detached-instance tracking/Re-sync. None of these were
touched in this close-out pass — this pass only re-verified and documented,
per the task's own instruction not to add any new feature.

**Verified fresh, this session (nothing carried over from the interrupted
run):**

- `xcodebuild -scheme Kadence -destination 'platform=macOS' build` —
  `** BUILD SUCCEEDED **`.
- `xcodebuild -scheme Kadence -destination 'platform=macOS'
  -only-testing:KadenceTests test` — `** TEST SUCCEEDED **`; 303 test cases
  passed, 0 failed (per `xcrun xcresulttool get test-results summary`),
  including `WindowSpanResolverTests`'s four new cases and
  `TimeWindowTests`'s updated seeding case; no regressions in any
  pre-existing suite.
- `swift Scripts/generate-tokens.swift --check` — `Kadence/DesignSystem/
  Tokens.swift is up to date.` — no new tokens needed; `editorModeLabel`
  (`TypeStyle.swift`) and `size.editorModeBarHeight`/
  `opacity.editorInactiveLayer` (`Tokens.swift`) already existed going into
  this task.
- `Scripts/check-accessibility.sh` — first run came back `FAIL: … found 0`
  (both the block count and the label count), which is neither the
  documented A20b shape (elements present, labels missing) nor a locked
  screen (`CGSSessionScreenIsLocked` read `0`; `osascript` reached the app's
  window directly). Traced it by hand: `default.store`
  (`~/Library/Containers/XIX.Kadence/Data/Library/Application Support/`) was
  last written 2026-09-17/19 by earlier task sessions, and
  `MockData.seedIfNeeded` only seeds `Event`s "if the store is empty" — it
  never re-seeds a non-empty store. With today's real date six days past
  that, the persisted timed events had aged out of the Week view's visible
  range entirely (the two chips that *did* still show, a deadline and an
  exam badge, come from `makeAllDay`/`makeTravel`, which recompute fresh
  from `now` on every launch rather than being persisted). This is a stale
  local fixture-store artifact of running many independent sessions on
  different real-world days, not a code defect in anything this task (or
  any other) built — nothing in `Kadence/**` was touched to reach this
  diagnosis. Deleted the stale `default.store`/`-wal`/`-shm` files (outside
  the repo, under the app's container; no tracked file touched) so the next
  launch reseeded relative to today's actual date, then re-ran: `PASS
  (elements present)`, 20 block-shaped elements, identical count to every
  prior passing run, `0` carrying the §11 label — the pre-existing,
  already-open A20b defect, unrelated to this task. Screen confirmed
  unlocked throughout (this machine's own known failure mode, per the
  script's own header comment, is a session-wide lock, not a per-app stale
  store — recorded here since the check surfaced this exact category of
  environmental noise for the first time as a *store* issue rather than a
  *lock* or *wedged-process* one).

**Blocked:** nothing. Next up, per this task's own scope note and
`DEVIATIONS.md`'s P2-T20 paragraph: `TimeWindow` drag/resize/create/delete
and the inspector's kind picker, `RoutineEngine.materialize` honouring
protected windows, `MenuBarExtra`, snooze — all explicitly out of scope for
both the original P2-T20 pass and this close-out.

## 22. P2-T21 — TimeWindow editor: select, move (drag), delete existing windows in Windows mode (2026-09-24)

components.md §13.3 calls protected/low-energy/peak-focus `TimeWindow`s
"editable" in the Routines window's Windows mode — creating, dragging,
resizing. P2-T20 (§21) built only the render-only layer: windows drew, but
were not selectable or draggable in either mode. This task adds the first
slice of the editable half, for an **existing** `TimeWindow` row only: select,
whole-span move-by-drag, and `⌫` delete. Explicitly, and deliberately, still
absent: drag-to-create a new `TimeWindow`, resize handles (top/bottom edge),
the inspector's kind picker, weekday-set editing, `RoutineEngine.materialize`
honouring windows, `MenuBarExtra`, snooze — next task's job (or later), per
this task's own brief.

**What was built:**

- `Kadence/State/TimeWindowStore.swift` (new file) — `RoutineBlockStore`'s
  sibling for `TimeWindow`: a `@MainActor struct` holding `context:
  ModelContext` and `undo: UndoStack`, resolving everything by `id` through
  the context (never a captured `@Model` reference), one named `UndoStack`
  step per mutation, same shape `RoutineEngine.swift`'s own `RoutineBlockStore`
  already established (tasks P2-T11/T12).
  - `move(_:byDeltaMinutes:)` — unlike `RoutineBlockStore.move` (clamped to a
    single day, per G-013, because `RoutineBlock` cannot wrap), a `TimeWindow`
    already supports spanning midnight (its own doc comment,
    `spans(on:calendar:)`), so this is a pure modular translation:
    `startMinutes`/`endMinutes` each wrap independently
    (`((x + delta) % 1440 + 1440) % 1440`), no clamping, duration preserved
    implicitly because both ends move by the same delta. Named undo step
    `"Move Time Window"`. A zero delta is a no-op and pushes no step.
  - `delete(_:)` — simpler than `RoutineBlockStore.delete`: a `TimeWindow` has
    no parent array membership to maintain, so this just inserts/deletes the
    row itself. Every field (id, weekdays, startMinutes, endMinutes, kind,
    label) is snapshotted (`TimeWindowRestoreSnapshot`) so `"Delete Time
    Window"`'s undo reconstructs the row exactly, including a non-default
    `kind` (tested with `.lowEnergy`, not just `.protected`'s default).
  - `resize`/`create` deliberately not added — next task's job.
- `Kadence/Views/Routines/RoutinesWindow.swift`:
  - New `@State private var windowSelection: UUID?` on `RoutinesWindow`,
    threaded down through `RoutinesCanvasView` into `RoutineDayColumnView`
    alongside a new `timeWindowStore: TimeWindowStore` (same one-`UndoStack`
    wiring `store` already has, so `⌘Z` for a window move/delete names
    correctly regardless of which window is key).
  - `RoutineDayColumnView.windowInteractionLayer(geometry:)` — one
    hit-testable region per `(window, span)` (a wrapping window can produce
    two spans on one day, each gets its own region), drawn above the existing
    background/block layers and gated
    `.allowsHitTesting(editorMode == .windows)` — the exact inverse of the
    existing `.allowsHitTesting(editorMode == .blocks)` pattern the
    block/draft layer already uses, so Blocks mode leaves windows exactly as
    non-interactive as before. Tapping a region sets `windowSelection`;
    tapping empty windows-mode canvas (a new full-height clear rectangle,
    drawn *below* the per-window regions so a tap landing inside an actual
    span still hits that window first) clears it — mirroring
    `createSurface`'s existing "clicking empty grid deselects" tap for blocks.
  - Selection ring: `Tokens.Color.Interactive.focusRing` /
    `Tokens.Size.borderSelected`, drawn outside the bounds with a 1pt gap,
    exactly the shape `GridBlockView.swift`'s `.selected` overlay already
    uses (§6's existing selection vocabulary, reused rather than reinvented —
    see the note below on the one judgement call this needed). Drawn with a
    plain `Rectangle`, not `RoundedRectangle`, matching every other window
    treatment already on this canvas (`BackgroundWindowsLayer`'s
    `protectedSpan`/`lowEnergySpan`/`peakFocusSpan` all draw plain rectangles,
    no corner radius).
  - `windowGesture(window:geometry:)` — `DragGesture(minimumDistance: 3)`,
    mirroring `blockGesture`'s snap shape but simpler: no resize-handle
    branch, every drag on a window's body is a whole-span move. The live pixel
    delta only moves the hit region/ring on screen during the drag (via a new
    `windowDrag: TimeWindowDragSession?` local state, `nil` until a drag
    starts); the actual minute delta is computed once at `.onEnded` — pixel
    delta → seconds → `TimeGeometry.snap` (15-minute, 5-minute with `⌃`,
    same as every other drag in this window) → minutes — and only then is
    `TimeWindowStore.move` called. Nothing is written to the store mid-drag.
  - `handleDelete()` now branches: if `windowSelection` is set, resolves the
    live `TimeWindow` from the `@Query` array and calls
    `TimeWindowStore.delete`; otherwise falls through to the pre-existing
    block-delete path, unchanged.
  - `onChange(of: selectedTemplateID)` and `onChange(of: editorMode)` both now
    clear `windowSelection` too (previously only `selection`), generalizing
    interactions.md §11.1's "the current selection is dropped on mode change"
    to the new selection kind, matching the same rule already applied to
    block selection.
- `KadenceTests/TimeWindowStoreTests.swift` (new file) — same in-memory
  `ModelContainer`/`ModelContext` pattern and undo/redo rigor as
  `RoutineWeekLayoutTests.swift`'s `RoutineBlockStore` suites. Ten cases:
  `TimeWindowStoreMoveTests` (plain within-day move and naming; forward wrap
  past 24:00; backward wrap past 00:00; moving an already-wrapping
  22:00–07:00 window and confirming the wrap and 9-hour duration survive;
  zero-delta no-op pushes nothing; undo/redo round-trip) and
  `TimeWindowStoreDeleteTests` (deletes immediately and names the step; undo
  restores every field including `kind`/`weekdays`; redo-after-undo deletes
  again; a non-default `.lowEnergy` kind survives the round trip too, not
  just `.protected`'s default).

**One judgement call, recorded per this task's own instruction (same
convention as prior P2 tasks' narrow calls — see `design/GAPS.md`'s existing
entries for the shape of this kind of note):** the selection ring reuses
§6's existing generic vocabulary (`Tokens.Color.Interactive.focusRing` /
`Tokens.Size.borderSelected`) applied to a new selectable object — this is
reuse, not an invented value, so no `design/GAPS.md` entry was filed. See
`DEVIATIONS.md`'s P2-T20 paragraph, appended by this task, for the full note.

**One additional narrow judgement call, not previously flagged:** the hit
region for each window is the *raw* `TimeWindow.spans(on:)` span, not the
protected-wins-over-low-energy-*subtracted* span `WindowSpanResolver`/
`BackgroundWindowsLayer` actually paint when two windows overlap. Selecting
and dragging the underlying model object (its full, real span) rather than
whatever fraction of it happens to still be visible under an overlapping
protected window reads as more correct for an editor, and avoids a second,
resolver-shaped hit-testing pass this task's brief did not ask for. Where two
windows' hit regions overlap, whichever is frontmost in `ForEach(timeWindows)`
order wins the tap — same "today's build keeps frontmost-wins behaviour, and
no value was invented" precedent DEVIATIONS.md's G-010/A24 already establish
for overlapping blocks, not a new gap.

**Verified:**

- `xcodebuild -scheme Kadence -destination 'platform=macOS' build` —
  `** BUILD SUCCEEDED **`.
- `xcodebuild -scheme Kadence -destination 'platform=macOS'
  -only-testing:KadenceTests test` — `** TEST SUCCEEDED **`; 313 test cases
  passed, 0 failed (per `xcrun xcresulttool get test-results summary`'s
  per-device count, which includes every parameterized run — the same
  convention §21 used), including all ten new `TimeWindowStoreTests.swift`
  cases; no regressions in any pre-existing suite (283 distinct test names
  per the same tool's top-level dedup count, consistent with +10 over §21's
  303/(implied ~273 unique)).
- `swift Scripts/generate-tokens.swift --check` — `Kadence/DesignSystem/
  Tokens.swift is up to date.` — no new tokens needed; every token this task
  used (`Tokens.Color.Interactive.focusRing`, `Tokens.Size.borderSelected`)
  already existed.
- Lock probe run first per Parsa's 2026-09-18 ruling: `swift -e
  'CGSessionCopyCurrentDictionary()'` → `CGSSessionScreenIsLocked` absent
  (unlocked), `kCGSSessionOnConsoleKey = 1`. `Scripts/check-accessibility.sh`
  taken at face value per that same ruling: `PASS (elements present)`, 20
  block-shaped elements, `0` carrying the §11 label — the pre-existing,
  already-open A20b defect (VoiceOver hover-help string, unrelated to this
  task, untouched by it).
- Grep confirmation of scope: no `resize`/`create` method on
  `TimeWindowStore`; no kind-picker/weekday-editing code added to
  `RoutinesWindow.swift`'s window-selection additions — see the grep output
  this task ran, which found only this task's own comments naming those as
  out of scope, nothing implementing them.

**Blocked:** nothing. Next up, per this task's own scope note and
`DEVIATIONS.md`'s P2-T20 paragraph (appended by this task): `TimeWindow` resize (drag a top/bottom
edge) and drag-to-create, the inspector's kind picker and weekday-set editing
for a selected window, `RoutineEngine.materialize` honouring protected
windows, `MenuBarExtra`, snooze.

## 23. P2-T22 — TimeWindow editor: resize existing windows by dragging top/bottom edge (Windows mode, 2026-09-24)

The piece §21/§22's own text named as "next task's job": resizing an
**existing** `TimeWindow` by dragging its top or bottom edge, using
"the same `size.blockResizeHandleHeight` handles blocks use" (components.md
§13.3, verbatim). Select/move/delete (P2-T21) are unchanged; this task only
adds the resize half.

**What was built:**

- `Kadence/State/TimeWindowStore.swift` — new `resize(_:newStartMinutes:newEndMinutes:)`,
  mirroring `RoutineBlockStore.resize`'s shape (accepts either or both ends
  independently, one named `UndoStack` step) but **not** its clamp. Per this
  file's own header (already explaining why `move` doesn't reuse G-013's
  day-bounded clamp), `resize` doesn't either: a candidate edge is wrapped
  mod 1440 (`wrapMinutes`, the same normalisation `move` already applies)
  rather than clamped into `[0, 1440]`. The only floor is the same 15-minute
  minimum `RoutineBlockStore.resize`/`EventStore.resize` both use
  (interactions.md §4), computed with a new `modularDuration(from:to:)`
  helper that measures forward and wraps past midnight exactly the way
  `spans(on:calendar:)` itself measures a window's span (an *equal*
  start/end reads as a full 24-hour window, never zero, matching
  `spans(on:)`'s own `else` branch) — not a plain subtraction, which would
  give the wrong answer once either end can wrap. If a candidate edge would
  leave less than 15 minutes measured that way against the other, fixed
  edge, it is pulled back to exactly 15 minutes instead of being allowed to
  collapse the window or invert it. Named undo step `"Resize Time Window"`,
  matching the file's existing `"Move Time Window"`/`"Delete Time Window"`
  naming. A candidate that changes neither end is a no-op and pushes no step.
- `Kadence/Views/Routines/RoutinesWindow.swift`:
  - `TimeWindowDragSession` gained a `Mode` enum (`.move` / `.resizeTop` /
    `.resizeBottom`, analogous to `RoutineDragSession.Mode` minus `.create` —
    a window is never created from this drag) alongside its existing
    `translationHeight`.
  - `windowGesture(window:span:geometry:)` now classifies the drag's mode
    once, from `value.startLocation` against `span`'s own top/bottom
    `Tokens.Size.blockResizeHandleHeight` band — the identical classification
    shape `blockGesture` already uses for routine blocks (`localY <= handle`
    → `.resizeTop`, `localY >= height - handle` → `.resizeBottom`, else
    `.move`). `.onEnded` now switches on that mode: `.move` calls the
    existing `TimeWindowStore.move` unchanged; `.resizeTop`/`.resizeBottom`
    call the new `TimeWindowStore.resize`, snapping the dragged edge's new
    date via `TimeGeometry.snap` (15-minute, 5-minute with `⌃`, same rule
    every other drag in this window already uses) before differencing it
    against the span's own start/end to get the minute delta applied to
    `window.startMinutes`/`endMinutes`.
  - `windowHitRegion` gained `liveWindowFeedback(for:)`, replacing the old
    single `liveOffset` computation: `.move` translates the whole region
    (unchanged from P2-T21); `.resizeTop` translates the top edge *and*
    shrinks the height by the same amount, so the bottom edge visibly stays
    put while dragging; `.resizeBottom` only grows/shrinks the height, so the
    top edge stays put. This is live visual feedback only — nothing is
    written to `TimeWindowStore` until `.onEnded`, same rule P2-T21 already
    established for the move case.
  - A window that wraps past midnight can render two spans on a given day
    (`spans(on:calendar:)`'s own doc comment); per this task's own brief,
    that is **not** special-cased in the gesture — whichever single span the
    pointer went down on supplies the reference date for that edge, and a
    top-edge drag always resizes `window.startMinutes` while a bottom-edge
    drag always resizes `window.endMinutes`, regardless of which span. This
    is correct for the common (non-wrapping) case; the render layer already
    recomputes both spans from the resulting fields either way, per the
    task's own instruction not to special-case the wrap here.
- `KadenceTests/TimeWindowStoreTests.swift` — new `TimeWindowStoreResizeTests`
  suite, eight cases: top-edge resize changes only `startMinutes` and names
  the step; bottom-edge resize changes only `endMinutes`; a bottom-edge drag
  past 24:00 wraps into the small hours instead of clamping at 1440; a
  top-edge drag before 00:00 wraps into the previous day's tail instead of
  clamping at 0; a top-edge drag that would leave less than 15 minutes before
  the fixed bottom edge is pulled back to exactly 15 (not collapsed or
  inverted); the symmetric bottom-edge case; a no-op candidate pushes no undo
  step; undo restores the exact original `startMinutes`/`endMinutes` and redo
  reapplies both changed ends. All eight pass individually
  (`-only-testing:KadenceTests/TimeWindowStoreResizeTests`) and as part of the
  full suite.

**Verified:**

- `xcodebuild -scheme Kadence -destination 'platform=macOS' build` —
  `** BUILD SUCCEEDED **`.
- `xcodebuild -scheme Kadence -destination 'platform=macOS'
  -only-testing:KadenceTests test` — `** TEST SUCCEEDED **`; 290 unique test
  names (counted from the raw log's `Test case '...' passed` lines,
  deduplicated — up from §22's reported count by the 8 new
  `TimeWindowStoreResizeTests` cases), 321 `passed` lines (the surplus is
  parameterized cases logged per argument, same wobble this file has noted
  since §1.4), 0 failed.
- `-only-testing:KadenceTests/TimeWindowStoreResizeTests` alone —
  `** TEST SUCCEEDED **`, all eight new cases passed individually.
- `-only-testing:KadenceTests/RoutineBlockStoreResizeTests` alone —
  `** TEST SUCCEEDED **`, all five pre-existing cases (`resizeTop`,
  `resizeBottom`, `clampsToMinimumDuration`, `noOpDoesNotPush`, `undoRedo`)
  still pass unchanged — confirms Blocks-mode routine-block resize is
  unaffected by this task's changes.
- `swift Scripts/generate-tokens.swift --check` —
  `Kadence/DesignSystem/Tokens.swift is up to date.` — no new tokens needed;
  `Tokens.Size.blockResizeHandleHeight` already existed (used already by
  `blockGesture`/`GridBlockView`'s hover handles).
- Lock probe run first per Parsa's 2026-09-18 ruling: `swift -e
  'CGSessionCopyCurrentDictionary()'` → the dictionary has no
  `CGSSessionScreenIsLocked` key at all (i.e. unlocked),
  `kCGSSessionOnConsoleKey = 1`. `Scripts/check-accessibility.sh` taken at
  face value per that same ruling: `PASS (elements present)`, 20
  block-shaped elements, `0` carrying the §11 label — the pre-existing,
  already-open A20b defect (VoiceOver hover-help string), unrelated to this
  task and untouched by it.
- All Kadence processes killed (`pkill -9`) after verification, confirmed
  zero matches.

**Blocked:** nothing. Next up, per this task's own scope note and
`DEVIATIONS.md`'s updated P2-T21 paragraph: creating a new `TimeWindow`
(drag-to-create), the inspector's kind picker, weekday-set editing,
`RoutineEngine.materialize` honouring protected windows, `MenuBarExtra`,
snooze.

## 24. P2-T23 — TimeWindow editor: drag-to-create a new window on empty canvas (Windows mode, 2026-09-24)

The piece §20/§21/§22's own headers all named as "next task's job", and the
one components.md §13.3 states in as many words: "Creating one: drag on empty
canvas, then pick the kind from the inspector." This task builds only the
drag half of that sentence — the inspector's kind picker, weekday-set
editing, and label editing are still out of scope, same deferral shape T20/
T21/T22 each used for their own remainder. A created window defaults to kind
`.protected` (`TimeWindow.swift`'s own model default), an empty label, and
exactly the one weekday of the column it was dragged on.

**What was built:**

- `Kadence/State/TimeWindowStore.swift` — new
  `create(weekdays:startMinutes:endMinutes:kind:label:) -> TimeWindow?`,
  mirroring `RoutineBlockStore.create`'s shape (`Kadence/State/RoutineEngine.swift`):
  one named `UndoStack` step (`"Create Time Window"`), `redo` inserts via the
  existing `TimeWindowRestoreSnapshot`/`insertWindow` plumbing `delete`'s undo
  already established, `undo` removes by `id` via the existing `removeWindow`.
  `TimeWindowRestoreSnapshot` gained a plain memberwise `init` (id, weekdays,
  startMinutes, endMinutes, kind, label) alongside its existing `@MainActor
  init(_ window:)`, mirroring `RoutineBlockRestoreSnapshot`'s own
  two-initializer shape exactly — a brand-new window has no `@Model` instance
  to snapshot *from*, so `create`'s `redo` needs the plain values-in
  initializer the same way `RoutineBlockStore.create`'s own snapshot needs
  one. Returns the created window (or `nil`) so the caller can select it,
  matching `RoutineEngine.create`'s optional-return convention
  `RoutinesWindow.commitDraft()` already relies on for `RoutineBlock`; the
  only failure case is an empty `weekdays` set (there is no title to be
  blank, since an empty label is this task's own explicit default, not a
  reason to refuse the create). The 15-minute minimum duration is enforced
  inside `create` itself, defensively — belt-and-braces, the same shape
  `RoutineBlockStore.create` already uses for its own floor — computed with
  the file's existing `wrapMinutes`/`modularDuration` helpers (the same
  wrap-aware floor `resize` already applies): a candidate `endMinutes` less
  than 15 minutes forward of `startMinutes` (measured wrapping, exactly as
  `spans(on:)` measures) is pushed forward to `startMinutes + 15`, wrapped,
  rather than collapsed or left to invert.
- `Kadence/Views/Routines/RoutinesWindow.swift`:
  - New `TimeWindowCreateDragSession` (`origin`/`current` snapped `Date`s),
    deliberately its own small type rather than a third case on
    `TimeWindowDragSession` — that type addresses an EXISTING window by
    `windowID`, and a window being created has none yet. New
    `@State private var windowCreateDrag: TimeWindowCreateDragSession?` on
    `RoutineDayColumnView`, alongside the existing `windowDrag`.
  - The windows-mode empty-canvas `Rectangle` (whose tap already deselects,
    hit-testable only when `editorMode == .windows`) gained a sibling
    `.gesture(windowCreateGesture(geometry:))`: `.onChanged` snaps
    `value.startLocation`/`value.location` via `TimeGeometry.snap` (15-minute,
    5-minute with `⌃` — the identical rule `createSurface`/`windowGesture`
    both already use); `.onEnded` computes `lower`/`upper`, floors the
    duration to 15 minutes (`max(upper.timeIntervalSince(lower), 15*60)`, the
    same pattern `commitDraft` uses for a routine block), wraps the resulting
    `startMinutes`/`endMinutes` mod 1440 (so a drag starting within the last
    15 minutes of the day produces a correctly-wrapping window instead of an
    out-of-range `endMinutes`), and calls
    `timeWindowStore.create(weekdays: [weekday], startMinutes:, endMinutes:)`
    with the column's own single `weekday` — never propagated to any other
    day. On success, `windowSelection = created.id`.
  - A live dashed preview during the drag: `windowCreatePreviewFrame(in:geometry:)`
    mirrors `dropPreviewFrame`'s own `.create`-case geometry math, keyed off
    `windowCreateDrag` instead of `drag`, rendered through the same existing
    `dropPreview(_:)` view (dashed accent-coloured `RoundedRectangle`) —
    reused, not reinvented, since the two drags never run in the same mode
    (`drag`/blocks-mode create is hit-testable only in `.blocks`;
    `windowCreateDrag`/this task's create is hit-testable only in `.windows`).
- Header comments in both files updated in place, T20–T22's own convention:
  `TimeWindowStore.swift`'s file header records `create` now exists and what
  is still deferred; `RoutinesWindow.swift`'s file header and the "MARK:
  TimeWindow select / move / resize" section comment both point at this
  task's drag-to-create instead of listing it as still-missing.

**Verified:**

- `xcodebuild -scheme Kadence -destination 'platform=macOS' build` —
  `** BUILD SUCCEEDED **`.
- `xcodebuild -scheme Kadence -destination 'platform=macOS'
  -only-testing:KadenceTests test` — `** TEST SUCCEEDED **`, run three times
  during this task (twice mid-task, once as the final re-verification pass);
  326 `passed` lines every time, 0 failed every time. The deduplicated unique
  test-name count itself wobbled by exactly one between runs (296 vs 297) —
  `LayoutItemsTests/activeWeekdayProducesItems()` was present in every run's
  raw log but missing from one run's captured `tail`-truncated intermediate
  file, not an actual missing/flaky test; the `passed`/`failed` line counts
  (the numbers that actually matter) were identical across all three runs.
  Either way, up from §23's reported 290 unique by the 6 new
  `TimeWindowStoreCreateTests` cases (the surplus of `passed` over unique
  names is parameterized cases logged per argument, same wobble this file has
  noted since §1.4).
- New `TimeWindowStoreCreateTests` suite, six cases, all passed as part of the
  full run above: `createsWithDefaults` (exact given weekday set, `.protected`
  kind by default, exact given start/end minutes, named undo step
  `"Create Time Window"`); `createsWithExplicitKindAndLabel` (a caller-supplied
  non-default kind/label round-trip); `pushesExactlyOneUndoStep`;
  `fifteenMinuteFloorEnforced` (a 5-minute span comes back as exactly 15,
  start held fixed); `emptyWeekdaysCreatesNothing` (returns `nil`, pushes no
  undo step); `undoRemovesRedoRestores` (undo removes the created window —
  fetch by id returns `nil` — redo restores it with the same id and every
  field).
- `swift Scripts/generate-tokens.swift --check` —
  `Kadence/DesignSystem/Tokens.swift is up to date.` — no new tokens needed;
  every token this task's preview reuses (`Tokens.Spacing.xxs`,
  `Tokens.Size.blockMinRenderedHeight`, `Tokens.Radius.block`,
  `Tokens.Color.Interactive.accent`) already existed, read through the
  existing `dropPreview(_:)`/`dropPreviewFrame` mechanism.
- Lock probe run first per Parsa's 2026-09-18 ruling: `swift -e
  'CGSessionCopyCurrentDictionary()'` → the dictionary has no
  `CGSSessionScreenIsLocked` key at all (i.e. unlocked),
  `kCGSSessionOnConsoleKey = 1`. `Scripts/check-accessibility.sh` taken at
  face value per that same ruling: `PASS (elements present)`, 20
  block-shaped elements, `0` carrying the §11 label — the pre-existing,
  already-open A20b defect (VoiceOver hover-help string), unrelated to this
  task and untouched by it.
- All Kadence processes killed (`pkill -9`) after verification, confirmed
  zero matches.

**Blocked:** nothing. Next up, per this task's own scope note and
`DEVIATIONS.md`'s updated P2-T23 paragraph: the inspector's kind picker,
weekday-set editing beyond this task's single-weekday default, label editing,
`RoutineEngine.materialize` honouring protected windows, `MenuBarExtra`,
snooze.
