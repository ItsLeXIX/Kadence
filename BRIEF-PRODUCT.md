# Project: "Kadence" (working name) — a personal macOS scheduling app

## Context
I'm a CS student in Vienna building a native macOS app for myself. My background is
Java and C#/Unity; Swift is new to me, so explain non-obvious Swift/SwiftUI idioms in
comments as you go. This app is not for the App Store — it's a personal tool, but I
want it built like production code.

The app's purpose: I run on routine, and I lose track of tasks when they're spread
across a uni portal, Moodle, and email. The app pulls all of it into one calendar,
auto-fills my daily routine, and tells me when to leave and what to do next.

## Design principle that governs behaviour, not just looks
At any moment the app must be able to answer "what now" with one thing. Nothing
important may depend on me remembering to check the app. Skipped or missed items are
re-offered, never just dismissed and never counted against me — no overdue counters,
no streaks.

## Target
- macOS 15+ (build against the current SDK), Apple Silicon
- SwiftUI + SwiftData, Swift 6 strict concurrency
- Xcode project, no third-party dependencies unless I approve them first
- Sandboxed, with entitlements only for: outgoing network, user notifications,
  calendars (EventKit), location (for travel time only)

## Architecture
- Layered: Models (SwiftData) / Services / ViewModels / Views. No networking in views.
- Every external integration sits behind a protocol with a mock implementation, so the
  UI can be built and tested with fake data before any connector works:
    - protocol ScheduleSource      { func fetchEvents(in: DateInterval) async throws -> [ExternalEvent] }
    - protocol AssignmentSource    { func fetchAssignments() async throws -> [ExternalAssignment] }
    - protocol MailSource          { func fetchRecent(since: Date) async throws -> [MailMessage] }
    - protocol TravelTimeProvider  { func duration(from: Place, to: Place, arrivingBy: Date, mode: TravelMode) async throws -> TimeInterval }
    - protocol PlanningAssistant   { func plan(for: WorkItem, availability: [FreeSlot], constraints: SchedulingConstraints) async throws -> [PlannedBlock] }
- All credentials and tokens in the Keychain. Never in UserDefaults, never in source,
  never logged. If a connector needs a password, the app asks at runtime.
- Sync is pull-only and idempotent: every imported item keeps a stable
  (sourceID, externalID) pair so re-syncing updates instead of duplicating.
- Background refresh via NSBackgroundActivityScheduler, interval configurable.

## Data model (first draft — propose changes if you see problems)
Event(id, title, start, end, isAllDay, location: Place?, origin: .manual/.routine/.imported/.planned,
      sourceID, externalID, colorTag, notes, isLocked, status: .scheduled/.done/.skipped)
Place(name, address, coordinate)

RoutineTemplate(name, activeWeekdays, blocks: [RoutineBlock])
RoutineBlock(title, startTime, duration, flexibility: .fixed/.shiftable(±minutes)/.droppable, priority)

// Protected and low-energy time — HARD constraints, not preferences.
TimeWindow(weekdays, start, end, kind: .protected/.lowEnergy/.peakFocus, label)
SchedulingConstraints(maxFocusHoursPerDay, minBlockDuration, maxBlockDuration,
                      minBreakBetweenBlocks, bufferBeforeDeadline, windows: [TimeWindow])

WorkItem(id, kind: .assignment/.project/.exam, title, course, dueOrExamDate,
         estimatedEffort: TimeInterval, effortConfidence: .low/.medium/.high,
         status, sourceID, externalID, notes)
PlannedBlock(workItemID, start, end, goal: String, isAccepted, generation: Int)
TimeLog(workItemID, plannedBlockID?, start, end, source: .timer/.manual)

TravelLeg(eventID, departAt, duration, mode, computedAt)
NotificationRule(kind, leadTime, isEnabled)
MailRule(matcher, action: .notify/.silence/.createEvent)

## Build order — do NOT skip ahead. Stop after each phase and let me test it.

### Phase 1 — the calendar (no network at all)
- Main window: sidebar (calendar sources, filters) + large calendar canvas + optional
  right inspector for the selected item.
- Month / Week / Day views, switchable, with keyboard shortcuts (⌘1/⌘2/⌘3, T for today,
  ←/→ to page). Day and Week are hour-gridded with a live current-time indicator.
- Create, edit, drag-to-move, drag-to-resize, delete events manually.
- SwiftData persistence. Seed with a mock data generator so views can be exercised.
- Definition of done: I can run it and use it as a plain calendar all day.

### Phase 2 — routines, conflicts, protected time, and the menu bar
- Routine template editor: name a routine, set weekday activity, add blocks with start
  time, duration and a flexibility setting.
- A RoutineEngine that materialises templates into a date range, and re-materialises
  when a template changes without destroying manual edits.
- TimeWindow editor for protected / low-energy / peak-focus windows. These are stored
  now even though only the planner consumes them later. Protected windows are never
  scheduled into by any automatic process, ever.
- Conflict detection: any overlap between a routine block and an imported/manual event,
  and any automatic placement that would land in a protected window.
- When there's a conflict, do NOT silently resolve it. Surface it in a "Needs your
  attention" list, and generate 2–3 concrete resolution options ranked by how little
  they disturb the day (e.g. "shift training 90 min later", "shorten it to 45 min",
  "skip today"), with one marked recommended. One click applies an option. Every
  applied change is undoable (⌘Z).
- Menu bar extra ("next up"): a status item showing only the single next thing —
  its title, its start time, and the leave-by time once Phase 3 exists. Clicking it
  opens a small popover with the rest of today and buttons for Done / Snooze / Open
  main window. It must be readable in one glance from across the room; do not turn it
  into a second calendar. It updates on a timer and on any data change.
- Definition of done: I define a weekday routine, drop a fixed 3-hour lecture on top of
  it, get sensible options, and can see what's next without opening the app.

### Phase 3 — work items, feeds and travel time
- Manual creation of assignments, projects and exams first, before any import:
  title, course, due/exam date, estimated effort and an effort confidence level.
- Time logging: a start/stop timer attached to a work item, plus manual entry, writing
  TimeLog records. Show estimated vs. actual effort per item, and a simple
  estimate-accuracy summary over time (e.g. "you typically underestimate by 60%").
  Feed that ratio into the planner in Phase 6 as a suggested multiplier — suggested,
  and visible, never silently applied.
- ICS subscription support: paste a URL, it polls and imports read-only events. This is
  how the uni timetable and Moodle deadlines get in if ICS URLs exist.
- Moodle REST client as an AssignmentSource: token via /login/token.php with
  service=moodle_mobile_app, then core_calendar_get_action_events_by_timesort and
  mod_assign_get_assignments. Handle token expiry by prompting for re-auth.
- CalDAV client for calendar data if the mail/groupware server exposes it.
- TravelTimeProvider: MapKit MKDirections implementation for .walking and .driving.
  Leave a stub for .transit and tell me clearly what an external provider would need.
- For any event with a location, compute a departure time (travel duration + a
  configurable buffer) and render it as a distinct "Leave by HH:MM" band before the
  event. Recompute on the morning of, not once at import.
- Definition of done: my real timetable appears, each on-campus lecture shows a
  leave-by time, and I can log time against a piece of coursework.

### Phase 4 — notifications
- UNUserNotificationCenter. Per-rule lead times, configurable per category (lectures
  30 min, leave-by 5 min before departure, deadlines 3 days / 1 day / 3 hours).
- Notification actions: Done, Open, and Snooze — where snooze RESCHEDULES rather than
  dismisses. Snoozing a study or routine block asks the scheduler for the next viable
  slot that respects protected windows and daily focus limits, then shows me where it
  landed. A block that is skipped outright goes back into the pool of work to be
  re-placed on a later day; it never silently disappears.
- A daily morning summary notification: the shape of the day and the first thing to do.
- Definition of done: nothing on my calendar can happen without me being told first,
  and skipping something puts it back in the queue instead of losing it.

### Phase 5 — mail triage
- IMAP read-only against the university mail server. Propose a library and justify it
  before adding anything; flag it clearly if you think this phase needs a different
  approach.
- Classification into: from a human at the institution (notify), automated/system mail
  (silent, still searchable), and everything else. Rules are user-editable regex or
  sender/subject matchers, plus a manual "always notify / never notify" override per
  sender settable from the UI.
- Detect schedule-relevant mail (room changes, cancellations) and offer — never apply —
  a calendar change I confirm.
- Definition of done: I get notified about my professor and nothing about mailing lists.

### Phase 6 — the planning assistant
- PlanningAssistant implementation calling an LLM API, key in Keychain, endpoint and
  model configurable. Input: the work item, my real free slots, and SchedulingConstraints.
  Output: PlannedBlocks each with a concrete goal for that session.
- Two distinct algorithms:
  - Assignments and projects: forward-fill from now toward the deadline, front-loaded,
    finishing before the buffer window so the deadline itself is empty.
  - Exams: backward-plan from the exam date. Ramp up in intensity as the date
    approaches, spaced repetition over topics rather than one long block, with the
    last day reserved for review only, not new material. Exams are never "finished
    early" — model them as a countdown, not a task.
- Hard constraints the planner may not violate: never place work in a protected window,
  never exceed maxFocusHoursPerDay, never place blocks shorter than minBlockDuration,
  respect minBreakBetweenBlocks, prefer peakFocus windows and avoid lowEnergy windows.
  Enforce these in Swift after the model responds — validate and reject the plan rather
  than trusting the model to have obeyed.
- The assistant proposes; I dispose. Every generated plan appears in a review sheet
  where I accept, edit individual blocks, or reject the whole thing. Nothing an LLM
  produces is written to the calendar without my explicit confirmation. This rule has
  no exceptions and no "auto-apply" setting.

## Non-negotiables
- Ask me before adding any dependency, and before doing anything that logs into a
  university system with my password.
- If a portal has no API and would need HTML scraping, say so and stop — don't scrape
  speculatively. Present the options and let me decide.
- Write unit tests for RoutineEngine, conflict detection, departure-time maths, the
  snooze/reschedule search, and the planner's constraint validator. Those are the parts
  where a silent bug makes me miss a lecture or an exam.
- No force-unwraps outside tests. Errors surface in the UI, never as a crash.
- Every phase must build and run on its own.

## First response
Don't write code yet. Give me: the Xcode project structure, the final data model with
your corrections, the open questions you need answered, and anything in the above plan
you think is wrong or out of order.
