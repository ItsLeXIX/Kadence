//
//  MenuBarLeaveTests.swift
//  KadenceTests
//
//  PHASE3-SLICE2-PLAN.md task 17 — components.md §26 (status item, popover,
//  last lines), §29; §30 items 13 and 15. Dataset `travel` with legs from
//  the real coordinator at each pinned clock.
//

import Testing
import Foundation
import SwiftData
import SwiftUI
@testable import Kadence

@MainActor
@Suite(.serialized)
struct MenuBarLeaveTests {
    typealias F = TravelFixtures

    func legs(_ rig: TravelRig) -> [UUID: LegValues] {
        Dictionary(uniqueKeysWithValues: rig.legs().map { ($0.eventID, LegValues($0)) })
    }

    func result(_ rig: TravelRig, at now: Date) -> NextUpProvider.Result {
        NextUpProvider.evaluate(events: rig.events(), now: now, legs: legs(rig), calendar: F.calendar)
    }

    func rig(_ clock: String, variant: TravelDataset.Variant? = nil) async throws -> TravelRig {
        let rig = try TravelRig(now: F.m(3, clock), variant: variant,
                                provider: variant.map { ReviewTravel.provider(dataset: .travel, variant: $0) })
        await rig.launchAndSettle()
        return rig
    }

    func text(_ r: NextUpProvider.Result, _ now: Date, width: CGFloat = 180) -> String? {
        StatusItemLabel.text(for: r, now: now, available: width)
    }

    @Test("§30 item 13: the eight rows — state and string at each clock and width")
    func item13() async throws {
        let morning = try await rig("11:50")
        let at1150 = F.m(3, "11:50")
        let r1 = result(morning, at: at1150)
        #expect(r1.next?.title == "EPC-ILV" && r1.state(now: at1150) == .leave(departAt: F.m(3, "12:15"), isEstimate: false))
        #expect(text(r1, at1150) == "Leave 12:15 · EPC-ILV")
        #expect(text(r1, at1150, width: 110) == "Leave 12:15")
        let at1220 = F.m(3, "12:20")
        let r3 = result(morning, at: at1220)
        #expect(r3.state(now: at1220) == .leaveNow(departAt: F.m(3, "12:15"), isEstimate: false))
        #expect(text(r3, at1220) == "Leave now · EPC-ILV" && StatusItemLabel.showsGlyph(r3, now: at1220))
        let at1305 = F.m(3, "13:05")
        #expect(text(result(morning, at: at1305), at1305) == "5m ago · EPC-ILV")
        // Takeover at 17:20 (EPC-ILV and REQEN-EXAM not done), not at 17:10.
        let at1720 = F.m(3, "17:20")
        let takeover = result(morning, at: at1720)
        #expect(takeover.next?.title == "Dinner with flatmates" && takeover.restOfToday.first?.title == "EPC-ILV")
        let takeoverText = try require(text(takeover, at1720))
        #expect(takeoverText.hasPrefix("Leave 17:45 · Dinner with") && takeoverText.hasSuffix("…"))
        let at1710 = F.m(3, "17:10")
        let late = result(morning, at: at1710)
        #expect(late.next?.title == "EPC-ILV" && late.isLate)
        #expect(text(late, at1710) == "250m ago · EPC-ILV")
        // travelOffline: an estimate; then an unavailable NEXT is Normal.
        let offline = try await rig("11:50", variant: .travelOffline)
        #expect(text(result(offline, at: at1150), at1150) == "Leave ≈12:15 · EPC-ILV")
        for title in ["EPC-ILV", "REQEN-EXAM"] { try require(offline.event(title, day: 3)).status = .done }
        let unavailable = result(offline, at: at1720)
        #expect(unavailable.next?.title == "Dinner with flatmates" && unavailable.state(now: at1720) == .normal)
        // Normal (no time to leave by): the start time, the title truncated
        // by §15.1's measured rule at 180pt (G-099: §30 shows it whole).
        let normal = try require(text(unavailable, at1720))
        #expect(normal.hasPrefix("18:30 · Dinner with") && !normal.contains("Leave"))
    }

    @Test("Leave now offers no Re-offer; an imported NEXT offers Done · Open; a manual one Done · Snooze · Open")
    func actions() {
        #expect(MenuBarPopoverKeys.actionButtons(isLate: false, isImported: true).map(\.kind) == [.done, .open])
        #expect(MenuBarPopoverKeys.actionButtons(isLate: false, isImported: false).map(\.kind) == [.done, .snooze, .open])
    }

    @Test("The leave line's seven forms and tones; semantic.now only in Leave now")
    func leaveLine() async throws {
        let morning = try await rig("11:50")
        let names = morning.coordinator.placeNames()
        func line(_ r: NextUpProvider.Result, _ now: Date) -> MenuBarFormatting.LeaveLine? {
            MenuBarFormatting.leaveLine(r, now: now, placeNames: names, calendar: F.calendar)
        }
        let at1150 = F.m(3, "11:50")
        #expect(line(result(morning, at: at1150), at1150) == .init(text: "Leave by 12:15 · 35 min from Home", tone: .primary))
        let at1220 = F.m(3, "12:20")
        #expect(line(result(morning, at: at1220), at1220) == .init(text: "Leave now · leave-by was 12:15", tone: .now))
        #expect(line(result(morning, at: F.m(3, "13:05")), F.m(3, "13:05")) == nil)
        let offline = try await rig("11:50", variant: .travelOffline)
        #expect(line(result(offline, at: at1150), at1150) == .init(text: "Leave by ≈12:15 · estimate, offline", tone: .primary))
        for title in ["EPC-ILV", "REQEN-EXAM"] { try require(offline.event(title, day: 3)).status = .done }
        let at1730 = F.m(3, "17:30")
        #expect(line(result(offline, at: at1730), at1730) == .init(text: "Travel time unavailable · offline", tone: .secondary))
        let noAddress = try TravelRig(now: at1150, variant: .travelNoAddress)
        noAddress.coordinator.launched()
        #expect(line(result(noAddress, at: at1150), at1150)?.text == "Travel time unavailable · Home has no address")
        let pending = try TravelRig(now: at1150, variant: .travelPending,
                                    provider: ReviewTravel.provider(dataset: .travel, variant: .travelPending))
        pending.coordinator.launched()
        #expect(line(result(pending, at: at1150), at1150) == .init(text: "Travel time from Home not worked out yet", tone: .secondary))
        // From where you are (Thu 12:00, the mock fix `cafe`).
        let fix = LocationFix(latitude: MockLocationSource.cafe.latitude, longitude: MockLocationSource.cafe.longitude,
                              horizontalAccuracy: 50, timestamp: F.m(3, "11:30"))
        let here = try TravelRig(now: F.m(3, "11:00"), location: MockLocationSource(authorization: .allowed, fix: .absolute(fix)))
        await here.launchAndSettle()
        await here.run(until: F.m(3, "12:00"))
        let at1200 = F.m(3, "12:00")
        #expect(line(result(here, at: at1200), at1200)?.text == "Leave by 12:22 · 28 min from where you are")
        // No leg: omitted.
        let routine = Event(title: "Training", start: F.m(3, "11:55"), end: F.m(3, "12:40"), origin: .routine,
                            sourceID: "routine")
        let r = NextUpProvider.evaluate(events: [routine], now: at1150, legs: [:], calendar: F.calendar)
        #expect(line(r, at1150) == nil)
    }

    @Test("The meta line: `13:00 – 14:30 · LAB_F5.12 · University timetable`; `17:30 – 18:15 · Daily routine`")
    func metaLine() async throws {
        let rig = try TravelRig(now: F.m(3, "06:00"))
        SourceCatalog.install(.testTimetable)
        let epc = try require(rig.event("EPC-ILV", day: 3))
        #expect(MenuBarFormatting.nextMeta(for: epc, now: F.m(3, "06:00"), isLate: false)
                == "13:00 – 14:30 · LAB_F5.12 · University timetable")
        let training = Event(title: "Training", start: F.m(3, "17:30"), end: F.m(3, "18:15"), origin: .routine,
                             sourceID: "routine")
        #expect(MenuBarFormatting.nextMeta(for: training, now: F.m(3, "06:00"), isLate: false) == "17:30 – 18:15 · Daily routine")
        let inno = try require(rig.event("INNO3-EL", day: 2))
        #expect(MenuBarFormatting.nextMeta(for: inno, now: F.m(2, "06:00"), isLate: false)
                == "14:00 – 15:30 · Online · University timetable")
    }

    @Test("The notifications line in off / notAllowedYet; none in allowed, notAsked, or with every rule off")
    func notificationsLine() {
        #expect(MenuBarFormatting.notificationsLine(.off, anyRuleOn: true) == "Notifications are off, so Kadence can't tell you when to leave.")
        #expect(MenuBarFormatting.notificationsLine(.notAllowedYet, anyRuleOn: true) == "Notifications aren't allowed yet. Settings ▸ Notifications")
        #expect(MenuBarFormatting.notificationsLine(.allowed, anyRuleOn: true) == nil)
        #expect(MenuBarFormatting.notificationsLine(.notAsked, anyRuleOn: true) == nil)
        #expect(MenuBarFormatting.notificationsLine(.off, anyRuleOn: false) == nil)
    }

    @Test("§29: the status item's and the popover's labels")
    func labels() async throws {
        SourceCatalog.install(.testTimetable)
        let morning = try await rig("11:50")
        let at1150 = F.m(3, "11:50"), at1220 = F.m(3, "12:20")
        #expect(MenuBarFormatting.statusAccessibilityLabel(result(morning, at: at1150), now: at1150) == "Leave by 12:15 for EPC-ILV")
        #expect(MenuBarFormatting.statusAccessibilityLabel(result(morning, at: at1220), now: at1220)
                == "Leave now for EPC-ILV, leave-by was 12:15")
        let names = morning.coordinator.placeNames()
        #expect(MenuBarFormatting.nextAccessibilityValue(result(morning, at: at1150), now: at1150, placeNames: names)
                == "Leave by 12:15, 35 minutes from Home. 13:00 to 14:30, LAB_F5.12, University timetable")
        #expect(MenuBarFormatting.nextAccessibilityValue(result(morning, at: at1220), now: at1220, placeNames: names)?
                    .hasPrefix("Leave now, leave-by was 12:15. ") == true)
        let offline = try await rig("11:50", variant: .travelOffline)
        #expect(MenuBarFormatting.statusAccessibilityLabel(result(offline, at: at1150), now: at1150)
                == "Leave by about 12:15 for EPC-ILV, estimate")
    }

    // MARK: Renders

    @Test("Task 17 renders: item 13's status item rows and item 15's popover states")
    func renders() async throws {
        SourceCatalog.install(.testTimetable)
        let morning = try await rig("11:50")
        let offline = try await rig("11:50", variant: .travelOffline)
        func status(_ name: String, _ r: TravelRig, _ clock: String, width: CGFloat = 180) {
            let now = F.m(3, clock)
            let view = StatusItemLabel(result: result(r, at: now), now: now, available: width)
                .padding(6).background(Tokens.Color.Surface.popover)
            #expect(Slice2Render.render("status-item-\(name)", view, size: CGSize(width: width + 12, height: 34)) != nil)
        }
        status("leave-full", morning, "11:50")
        status("leave-degraded", morning, "11:50", width: 110)
        status("leave-now", morning, "12:20")
        status("late", morning, "13:05")
        status("takeover", morning, "17:20")
        status("no-takeover", morning, "17:10")
        status("estimate", offline, "11:50")

        func popover(_ name: String, _ r: TravelRig, _ clock: String,
                     permission: NotificationAuthorization = .allowed, asked: Bool = false, dark: Bool = false) async {
            let now = F.m(3, clock)
            let scheduler = NotificationScheduler(context: r.context, centre: RecordingNotificationCenter(authorization: permission),
                                                  clock: r.clock, calendar: F.calendar, log: RoutingLog())
            TravelBuiltIns.settings(in: r.context).notificationsRequestedAt = asked ? now : nil
            await scheduler.refreshPermission()
            let view = MenuBarPopoverView(initialNow: now)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxHeight: .infinity, alignment: .top)
                .background(Tokens.Color.Surface.popover)
                .modelContainer(r.container)
                .environment(r.undo)
                .environment(CalendarState())
                .environment(r.coordinator)
                .environment(scheduler)
            #expect(Slice2Render.render("popover-\(name)", view, size: CGSize(width: Tokens.Size.popoverWidth, height: 420),
                                        dark: dark) != nil)
        }
        await popover("leave", morning, "11:50")
        await popover("leave-now", morning, "12:20")
        await popover("leave-now-dark", morning, "12:20", dark: true)
        await popover("late", morning, "13:05")
        await popover("takeover", morning, "17:20")
        await popover("notifications-off", morning, "11:50", permission: .off)
        await popover("notifications-not-allowed-yet", morning, "11:50", permission: .notDetermined, asked: true)
        await popover("estimate", offline, "11:50")
        for title in ["EPC-ILV", "REQEN-EXAM"] { try require(morning.event(title, day: 3)).status = .done }
        await popover("manual-next", morning, "17:30")
        for title in ["EPC-ILV", "REQEN-EXAM"] { try require(offline.event(title, day: 3)).status = .done }
        await popover("unavailable", offline, "17:30")
        let noAddress = try TravelRig(now: F.m(3, "11:50"), variant: .travelNoAddress)
        noAddress.coordinator.launched()
        await popover("no-address", noAddress, "11:50")
    }
}
