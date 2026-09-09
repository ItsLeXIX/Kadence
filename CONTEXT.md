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

## Hard rules
- Design tokens live in design/tokens.json. Tokens.swift is generated.
  Never hand-edit Tokens.swift.
- The assistant proposes, the user disposes: no LLM output is ever
  written to the calendar without explicit confirmation.
- Protected time windows are never scheduled into automatically.
- One phase at a time. Do not build ahead.

## Current phase
See STATUS.md
