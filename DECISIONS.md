# Kadence — decisions

## 2026-09-09 — Spec and build all six block variants in Phase 1.

Why: block anatomy is a system; the six only become distinguishable
when designed together. Phases 2/3 add data, not views.

Implementation: shared style resolver + ~3 views (grid block,
travel band, all-day item), NOT one view with six branches.

Scope of exemption: design system only. Does not extend to
models, services or network code.

Phase 1 therefore ships: the style resolver, all three views, and a mock
data generator producing every variant and state so all six can be
reviewed on one day grid. Only `.manual` and `.imported` come from real
data. No TravelLeg service, no routine engine, no work items.
