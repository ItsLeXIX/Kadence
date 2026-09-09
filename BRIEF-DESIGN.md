# Design brief: "Kadence" — a personal macOS scheduling app

## What it is
A native macOS app that merges a university timetable, coursework deadlines, email-
derived appointments and a personal daily routine into one calendar, tells the user
when to leave, and turns assignments and exams into scheduled work sessions.

## Who it's for
One person: a CS student who relies on routine to stay on track and who loses time to
context-switching. The design consequence is specific and load-bearing:
- At any moment there must be exactly one obvious "what now" — never a wall of equally
  weighted information.
- Nothing important may depend on the user remembering to check it. The app tells them.
- Density is fine; ambiguity is not. Every block should be readable at a glance for
  what it is, where it is, and whether it's fixed or movable.
- Decisions come with defaults. A conflict is presented as 2–3 ranked options with a
  recommended one, not an open-ended problem.
- Avoid guilt UI: no red overdue counters, no streaks that break, no shaming empty
  states. Missed items are re-offered, not punished. Snoozing shows where something
  moved TO — the feedback is "it's handled", not "you failed".

## Platform
Native macOS, SwiftUI, current design language. Use the platform: standard window
chrome, sidebar + detail layout, toolbar, system materials, SF Symbols, system
typography (SF), Dynamic Type, full light and dark mode, correct behaviour under Reduce
Motion, Reduce Transparency and Increase Contrast. Do not design an iOS app on a big
screen, and do not invent custom window chrome.

## Screens and states to design
1. Main window — sidebar (sources, filters, "needs attention" count), calendar canvas,
   optional right-hand inspector for a selected item.
2. Calendar canvas in three modes:
   - Month: density-first, one line per event, colour-coded by source.
   - Week: hour grid, current-time indicator, overlapping events resolved legibly.
   - Day: hour grid with room for detail — travel bands, routine blocks, focus blocks.
3. Event block anatomy — the most important piece of the system. Six types must be
   distinguishable at a glance without relying on colour alone: an imported lecture,
   a routine block, a travel / "leave by" band, a planned study session, an all-day
   deadline, and an exam. Also show how protected and low-energy time windows are
   rendered as background treatment on the grid — present but recessive, clearly
   "not available" without shouting.
4. Menu bar extra ("next up"): the status item itself (title + time, must survive a
   crowded menu bar and be legible in a glance) and its popover — the next item large
   and unmissable, the rest of today secondary, and Done / Snooze / Open actions.
   Design its empty state (nothing left today) and its "you're late" state, the latter
   informative rather than alarming.
5. Conflict resolution sheet: the collision, 2–3 resolution options with a clear
   recommendation, and a preview of the resulting day.
6. Snooze / reschedule confirmation: small, fast, and it must show where the block
   landed, not just that it was snoozed.
7. Routine template editor: weekly blocks with a flexibility setting per block
   (fixed / shiftable / droppable) — find a way to show flexibility visually — plus
   the editor for protected, low-energy and peak-focus time windows.
8. Work item view: assignments, projects and exams with due dates, estimated effort,
   logged time, and the generated plan shown as a proposal to accept, edit or reject.
   Include the running timer state and the estimate-vs-actual comparison; present the
   accuracy feedback as useful calibration information, never as a judgement.
9. Exam countdown view: an exam is a ramp toward a fixed date, not a task to finish.
   Design something that communicates time remaining and revision coverage across
   topics, distinct from how assignments are shown.
10. Settings: sources and connection state, travel mode and buffer, notification rules
    per category, mail rules, focus limits.
11. Notification designs: pre-event, leave-by, daily morning summary — including their
    action buttons. Plus the states usually skipped: a source failing to sync, an
    expired login, an empty day, and first-run with nothing connected.

## Deliverables
1. A design-token set: colour (semantic, both appearances), spacing scale, type scale,
   corner radii, elevation. Named so they map directly to Swift constants.
2. A source colour system that survives 6+ sources, stays legible in both appearances,
   and passes WCAG AA for text on the block fill. Colour must never be the only carrier
   of meaning — pair it with shape, icon, or border treatment.
3. Component specs for the event block variants, including selected, hover, dragging,
   conflicted, past, in-progress, done and skipped states.
4. Layout specs for each view: fixed vs. flexible regions, minimum window size,
   behaviour when the window is narrow, and what collapses first.
5. A keyboard-first interaction map. This app should be fully usable without the mouse;
   specify focus order and shortcuts.
6. Motion guidance: what animates, for how long, what stops under Reduce Motion. Keep
   it minimal — motion here is for orientation during view changes, not delight. The
   one place motion earns its keep is showing a block moving to its new slot after a
   snooze; specify that transition precisely.

## Constraints
- Legibility over decoration. The day view will regularly hold 10+ blocks.
- No gradients-as-branding, no glassmorphism for its own sake, no dashboard-style
  metric cards. This is a working tool.
- Everything specified precisely enough that a developer implements it without asking
  follow-up questions — actual values, not adjectives.

## First response
Before producing visuals, tell me your reading of the core design problem, the two or
three hardest decisions you see (start with how to make six block types plus two
background window treatments legible on one day grid), and how you'd resolve them.
