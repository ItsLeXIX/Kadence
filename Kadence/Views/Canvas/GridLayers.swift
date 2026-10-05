//
//  GridLayers.swift
//  Kadence
//
//  The canvas underneath the blocks: background windows, hour lines, the time
//  gutter and the now line. Drawn bottom-up in the order layouts.md §3.1 and
//  components.md §7–§8 require.
//

import SwiftUI

// MARK: - Background windows (components.md §7)
//
// `TimeWindowRenderable` and the actual span-resolution logic (protected-
// wins-over-low-energy subtraction, peak-focus gating) live in
// `Kadence/Layout/WindowSpanResolver.swift` — pulled out to a pure,
// SwiftUI-free type (task P2-T20) so it can be unit-tested the same way
// `DayLayoutEngine` is. The views below are thin drawing wrappers around it.

/// Canvas, not content. Never uses hue; spans the full width *including the
/// time gutter*; drawn below the hour lines and below every block, so its edges
/// stay visible when the column is full — which is the only time it matters.
struct BackgroundWindowsLayer<Window: TimeWindowRenderable>: View {
    let windows: [Window]
    let day: Date
    let geometry: TimeGeometry
    /// components.md §7's "Editor exception" — peak-focus is drawn only
    /// "inside the Routines window's windows mode (§13.3), never on the
    /// calendar canvas." Defaults to `false` so every existing main-grid call
    /// site (`DayColumnView`, `TimedCanvasView`) is unchanged; the Routines
    /// window (task P2-T20) passes `true` only while in windows mode.
    var showsPeakFocus: Bool = false

    @Environment(\.colorSchemeContrast) private var contrast

    private var increaseContrast: Bool { contrast == .increased }

    var body: some View {
        ZStack(alignment: .topLeading) {
            // Protected wins where the two overlap; never render both.
            ForEach(resolvedSpans(for: .protected), id: \.id) { span in
                protectedSpan(span)
            }
            ForEach(resolvedSpans(for: .lowEnergy), id: \.id) { span in
                lowEnergySpan(span)
            }
            ForEach(resolvedSpans(for: .peakFocus), id: \.id) { span in
                peakFocusSpan(span)
            }
        }
        // components.md §7 rule 1 (amended 2026-10-05): a window paints only
        // inside its own spans — this layer is one day column (or the gutter
        // strip), so nothing it draws may leave that rect. The hatch is
        // confined by `HatchPattern` itself; this clip is the backstop for
        // fill and edge lines, so no treatment reaches a neighbouring day.
        //
        // The frame comes first and is load-bearing: each span is placed
        // with `.offset(y:)`, which moves drawing but not layout, so the
        // ZStack on its own is only as tall as one span. Clipping that would
        // erase every window below the first span's height. Filling the
        // proposed size (the caller's column × 24h) makes the clip the column.
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .clipped()
    }

    private struct Span: Identifiable {
        let id = UUID()
        let start: Date
        let end: Date
        let label: String
    }

    private func resolvedSpans(for kind: TimeWindowKind) -> [Span] {
        WindowSpanResolver.spans(for: kind, in: windows, on: day, showsPeakFocus: showsPeakFocus)
            .map { Span(start: $0.start, end: $0.end, label: $0.label) }
    }

    @ViewBuilder
    private func protectedSpan(_ span: Span) -> some View {
        let y = geometry.y(for: span.start)
        let height = geometry.height(from: span.start, to: span.end)
        ZStack(alignment: .top) {
            Rectangle().fill(Tokens.Color.Window.protectedFill)
            if increaseContrast {
                // The 1.12:1 value step disappears under Increase Contrast, so
                // protected switches to a bordered treatment on all four sides.
                Rectangle()
                    .strokeBorder(Tokens.Color.Window.protectedEdgeHC, lineWidth: 1)
            } else {
                VStack {
                    Rectangle().fill(Tokens.Color.Window.protectedEdge).frame(height: 1)
                    Spacer(minLength: 0)
                    Rectangle().fill(Tokens.Color.Window.protectedEdge).frame(height: 1)
                }
            }
        }
        .frame(height: max(height, 0))
        .offset(y: y)
        .allowsHitTesting(false)
    }

    @ViewBuilder
    private func lowEnergySpan(_ span: Span) -> some View {
        let y = geometry.y(for: span.start)
        let height = geometry.height(from: span.start, to: span.end)
        HatchPattern(pitch: increaseContrast ? 4 : 6, lineWidth: 1)
            .foregroundStyle(Tokens.Color.Window.lowEnergyHatch)
            .opacity(Tokens.Opacity.lowEnergyHatchOpacity)
            .frame(height: max(height, 0))
            .offset(y: y)
            .allowsHitTesting(false)
    }

    /// components.md §7 "Editor exception", verbatim: "a 1pt dashed outline in
    /// `color.window.peakFocusEdge`, dash `[4, 4]`, with no fill
    /// (`color.window.peakFocusFill` is transparent by definition), plus the
    /// standard window label." Only ever drawn when `showsPeakFocus` is true —
    /// the Routines window's windows mode.
    @ViewBuilder
    private func peakFocusSpan(_ span: Span) -> some View {
        let y = geometry.y(for: span.start)
        let height = geometry.height(from: span.start, to: span.end)
        Rectangle()
            .fill(Tokens.Color.Window.peakFocusFill)
            .overlay(
                Rectangle()
                    .strokeBorder(
                        Tokens.Color.Window.peakFocusEdge,
                        style: StrokeStyle(lineWidth: 1, dash: [4, 4]))
            )
            .frame(height: max(height, 0))
            .offset(y: y)
            .allowsHitTesting(false)
    }
}

/// The window labels one column draws, already placed by
/// `WindowLabelPlacement` (components.md §7 rules 2–3, task P2-F06).
///
/// components.md §7: in a **day column, never the gutter**. The first draft
/// put it in the gutter and the 2026-09-09 screenshot showed both collisions
/// that causes — a low-energy label overprinting `13:00` and a protected
/// label overprinting `00:00`. Which column, and how far down, is decided by
/// the canvas from every column's block frames; this view only draws.
struct WindowLabelsLayer: View {
    let labels: [WindowLabelPlacement.Placed]

    var body: some View {
        ZStack(alignment: .topLeading) {
            // `enumerated()` gives each label a stable position-based id;
            // two windows may share a label text.
            ForEach(Array(labels.enumerated()), id: \.offset) { _, label in
                Text(label.text)
                    .typeStyle(.windowLabel)
                    .foregroundStyle(Tokens.Color.Window.label)
                    .fixedSize()
                    .offset(x: label.frame.minX, y: label.frame.minY)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}

/// What a column reports up to its canvas so the canvas can place window
/// labels (§7 rule 2 needs every column's block frames; rule 3 the note's).
struct ColumnLabelInputs: Equatable {
    var blockFrames: [CGRect] = []
    var noteFrame: CGRect? = nil
}

/// A SwiftUI preference: a value a child view publishes that an ancestor
/// collects with `.onPreferenceChange` — the reverse of the environment, and
/// how one column's layout reaches the canvas that owns all seven. Keyed by
/// column index; `reduce` merges siblings' dictionaries.
struct ColumnLabelInputsKey: PreferenceKey {
    static let defaultValue: [Int: ColumnLabelInputs] = [:]
    static func reduce(value: inout [Int: ColumnLabelInputs], nextValue: () -> [Int: ColumnLabelInputs]) {
        value.merge(nextValue()) { _, new in new }
    }
}

// MARK: - Hour lines (layouts.md §3.1)

struct HourLinesLayer: View {
    let geometry: TimeGeometry
    /// Half-hour lines are drawn in the columns only, never across the gutter.
    var includeHalfHours: Bool = true
    /// components.md §13.5.2 — an inactive weekday column in the Routines
    /// window draws its hour lines at half-hour weight ("hour and half-hour
    /// lines both" in `color.separator.halfHour`), which recedes the column
    /// without touching its ground. `false` everywhere else.
    var recessed: Bool = false

    @Environment(\.colorSchemeContrast) private var contrast

    private var hourColor: Color {
        // §13.5.2's table gives one value for a recessed column and does not
        // carve out Increase Contrast, so the recessed case wins outright.
        if recessed { return Tokens.Color.Separator.halfHour }
        return contrast == .increased ? Tokens.Color.Separator.strong : Tokens.Color.Separator.hour
    }

    var body: some View {
        ZStack(alignment: .top) {
            ForEach(0...24, id: \.self) { hour in
                Rectangle()
                    .fill(hourColor)
                    .frame(height: Tokens.Size.hairline)
                    .offset(y: CGFloat(hour) * geometry.hourHeight)
            }
            if includeHalfHours {
                ForEach(0..<24, id: \.self) { hour in
                    Rectangle()
                        .fill(Tokens.Color.Separator.halfHour)
                        .frame(height: Tokens.Size.hairline)
                        .offset(y: (CGFloat(hour) + 0.5) * geometry.hourHeight)
                }
            }
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}

// MARK: - Time gutter

struct TimeGutterView: View {
    let geometry: TimeGeometry
    let now: Date
    /// Whether the now time replaces a colliding hour label.
    let showsNow: Bool
    /// interactions.md §1 — in cursor mode the cursor's time is printed here in
    /// `hourLabel` / `color.interactive.accent`. This is what makes the keyboard
    /// cursor legible: the accent line alone says *where*, not *when*.
    ///
    /// Note: components.md §7 (revised 17:15) says the gutter carries hour labels
    /// and the now time "and nothing else". interactions.md §1 predates it and
    /// puts the cursor time here. Implemented per §1 on Parsa's instruction; the
    /// two specs need reconciling.
    var cursor: Date? = nil

    var body: some View {
        ZStack(alignment: .topTrailing) {
            ForEach(0..<24, id: \.self) { hour in
                let y = CGFloat(hour) * geometry.hourHeight
                if !isSuppressed(hour: hour) {
                    Text(String(format: "%02d:00", hour))
                        .typeStyle(.hourLabel)
                        .foregroundStyle(Tokens.Color.Text.secondary)
                        .padding(.trailing, Tokens.Spacing.md)
                        // Top edge at the hour line + 2, so 00:00 is never clipped.
                        .offset(y: y + 2)
                }
            }
            if showsNow {
                Text(BlockFormatters.time.string(from: now))
                    .typeStyle(.hourLabel)
                    .foregroundStyle(Tokens.Color.Semantic.now)
                    .padding(.trailing, Tokens.Spacing.md)
                    .offset(y: geometry.yForTimeOfDay(now) - 5)
            }
            if let cursor {
                Text(BlockFormatters.time.string(from: cursor))
                    .typeStyle(.hourLabel)
                    .foregroundStyle(Tokens.Color.Interactive.accent)
                    .padding(.trailing, Tokens.Spacing.md)
                    .offset(y: geometry.yForTimeOfDay(cursor) - 5)
            }
        }
        .frame(width: Tokens.Size.timeGutterWidth, alignment: .trailing)
        // Hour lines span the gutter too; half-hour lines do not.
        .overlay(alignment: .top) {
            ForEach(0...24, id: \.self) { hour in
                Rectangle()
                    .fill(Tokens.Color.Separator.hour)
                    .frame(height: Tokens.Size.hairline)
                    .offset(y: CGFloat(hour) * geometry.hourHeight)
            }
        }
    }

    /// An hour label is dropped when the now time or the cursor time would
    /// overprint it (within 12pt), the same rule for both.
    private func isSuppressed(hour: Int) -> Bool {
        let hourY = CGFloat(hour) * geometry.hourHeight
        if showsNow, abs(hourY - geometry.yForTimeOfDay(now)) < 12 { return true }
        if let cursor, abs(hourY - geometry.yForTimeOfDay(cursor)) < 12 { return true }
        return false
    }
}

// MARK: - Now line (components.md §8)

struct NowLineView: View {
    let geometry: TimeGeometry
    let now: Date
    /// Day draws the dot at the gutter edge; Week at the column's leading edge.
    var showsDot: Bool = true

    var body: some View {
        ZStack(alignment: .leading) {
            Rectangle()
                .fill(Tokens.Color.Semantic.now)
                .frame(height: Tokens.Size.nowLineThickness)
            if showsDot {
                Circle()
                    .fill(Tokens.Color.Semantic.now)
                    .frame(width: Tokens.Size.nowDotDiameter, height: Tokens.Size.nowDotDiameter)
                    .offset(x: -Tokens.Size.nowDotDiameter / 2)
            }
        }
        .frame(height: Tokens.Size.nowDotDiameter)
        .offset(y: geometry.y(for: now) - Tokens.Size.nowDotDiameter / 2)
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}
