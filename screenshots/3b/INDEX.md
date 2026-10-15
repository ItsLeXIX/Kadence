# screenshots/3b — Phase 3 slice 2 review set (components.md §30)

First produced on Thu 15 Oct 2026 (Europe/Vienna) by CA, task P3S2-T18
(`-p3b`); updated the same day by the review fixes P3S2-F01 … F05
(`-p3bfNN`). Where a fix frame replaces a `-p3b` frame the `-p3b` file was
removed (list at the end). Three kinds:

- **Offscreen (fixes)** — rendered by the test suite from the real views
  (`ClockChangeRenderTests`, `F05RenderTests`, and the existing render tests
  with a fix suffix) on in-memory stores with the mock provider, geocoder,
  location source and path monitor and the recording notification centre,
  clock pinned. Collected by `Scripts/capture-p3b-renders.sh` from the
  result bundle's attachments. No app launch, no UI input; the test host is
  a launch kind that builds no real service (DECISIONS 2026-10-14).
  The `travel` frames that were live (items 5, 6, 8, 12, 16, 17, 20) are
  rendered from the review launch's own seeding at **Thu 15 Oct 2026 12:00**,
  so Week `M` is **Mon 19 – Sun 25 Oct** and its Sunday is the clock change
  (DEVIATIONS B55 — why not live).
- **Offscreen (T18)** — the `-p3b` renders, dataset `travel` at `M` = Mon 12
  Oct 2026 unless stated.
- **Live (T18)** — `Scripts/capture-p3b.sh`, `-KadenceReview` launches,
  services list mocks only every time (`ScriptedPathMonitoring
  MockTravelTimeProvider MockPlaceGeocoder MockLocationSource
  RecordingNotificationCenter`); Week `M` Mon 19 Oct; launch time below.

No launch was made in the fixes run, so no services list was produced; no
permission prompt, real notification or Location prompt appeared at any
point.

| § 30 item | Current frame(s) | Kind | Dataset / variant | Clock |
|---|---|---|---|---|
| 1 Settings ▸ Travel, first run | `settings-travel-first-run-p3bf05.png` — the whole Travel pane: Places (Home empty, `Address`; campus `Höchstädtplatz 6, 1200 Wien, Austria`, found at the first launch with no switch, F04), footer, `Add Place`; Ways (`Usually Public transport`, `Home ↔ FH Technikum Wien Usual`); `Buffer 10 minutes`; `Use where you are` on (grey: an offscreen window is never key), no block. The three tabs are not drawn offscreen (B55) | offscreen (fixes) | `empty`, location not asked | Thu 15 Oct 12:00 |
| 2 Settings ▸ Travel, filled | `settings-travel-filled-p3b.png`; live `settings-travel-live-p3b.png` | offscreen + live (T18) | `travel` | live 01:49 |
| 3 Notifications, allowed | `settings-notifications-allowed-p3b.png`; live `settings-notifications-live-p3b.png` | offscreen + live (T18) | `travel` | live 01:50 |
| 4 Notifications `off` / `notAllowedYet` | `settings-notifications-off-p3b.png`, `settings-notifications-not-allowed-yet-p3b.png` | offscreen (T18) | | pinned |
| 5 Week `M` | `week-M-travel-p3bf05.png` | offscreen (fixes) | `travel` + P6 | Thu 15 Oct 12:00 |
| 6 Week `M`, early and late | `week-M-travel-p3bf05.png` (Sat `Leave 06:45`, `Late call` 23:15 with no band, whole day in one frame) | offscreen (fixes) | `travel` | Thu 15 Oct 12:00 |
| 7 Day, Thu `M + 3` | `day-thu-travel-p3b.png` | live (T18) | `travel` | launch 01:48 |
| 8 Case-2 band, `Climbing` | Week `week-M-travel-p3bf05.png` and Day `day-sun-climbing-p3bf05.png`: Sun 25 Oct, **`Climbing` on the 18:00 row, band from 17:45** (`Leave 17:45 · 5min`) — after F01; render `band-states-p3b.png` | offscreen (fixes) + (T18) | `travel` | Thu 15 Oct 12:00 |
| 9 Inspector `SWQM-ILV` | `inspector-swqm-live-p3b.png`; `inspector-swqm-leave-p3b.png` | live + offscreen (T18) | `travel` | launch 02:06 |
| 10 Inspector `REQEN-EXAM` | `inspector-reqen-no-travel-p3b.png` | offscreen (T18) | `travel` | pinned |
| 11 Inspector `Dinner with flatmates` | `inspector-dinner-place-p3bf02.png` (`Origin Manual`, F02); pop-up open `inspector-dinner-popup-p3b.png` | offscreen (fixes) + live (T18) | `travel` | Mon 12 Oct 06:00 / launch 02:07 |
| 12 Unavailable — no address | `inspector-no-address-p3b.png`; Week `week-M-no-address-p3bf05.png` | offscreen (T18) + offscreen (fixes) | `travelNoAddress` | Thu 15 Oct 12:00 |
| 13 Status item renders | `status-item-leave-full-p3b.png`, `-leave-degraded-`, `-leave-now-`, `-late-`, `-takeover-`, `-no-takeover-`, `-estimate-p3b.png`; **`status-item-unavailable-p3bf05.png`** (`18:30 · Dinner with flatmat…`, truncated as measured) | offscreen (T18) + (fixes) | per item 13; unavailable: `travelOffline`, EPC-ILV and REQEN-EXAM done | Thu 17:30 |
| 14 Notification plan | `notification-plan-travel.txt` (rewritten by F05: catch-up passes **at** 12:12 / 12:20 / 13:05, the pass clock in each header); live plan `notification-plan-live-p3bf05.txt` (P6 at Thu 12:00) | test dump | `travel` | pinned |
| 15 Popover renders | `popover-leave-p3bf03.png` (one line), `popover-takeover-p3bf03.png`, `popover-manual-next-p3bf03.png`, `popover-no-address-p3bf03.png` (leave line on two lines, F03); `popover-leave-now-p3b.png`, `-leave-now-dark-`, `-late-`, `-notifications-off-`, `-notifications-not-allowed-yet-`, `-estimate-`, `-unavailable-p3b.png`; **`popover-pending-p3bf05.png`** (`Travel time from Home not worked out yet`, Thu 11:50), **`popover-from-here-p3bf05.png`** (`Leave by 12:22 · 28 min from where you are`, Thu 12:00, location allowed, fix `cafe`) | offscreen | per item 15 | pinned |
| 16 Status item + popover for P6 | `status-item-live-p3bf05.png` (`Leave 12:15 · Pick up parcel`), `popover-live-p3bf05.png` (`Leave by 12:15 · 35 min from Home`, `13:00 – 13:30 · Personal`) — **at 12:00, inside 07:00–20:00** | offscreen (fixes) | `travel` + P6 | Thu 15 Oct 12:00 |
| 17 Regression `phase3` | `phase3-today-p3b.png` (live, T18); `phase3-week-M-p3bf05.png` — Sunday 25 Oct's routine blocks on their wall-clock rows after F01 (`Fixture review` 20:00 like every other day) | live (T18) + offscreen (fixes) | `phase3` | launch 01:56 / Thu 15 Oct 12:00 |
| 18 Looking up an address | `settings-travel-lookup-{one,several,none,offline,searching}-p3b.png`, `settings-travel-lookup-still-using-p3b.png`; **`settings-travel-lookup-many-p3bf05.png`** (tall enough for `Add Place`) | offscreen | `empty` | pinned |
| 19 Location states | `settings-travel-location-{denied,services-off,not-allowed-yet,switch-off}-p3b.png`; Ways `settings-travel-ways-p3b.png` | offscreen (T18) | `travel` | pinned |
| 20 Week `M`, estimates | `week-M-estimates-p3bf05.png`; `inspector-epc-estimate-p3b.png`, `inspector-dinner-unavailable-p3b.png` | offscreen (fixes) + (T18) | `travelOffline` | Thu 15 Oct 12:00 |
| 21 Inspector `noRoute` | `inspector-climbing-no-route-p3b.png` | offscreen (T18) | `travelNoRoute` | pinned |
| 22 Now time and an hour label | `now-label-week-1018-p3b.png`, `now-label-day-1018-p3b.png`, `now-label-week-1040-p3b.png`; **`now-label-cursor-week-1018-p3bf05.png`** (cursor 10:18, `10:00` dropped) | offscreen | | 10:18 / 10:40 |
| 23 Plan, routing and sync | `notification-plan-travel.txt` sections `Routing: …`, `Departure refresh …`, `From where you are …`, `Sync paused: …` | test dump | `travelOffline`, `travelNoAddress`; N8 | pinned |
| 24 Clock changes | `dst-day-1025-p3bf01.png`, `dst-week-1025-p3bf01.png`, `dst-month-1025-p3bf01.png`, `dst-day-0329-p3bf01.png`, `dst-week-0329-p3bf01.png`, `dst-month-0329-p3bf01.png` — §31.5's events, a 20:00 routine block, `Climbing`'s band, Sleep, the now line at 18:30 | offscreen (fixes) | §31.5 | Sun 25 Oct / 29 Mar 18:30 |

## Notes

- Removed (superseded by a fix frame of the same name): `week-M-travel`,
  `day-sun-climbing`, `week-M-no-address`, `week-M-estimates`,
  `status-item-live`, `popover-live`, `phase3-week-M`,
  `settings-travel-first-run`, `settings-travel-lookup-many` (→ `-p3bf05`);
  `inspector-dinner-place` (→ `-p3bf02`); `popover-leave`,
  `popover-takeover`, `popover-manual-next`, `popover-no-address` (→
  `-p3bf03`), all `-p3b.png`; and `notification-plan-live-p3b.txt` (→
  `notification-plan-live-p3bf05.txt`).
- Week frames: in a Week column `Leave HH:mm · NNmin` does not fit, so the
  minutes drop and the time stays whole (DEVIATIONS B53); Day frames show
  the full label.
- The ⚠ marks in the `dst-*` frames are the existing late state of past,
  unmarked manual events at 18:30, not a clock-change effect.
- Edge check (`Scripts/check-frame-edges.py`): every frame `ok`.
- G-096 (Parsa, Xcode): `INFOPLIST_KEY_NSLocationUsageDescription` and
  `INFOPLIST_KEY_NSLocationWhenInUseUsageDescription` are now **present**
  in `project.pbxproj` (Debug and Release, `a0deaaa`); still no
  `CODE_SIGN_ENTITLEMENTS` (time-sensitive delivery optional).
