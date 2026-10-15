# screenshots/3b — Phase 3 slice 2 review set (components.md §30)

Every frame was produced on Thu 15 Oct 2026 (Europe/Vienna) by CA, task
P3S2-T18. Two kinds:

- **Live** — `Scripts/capture-p3b.sh <item>` (`SUFFIX=p3b`): a `-KadenceReview`
  launch on its own in-memory store, a fresh pre-flight before every item,
  input to Kadence only. Each launch's `kadence-review/launch-services.txt`
  was checked: `ScriptedPathMonitoring MockTravelTimeProvider
  MockPlaceGeocoder MockLocationSource ScriptedPathMonitoring
  RecordingNotificationCenter` — mocks only, every time. Week `M` for the
  `travel` dataset is the next Monday after launch: **Mon 19 Oct 2026**.
  The launch time is the frame's file time below; the clock is the real one.
- **Offscreen** — rendered by the test suite (`Slice2Render`, run with
  `TEST_RUNNER_KADENCE_CAPTURE_DIR=1`, full suite green: 1067 passed) with the
  clock pinned in the test; dataset `travel` at `M` = **Mon 12 Oct 2026**
  unless stated. No window, no launch.

No permission prompt, real notification or Location prompt appeared during
any capture. The real store's `stat` was identical before and after.

| § 30 item | File(s) | Kind | Dataset / variant / arguments | Clock |
|---|---|---|---|---|
| 1 Settings ▸ Travel, first run | `settings-travel-first-run-p3b.png` | offscreen | `empty`, `-KadenceLocation notAsked` | pinned |
| 2 Settings ▸ Travel, filled | `settings-travel-filled-p3b.png`; live: `settings-travel-live-p3b.png` | offscreen + live | `travel` | live 01:49 |
| 3 Settings ▸ Notifications, allowed | `settings-notifications-allowed-p3b.png`; live: `settings-notifications-live-p3b.png` | offscreen + live | `travel`, `-KadenceNotifications allowed` (default) | live 01:50 |
| 4 Notifications `off` / `notAllowedYet` | `settings-notifications-off-p3b.png`, `settings-notifications-not-allowed-yet-p3b.png` | offscreen | `-KadenceNotifications off` / `notDetermined` after a recorded ask | pinned |
| 5 Week `M` | `week-M-travel-p3b.png` | live | `travel` | launch 02:04 |
| 6 Week `M`, early and late | `week-M-travel-p3b.png` (06:00–23:xx in one frame: Sat `Leave 06:45`; `Late call` 23:15, no band) | live | `travel` | launch 02:04 |
| 7 Day, Thu `M + 3` | `day-thu-travel-p3b.png` | live | `travel` | launch 01:48 |
| 8 Case-2 band, `Climbing` | Week: `week-M-travel-p3b.png`; Day: `day-sun-climbing-p3b.png`; render: `band-states-p3b.png` | live + offscreen | `travel` | launch 02:06 — see G-100 |
| 9 Inspector `SWQM-ILV` | `inspector-swqm-live-p3b.png`; render: `inspector-swqm-leave-p3b.png` | live + offscreen | `travel` | launch 02:06 |
| 10 Inspector `REQEN-EXAM` | `inspector-reqen-no-travel-p3b.png` | offscreen | `travel` | pinned |
| 11 Inspector `Dinner with flatmates` | `inspector-dinner-place-p3b.png`; pop-up open: `inspector-dinner-popup-p3b.png` | offscreen + live | `travel` | launch 02:07 |
| 12 Unavailable — no address | `inspector-no-address-p3b.png`; Week: `week-M-no-address-p3b.png` | offscreen + live | `travel`, variant `travelNoAddress` | launch 02:05 |
| 13 Status item renders | `status-item-leave-full-p3b.png`, `status-item-leave-degraded-p3b.png`, `status-item-leave-now-p3b.png`, `status-item-late-p3b.png`, `status-item-takeover-p3b.png`, `status-item-no-takeover-p3b.png`, `status-item-estimate-p3b.png`; `unavailable` row asserted by test (G-099) | offscreen | per §30 item 13's table | Thu 11:50 / 12:20 / 13:05 / 17:10 / 17:20 |
| 14 Notification plan | `notification-plan-travel.txt` (Thu 15 Oct 06:00, Fri 16 Oct 23:00, catch-up, snooze); live recorded plan: `notification-plan-live-p3b.txt` | test dump + live | `travel` | pinned; live 01:51 |
| 15 Popover renders | `popover-leave-p3b.png`, `popover-leave-now-p3b.png` (light), `popover-leave-now-dark-p3b.png`, `popover-late-p3b.png`, `popover-takeover-p3b.png`, `popover-manual-next-p3b.png`, `popover-notifications-off-p3b.png`, `popover-notifications-not-allowed-yet-p3b.png`, `popover-estimate-p3b.png`, `popover-unavailable-p3b.png`, `popover-no-address-p3b.png`; pending and from-where-you-are asserted by tests | offscreen | per §30 item 15 | pinned |
| 16 Live status item + popover | `status-item-live-p3b.png` (`Leave 02:30 · Pick up parcel`), `popover-live-p3b.png` | live | `travel`, live event P6 | launch 02:13 — outside 07:00–20:00 (the run was at night); P6 follows the launch clock, so the state is the same |
| 17 Regression, `phase3` | `phase3-today-p3b.png` (Thu 15 Oct, `Datenmodellierung` `Leave 08:38`), `phase3-week-M-p3b.png` | live | `phase3`, `-KadenceMockCalDAV reportOK` | launch 01:56 |
| 18 Looking up an address | `settings-travel-lookup-{one,several,many,none,offline,searching}-p3b.png`, `settings-travel-lookup-still-using-p3b.png` | offscreen | `empty`, `-KadenceGeocode <case>` | pinned |
| 19 Location states | `settings-travel-location-{denied,services-off,not-allowed-yet,switch-off}-p3b.png`; Ways: `settings-travel-ways-p3b.png` | offscreen | `travel`, `-KadenceLocation <case>` | pinned |
| 20 Week `M`, estimates | `week-M-estimates-p3b.png`; inspectors `inspector-epc-estimate-p3b.png`, `inspector-dinner-unavailable-p3b.png` | live + offscreen | `travel`, variant `travelOffline` | launch 02:05 |
| 21 Inspector `noRoute` | `inspector-climbing-no-route-p3b.png` | offscreen | `travel`, variant `travelNoRoute` | pinned |
| 22 Now time and an hour label | `now-label-week-1018-p3b.png`, `now-label-day-1018-p3b.png`, `now-label-week-1040-p3b.png` | offscreen | `travel` | 10:18 / 10:40 |
| 23 Plan, routing and sync | `notification-plan-travel.txt` sections `Routing: …`, `Departure refresh …`, `From where you are …`, `Sync paused: …` | test dump | `travelOffline`, `travelNoAddress`; N8 `unauthorized` / `forbidden` | pinned |

## Notes

- Week frames: in a Week column `Leave HH:mm · NNmin` does not fit, so the
  minutes drop and the time stays whole (DEVIATIONS B53); Day frames show
  the full label.
- `day-sun-climbing-p3b.png`: Sun 25 Oct 2026 is the night the clocks go
  back. The event and its band read right (`Climbing` 18:00–19:30, `Leave
  17:45 · 5min`) but the grid draws them one hour low — a Phase 1 geometry
  bug, GAPS G-100.
- The Day header's secondary line is clipped (`3 blocks · 4.5 h scheduled`)
  — already recorded in GAPS (layouts.md §4, `size.dayHeaderHeight`).
- Edge check (`Scripts/check-frame-edges.py`): every frame `ok`.
- Earlier per-task frames (`-p3bt<N>`) were replaced by these and removed.
