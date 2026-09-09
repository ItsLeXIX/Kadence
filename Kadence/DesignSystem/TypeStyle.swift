//
//  TypeStyle.swift
//  Kadence
//
//  Turns the `typography.*` token groups into something a view can apply.
//
//  Every style carries a `textStyle`, and the font is built relative to it, so
//  the whole app scales with Dynamic Type (BRIEF-DESIGN.md, components.md §11)
//  rather than being pinned to fixed point sizes.
//

import SwiftUI

struct TypeStyle: Equatable, Sendable {
    var size: CGFloat
    var weight: Font.Weight
    var textStyle: Font.TextStyle
    /// 0 in the tokens means "no limit"; SwiftUI wants `nil` for that.
    var lineLimit: Int?
    var tracking: CGFloat
    var isUppercased: Bool
    var monospacedDigit: Bool

    init(
        size: CGFloat,
        weight: String,
        textStyle: String,
        lineLimit: CGFloat,
        tracking: CGFloat = 0,
        textCase: String? = nil,
        monospacedDigit: Bool = false
    ) {
        self.size = size
        self.weight = TypeStyle.weight(named: weight)
        self.textStyle = TypeStyle.textStyle(named: textStyle)
        let limit = Int(lineLimit)
        self.lineLimit = limit > 0 ? limit : nil
        self.tracking = tracking
        self.isUppercased = (textCase == "uppercase")
        self.monospacedDigit = monospacedDigit
    }

    // The token vocabulary. An unknown name falls back rather than trapping —
    // a typo in tokens.json must not crash the app (BRIEF-PRODUCT.md: errors
    // surface in the UI, never as a crash).
    static func weight(named name: String) -> Font.Weight {
        switch name {
        case "ultraLight": .ultraLight
        case "thin": .thin
        case "light": .light
        case "regular": .regular
        case "medium": .medium
        case "semibold": .semibold
        case "bold": .bold
        case "heavy": .heavy
        case "black": .black
        default: .regular
        }
    }

    static func textStyle(named name: String) -> Font.TextStyle {
        switch name {
        case "largeTitle": .largeTitle
        case "title": .title
        case "title2": .title2
        case "title3": .title3
        case "headline": .headline
        case "subheadline": .subheadline
        case "body": .body
        case "callout": .callout
        case "footnote": .footnote
        case "caption1": .caption
        case "caption2": .caption2
        default: .body
        }
    }
}

// MARK: - The token-backed styles

extension TypeStyle {
    static let blockTitle = TypeStyle(
        size: Tokens.Typography.BlockTitle.size,
        weight: Tokens.Typography.BlockTitle.weight,
        textStyle: Tokens.Typography.BlockTitle.textStyle,
        lineLimit: Tokens.Typography.BlockTitle.lineLimit)

    static let blockTitleCompact = TypeStyle(
        size: Tokens.Typography.BlockTitleCompact.size,
        weight: Tokens.Typography.BlockTitleCompact.weight,
        textStyle: Tokens.Typography.BlockTitleCompact.textStyle,
        lineLimit: Tokens.Typography.BlockTitleCompact.lineLimit)

    static let blockMeta = TypeStyle(
        size: Tokens.Typography.BlockMeta.size,
        weight: Tokens.Typography.BlockMeta.weight,
        textStyle: Tokens.Typography.BlockMeta.textStyle,
        lineLimit: Tokens.Typography.BlockMeta.lineLimit,
        monospacedDigit: Tokens.Typography.BlockMeta.monospacedDigit)

    static let travelLabel = TypeStyle(
        size: Tokens.Typography.TravelLabel.size,
        weight: Tokens.Typography.TravelLabel.weight,
        textStyle: Tokens.Typography.TravelLabel.textStyle,
        lineLimit: Tokens.Typography.TravelLabel.lineLimit,
        monospacedDigit: Tokens.Typography.TravelLabel.monospacedDigit)

    static let countdownChip = TypeStyle(
        size: Tokens.Typography.CountdownChip.size,
        weight: Tokens.Typography.CountdownChip.weight,
        textStyle: Tokens.Typography.CountdownChip.textStyle,
        lineLimit: Tokens.Typography.CountdownChip.lineLimit,
        monospacedDigit: Tokens.Typography.CountdownChip.monospacedDigit)

    static let hourLabel = TypeStyle(
        size: Tokens.Typography.HourLabel.size,
        weight: Tokens.Typography.HourLabel.weight,
        textStyle: Tokens.Typography.HourLabel.textStyle,
        lineLimit: Tokens.Typography.HourLabel.lineLimit,
        monospacedDigit: Tokens.Typography.HourLabel.monospacedDigit)

    static let windowLabel = TypeStyle(
        size: Tokens.Typography.WindowLabel.size,
        weight: Tokens.Typography.WindowLabel.weight,
        textStyle: Tokens.Typography.WindowLabel.textStyle,
        lineLimit: Tokens.Typography.WindowLabel.lineLimit)

    static let dayHeaderWeekday = TypeStyle(
        size: Tokens.Typography.DayHeaderWeekday.size,
        weight: Tokens.Typography.DayHeaderWeekday.weight,
        textStyle: Tokens.Typography.DayHeaderWeekday.textStyle,
        lineLimit: Tokens.Typography.DayHeaderWeekday.lineLimit,
        tracking: Tokens.Typography.DayHeaderWeekday.tracking,
        textCase: Tokens.Typography.DayHeaderWeekday.textCase)

    static let dayHeaderDate = TypeStyle(
        size: Tokens.Typography.DayHeaderDate.size,
        weight: Tokens.Typography.DayHeaderDate.weight,
        textStyle: Tokens.Typography.DayHeaderDate.textStyle,
        lineLimit: Tokens.Typography.DayHeaderDate.lineLimit,
        monospacedDigit: Tokens.Typography.DayHeaderDate.monospacedDigit)

    static let monthDate = TypeStyle(
        size: Tokens.Typography.MonthDate.size,
        weight: Tokens.Typography.MonthDate.weight,
        textStyle: Tokens.Typography.MonthDate.textStyle,
        lineLimit: Tokens.Typography.MonthDate.lineLimit,
        monospacedDigit: Tokens.Typography.MonthDate.monospacedDigit)

    static let allDayLabel = TypeStyle(
        size: Tokens.Typography.AllDayLabel.size,
        weight: Tokens.Typography.AllDayLabel.weight,
        textStyle: Tokens.Typography.AllDayLabel.textStyle,
        lineLimit: Tokens.Typography.AllDayLabel.lineLimit)

    static let sidebarSection = TypeStyle(
        size: Tokens.Typography.SidebarSection.size,
        weight: Tokens.Typography.SidebarSection.weight,
        textStyle: Tokens.Typography.SidebarSection.textStyle,
        lineLimit: Tokens.Typography.SidebarSection.lineLimit,
        tracking: Tokens.Typography.SidebarSection.tracking,
        textCase: Tokens.Typography.SidebarSection.textCase)

    static let sidebarItem = TypeStyle(
        size: Tokens.Typography.SidebarItem.size,
        weight: Tokens.Typography.SidebarItem.weight,
        textStyle: Tokens.Typography.SidebarItem.textStyle,
        lineLimit: Tokens.Typography.SidebarItem.lineLimit)

    static let toolbarTitle = TypeStyle(
        size: Tokens.Typography.ToolbarTitle.size,
        weight: Tokens.Typography.ToolbarTitle.weight,
        textStyle: Tokens.Typography.ToolbarTitle.textStyle,
        lineLimit: Tokens.Typography.ToolbarTitle.lineLimit)

    static let inspectorTitle = TypeStyle(
        size: Tokens.Typography.InspectorTitle.size,
        weight: Tokens.Typography.InspectorTitle.weight,
        textStyle: Tokens.Typography.InspectorTitle.textStyle,
        lineLimit: Tokens.Typography.InspectorTitle.lineLimit)

    static let inspectorLabel = TypeStyle(
        size: Tokens.Typography.InspectorLabel.size,
        weight: Tokens.Typography.InspectorLabel.weight,
        textStyle: Tokens.Typography.InspectorLabel.textStyle,
        lineLimit: Tokens.Typography.InspectorLabel.lineLimit)

    static let inspectorValue = TypeStyle(
        size: Tokens.Typography.InspectorValue.size,
        weight: Tokens.Typography.InspectorValue.weight,
        textStyle: Tokens.Typography.InspectorValue.textStyle,
        lineLimit: Tokens.Typography.InspectorValue.lineLimit)
}

// MARK: - Applying a style

private struct TypeStyleModifier: ViewModifier {
    let style: TypeStyle
    /// `@ScaledMetric` is how an explicit point size still participates in
    /// Dynamic Type: it scales `size` by the same factor the named text style
    /// would be scaled by.
    @ScaledMetric private var scaledSize: CGFloat

    init(style: TypeStyle) {
        self.style = style
        _scaledSize = ScaledMetric(wrappedValue: style.size, relativeTo: style.textStyle)
    }

    func body(content: Content) -> some View {
        var font = Font.system(size: scaledSize, weight: style.weight)
        if style.monospacedDigit { font = font.monospacedDigit() }
        return content
            .font(font)
            .tracking(style.tracking)
            .lineLimit(style.lineLimit)
            .textCase(style.isUppercased ? .uppercase : nil)
    }
}

extension View {
    func typeStyle(_ style: TypeStyle) -> some View {
        modifier(TypeStyleModifier(style: style))
    }
}
