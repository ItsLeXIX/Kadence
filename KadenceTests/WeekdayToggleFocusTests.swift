//
//  WeekdayToggleFocusTests.swift
//  KadenceTests
//
//  Task P2-C2 (PHASE2-REVIEW.md "Closeout — 2026-10-07" CF2; layouts.md §8.1
//  amended 2026-10-07; G-049; tokens 1.3.0): the focused weekday toggle's
//  inset stroke takes its colour from the toggle's fill — `focusRingOnAccent`
//  on an ON (accent) toggle, `focusRing` on an OFF one — so focus shows in
//  both states.
//
//  The render test draws the real `WeekdayToggleRow` (the editor inspector's
//  row: `Daily routine`, Mon/Wed/Fri on, Monday first) with
//  `renderFocusedWeekday` set, because an offscreen render has no first
//  responder, and samples the stroke's pixels. With `KADENCE_CAPTURE_DIR`
//  set it also writes CF2's four frames.
//

import Testing
import Foundation
import SwiftUI
import AppKit
@testable import Kadence

/// Mon-first display order, as the Routines window orders it here.
private let monFirst = [2, 3, 4, 5, 6, 7, 1]
/// `Daily routine`: Mon, Wed, Fri.
private let dailyRoutine: Set<Int> = [2, 4, 6]

@MainActor
private func items(on: Set<Int>, context: WeekdayToggleItem.Context = .routine) -> [WeekdayToggleItem] {
    WeekdayToggleItem.items(weekdays: monFirst, isOn: { on.contains($0) }, context: context)
}

/// The row as the editor inspector draws it, on the inspector's surface,
/// focused on `weekday` (render only). `spacing.lg` around it is framing
/// for the capture, not a layout value of the row.
@MainActor
private func inspectorRow(focused weekday: Int) -> some View {
    WeekdayToggleRow(weekdays: monFirst, isOn: { dailyRoutine.contains($0) }, context: .routine,
                     onFlip: { _ in }, renderFocusedWeekday: weekday)
        .padding(Tokens.Spacing.lg)
        .background(Tokens.Color.Surface.inspector)
}

/// Renders at 2× in the given appearance. Token colours are dynamic
/// `NSColor`s, resolved against the *current drawing appearance*, so the
/// render runs inside `performAsCurrentDrawingAppearance` as well as with
/// SwiftUI's `colorScheme`.
@MainActor
private func renderInAppearance(_ view: some View, dark: Bool) throws -> NSBitmapImageRep {
    let appearance = try #require(NSAppearance(named: dark ? .darkAqua : .aqua))
    var image: CGImage?
    appearance.performAsCurrentDrawingAppearance {
        let renderer = ImageRenderer(content: view.environment(\.colorScheme, dark ? .dark : .light))
        renderer.scale = 2
        image = renderer.cgImage
    }
    return NSBitmapImageRep(cgImage: try #require(image))
}

/// 8-bit RGB of the pixel at a point (in points; the rep is 2×), as stored.
/// Raw components, like the other render tests (`RoutineGutterStripTests`):
/// converting through `NSColor.usingColorSpace(.sRGB)` moved the accent blue
/// to (0, 133, 255) — the bitmap is tagged with a wider space than the sRGB
/// values `ImageRenderer` wrote into it, while neutrals came through exact.
private func rgb(_ rep: NSBitmapImageRep, _ x: CGFloat, _ y: CGFloat) -> (Int, Int, Int) {
    var p = [Int](repeating: 0, count: 4)
    rep.getPixel(&p, atX: Int(x * 2), y: Int(y * 2))
    return (p[0], p[1], p[2])
}

private func close(_ a: (Int, Int, Int), _ hex: Int, tolerance: Int = 3) -> Bool {
    abs(a.0 - (hex >> 16 & 0xFF)) <= tolerance && abs(a.1 - (hex >> 8 & 0xFF)) <= tolerance
        && abs(a.2 - (hex & 0xFF)) <= tolerance
}

private func write(_ rep: NSBitmapImageRep, _ name: String) throws {
    guard ProcessInfo.processInfo.environment["KADENCE_CAPTURE_DIR"].map({ !$0.isEmpty }) == true else { return }
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent("kadence-captures")
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    try rep.representation(using: .png, properties: [:])?.write(to: directory.appendingPathComponent("\(name)-p2c.png"))
}

@Suite("CF2 — the focused weekday toggle shows focus on and off (§8.1, 2026-10-07)")
@MainActor
struct WeekdayToggleFocusTests {

    @Test("Resolver: on → focusRingOnAccent, off → focusRing, disabled on → focusRingOnAccent")
    func resolver() throws {
        let row = items(on: dailyRoutine)
        let monday = try #require(row.first { $0.weekday == 2 })
        let tuesday = try #require(row.first { $0.weekday == 3 })
        #expect(monday.fill == .accent && monday.focusStroke == .focusRingOnAccent)
        #expect(tuesday.fill == .canvasSunken && tuesday.focusStroke == .focusRing)
        // The time-window inspector's last active day: disabled, still on.
        let lastDay = try #require(items(on: [4], context: .window).first { $0.weekday == 4 })
        #expect(lastDay.isDisabled && lastDay.isOn)
        #expect(lastDay.focusStroke == .focusRingOnAccent)
    }

    @Test("Tokens 1.3.0: focusRingOnAccent = text.onSolid; 57 contrast pairs incl. the two strokes")
    func tokens() throws {
        // `focusRingOnAccent` must stay equal to `text.onSolid` (tokens.json's note).
        #expect(Tokens.Color.Interactive.focusRingOnAccent == Tokens.Color.Text.onSolid)
        // tokens.json is read from the repo (`#filePath` → ../design). The
        // generator skips `contrastPairs` (metadata), so this is the only
        // way a test can see them.
        let url = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
            .deletingLastPathComponent().appendingPathComponent("design/tokens.json")
        let json = try #require(try JSONSerialization.jsonObject(with: Data(contentsOf: url)) as? [String: Any])
        let meta = try #require(json["$meta"] as? [String: Any])
        #expect(meta["version"] as? String == "1.3.0")
        let pairs = try #require((meta["contrastPairs"] as? [String: Any])?["pairs"] as? [[String: Any]])
        #expect(pairs.count == 57)
        func declared(_ fg: String, _ bg: String) -> Bool {
            pairs.contains { $0["fg"] as? String == fg && $0["bg"] as? String == bg && ($0["min"] as? Double) == 3.0 }
        }
        #expect(declared("color.interactive.focusRingOnAccent", "color.interactive.accent"))
        #expect(declared("color.interactive.focusRing", "color.surface.canvasSunken"))
    }

    @Test("Render, light and dark: focused ON `M` strokes #FFFFFF / #0C0C0D; focused OFF `T` strokes #0A6CFF / #4C9BFF",
          arguments: [false, true])
    func render(dark: Bool) throws {
        let size = Tokens.Size.weekdayToggleSize
        let step = size + Tokens.Spacing.xs
        let left = Tokens.Spacing.lg                       // first toggle's leading edge
        let midY = Tokens.Spacing.lg + size / 2
        // Inside the 2pt stroke inset 1pt: 2pt in from the toggle's edge,
        // halfway down its side (clear of the rounded corners and the letter).
        func strokeSample(_ rep: NSBitmapImageRep, index: CGFloat) -> (Int, Int, Int) {
            rgb(rep, left + index * step + 2, midY)
        }
        func fillSample(_ rep: NSBitmapImageRep, index: CGFloat) -> (Int, Int, Int) {
            rgb(rep, left + index * step + 5, Tokens.Spacing.lg + 5)
        }

        // `M` (index 0) focused: on, accent fill.
        let on = try Self.renderRow(focused: 2, dark: dark)
        #expect(close(strokeSample(on, index: 0), dark ? 0x0C0C0D : 0xFFFFFF),
                "on stroke \(strokeSample(on, index: 0))")
        #expect(close(fillSample(on, index: 0), dark ? 0x4C9BFF : 0x0A6CFF), "on fill \(fillSample(on, index: 0))")
        // The stroke is not the fill (the G-049 defect).
        #expect(!close(strokeSample(on, index: 0), dark ? 0x4C9BFF : 0x0A6CFF))
        // No stroke on the unfocused `W` (index 2, also on): the fill reaches the edge band.
        #expect(close(strokeSample(on, index: 2), dark ? 0x4C9BFF : 0x0A6CFF))
        try write(on, "weekday-toggle-focus-on-\(dark ? "dark" : "light")")

        // `T` (index 1) focused: off, canvasSunken fill.
        let off = try Self.renderRow(focused: 3, dark: dark)
        #expect(close(strokeSample(off, index: 1), dark ? 0x4C9BFF : 0x0A6CFF),
                "off stroke \(strokeSample(off, index: 1))")
        #expect(!close(fillSample(off, index: 1), dark ? 0x4C9BFF : 0x0A6CFF))
        try write(off, "weekday-toggle-focus-off-\(dark ? "dark" : "light")")
    }

    static func renderRow(focused weekday: Int, dark: Bool) throws -> NSBitmapImageRep {
        try renderInAppearance(inspectorRow(focused: weekday), dark: dark)
    }
}
