//
//  BlockStyleResolverTests.swift
//  KadenceTests
//
//  components.md §2–§6. The resolver is a pure function, which is the whole
//  reason it can be checked like this.
//

import Testing
import Foundation
import SwiftUI
@testable import Kadence

private func style(
    _ kind: BlockKind,
    flexibility: Flexibility = .fixed,
    status: BlockStatus = .scheduled,
    presentation: Presentation = [],
    source: SourceKey = .blue,
    height: CGFloat = 60,
    increaseContrast: Bool = false
) -> BlockStyle {
    resolveBlockStyle(
        kind: kind, flexibility: flexibility, status: status,
        presentation: presentation, source: source,
        renderedHeight: height, increaseContrast: increaseContrast)
}

@Suite("The fill-weight ladder")
struct FillWeightTests {

    @Test("Fixed is solid, routine is tinted, planned is transparent and dashed")
    func ladder() {
        #expect(style(.fixedTimed).fill == SourceKey.blue.solid)
        #expect(style(.routineTimed).fill == SourceKey.blue.tint)
        #expect(style(.plannedTimed).fill == Color.clear)
        #expect(style(.plannedTimed).borderDash == [4, 3])
    }

    @Test("An exam is solid and a deadline is tinted, matching the timed ladder")
    func allDayLadder() {
        #expect(style(.examAllDay).fill == SourceKey.blue.solid)
        #expect(style(.deadlineAllDay).fill == SourceKey.blue.tint)
    }

    @Test("Only fixed blocks have no rail — the absence is the signal")
    func fixedHasNoRail() {
        #expect(style(.fixedTimed).railStyle == .none)
        #expect(style(.routineTimed).railStyle != .none)
        #expect(style(.plannedTimed).railStyle != .none)
    }
}

@Suite("Flexibility rides the rail, never the fill")
struct FlexibilityTests {

    @Test("Each flexibility gets its own rail style")
    func railStyles() {
        #expect(style(.routineTimed, flexibility: .fixed).railStyle == .solid)
        #expect(style(.routineTimed, flexibility: .shiftable).railStyle == .inset)
        #expect(style(.routineTimed, flexibility: .droppable).railStyle == .dotted)
    }

    @Test("Changing flexibility never changes the fill")
    func fillIsUntouched() {
        let fills = Flexibility.allCases.map { style(.routineTimed, flexibility: $0).fill }
        #expect(Set(fills).count == 1)
    }
}

@Suite("States")
struct StateTests {

    @Test("Conflicted swaps the border but never the fill")
    func conflictedKeepsFill() {
        let plain = style(.routineTimed)
        let conflicted = style(.routineTimed, presentation: .conflicted)
        #expect(conflicted.fill == plain.fill)
        #expect(conflicted.border == Tokens.Color.Semantic.alert)
        #expect(conflicted.borderWidth == Tokens.Size.borderEmphasis)
        #expect(conflicted.badge?.symbol == "exclamationmark.triangle.fill")
    }

    @Test("Conflicted preserves a dash pattern the variant already had")
    func conflictedPreservesDash() {
        #expect(style(.plannedTimed, presentation: .conflicted).borderDash == [4, 3])
    }

    @Test("At `.glyphOnly` the conflict badge replaces the type glyph")
    func conflictBadgeReplacesGlyph() {
        // §6's state rows were restated in tier names by GAPS.md G-011; the
        // literal 16 this rule used to carry is no longer a tier edge. 17pt is
        // `.glyphOnly` under the new ladder and was `.titleOnly` under the old.
        for height in [12.0, 17.0] as [CGFloat] {
            let small = style(.routineTimed, presentation: .conflicted, height: height)
            #expect(small.glyph == "exclamationmark.triangle.fill")
            #expect(small.badge == nil)
        }
        // At `.titleOnly` and above the type glyph stays and the badge is drawn.
        let taller = style(.routineTimed, presentation: .conflicted, height: 18)
        #expect(taller.glyph == "repeat")
        #expect(taller.badge?.symbol == "exclamationmark.triangle.fill")
    }

    @Test("Done and skipped are siblings: neither is styled as a failure")
    func doneAndSkippedAreSiblings() {
        let done = style(.routineTimed, status: .done)
        let skipped = style(.routineTimed, status: .skipped)
        #expect(done.label == Tokens.Color.Text.secondary)
        #expect(skipped.glyphColor == Tokens.Color.Text.secondary)
        // No red anywhere on a skipped block.
        #expect(skipped.border != Tokens.Color.Semantic.alert)
        #expect(skipped.badge == nil)
        // Neither uses a strikethrough or an alert fill.
        #expect(done.fillBlendWithCanvas == Tokens.Opacity.blockDoneFillBlend)
        #expect(skipped.fillBlendWithCanvas == Tokens.Opacity.blockSkippedFillBlend)
    }

    @Test("Skipped is dashed in a neutral separator colour, not an alert colour")
    func skippedBorder() {
        let skipped = style(.fixedTimed, status: .skipped)
        #expect(skipped.borderDash == [3, 3])
        #expect(skipped.border == Tokens.Color.Separator.strong)
    }

    @Test("In progress marks the trailing edge and leaves the leading rail alone")
    func inProgress() {
        let running = style(.routineTimed, flexibility: .shiftable, status: .inProgress)
        #expect(running.trailingBar == Tokens.Color.Semantic.now)
        #expect(running.railStyle == .inset, "type must stay readable while an item is running")
        #expect(running.elevation == .level1)
    }

    @Test("Past dims content and blends the fill toward the canvas")
    func past() {
        let past = style(.fixedTimed, presentation: .past)
        #expect(past.contentOpacity == Tokens.Opacity.blockPastContent)
        #expect(past.fillBlendWithCanvas == Tokens.Opacity.blockPastFillBlend)
    }

    @Test("Selected and dragging raise the block")
    func elevationStates() {
        #expect(style(.fixedTimed, presentation: .selected).elevation == .level1)
        #expect(style(.fixedTimed, presentation: .dragging).elevation == .level2)
    }

    @Test("States compose: past and done together")
    func composition() {
        let both = style(.routineTimed, status: .done, presentation: .past)
        #expect(both.contentOpacity == Tokens.Opacity.blockPastContent)
        #expect(both.glyph == "checkmark.circle.fill")
    }
}

@Suite("Geometry and contrast")
struct GeometryContrastTests {

    @Test("Very short timed blocks take the compact radius")
    func compactRadius() {
        // §3.1, amended by G-011: the cutover is the `.glyphOnly` top (18), not 16.
        #expect(style(.fixedTimed, height: 12).cornerRadius == Tokens.Radius.blockCompact)
        #expect(style(.fixedTimed, height: 17).cornerRadius == Tokens.Radius.blockCompact)
        #expect(style(.fixedTimed, height: 18).cornerRadius == Tokens.Radius.block)
        #expect(style(.fixedTimed, height: 40).cornerRadius == Tokens.Radius.block)
    }

    @Test("All-day pills keep their own radius at any height")
    func allDayRadius() {
        #expect(style(.deadlineAllDay, height: 12).cornerRadius == Tokens.Radius.allDayPill)
    }

    @Test("Increase Contrast steps borders up and tightens the planned dash")
    func increaseContrast() {
        let routine = style(.routineTimed, increaseContrast: true)
        #expect(routine.borderWidth == Tokens.Size.borderEmphasis)
        #expect(routine.border == SourceKey.blue.rail, "the routine border drops its opacity")

        let planned = style(.plannedTimed, increaseContrast: true)
        #expect(planned.borderDash == [3, 2])
    }

    @Test("Every kind resolves to a non-empty glyph")
    func everyKindHasAGlyph() {
        for kind in BlockKind.allCases {
            #expect(!style(kind).glyph.isEmpty, "\(kind) has no glyph")
        }
    }

    @Test("Text on a solid fill uses the on-solid token, never the primary one")
    func onSolidText() {
        #expect(style(.fixedTimed).label == Tokens.Color.Text.onSolid)
        #expect(style(.examAllDay).label == Tokens.Color.Text.onSolid)
        #expect(style(.routineTimed).label == Tokens.Color.Text.primary)
    }
}

@Suite("Countdown")
struct CountdownTests {

    private let calendar = Calendar(identifier: .gregorian)
    private let today = Calendar(identifier: .gregorian).date(
        from: DateComponents(year: 2026, month: 9, day: 9))!

    private func exam(daysOut: Int) -> AllDayFixture {
        let date = calendar.date(byAdding: .day, value: daysOut, to: today)!
        return AllDayFixture(title: "Exam", startDay: date, endDay: date, kind: .exam, source: .teal)
    }

    @Test("Counts down and says today on the day")
    func labels() {
        #expect(exam(daysOut: 6).countdownLabel(now: today, calendar: calendar) == "T−6d")
        #expect(exam(daysOut: 1).countdownLabel(now: today, calendar: calendar) == "T−1d")
        #expect(exam(daysOut: 0).countdownLabel(now: today, calendar: calendar) == "today")
    }

    @Test("A passed exam shows no chip at all — never a negative countdown")
    func neverNegative() {
        #expect(exam(daysOut: -1).countdownLabel(now: today, calendar: calendar) == nil)
        #expect(exam(daysOut: -1).isPast(now: today, calendar: calendar))
    }

    @Test("A deadline never gets a countdown chip")
    func deadlineHasNoChip() {
        let deadline = AllDayFixture(
            title: "Abgabe", startDay: today, endDay: today, kind: .deadline, source: .orange)
        #expect(deadline.countdownLabel(now: today, calendar: calendar) == nil)
    }
}
