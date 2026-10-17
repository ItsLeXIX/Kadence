//
//  MoodleInspectorTests.swift
//  KadenceTests
//
//  PHASE3-SLICE3-PLAN.md task 12 — layouts.md §17; components.md §37.4,
//  §38. The rows' values are task 4's (`MomentInspectorValues`, tested there
//  row by row); here the Status row, the description's collapse, links and
//  VoiceOver, and §43 items 15–17 as offscreen renders (`-p3ct12`).
//

import Testing
import Foundation
import SwiftUI
import SwiftData
@testable import Kadence

private typealias F = MoodleFixture

@MainActor
@Suite(.serialized)
struct MoodleInspectorTests {
    /// The inspector's description width at its default width (320) less
    /// its padding.
    static let width = Tokens.Size.inspectorWidthDefault - 2 * Tokens.Spacing.xl

    @Test("Status: Not done / Done with Mark Done ↔ Mark Not Done; the note; no Skip")
    func status() {
        #expect(MoodleInspectorCopy.statusValue(isDone: false) == "Not done")
        #expect(MoodleInspectorCopy.statusValue(isDone: true) == "Done")
        #expect(MoodleInspectorCopy.statusButton(isDone: false) == "Mark Done")
        #expect(MoodleInspectorCopy.statusButton(isDone: true) == "Mark Not Done")
        #expect(MoodleInspectorCopy.statusNote == "Your own mark — Moodle doesn't say what you've handed in.")
        let source = (try? String(contentsOf: Fixture.repoRoot.appendingPathComponent("Kadence/Views/Sources/MoodleInspector.swift"),
                                  encoding: .utf8)) ?? ""
        #expect(!source.contains("\"Skip\"") && !source.contains("toggleSkipped"))
    }

    @Test("Description: 900004's collapses to 6 lines, a short one does not; Show more / Show less; URLs are links; VoiceOver strings")
    func description() throws {
        let feed = try #require(F.feed())
        let long = try #require(feed.items.first { F.number($0) == "900004" }?.description)
        #expect(MoodleInspectorCopy.renderedLines(long, width: Self.width) > 6)
        #expect(MoodleInspectorCopy.isCollapsible(long, width: Self.width))
        #expect(!MoodleInspectorCopy.isCollapsible("Fixture description 2.", width: Self.width))
        #expect(MoodleInspectorCopy.descriptionButton(expanded: false) == "Show more")
        #expect(MoodleInspectorCopy.descriptionButton(expanded: true) == "Show less")
        #expect(MoodleInspectorCopy.descriptionButtonAccessibility(expanded: false) == "Show more of the description")
        #expect(MoodleInspectorCopy.descriptionButtonAccessibility(expanded: true) == "Show less of the description")
        let text = "See https://moodle.technikum-wien.at/mod/assign/view.php?id=1 and http://example.org, not ftp://x.y."
        #expect(MoodleInspectorCopy.links(text).map(\.absoluteString)
                == ["https://moodle.technikum-wien.at/mod/assign/view.php?id=1", "http://example.org"])
        #expect(String(MoodleInspectorCopy.linked(text).characters) == text)
    }

    // MARK: §43 items 15–17, rendered (`-p3ct12`)

    @Test("§43 items 15–17 render from the real inspector")
    func renders() async throws {
        guard F.calendar.timeZone == TimeZone.current else { return }
        let rig = try MoodleCanvasRig()
        Slice3Render.keep.append(rig.container)
        let suffix = "p3ct12"
        let coordinator = SyncCoordinator(context: rig.context, secrets: InMemorySecretStore(), scheduling: FakeScheduling(),
                                          path: FakePath(), makeSource: { _ in RefusingScheduleSource() })
        Slice3Render.keep.append(coordinator)
        // feedNotice's 900040 and feedChanged's 900031 added to the source.
        let source = try #require(try rig.context.fetch(FetchDescriptor<Source>()).first { $0.id == MoodleReview.sourceID })
        guard case .calendar(let notice) = MoodleProfile.read(F.body(.feedNotice), zone: F.zone),
              case .calendar(let changed) = MoodleProfile.read(F.body(.feedChanged), zone: F.zone) else { return }
        for item in (notice.items + changed.items) where ["900040", "900031"].contains(F.number(item)) {
            let e = Event(title: item.title, start: item.start, end: item.end, origin: .imported, sourceKey: .teal,
                          sourceID: source.id, externalID: item.externalID)
            e.applyMoodle(item)
            rig.context.insert(e)
        }
        try rig.context.save()
        func inspector(_ name: String, _ number: String, expanded: Bool = false, height: CGFloat = 560) throws {
            let event = try #require(rig.event(number))
            let state = CalendarState()
            state.now = rig.now
            state.selectedEventID = event.id
            Slice3Render.keep.append(state)
            let view = MoodleInspectorDetails(event: event, now: rig.now, store: rig.store, expanded: expanded)
                .padding(Tokens.Spacing.xl)
                .frame(width: Tokens.Size.inspectorWidthDefault, alignment: .topLeading)
                .frame(maxHeight: .infinity, alignment: .top)
                .background(Tokens.Color.Surface.inspector)
                .environment(state)
                .environment(coordinator)
                .modelContainer(rig.container)
            #expect(Slice3Render.render(name, view, size: CGSize(width: Tokens.Size.inspectorWidthDefault, height: height),
                                        suffix: suffix, directory: rig.directory) != nil)
        }
        // Item 15.
        try inspector("inspector-900008", "900008")
        try inspector("inspector-900011", "900011")
        try inspector("inspector-900013", "900013")
        try inspector("inspector-900028", "900028")
        try inspector("inspector-notice-900040", "900040")
        try inspector("inspector-900004-collapsed", "900004", height: 700)
        try inspector("inspector-900004-expanded", "900004", expanded: true, height: 1000)
        // Item 16: 900005 done; 900008 done then moved by feedChanged's E1.
        rig.store.toggleDone(try #require(rig.event("900005")))
        try inspector("inspector-900005-done", "900005")
        let e8 = try #require(rig.event("900008"))
        rig.store.toggleDone(e8)
        e8.start = F.date("2026-10-22 12:00"); e8.end = e8.start
        try rig.context.save()
        #expect(e8.dueTimeChangedAfterDone)
        try inspector("inspector-900008-moved", "900008")
        // Item 17: the unpaired opening's inspector.
        try inspector("inspector-opening-900031", "900031")
        // The pills: 900005 done (Tue 13 Oct), 900031 (Thu 10 Dec).
        for (name, day) in [("pill-900005-done", "2026-10-13"), ("pill-opening-900031", "2026-12-10")] {
            let days = [F.date("\(day) 00:00")]
            let state = CalendarState()
            state.now = rig.now
            Slice3Render.keep.append(state)
            let view = ClockChangeCanvas(mode: .day, days: days, events: [], fixtures: rig.fixtures, now: rig.now,
                                         store: rig.store, state: state)
            #expect(Slice3Render.render(name, view, size: CGSize(width: Tokens.Size.timeGutterWidth + 420, height: 200),
                                        suffix: suffix, directory: rig.directory) != nil)
        }
        let opening = try #require(rig.fixtures.allDay.first { $0.eventID == rig.event("900031")?.id })
        #expect(opening.moment?.glyph == "lock.open.fill")
    }
}
