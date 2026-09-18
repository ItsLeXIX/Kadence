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

/// The window label, drawn once at each window's top edge.
///
/// components.md §7: in the **leading day column, never the gutter**. The first
/// draft put it in the gutter and the 2026-09-09 screenshot showed both
/// collisions that causes — a low-energy label overprinting `13:00` and a
/// protected label overprinting `00:00`. The gutter now belongs to hour labels
/// and the now time, and nothing else.
struct WindowLabelsLayer<Window: TimeWindowRenderable>: View {
    let windows: [Window]
    let day: Date
    let geometry: TimeGeometry
    /// See `BackgroundWindowsLayer.showsPeakFocus` — same default, same
    /// reasoning: `false` leaves every main-grid call site unchanged.
    var showsPeakFocus: Bool = false

    var body: some View {
        ZStack(alignment: .topLeading) {
            ForEach(labels, id: \.id) { label in
                Text(label.text)
                    .typeStyle(.windowLabel)
                    .foregroundStyle(Tokens.Color.Window.label)
                    .padding(.leading, Tokens.Spacing.xs)
                    .offset(y: label.y + 1)
            }
        }
        .frame(maxWidth: .infinity, alignment: .topLeading)
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }

    private struct Label: Identifiable { let id = UUID(); let text: String; let y: CGFloat }

    private var labels: [Label] {
        WindowSpanResolver.labels(in: windows, on: day, showsPeakFocus: showsPeakFocus)
            .map { Label(text: $0.text, y: geometry.y(for: $0.start)) }
    }
}

// MARK: - Hour lines (layouts.md §3.1)

struct HourLinesLayer: View {
    let geometry: TimeGeometry
    /// Half-hour lines are drawn in the columns only, never across the gutter.
    var includeHalfHours: Bool = true

    @Environment(\.colorSchemeContrast) private var contrast

    private var hourColor: Color {
        contrast == .increased ? Tokens.Color.Separator.strong : Tokens.Color.Separator.hour
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
