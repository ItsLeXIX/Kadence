//
//  StatusItemLayoutTests.swift
//  KadenceTests
//
//  Task P2-T47: components.md §15.1 (amended 2026-10-01) — the degrade
//  threshold, the time never truncated, and the item at most
//  `size.statusItemMaxWidth` wide (DEVIATIONS B14, B15). Plus §17.1 item
//  10's six rows rendered through the real `StatusItemLabel`; with
//  `KADENCE_CAPTURE_DIR` set (passed to the runner as
//  `TEST_RUNNER_KADENCE_CAPTURE_DIR`), each row is also written there as a
//  PNG, which is how screenshots/2/status-item-*-p2t47.png were made.
//

import Testing
import Foundation
import SwiftUI
import AppKit
@testable import Kadence

@Suite("Status item — the §15.1 degrade rule")
struct StatusItemLayoutTests {

    @Test("At the threshold the title shows; one point below it, the time alone")
    func threshold() {
        // budget 180 − time 40 − separator 10 = 130 left.
        let atMin = StatusItemLayout.resolve(leadingWidth: 40, separatorWidth: 10, titleWidth: 200,
                                             available: 40 + 10 + 32)
        #expect(atMin.showsTitle)
        #expect(atMin.titleSlotWidth == CGFloat(42))

        let below = StatusItemLayout.resolve(leadingWidth: 40, separatorWidth: 10, titleWidth: 200,
                                             available: 40 + 10 + 31)
        #expect(!below.showsTitle)
        #expect(below.titleSlotWidth == CGFloat(0), "no separator, no ellipsis")
        #expect(below.totalWidth == CGFloat(40))
    }

    @Test("The time is never truncated, even when it alone exceeds the budget")
    func timeNeverTruncated() {
        let tiny = StatusItemLayout.resolve(leadingWidth: 40, separatorWidth: 10, titleWidth: 80, available: 20)
        #expect(!tiny.showsTitle)
        #expect(tiny.totalWidth == CGFloat(40))

        for available in stride(from: CGFloat(0), through: 300, by: 7) {
            let layout = StatusItemLayout.resolve(leadingWidth: 37, separatorWidth: 9, titleWidth: 150, available: available)
            #expect(layout.totalWidth >= 37, "the leading part always gets its full width")
        }
    }

    @Test("At most statusItemMaxWidth wide — and only as wide as it draws")
    func atMostMax() {
        let long = StatusItemLayout.resolve(leadingWidth: 40, separatorWidth: 10, titleWidth: 1000, available: 500)
        #expect(long.totalWidth == Tokens.Size.statusItemMaxWidth)
        let short = StatusItemLayout.resolve(leadingWidth: 40, separatorWidth: 10, titleWidth: 25, available: 180)
        #expect(short.totalWidth == CGFloat(75), "not padded out to 180 (B15)")
    }

    @Test("No title shows the time alone")
    func noTitle() {
        let layout = StatusItemLayout.resolve(leadingWidth: 40, separatorWidth: 10, titleWidth: 0, available: 180)
        #expect(!layout.showsTitle)
        #expect(layout.totalWidth == CGFloat(40))
    }
}

// MARK: - §17.1 item 10, rendered

@Suite("Status item — §17.1 item 10's six rows through the real label")
@MainActor
struct StatusItemRowsTests {

    private static func date(_ hour: Int, _ minute: Int) -> Date {
        Calendar.current.date(from: DateComponents(year: 2026, month: 10, day: 5, hour: hour, minute: minute))!
    }

    private static func event(_ title: String) -> Event {
        Event(title: title, start: date(17, 30), end: date(18, 15), origin: .routine)
    }

    /// (file name, now, title or nil for empty, available width)
    private static let rows: [(String, (Int, Int), String?, CGFloat)] = [
        ("status-item-normal-full", (17, 10), "Gym", 180),
        ("status-item-normal-clipped", (17, 10), "Statistik Übung Gruppe 4", 180),
        ("status-item-late-full", (17, 42), "Gym", 180),
        ("status-item-late-clipped", (17, 42), "Statistik Übung Gruppe 4", 180),
        ("status-item-empty", (23, 40), nil, 180),
        // §17.1 names 110pt for the degraded row, but at the `statusItem`
        // font `17:30` (37.3) + ` · ` (11.0) leaves 61.8 ≥ 32, so §15.1's
        // rule still shows a truncated title there (GAPS G-037). Both are
        // rendered: 110 as the rule draws it, and 80 (31.7 left), where the
        // rule does degrade to the time alone.
        ("status-item-degraded-110", (17, 10), "Statistik Übung Gruppe 4", 110),
        ("status-item-degraded-80", (17, 10), "Statistik Übung Gruppe 4", 80),
    ]

    @Test("Each row lays out as §17.1 expects: time intact, title only with room, ≤ the width given")
    func rowsLayOut() throws {
        for (name, clock, title, available) in Self.rows {
            let now = Self.date(clock.0, clock.1)
            let result = NextUpProvider.evaluate(events: title.map { [Self.event($0)] } ?? [], now: now)
            if title == nil {
                #expect(result.next == nil, "\(name)")
                continue
            }
            let next = try #require(result.next)
            let primary = result.isLate
                ? MenuBarFormatting.elapsed(since: next.start, now: now)
                : MenuBarFormatting.time(next.start)
            #expect(primary == (clock == (17, 42) ? "12m ago" : "17:30"), "\(name)")

            let leading = StatusItemLabel.width(of: primary) + (result.isLate ? StatusItemLabel.lateGlyphWidth : 0)
            let layout = StatusItemLayout.resolve(
                leadingWidth: leading,
                separatorWidth: StatusItemLabel.width(of: StatusItemLabel.separator),
                titleWidth: StatusItemLabel.width(of: next.title),
                available: available)
            #expect(layout.totalWidth <= available, "\(name)")
            #expect(layout.totalWidth >= leading, "\(name): the time is never cut")
            if name == "status-item-degraded-80" {
                #expect(!layout.showsTitle, "80pt leaves under 32pt: the time alone")
                #expect(layout.totalWidth == leading)
            } else {
                #expect(layout.showsTitle, "\(name)")
            }
            if name.hasSuffix("clipped") || name == "status-item-degraded-110" {
                #expect(layout.titleSlotWidth < StatusItemLabel.width(of: StatusItemLabel.separator + next.title),
                        "\(name): the title is truncated")
            }
        }
    }

    @Test("The one string the menu bar shows, per row: time intact, tail-truncated title, ≤ the width given")
    func rowStrings() throws {
        for (name, clock, title, available) in Self.rows where title != nil {
            let now = Self.date(clock.0, clock.1)
            let result = NextUpProvider.evaluate(events: [Self.event(title!)], now: now)
            let text = try #require(StatusItemLabel.text(for: result, now: now, available: available), "\(name)")
            let lead = clock == (17, 42) ? "12m ago" : "17:30"
            #expect(text.hasPrefix(lead), "\(name): the time is intact")
            let drawn = StatusItemLabel.width(of: text) + (result.isLate ? StatusItemLabel.lateGlyphWidth : 0)
            #expect(drawn <= available, "\(name): \(text) is \(drawn)pt")
            switch name {
            case "status-item-normal-full": #expect(text == "17:30 · Gym")
            case "status-item-late-full": #expect(text == "12m ago · Gym")
            case "status-item-degraded-80": #expect(text == "17:30", "no separator, no ellipsis")
            default:
                #expect(text.hasPrefix(lead + " · Stat"), "\(name): \(text)")
                #expect(text.hasSuffix("…"), "\(name): \(text)")
            }
        }
    }

    @Test("truncated: whole title when it fits; otherwise the longest prefix plus an ellipsis that fits")
    func truncation() {
        #expect(StatusItemLabel.truncated("Gym", toFit: 200) == "Gym")
        let cut = StatusItemLabel.truncated("Statistik Übung Gruppe 4", toFit: 60)
        #expect(cut.hasSuffix("…"))
        #expect(StatusItemLabel.width(of: cut) <= 60)
        #expect(!cut.contains(" …"), "no space before the ellipsis")
    }

    @Test("Rendering each row; written as PNG when KADENCE_CAPTURE_DIR is set")
    func renderRows() throws {
        // The test host is sandboxed, so it can't write into the repo: with
        // KADENCE_CAPTURE_DIR set it writes to its own temporary directory
        // (`kadence-captures`), and the capture step copies the files out.
        let directory = ProcessInfo.processInfo.environment["KADENCE_CAPTURE_DIR"].flatMap { $0.isEmpty ? nil : $0 }
            .map { _ in FileManager.default.temporaryDirectory.appendingPathComponent("kadence-captures").path }
        if let directory {
            try FileManager.default.createDirectory(atPath: directory, withIntermediateDirectories: true)
        }
        for (name, clock, title, available) in Self.rows {
            let now = Self.date(clock.0, clock.1)
            let result = NextUpProvider.evaluate(events: title.map { [Self.event($0)] } ?? [], now: now)
            // The label on a menu-bar-like strip, the available width wide,
            // so a review can see how much of it the item uses.
            let view = StatusItemLabel(result: result, now: now, available: available)
                .frame(width: available, height: 22, alignment: .leading)
                .padding(.horizontal, Tokens.Spacing.sm)
                .background(Tokens.Color.Surface.toolbar)
                .environment(\.colorScheme, .light)
            let renderer = ImageRenderer(content: view)
            renderer.scale = 2
            let image = try #require(renderer.nsImage, "\(name) rendered")
            #expect(image.size.width > 0)

            if let directory,
               let tiff = image.tiffRepresentation,
               let png = NSBitmapImageRep(data: tiff)?.representation(using: .png, properties: [:]) {
                try png.write(to: URL(fileURLWithPath: directory).appendingPathComponent("\(name)-p2t47.png"))
            }
        }
    }
}
