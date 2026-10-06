//
//  PopoverCaptureTests.swift
//  KadenceTests
//
//  Task P2-T48: components.md §17 items 11 (popover normal / late / empty /
//  rest-row overflow) and 12 (the snooze result row, same-day and next-day),
//  with §17.1's exact fixtures. §17.1 pins `now` (17:10, 17:42, 23:40), which
//  the real menu bar can't be set to, and in this environment the status item
//  is hidden off the visible menu bar, so its popover can't be opened. So the
//  real `MenuBarPopoverView` is rendered offscreen against an in-memory store
//  holding the fixture. The NextUpProvider assertions check the content the
//  render shows. With `KADENCE_CAPTURE_DIR` set (passed to the runner as
//  `TEST_RUNNER_KADENCE_CAPTURE_DIR`), each render is written as a PNG to the
//  sandboxed host's temp directory (`kadence-captures`).
//

import Testing
import Foundation
import SwiftUI
import SwiftData
import AppKit
@testable import Kadence

private func at(_ hour: Int, _ minute: Int, day: Int = 5) -> Date {
    Calendar.current.date(from: DateComponents(year: 2026, month: 10, day: day, hour: hour, minute: minute))!
}

/// §17.1 item 11's rest of today, nine rows.
private let restRows: [(String, Int, Int)] = [
    ("Code review", 18, 30), ("Dinner", 19, 0), ("Reading", 19, 30), ("Mail triage", 20, 0),
    ("Stretching", 20, 30), ("Journal", 21, 0), ("Plan tomorrow", 21, 30), ("Tidy desk", 22, 0),
    ("Water plants", 22, 30),
]

@MainActor
private func container(restCount: Int, next: Bool = true) throws -> ModelContainer {
    let container = try ModelContainer(
        for: Schema(KadenceSchema.models),
        configurations: ModelConfiguration(isStoredInMemoryOnly: true))
    let context = container.mainContext
    if next {
        context.insert(Event(title: "Training", start: at(17, 30), end: at(18, 15),
                             origin: .routine, flexibility: .shiftable, sourceKey: .green))
    }
    for (title, hour, minute) in restRows.prefix(restCount) {
        context.insert(Event(title: title, start: at(hour, minute), end: at(hour, minute + 25), sourceKey: .graphite))
    }
    try context.save()
    return container
}

@MainActor
private func render(_ name: String, container: ModelContainer, now: Date,
                    snooze: MenuBarPopoverView.SnoozeConfirmation? = nil, suffix: String = "p2f20") throws {
    let view = MenuBarPopoverView(initialNow: now, initialSnooze: snooze)
        .modelContainer(container)
        .environment(UndoStack())
        .environment(CalendarState())   // P2-F18: `Open` reads it
        .environment(\.colorScheme, .light)
    let renderer = ImageRenderer(content: view)
    renderer.scale = 2
    let image = try #require(renderer.nsImage, "\(name) rendered")
    #expect(image.size.width > 0)
    guard ProcessInfo.processInfo.environment["KADENCE_CAPTURE_DIR"].map({ !$0.isEmpty }) == true else { return }
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent("kadence-captures")
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    if let tiff = image.tiffRepresentation,
       let png = NSBitmapImageRep(data: tiff)?.representation(using: .png, properties: [:]) {
        // The batch suffix of the files written (task P2-F20 re-rendered item
        // 11 after P2-F18; P2-B1 re-renders item 12 as `-p2f25`; the P2-T48
        // files keep their own names).
        try png.write(to: directory.appendingPathComponent("\(name)-\(suffix).png"))
    }
}

@Suite("§17 items 11 and 12 — the popover, rendered from §17.1's fixtures")
@MainActor
struct PopoverCaptureTests {

    @Test("Item 11, overflow: nine rest rows → six rows, then +3 more")
    func overflow() throws {
        let c = try container(restCount: 9)
        let result = NextUpProvider.evaluate(events: try c.mainContext.fetch(FetchDescriptor<Event>()), now: at(17, 10))
        #expect(result.next?.title == "Training")
        let rest = NextUpProvider.restDisplay(result.restOfToday)
        #expect(rest.rows.map(\.title) == ["Code review", "Dinner", "Reading", "Mail triage", "Stretching", "Journal"])
        #expect(rest.moreCount == 3)
        try render("popover-overflow", container: c, now: at(17, 10))
    }

    @Test("Item 11, normal: three rest rows, no +N")
    func normal() throws {
        let c = try container(restCount: 3)
        let result = NextUpProvider.evaluate(events: try c.mainContext.fetch(FetchDescriptor<Event>()), now: at(17, 10))
        #expect(NextUpProvider.restDisplay(result.restOfToday).moreCount == 0)
        try render("popover-normal", container: c, now: at(17, 10))
    }

    @Test("Item 11, late: 17:42 against the same next item reads 'Started 12m ago'")
    func late() throws {
        let c = try container(restCount: 3)
        let events = try c.mainContext.fetch(FetchDescriptor<Event>())
        let result = NextUpProvider.evaluate(events: events, now: at(17, 42))
        #expect(result.isLate)
        let next = try #require(result.next)
        #expect(MenuBarFormatting.nextMeta(for: next, now: at(17, 42), isLate: true).hasPrefix("Started 12m ago · "))
        try render("popover-late", container: c, now: at(17, 42))
    }

    @Test("Item 11, empty: 23:40, no next item")
    func empty() throws {
        let c = try container(restCount: 0, next: false)
        #expect(NextUpProvider.evaluate(events: try c.mainContext.fetch(FetchDescriptor<Event>()), now: at(23, 40)).next == nil)
        try render("popover-empty", container: c, now: at(23, 40))
    }

    @Test("Item 12, same-day: Training 17:30 snoozed at 17:10 → Moved to 17:45")
    func snoozeSameDay() throws {
        // `snooze-same-day-p2t48.png` stays the filed evidence (§17.1 item
        // 12: "unchanged"); this keeps the render path tested.
        let same = try container(restCount: 3)
        let training = try #require(try same.mainContext.fetch(FetchDescriptor<Event>()).first { $0.title == "Training" })
        let row = try #require(MenuBarPopoverView.SnoozeConfirmation.perform(
            training, store: EventStore(context: same.mainContext, undo: UndoStack())))
        #expect(row.text == "Moved to 17:45")
        try render("snooze-same-day", container: same, now: at(17, 10), snooze: row)
    }

    /// §17.1 item 12's next-day fixture: `Prep: relational algebra`
    /// 23:50–01:20, `now` 23:40; `withSleep` adds Sleep 22:00–07:00 daily.
    private func prepContainer(withSleep: Bool) throws -> (ModelContainer, Event) {
        let c = try ModelContainer(
            for: Schema(KadenceSchema.models),
            configurations: ModelConfiguration(isStoredInMemoryOnly: true))
        let prep = Event(title: "Prep: relational algebra", start: at(23, 50), end: at(1, 20, day: 6),
                         origin: .planned, flexibility: .droppable, sourceKey: .purple)
        c.mainContext.insert(prep)
        if withSleep {
            c.mainContext.insert(TimeWindow(weekdays: Set(1...7), startMinutes: 22 * 60, endMinutes: 7 * 60,
                                            kind: .protected, label: "Sleep"))
        }
        try c.mainContext.save()
        return (c, prep)
    }

    @Test("Item 12, next-day (no time windows): 00:05 – 01:35 above Moved to tomorrow 00:05")
    func snoozeNextDay() throws {
        let (c, prep) = try prepContainer(withSleep: false)
        let row = try #require(MenuBarPopoverView.SnoozeConfirmation.perform(
            prep, store: EventStore(context: c.mainContext, undo: UndoStack())))
        #expect(row.text == "Moved to tomorrow 00:05")
        #expect(!row.isRefusal)
        let pinned = NextUpProvider.pinning(
            NextUpProvider.evaluate(events: [prep], now: at(23, 40)), events: [prep], to: (prep.id, row.expectedStart))
        #expect(MenuBarFormatting.nextMeta(for: try #require(pinned.next), now: at(23, 40), isLate: false)
                .hasPrefix("00:05 – 01:35"))
        try render("snooze-next-day", container: c, now: at(23, 40), snooze: row, suffix: "p2f25")
    }

    @Test("Item 12, refused (with Sleep): NEXT unchanged 23:50 – 01:20 above Not moved — 00:05 is inside Sleep (protected)")
    func snoozeRefused() throws {
        let (c, prep) = try prepContainer(withSleep: true)
        let row = try #require(MenuBarPopoverView.SnoozeConfirmation.perform(
            prep, store: EventStore(context: c.mainContext, undo: UndoStack())))
        #expect(row.text == "Not moved — 00:05 is inside Sleep (protected)")
        #expect(row.isRefusal)
        let pinned = NextUpProvider.pinning(
            NextUpProvider.evaluate(events: [prep], now: at(23, 40)), events: [prep], to: (prep.id, row.expectedStart))
        #expect(MenuBarFormatting.nextMeta(for: try #require(pinned.next), now: at(23, 40), isLate: false)
                .hasPrefix("23:50 – 01:20"))
        try render("snooze-refused", container: c, now: at(23, 40), snooze: row, suffix: "p2f25")
    }
}
