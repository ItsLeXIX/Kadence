//
//  WindowSpanResolver.swift
//  Kadence
//
//  Pure resolution of which background-window spans to draw on a given day —
//  components.md §7's protected-wins-over-low-energy subtraction rule, plus
//  the §7 "Editor exception" that gates peak-focus behind `showsPeakFocus`.
//  Free of SwiftUI and of the system clock (the caller supplies `day` and
//  `calendar`), so it is directly testable — same shape as `DayLayoutEngine`
//  and `resolveBlockStyle`. `BackgroundWindowsLayer`/`WindowLabelsLayer`
//  (`Kadence/Views/Canvas/GridLayers.swift`) are thin SwiftUI wrappers around
//  this.
//
//  Task P2-T20: extracted from what was, until this task, a private method on
//  `BackgroundWindowsLayer` — pulled out here so it can be generalized over
//  `TimeWindowRenderable` (both `TimeWindowFixture` and the persisted
//  `TimeWindow`) and unit-tested without going through SwiftUI.
//

import Foundation

/// Conformed to by both `TimeWindowFixture` (`Kadence/Models/DisplayFixtures.swift`
/// — display-only, Phase 1's mock set) and `TimeWindow`
/// (`Kadence/Models/TimeWindow.swift` — persisted, Phase 2), so this resolver
/// and `GridLayers.swift`'s views can draw either representation through the
/// same code.
protocol TimeWindowRenderable {
    var kind: TimeWindowKind { get }
    var label: String { get }
    func spans(on day: Date, calendar: Calendar) -> [(start: Date, end: Date)]
}

extension TimeWindowFixture: TimeWindowRenderable {}
extension TimeWindow: TimeWindowRenderable {}

enum WindowSpanResolver {
    struct ResolvedSpan: Equatable {
        var start: Date
        var end: Date
        var label: String
    }

    struct ResolvedLabel: Equatable {
        var text: String
        var start: Date
    }

    /// The spans of `kind` to draw on `day`.
    ///
    /// - Peak focus: components.md §7's "Editor exception" — drawn only when
    ///   `showsPeakFocus` is true (the Routines window's windows mode); every
    ///   main-grid caller leaves it `false`, so peak-focus stays undrawn there,
    ///   unchanged from Phase 1.
    /// - Low energy: split around every protected span on the same day — "§7:
    ///   Overlapping windows: protected wins. Never render both treatments in
    ///   the same region."
    /// - Protected: returned as-is.
    static func spans<Window: TimeWindowRenderable>(
        for kind: TimeWindowKind,
        in windows: [Window],
        on day: Date,
        calendar: Calendar = .current,
        showsPeakFocus: Bool
    ) -> [ResolvedSpan] {
        if kind == .peakFocus {
            guard showsPeakFocus else { return [] }
            return windows
                .filter { $0.kind == .peakFocus }
                .flatMap { window in
                    window.spans(on: day, calendar: calendar)
                        .map { ResolvedSpan(start: $0.start, end: $0.end, label: window.label) }
                }
        }

        let protectedSpans = windows
            .filter { $0.kind == .protected }
            .flatMap { window in window.spans(on: day, calendar: calendar).map { ($0.start, $0.end) } }

        return windows
            .filter { $0.kind == kind }
            .flatMap { window in
                window.spans(on: day, calendar: calendar).flatMap { span -> [ResolvedSpan] in
                    guard kind == .lowEnergy else {
                        return [ResolvedSpan(start: span.start, end: span.end, label: window.label)]
                    }
                    var remaining = [(span.start, span.end)]
                    for blocker in protectedSpans {
                        remaining = remaining.flatMap { piece -> [(Date, Date)] in
                            guard piece.0 < blocker.1 && blocker.0 < piece.1 else { return [piece] }
                            var out: [(Date, Date)] = []
                            if piece.0 < blocker.0 { out.append((piece.0, blocker.0)) }
                            if blocker.1 < piece.1 { out.append((blocker.1, piece.1)) }
                            return out
                        }
                    }
                    return remaining.map { ResolvedSpan(start: $0.0, end: $0.1, label: window.label) }
                }
            }
    }

    /// One label per span's start, in source order. Same `showsPeakFocus`
    /// gating as `spans(for:in:on:calendar:showsPeakFocus:)` above — mirrors
    /// it rather than calling it three times, since a label needs no
    /// protected-vs-low-energy subtraction (every window that has a span
    /// gets a label at that span's top edge, per components.md §7).
    static func labels<Window: TimeWindowRenderable>(
        in windows: [Window],
        on day: Date,
        calendar: Calendar = .current,
        showsPeakFocus: Bool
    ) -> [ResolvedLabel] {
        windows
            .filter { $0.kind != .peakFocus || showsPeakFocus }
            .flatMap { window in
                window.spans(on: day, calendar: calendar)
                    .map { ResolvedLabel(text: window.label, start: $0.start) }
            }
    }
}
