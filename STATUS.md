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
2. **Phase 2 has a design and, as of tasks P2-T08–P2-T13, four slices of
   code.** `design/components.md` §13–§17, `layouts.md` §8–§10,
   `interactions.md` §10–§12 and the 67 new tokens are complete and frozen.
   `RoutineTemplate`/`RoutineBlock` (models) and `RoutineEngine.materialize`
   exist and are tested (§6), a Routines window shell exists and renders one
   template's blocks (§8), that window's blocks can now be moved, resized,
   created and deleted, undoably (§9, §10), and `ConflictEngine` now detects
   routine-vs-manual/imported overlaps and generates their ranked resolution
   options, data layer only (§12) — everything else (the Blocks/Windows mode
   control, the interactive flexibility control, detached-instance tracking
   and re-sync, wiring detected conflicts onto the grid or into a panel,
   applying a resolution option, the menu bar extra, snooze, and the
   `TimeWindow` model and editor) is still unbuilt. The design pass also notes
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
- **A21** — the sidebar's needs-attention row draws `tray.full`, which the
  amended components.md §10.2 now forbids outright. New, and a one-line fix; see
  DEVIATIONS.md.

### 5.2 Gaps

*(Corrected 2026-09-11 by task P2-T05 — G-010 and G-011 had been closed by DA's
task P2-T04 in `design/GAPS.md` but this section still listed them as open.
That was a stale-entry bug in this file, not in the spec; it is fixed below.)*

*(Corrected again 2026-09-11 by task P2-T06 — G-012 was ruled CLOSED at the
spec level by task P2-T04 on the same day as G-010/G-011, but this section
kept listing it as open because the code side had not been built yet. It is
fixed in code now too; the stale entry is corrected below.)*

Two remain open, none blocking: **G-003** and **G-005**. Closed: G-004, G-006,
G-007, G-008, G-009, G-010, G-011, G-012. **There are no invented design
values in the codebase** and no `// SPEC-GAP` markers left in `Kadence/`.

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
