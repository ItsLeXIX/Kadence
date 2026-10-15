//
//  F05RenderTests.swift
//  KadenceTests
//
//  P3S2-F05 — PHASE3-SLICE2-REVIEW.md §7 F05's frames, offscreen (DEVIATIONS
//  B55): the real views on in-memory stores with the mock provider, geocoder,
//  location source and path monitor and the recording centre, clock pinned.
//  The `travel` frames that were live use the review launch's own seeding
//  (`ReviewMode.seedIfRequested(.travel)` / `TravelDataset.seed` with `M` =
//  the first Monday after the clock and the live event P6), at Thu 15 Oct
//  2026 12:00 — inside §30.1's 07:00–20:00 — so Week `M` is 19–25 Oct and
//  its Sunday is the clock change.
//

import Testing
import Foundation
import SwiftUI
import SwiftData
@testable import Kadence

@MainActor
@Suite(.serialized)
struct F05RenderTests {
    typealias F = TravelFixtures
    static let suffix = "p3bf05"
    /// Thu 15 Oct 2026 12:00, Europe/Vienna.
    static let noon = F.date("2026-10-15 12:00")
    static var m: Date { ReviewFeed.firstMonday(after: noon, zone: F.zone) }
    static var week: [Date] { (0..<7).map { F.calendar.date(byAdding: .day, value: $0, to: m)! } }

    func render(_ name: String, _ view: some View, size: CGSize) {
        #expect(Slice2Render.render(name, view, size: size, suffix: Self.suffix) != nil)
    }

    func legs(_ rig: TravelRig) -> [UUID: LegValues] {
        Dictionary(uniqueKeysWithValues: rig.legs().map { ($0.eventID, LegValues($0)) })
    }

    /// Week `M` or one day of it, drawn as the main window draws it.
    func canvas(_ name: String, _ rig: TravelRig, days: [Date], fixtures: MockFixtures = MockFixtures()) {
        let state = CalendarState()
        state.now = rig.clock.now
        var withLegs = fixtures
        withLegs.travelInfo = rig.coordinator.travelInfo()
        let events = rig.events().filter { e in days.contains { F.calendar.isDate(e.start, inSameDayAs: $0) } }
        let isDay = days.count == 1
        let hour = isDay ? Tokens.Size.hourHeightDay : Tokens.Size.hourHeightWeek
        let view = ClockChangeCanvas(mode: isDay ? .day : .week, days: days, events: events, fixtures: withLegs,
                                     now: rig.clock.now, store: rig.store, state: state)
        render(name, view, size: CGSize(width: Tokens.Size.timeGutterWidth + (isDay ? 420 : 7 * 130),
                                        height: 24 * hour + 60))
    }

    func travelRig(_ variant: TravelDataset.Variant? = nil, now: Date = noon,
                   location: MockLocationSource = MockLocationSource(authorization: .notDetermined)) async throws -> TravelRig {
        let rig = try TravelRig(now: now, variant: variant, m: Self.m, liveEvent: true,
                                provider: variant.map { ReviewTravel.provider(dataset: .travel, variant: $0) },
                                location: location)
        rig.keepAlive()
        await rig.launchAndSettle()
        return rig
    }

    func popoverView(_ r: TravelRig, now: Date) async -> some View {
        let scheduler = NotificationScheduler(context: r.context, centre: RecordingNotificationCenter(authorization: .allowed),
                                              clock: r.clock, calendar: F.calendar, log: RoutingLog())
        await scheduler.refreshPermission()
        return MenuBarPopoverView(initialNow: now)
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxHeight: .infinity, alignment: .top)
            .background(Tokens.Color.Surface.popover)
            .modelContainer(r.container)
            .environment(r.undo)
            .environment(CalendarState())
            .environment(r.coordinator)
            .environment(scheduler)
    }

    func popover(_ name: String, _ r: TravelRig, now: Date) async {
        render("popover-\(name)", await popoverView(r, now: now), size: CGSize(width: Tokens.Size.popoverWidth, height: 420))
    }

    func status(_ name: String, _ r: TravelRig, now: Date, width: CGFloat = 180) -> String? {
        let result = NextUpProvider.evaluate(events: r.events(), now: now, legs: legs(r), calendar: F.calendar)
        let view = StatusItemLabel(result: result, now: now, available: width).padding(6).background(Tokens.Color.Surface.popover)
        render("status-item-\(name)", view, size: CGSize(width: width + 12, height: 34))
        return StatusItemLabel.text(for: result, now: now, available: width)
    }

    // MARK: Items 5, 6, 8, 12, 20 — Week `M` and Sun 25 Oct, after F01

    @Test("Items 5, 6, 8: Week M (19–25 Oct) with Climbing on the 18:00 row; Day Sun 25 Oct")
    func weekAndDay() async throws {
        guard F.calendar.timeZone == TimeZone.current else { return }   // the views draw in the Mac's zone
        let rig = try await travelRig()
        let climbing = try require(rig.events().first { $0.title == "Climbing" })
        #expect(F.calendar.isDate(climbing.start, inSameDayAs: F.date("2026-10-25 12:00")))
        #expect(WallClock.minuteOfDay(climbing.start, on: climbing.start, calendar: F.calendar) == 18 * 60)
        #expect(rig.coordinator.travelInfo()[climbing.id]?.band.map { F.calendar.dateComponents([.hour, .minute], from: $0.departAt) }
                == DateComponents(hour: 17, minute: 45))
        canvas("week-M-travel", rig, days: Self.week)
        canvas("day-sun-climbing", rig, days: [Self.week[6]])
    }

    @Test("Items 12 and 20: Week M without Home's address, and offline (estimates)")
    func weekVariants() async throws {
        guard F.calendar.timeZone == TimeZone.current else { return }
        canvas("week-M-no-address", try await travelRig(.travelNoAddress), days: Self.week)
        canvas("week-M-estimates", try await travelRig(.travelOffline), days: Self.week)
    }

    // MARK: Item 13 — the `unavailable` status item row

    @Test("Item 13: status item `unavailable` — `18:30 · Dinner with flatmat…`")
    func statusUnavailable() async throws {
        let rig = try TravelRig(now: F.m(3, "11:50"), variant: .travelOffline,
                                provider: ReviewTravel.provider(dataset: .travel, variant: .travelOffline))
        rig.keepAlive()
        await rig.launchAndSettle()
        for title in ["EPC-ILV", "REQEN-EXAM"] { try require(rig.event(title, day: 3)).status = .done }
        let text = status("unavailable", rig, now: F.m(3, "17:30"))
        #expect(text?.hasPrefix("18:30 · Dinner with flatmat") == true)
    }

    // MARK: Item 15 — pending and from where you are

    @Test("Item 15: popover `pending` (Thu 11:50) and `from where you are` (Thu 12:00)")
    func popoverPendingAndHere() async throws {
        let pending = try TravelRig(now: F.m(3, "11:50"), variant: .travelPending,
                                    provider: ReviewTravel.provider(dataset: .travel, variant: .travelPending))
        pending.keepAlive()
        // The provider never answers: launch only, never settle (as
        // `MenuBarLeaveTests` and `ReviewTravelTests` drive it).
        pending.coordinator.launched()
        let pendingResult = NextUpProvider.evaluate(events: pending.events(), now: F.m(3, "11:50"), legs: legs(pending),
                                                    calendar: F.calendar)
        #expect(MenuBarFormatting.leaveLine(pendingResult, now: F.m(3, "11:50"), placeNames: pending.coordinator.placeNames(),
                                            calendar: F.calendar)?.text == "Travel time from Home not worked out yet")
        await popover("pending", pending, now: F.m(3, "11:50"))

        let fix = LocationFix(latitude: MockLocationSource.cafe.latitude, longitude: MockLocationSource.cafe.longitude,
                              horizontalAccuracy: 50, timestamp: F.m(3, "11:30"))
        let here = try TravelRig(now: F.m(3, "11:00"), location: MockLocationSource(authorization: .allowed, fix: .absolute(fix)))
        here.keepAlive()
        await here.launchAndSettle()
        await here.run(until: F.m(3, "12:00"))
        let hereResult = NextUpProvider.evaluate(events: here.events(), now: F.m(3, "12:00"), legs: legs(here), calendar: F.calendar)
        #expect(MenuBarFormatting.leaveLine(hereResult, now: F.m(3, "12:00"), placeNames: here.coordinator.placeNames(),
                                            calendar: F.calendar)?.text == "Leave by 12:22 · 28 min from where you are")
        await popover("from-here", here, now: F.m(3, "12:00"))
    }

    // MARK: Item 16 — the live event P6 between 07:00 and 20:00

    @Test("Item 16: status item and popover for P6 at Thu 12:00, and the plan the launch records")
    func live() async throws {
        guard F.calendar.timeZone == TimeZone.current else { return }
        let rig = try TravelRig(now: Self.noon, m: Self.m, liveEvent: true)
        rig.keepAlive()
        let centre = RecordingNotificationCenter(authorization: .allowed)
        let scheduler = NotificationScheduler(context: rig.context, centre: centre, clock: rig.clock, calendar: F.calendar,
                                              log: RoutingLog(category: "notifications"))
        await rig.launchAndSettle()
        rig.clock.set(Self.noon)
        let parcel = try require(rig.events().first { $0.title == "Pick up parcel" })
        #expect(parcel.start == F.date("2026-10-15 13:00"))
        let text = status("live", rig, now: Self.noon)
        #expect(text == "Leave 12:15 · Pick up parcel")
        await popover("live", rig, now: Self.noon)

        // The plan as a launch at this clock records it (ReviewEvidence's form).
        let plan = scheduler.makePlan(now: Self.noon, catchUp: true)
        var names = Dictionary(rig.events().map { ($0.id.uuidString, $0.title) }, uniquingKeysWith: { a, _ in a })
        names[TravelDataset.sourceID] = "source"
        let dump = "# Notification plan recorded at Thu 15 Oct 2026 12:00 (Europe/Vienna) — dataset travel, M = Mon 19 Oct,\n"
            + "# live event P6; the launch pass, recording centre, mocks only (F05RenderTests).\n\n"
            + NotificationPlanText.blocks(plan, names: names, calendar: F.calendar)
        #expect(plan.first?.text.title == "Leave by 12:15 for Pick up parcel")
        if ProcessInfo.processInfo.environment["KADENCE_CAPTURE_DIR"].map({ !$0.isEmpty }) == true {
            Attachment.record(Data(dump.utf8), named: "notification-plan-live-\(Self.suffix).txt")
        }
    }

    // MARK: Item 17 — phase3, Week M after F01

    @Test("Item 17: phase3 Week M (19–25 Oct) — Sunday's routine blocks at their wall-clock rows")
    func phase3Week() async throws {
        guard F.calendar.timeZone == TimeZone.current else { return }
        let rig = try TravelRig(now: Self.noon, seed: false, provider: ReviewTravel.provider(dataset: .phase3, variant: nil))
        rig.keepAlive()
        let weekEnd = F.calendar.date(byAdding: .day, value: 7, to: Self.m)!
        let fixtures = ReviewMode.seedIfRequested(.phase3, context: rig.context, now: Self.noon,
                                                  secrets: InMemorySecretStore()) {
            RoutineMaterialization.run(context: rig.context, undo: rig.undo, visibleEnd: weekEnd, today: Self.noon,
                                       calendar: F.calendar)
        }
        await rig.launchAndSettle()
        let sunday = rig.events().filter { $0.origin == .routine && F.calendar.isDate($0.start, inSameDayAs: Self.week[6]) }
        #expect(!sunday.isEmpty)
        canvas("phase3-week-M", rig, days: Self.week, fixtures: fixtures)
    }

    // MARK: Item 1 — Settings ▸ Travel, first run, the whole pane

    @Test("Item 1: Settings ▸ Travel at the first run — tabs, Places, Ways, Buffer, Use where you are")
    func settingsFirstRun() async throws {
        let geocoder = MockPlaceGeocoder()
        let rig = try TravelRig(now: Self.noon, seed: false, geocoder: geocoder)
        rig.keepAlive()
        rig.coordinator.launched()            // F04: the campus at the first launch, no switch
        await rig.run(for: 30)
        #expect(await geocoder.lookupCount == 1)
        // The whole Travel pane, the form the Settings window's Travel tab
        // shows (`TravelSettingsPane` → `TravelSettingsForm`), tall enough for
        // every section. Offscreen a `TabView` draws no tab bar (in a window
        // it is the toolbar), so the three tabs are not in this frame (B55).
        let model = TravelSettingsModel(context: rig.context, queue: rig.queue, clock: rig.clock,
                                        calendar: F.calendar, recompute: {})
        #expect(model.places.map(\.id) == ["home", "campus"])
        // `Use where you are` on (DECISIONS 2026-10-14 defaults); offscreen
        // the window is never key, so the switch draws grey, knob right.
        #expect(model.usesCurrentLocation)
        let height: CGFloat = 1000
        let view = TravelSettingsForm(model: model)
            .environment(SourcesRouter())
            .environment(rig.coordinator)
            .frame(width: Tokens.Size.settingsWindowWidth, height: height)
        render("settings-travel-first-run", view, size: CGSize(width: Tokens.Size.settingsWindowWidth, height: height))
    }

    // MARK: Item 22 — the cursor case

    @Test("Item 22: the cursor at 10:18 in Week drops `10:00`")
    func cursor() {
        let hour = Tokens.Size.hourHeightWeek
        let g = TimeGeometry(dayStart: F.date("2026-10-18 00:00"), hourHeight: hour, calendar: F.calendar)
        let cursor = F.date("2026-10-18 10:18")
        let gutter = TimeGutterView(geometry: g, now: F.date("2026-10-18 06:00"), showsNow: false, cursor: cursor)
        #expect(GutterLabelLayout.isSuppressed(hour: 10, hourHeight: hour, markerYs: gutter.markerYs))
        let top = 8 * hour, height = 5 * hour
        let view = HStack(alignment: .top, spacing: 0) {
            gutter.frame(width: Tokens.Size.timeGutterWidth, height: 24 * hour, alignment: .top)
            ZStack(alignment: .top) {
                HourLinesLayer(geometry: g)
                Rectangle().fill(Tokens.Color.Interactive.accent).frame(height: 1)
                    .offset(y: g.y(for: cursor))
            }
            .frame(width: 160, height: 24 * hour, alignment: .top)
        }
        .offset(y: -top)
        .frame(width: Tokens.Size.timeGutterWidth + 160, height: height, alignment: .top)
        .clipped()
        // A canvas margin past the column, so the accent cursor line ends
        // inside the frame (§17.2 rule 6's edge band).
        .padding(.trailing, 12)
        .background(Tokens.Color.Surface.canvas)
        render("now-label-cursor-week-1018", view, size: CGSize(width: Tokens.Size.timeGutterWidth + 172, height: height))
    }
}
