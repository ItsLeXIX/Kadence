# Kadence — project context

## What this is
Personal macOS scheduling app. Native SwiftUI + SwiftData, macOS 15+.
Merges uni timetable, Moodle deadlines, email appointments and a personal
daily routine into one calendar. Tells me when to leave and what's next.

## Who works on what
- Design agent: writes ONLY into /design. Never touches Swift.
- Coding agent: reads /design, writes ONLY into /Kadence.
  Cannot invent UI values. If /design doesn't specify something,
  append the question to /design/GAPS.md and use a placeholder
  marked // SPEC-GAP.
- I (Parsa) am the only one who resolves conflicts between them.
- DECISIONS.md is mine. Agents may propose entries in their reports;
  only I write and commit them.

## Hard rules

### Product
- The assistant proposes, the user disposes: no LLM output is ever
  written to the calendar without explicit confirmation.
- Protected time windows are never scheduled into automatically.

### Process
- One phase at a time. Do not build ahead. The one standing exemption
  is the design system: all block variants and states are specced and
  built ahead of the data that fills them. This does not extend to
  models, services or network code.
- design/ is frozen for the duration of a build session. The design agent
  revises it only during a screenshot-review session, never while the
  coding agent is running. A revision needed mid-build goes in GAPS.md
  and waits.
- A gap is closed only when the resolution is written into the spec file
  AND GAPS.md records it as closed with a section reference. An agent's
  report that something is resolved is a claim to verify, not a state.
- Every build phase ends with screenshots/<phase>/ populated plus an
  INDEX.md. A phase is not done until the design agent has reviewed them.

### Build
- Design tokens live in design/tokens.json. Tokens.swift is generated.
  Never hand-edit Tokens.swift. Run generate-tokens --check before
  reporting a phase complete.
- Run tests with -only-testing:KadenceTests. KadenceUITests is empty
  Apple template code, deliberately left at Swift 5, and its runner
  cannot start in this environment. A red plain `test` is that target,
  not a real failure.

## Current phase
See STATUS.md