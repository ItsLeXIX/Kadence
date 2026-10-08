//
//  ImportedInspectorTests.swift
//  KadenceTests
//
//  PHASE3-PLAN.md task 16: refusals, the imported inspector rows, the menu
//  bar for an imported NEXT, undo (layouts.md §6.1; interactions.md §13.4,
//  §13.5; components.md §18.1, §18.3).
//

import Testing
import Foundation
import SwiftData
@testable import Kadence

@MainActor
@Suite(.serialized)
struct ImportedInspectorTests {

    private func rig() throws -> (ModelContext, EventStore, UndoStack, Event) {
        let container = try ModelContainer(for: Schema(KadenceSchema.models),
                                           configurations: ModelConfiguration(isStoredInMemoryOnly: true))
        let context = ModelContext(container)
        let undo = UndoStack()
        let start = TestClock.date("2026-10-12 09:00")
        let event = Event(title: "SWQM-ILV", start: start, end: start + 5400, origin: .imported, sourceKey: .blue,
                          location: Place(name: "HS_A3.15"), sourceID: "timetable", externalID: "k")
        event.courseCode = "SWQM-ILV"; event.group = "BIF-5C"; event.lecturers = ["L01"]
        context.insert(event)
        try context.save()
        Phase3Render.keep.append(container)
        return (context, EventStore(context: context, undo: undo), undo, event)
    }

    // MARK: Refusals (§13.4's table)

    @Test("Every refused gesture leaves the store unchanged; keyboard paths sound; emphasis 0.6 s; inspector untouched")
    func refusals() throws {
        let (context, store, _, event) = try rig()
        let state = CalendarState()
        var sounds = 0
        state.playRefusalSound = { sounds += 1 }
        state.isInspectorVisible = false
        let before = (event.start, event.end, event.status)
        let cases: [(ReadOnlyGate.Gesture, Bool)] = [
            (.drag, false), (.duplicateDrag, false), (.delete, true), (.moveKey, true), (.resizeKey, true),
            (.doubleClick, false),
        ]
        for (gesture, sound) in cases {
            let soundsBefore = sounds
            let now = TestClock.now
            #expect(!state.permits(gesture, on: event, now: now), "\(gesture)")
            #expect((sounds - soundsBefore == 1) == sound, "\(gesture) sound")
            #expect(state.readOnlyEmphasis && state.readOnlyEmphasisUntil == now.addingTimeInterval(0.6))
        }
        // The six ⌥ keys are moveKey (⌥←, ⌥→, ⌥↑, ⌥↓) and resizeKey (⌥⇧↑, ⌥⇧↓): both refused above.
        #expect(event.start == before.0 && event.end == before.1 && event.status == before.2)
        #expect(try context.fetchCount(FetchDescriptor<Event>()) == 1)
        #expect(!state.isInspectorVisible)
        // Done / skip are allowed …
        #expect(state.permits(.done, on: event) && state.permits(.skip, on: event))
        // … and refused on a cancelled event.
        event.isCancelled = true
        let s = sounds
        #expect(!state.permits(.done, on: event) && !state.permits(.skip, on: event))
        #expect(sounds == s + 2)
        // Non-imported events pass.
        let manual = Event(title: "Coffee", start: event.start, end: event.end)
        #expect(state.permits(.delete, on: manual) && state.permits(.moveKey, on: manual))
        // The store itself refuses to move or resize an imported event.
        event.isCancelled = false
        store.move(event, by: 900)
        store.resize(event, newEnd: event.end + 900)
        #expect(event.start == before.0 && event.end == before.1)
    }

    // MARK: Lecturer rows

    @Test("Lecturers: 1 → Lecturer; 2–4 all; 5 → 3 + and 2 more; 22 → 3 + and 19 more; expanded → all + Show fewer; AX")
    func lecturers() {
        let names = (10...31).map { "L\($0)" }
        #expect(ImportedInspectorCopy.lecturersLabel(["L01"]) == "Lecturer")
        #expect(ImportedInspectorCopy.lecturersLabel(["L05", "L06"]) == "Lecturers")
        for n in 2...4 {
            let lines = ImportedInspectorCopy.lecturerLines(Array(names.prefix(n)), expanded: false)
            #expect(lines.names.count == n && lines.button == nil)
        }
        let five = ImportedInspectorCopy.lecturerLines(Array(names.prefix(5)), expanded: false)
        #expect(five.names == ["L10", "L11", "L12"] && five.button == "and 2 more")
        let all = ImportedInspectorCopy.lecturerLines(names, expanded: false)
        #expect(all.names == ["L10", "L11", "L12"] && all.button == "and 19 more")
        let open = ImportedInspectorCopy.lecturerLines(names, expanded: true)
        #expect(open.names.count == 22 && open.button == "Show fewer")
        #expect(ImportedInspectorCopy.lecturersAccessibilityValue(names) == "22 lecturers: " + names.joined(separator: ", "))
        #expect(ImportedInspectorCopy.lecturersButtonAccessibility(22, expanded: false) == "Show all 22 lecturers")
        #expect(ImportedInspectorCopy.lecturersButtonAccessibility(22, expanded: true) == "Show fewer lecturers")
    }

    @Test("Location label: Room vs Location by profile; Online · WEBINAR01; read-only and cancelled lines")
    func locationAndLines() {
        #expect(ImportedInspectorCopy.locationLabel(isCISProfile: true) == "Room")
        #expect(ImportedInspectorCopy.locationLabel(isCISProfile: false) == "Location")
        #expect(ImportedInspectorCopy.locationValue("WEBINAR01", isOnline: true) == "Online · WEBINAR01")
        #expect(ImportedInspectorCopy.locationValue("HS_A3.15", isOnline: false) == "HS_A3.15")
        #expect(ImportedInspectorCopy.readOnlyLine(sourceName: "University timetable", isCancelled: false)
                == "Read-only — from University timetable")
        #expect(ImportedInspectorCopy.readOnlyLine(sourceName: "University timetable", isCancelled: true)
                == "Cancelled by University timetable")
    }

    @Test("Description: no row for a CIS event, and sync never writes notes")
    func description() async throws {
        let f = try SyncFixture()
        try await f.run(MockHarness(.reportOK), kind: .import)
        #expect(f.events.allSatisfy { $0.importedDescription == nil && $0.notes.isEmpty })
        let generic = FeedDerivation.derive([FeedObject(calendarHref: "", objectHref: "",
                                                        calendar: CISFeed.parse(try Fixture.text("edge-cases.ics")))],
                                            today: TestClock.now, zone: TestClock.zone)
        let escaped = try #require(generic.events.first { $0.externalID == "edge-escaped@kadence.test" })
        let event = Event(title: "", start: .now, end: .now)
        event.notes = "mine"
        event.applyUpstream(escaped)
        #expect(event.importedDescription?.hasPrefix("First line") == true && event.notes == "mine")
    }

    @Test("Link: the host, opened through NSWorkspace (stubbed)")
    func link() {
        #expect(ImportedInspectorCopy.linkTitle("https://example.invalid/course/42") == "example.invalid")
        var opened: URL?
        let original = LinkOpener.open
        LinkOpener.open = { opened = $0 }
        defer { LinkOpener.open = original }
        LinkOpener.open(URL(string: "https://example.invalid/course/42")!)
        #expect(opened?.host() == "example.invalid")
    }

    // MARK: Menu bar

    @Test("The popover's action set for an imported NEXT, normal and late; the refusal row's text and AX label")
    func menuBar() throws {
        #expect(MenuBarPopoverKeys.actionButtons(isLate: false, isImported: true).map(\.title) == ["Done", "Open"])
        #expect(MenuBarPopoverKeys.actionButtons(isLate: true, isImported: true).map(\.title) == ["Done", "Open"])
        #expect(MenuBarPopoverKeys.actionButtons(isLate: true).map(\.title) == ["Re-offer", "Done", "Snooze", "Open"])
        let (_, store, undo, event) = try rig()
        let row = try #require(MenuBarPopoverView.SnoozeConfirmation.perform(event, store: store))
        #expect(row.refusalLines == MenuBarFormatting.RefusalLines(first: "Not moved — SWQM-ILV",
                                                                  second: "is read-only (University timetable)"))
        #expect(row.text == "Not moved — SWQM-ILV is read-only (University timetable)")
        #expect(row.isRefusal && row.expectedStart == event.start)
        #expect(undo.undoSteps.isEmpty)  // nothing written
    }

    // MARK: Undo

    @Test("Done and skip on an imported event are named undo steps")
    func undo() throws {
        let (_, store, undo, event) = try rig()
        store.toggleDone(event)
        #expect(undo.undoMenuTitle == "Undo Mark Done" && event.status == .done)
        store.toggleSkipped(event)
        #expect(undo.undoMenuTitle == "Undo Skip")
        undo.undo(); undo.undo()
        #expect(event.status == .scheduled)
    }

    @Test("The sync line reads `Access refused` for a forbidden source, `Synced HH:mm` when up to date")
    func syncLine() {
        let source = Source.connected(id: "timetable", displayName: "University timetable",
                                      serverURL: "https://cis.technikum-wien.at", username: "user01", principalHref: nil,
                                      calendarHomeHref: nil, calendars: [], capabilities: SourceCapabilities(), paletteKey: .blue)
        source.state = .forbidden
        #expect(ImportedInspectorCopy.syncLine(source, now: TestClock.now) == "Access refused")
        source.state = .upToDate
        source.lastSuccessAt = TestClock.date("2026-10-08 09:02")
        #expect(ImportedInspectorCopy.syncLine(source, now: TestClock.now) == "Synced 09:02")
        #expect(ImportedInspectorCopy.syncLine(nil, now: TestClock.now) == nil)
    }

    @Test("VoiceOver: the block's label adds `cancelled`")
    func voiceOver() throws {
        let (_, _, _, event) = try rig()
        event.isCancelled = true
        #expect(GridBlockModel(event: event, now: TestClock.now).accessibilityLabel(presentation: []).hasSuffix(", cancelled"))
    }
}
