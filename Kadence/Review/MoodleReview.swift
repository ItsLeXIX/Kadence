//
//  MoodleReview.swift
//  Kadence
//
//  Phase 3 slice 3 (PHASE3-SLICE3-PLAN.md task 9) — components.md §43.1:
//  the review template, the datasets `moodle` and `moodleOnly`, and
//  `-KadenceFeed <case>`.
//
//  `Fixtures/moodle-review.ics.template` is `fixtures/moodle-2026WS-redacted.ics`
//  byte for byte (CRLF, TAB folding, the lone-TAB lines, entities, emoji)
//  with each `DTSTART` / `DTEND` replaced by `{{M±d HH:mm}}` — the fixture's
//  local Vienna date and time, `d` days from Mon 12 Oct 2026 — and every
//  `DTSTAMP` by `{{NOW}}`. Rendered to UTC `Z` through `WallClock`, so a
//  week that holds a clock change keeps every item at its local time. With
//  `M` = 2026-10-12 it reproduces the fixture (`DTSTAMP` aside).
//

import Foundation
import SwiftData

nonisolated enum MoodleReviewTemplate {
    static var text: String {
        guard let url = Bundle.main.url(forResource: "moodle-review.ics", withExtension: "template"),
              let data = try? Data(contentsOf: url) else { return "" }
        return String(decoding: data, as: UTF8.self)
    }

    /// The fixture's own `M`.
    static let fixtureM = "2026-10-12"

    static func calendar(_ zone: TimeZone) -> Calendar {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = zone
        return cal
    }

    /// `M + d` at `HH:mm`, local, as `yyyyMMdd'T'HHmmss'Z'`.
    static func stamp(days: Int, minuteOfDay: Int, m: Date, zone: TimeZone) -> String {
        let cal = calendar(zone)
        let day = cal.date(byAdding: .day, value: days, to: cal.startOfDay(for: m)) ?? m
        return ICSFormat.utcStamp(WallClock.moment(minuteOfDay: minuteOfDay, on: day, calendar: cal))
    }

    /// Renders `{{M±d HH:mm}}` and `{{NOW}}`.
    static func render(_ template: String, m: Date, now: Date, zone: TimeZone) -> String {
        var out = template.replacingOccurrences(of: "{{NOW}}", with: ICSFormat.utcStamp(now))
        let pattern = /\{\{M([+-])(\d+) (\d\d):(\d\d)\}\}/
        while let match = out.firstMatch(of: pattern) {
            let sign = match.1 == "-" ? -1 : 1
            let days = sign * (Int(match.2) ?? 0)
            let minute = (Int(match.3) ?? 0) * 60 + (Int(match.4) ?? 0)
            out.replaceSubrange(match.range, with: stamp(days: days, minuteOfDay: minute, m: m, zone: zone))
        }
        return out
    }

    /// The feed cases' inserted dates (written as the fixture's UTC values)
    /// moved to `m`'s week at the same local time — identity for `M` = 12 Oct.
    static func shift(m: Date, zone: TimeZone) -> @Sendable (String) -> String {
        let vienna = TimeZone(identifier: "Europe/Vienna") ?? zone
        return { value in
            let f = DateFormatter()
            f.locale = Locale(identifier: "en_US_POSIX")
            f.timeZone = TimeZone(identifier: "UTC")
            f.dateFormat = "yyyyMMdd'T'HHmmss'Z'"
            guard let instant = f.date(from: value) else { return value }
            let fixtureCal = calendar(vienna)
            let base = DateComponents(calendar: fixtureCal, year: 2026, month: 10, day: 12).date ?? instant
            let days = fixtureCal.dateComponents([.day], from: base, to: fixtureCal.startOfDay(for: instant)).day ?? 0
            let parts = fixtureCal.dateComponents([.hour, .minute], from: instant)
            return stamp(days: days, minuteOfDay: (parts.hour ?? 0) * 60 + (parts.minute ?? 0), m: m, zone: zone)
        }
    }
}

nonisolated enum MoodleReview {
    /// The review Moodle source's id: fixed, so a second seeding finds it.
    static let sourceID = "review-moodle"

    /// `-KadenceFeed <case>` (moodle-mocks.md), default `feedOK`.
    static func feedCase(_ defaults: UserDefaults = .standard) -> MoodleFeedCase {
        defaults.string(forKey: "KadenceFeed").flatMap(MoodleFeedCase.init(rawValue:)) ?? .feedOK
    }

    /// The review launch's mock feed: the template rendered at `m`.
    static func transport(case feedCase: MoodleFeedCase, m: Date, now: Date, zone: TimeZone) -> MockFeedTransport {
        MockFeedTransport(case: feedCase, base: MoodleReviewTemplate.render(MoodleReviewTemplate.text, m: m, now: now, zone: zone),
                          shift: MoodleReviewTemplate.shift(m: m, zone: zone))
    }

    /// §43.1 `moodle` (`withTravel`) and `moodleOnly`. Idempotent.
    @MainActor
    static func seed(context: ModelContext, now: Date, m: Date, zone: TimeZone, secrets: any SecretStore,
                     withTravel: Bool, template: String = MoodleReviewTemplate.text,
                     travelTemplate: String = ReviewTravelTemplate.text,
                     travelVariant: TravelDataset.Variant? = nil, liveEvent: Bool = false) {
        if withTravel {
            TravelDataset.seed(context: context, now: now, m: m, zone: zone, variant: travelVariant,
                               liveEvent: liveEvent, template: travelTemplate)
        } else {
            BuiltInSource.ensure(in: context)
            TravelBuiltIns.ensure(in: context)
            // `Sleep` 22:00–07:00, every day (the menu bar and the
            // notification tables depend on nothing but deadlines and it).
            let windows = (try? context.fetch(FetchDescriptor<TimeWindow>())) ?? []
            if !windows.contains(where: { $0.label == "Sleep" }) {
                context.insert(TimeWindow(weekdays: Set(1...7), startMinutes: 22 * 60, endMinutes: 7 * 60,
                                          kind: .protected, label: "Sleep"))
            }
        }
        TravelBuiltIns.ensure(in: context)
        let sources = (try? context.fetch(FetchDescriptor<Source>())) ?? []
        guard !sources.contains(where: { $0.id == sourceID }), let url = MoodleMock.url else {
            try? context.save()
            return
        }
        // `teal` (§43.1): the next free slot when the timetable holds blue,
        // and the same source in `moodleOnly`.
        let source = Source.moodleFeed(id: sourceID, host: url.host, paletteKey: .teal)
        context.insert(source)
        try? secrets.saveFeedURL(url, sourceID: source.id, label: feedItemLabel(displayName: source.displayName))
        // Seeded as already imported from `feedOK` at the clock's today
        // (§22.1's rule): the Import's planner and applier, no request.
        let body = Data(MoodleReviewTemplate.render(template, m: m, now: now, zone: zone).utf8)
        if case .calendar(let feed) = MoodleProfile.read(body, zone: zone) {
            let fetch = FeedFetch(feed: feed, requests: 1, milliseconds: 0, bytes: body.count)
            let plan = FeedSyncPlanner.plan(existing: [], source: FeedSyncApplier.sourceSnapshot(source), fetch: fetch,
                                            kind: .import, now: now, zone: zone)
            _ = try? FeedSyncApplier.apply(plan, to: source, context: context, now: now)
        }
        // `900004` done, `markedDoneDueAt` = its start.
        if let retake = SyncApplier.events(of: source, in: context)
            .first(where: { $0.externalID?.hasPrefix("900004@") == true }) {
            retake.status = .done
            retake.markedDoneDueAt = retake.start
        }
        // The launch sync still runs and reaches `-KadenceFeed`'s case.
        source.lastAttemptAt = nil
        try? context.save()
    }
}
