//
//  WeekdayToggleRow.swift
//  Kadence
//
//  layouts.md §8.1 (amended 2026-10-05; closes G-028) and components.md
//  §13.5.4 (amended 2026-10-05; closes G-027). Seven weekday toggles in the
//  window's column order, used by both Routines inspectors: the template's
//  active weekdays and a `TimeWindow`'s weekdays. Task P2-F08 (it was P2-T39's
//  native `.toggleStyle(.button)` row, squeezed beside the label column until
//  `M`/`W` clipped).
//
//  Keyboard (interactions.md §11.1.1, layouts.md §8.1): reached by `⇥`;
//  `←`/`→` move between the seven toggles and `space` flips the focused one.
//  The ROW is the single focus target, never each toggle: interactions.md §1
//  says `⇥` leaves a region rather than walking inside it. The row tracks
//  which toggle is focused itself and marks it with an inset stroke; the
//  system focus ring stays on the row as a whole.
//

import SwiftUI

/// What each toggle shows and speaks — pure, so tests need no view.
struct WeekdayToggleItem: Equatable, Sendable {
    /// Which inspector the row is in. They differ in the spoken value and in
    /// whether the last active toggle can be turned off.
    enum Context: Sendable { case routine, window }

    var weekday: Int
    /// `veryShortStandaloneWeekdaySymbols` — `M T W T F S S`.
    var letter: String
    /// Full weekday name, `Monday`.
    var accessibilityLabel: String
    /// `in routine` / `not in routine`; time windows `on` / `off`.
    var accessibilityValue: String
    var isOn: Bool
    /// components.md §13.5.4: a window's last active day can't be removed.
    var isDisabled: Bool
    /// The reason, shown before the gesture (§13.5.1's standard).
    var help: String?

    static let lastWindowDayHelp = "A window needs at least one day. Delete it instead."

    static func items(
        weekdays: [Int],
        isOn: (Int) -> Bool,
        context: Context,
        calendar: Calendar = .current
    ) -> [WeekdayToggleItem] {
        let onCount = weekdays.filter(isOn).count
        return weekdays.map { weekday in
            let on = isOn(weekday)
            // §13.5.4: removing a TEMPLATE's last weekday is allowed (a
            // paused routine); a WINDOW's is refused with a disabled toggle.
            let disabled = context == .window && on && onCount == 1
            let value: String = switch context {
            case .routine: on ? "in routine" : "not in routine"
            case .window: on ? "on" : "off"
            }
            return WeekdayToggleItem(
                weekday: weekday,
                letter: calendar.veryShortStandaloneWeekdaySymbols[weekday - 1],
                accessibilityLabel: calendar.standaloneWeekdaySymbols[weekday - 1],
                accessibilityValue: value,
                isOn: on,
                isDisabled: disabled,
                help: disabled ? lastWindowDayHelp : nil)
        }
    }

    /// The two fills a toggle can have (layouts.md §8.1). Disabled doesn't
    /// change the fill: a window's last day (§13.5.4) is still drawn on.
    enum Fill: Equatable, Sendable { case accent, canvasSunken }

    /// The two colours the focused toggle's inset stroke can take.
    enum FocusStroke: Equatable, Sendable { case focusRingOnAccent, focusRing }

    var fill: Fill { isOn ? .accent : .canvasSunken }

    /// layouts.md §8.1 (amended 2026-10-07, G-049): the stroke's colour
    /// follows the fill it sits on, never the meaning — `focusRing` equals
    /// `accent`, so on an accent fill it would be invisible (1.00:1).
    /// Accent → `focusRingOnAccent` (4.56 / 6.93 : 1); anything else →
    /// `focusRing` (4.05 / 6.40 : 1). Never `keyboardFocusIndicatorColor`
    /// (it follows the accent and would recreate the defect).
    var focusStroke: FocusStroke {
        switch fill {
        case .accent: .focusRingOnAccent
        case .canvasSunken: .focusRing
        }
    }

    /// layouts.md §8.1: 7 × `size.weekdayToggleSize` + 6 × `spacing.xs`.
    static func rowWidth(count: Int = 7) -> CGFloat {
        CGFloat(count) * Tokens.Size.weekdayToggleSize + CGFloat(max(0, count - 1)) * Tokens.Spacing.xs
    }
}

struct WeekdayToggleRow: View {
    /// Display order — `RoutineWeekLayout.orderedWeekdays`.
    let weekdays: [Int]
    /// Task P2-SF1: the Routines window's ⇥ into its editor inspector lands
    /// here (interactions.md §11.1: the row "is reached by ⇥ into the
    /// inspector"). Each increment asks the row to take focus; the row
    /// reports its focus back through `onFocusChange`. (A second `.focused`
    /// binding from outside didn't hold — SwiftUI dropped it at once, found
    /// live — so the row moves its own `@FocusState`.)
    var focusRequest = 0
    var onFocusChange: (Bool) -> Void = { _ in }
    let isOn: (Int) -> Bool
    let context: WeekdayToggleItem.Context
    /// Called with the weekday to flip; the caller does the write.
    let onFlip: (Int) -> Void
    /// Render tests only (`WeekdayToggleFocusTests`, P2-C2): draw the row as
    /// if it had keyboard focus on this weekday. An offscreen `ImageRenderer`
    /// has no window and so no first responder, so `@FocusState` can never
    /// become true there. `nil` (every real use) changes nothing.
    var renderFocusedWeekday: Int? = nil

    /// `@FocusState` is SwiftUI's handle on keyboard focus: SwiftUI sets it
    /// to `true` when this view becomes first responder, and setting it moves
    /// focus here.
    @FocusState private var rowFocused: Bool
    /// The toggle `←`/`→` have moved to, by weekday. `nil` until the row is
    /// first focused.
    @State private var focusedWeekday: Int?

    /// `dayHeaderWeekday` without its `textCase: uppercase`. The case
    /// transform is an environment value, and on macOS it also reaches the
    /// button's accessibility strings — the live AX tree read `MONDAY` /
    /// `IN ROUTINE`. The very-short symbols are capitals already, so dropping
    /// the transform changes nothing drawn. (`var` copy of a struct: Swift
    /// value types copy on assignment, so the shared style is untouched.)
    static let letterStyle: TypeStyle = {
        var style = TypeStyle.dayHeaderWeekday
        style.isUppercased = false
        return style
    }()

    private var items: [WeekdayToggleItem] {
        WeekdayToggleItem.items(weekdays: weekdays, isOn: isOn, context: context)
    }

    var body: some View {
        HStack(spacing: Tokens.Spacing.xs) {
            ForEach(items, id: \.weekday) { item in
                toggle(item)
            }
        }
        .focusable()
        // layouts.md §8.1 (amended 2026-10-06; interactions.md §1, G-039):
        // no ring on the row — the focused toggle's inset stroke is the
        // row's whole focus indicator.
        .focusEffectDisabled()
        .focused($rowFocused)
        .onChange(of: focusRequest) { _, _ in rowFocused = true }
        .onChange(of: rowFocused) { _, focused in
            // Entering the row lands on the first toggle in display order,
            // unless `←`/`→` already chose one earlier.
            if focused, focusedWeekday == nil { focusedWeekday = weekdays.first }
            onFocusChange(focused)
        }
        // `.onKeyPress` returns `.handled` to stop the key here, or
        // `.ignored` to let it continue up to the window (e.g. `⌫`, `⌘[`).
        .onKeyPress(.leftArrow) { moveFocus(by: -1) }
        .onKeyPress(.rightArrow) { moveFocus(by: 1) }
        .onKeyPress(.space) {
            guard let focusedWeekday,
                  let item = items.first(where: { $0.weekday == focusedWeekday }) else { return .ignored }
            // A disabled toggle refuses `space` exactly as it refuses a click.
            if !item.isDisabled { onFlip(focusedWeekday) }
            return .handled
        }
        .accessibilityElement(children: .contain)
    }

    private func toggle(_ item: WeekdayToggleItem) -> some View {
        let focused = renderFocusedWeekday.map { $0 == item.weekday }
            ?? (rowFocused && focusedWeekday == item.weekday)
        return Button { onFlip(item.weekday) } label: {
            WeekdayToggleFace(item: item, isFocused: focused, letterStyle: Self.letterStyle)
                .contentShape(Rectangle())
        }
        // `.plain` drops the bezel (the square above is the whole look) and
        // keeps the system's disabled appearance for `.disabled(true)`.
        .buttonStyle(.plain)
        .disabled(item.isDisabled)
        // Not a tab stop of its own — the row is (see the file header).
        .focusable(false)
        .help(item.help ?? "")
        .accessibilityLabel(item.accessibilityLabel)
        .accessibilityValue(item.accessibilityValue)
        .accessibilityHint(item.help ?? "")
    }

    private func moveFocus(by offset: Int) -> KeyPress.Result {
        focusedWeekday = RoutineWeekdayActivation.movingFocus(from: focusedWeekday, by: offset, in: weekdays)
        return .handled
    }
}


/// One toggle's square: fill, letter, and the focused inset stroke. Split
/// out of the row so the stroke rule has one place it is drawn.
struct WeekdayToggleFace: View {
    let item: WeekdayToggleItem
    let isFocused: Bool
    let letterStyle: TypeStyle

    var body: some View {
        Text(item.letter)
            .typeStyle(letterStyle)
            // On: `text.onSolid` on `interactive.accent` (4.56 / 6.93).
            // Off: `text.secondary` on `surface.canvasSunken` (5.69 / 8.01).
            .foregroundStyle(item.isOn ? Tokens.Color.Text.onSolid : Tokens.Color.Text.secondary)
            .frame(width: Tokens.Size.weekdayToggleSize, height: Tokens.Size.weekdayToggleSize)
            .background(
                RoundedRectangle(cornerRadius: Tokens.Radius.chip, style: .continuous)
                    .fill(Self.color(item.fill)))
            .overlay {
                if isFocused {
                    // layouts.md §8.1 (G-028): `size.borderSelected`, INSET
                    // 1pt inside the toggle at `radius.chip` — an outside
                    // ring would touch the neighbour `spacing.xs` away.
                    // Keyboard focus only. Colour by fill (2026-10-07,
                    // G-049): see `WeekdayToggleItem.focusStroke`.
                    // (`strokeBorder` draws the whole line inside the shape;
                    // `padding(1)` then moves that shape 1pt in.)
                    RoundedRectangle(cornerRadius: Tokens.Radius.chip, style: .continuous)
                        .strokeBorder(Self.color(item.focusStroke), lineWidth: Tokens.Size.borderSelected)
                        .padding(1)
                        .allowsHitTesting(false)
                }
            }
    }

    static func color(_ fill: WeekdayToggleItem.Fill) -> Color {
        switch fill {
        case .accent: Tokens.Color.Interactive.accent
        case .canvasSunken: Tokens.Color.Surface.canvasSunken
        }
    }

    static func color(_ stroke: WeekdayToggleItem.FocusStroke) -> Color {
        switch stroke {
        case .focusRingOnAccent: Tokens.Color.Interactive.focusRingOnAccent
        case .focusRing: Tokens.Color.Interactive.focusRing
        }
    }
}
