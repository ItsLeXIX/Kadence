//
//  StatusItemLayout.swift
//  Kadence
//
//  components.md §15.1 with its 2026-10-01 amendment (task P2-T47): how the
//  status item spends the width it is given.
//
//  - The leading part (the time, or in the late state the glyph plus the
//    elapsed figure) is never truncated. It is always drawn at its full
//    measured width, even if that exceeds what is available.
//  - `HH:mm · Title` is shown, title truncated tail-first, while the space
//    left after the leading part and the ` · ` separator is at least
//    `size.statusItemTitleMinWidth`.
//  - Below that, the leading part alone: no separator, no ellipsis.
//  - The item is AT MOST `size.statusItemMaxWidth` wide (a budget, not a
//    guarantee): its width is what it actually draws.
//
//  Pure arithmetic over measured widths, so the rule is unit-testable.
//

import Foundation
import CoreGraphics

enum StatusItemLayout {

    struct Result: Equatable {
        /// Whether ` · Title` is drawn at all.
        let showsTitle: Bool
        /// Width given to ` · Title` (separator included); 0 when hidden.
        let titleSlotWidth: CGFloat
        /// The item's width: leading + title slot.
        let totalWidth: CGFloat
    }

    /// - Parameters:
    ///   - leadingWidth: the time (or glyph + elapsed), measured.
    ///   - separatorWidth: ` · `, measured.
    ///   - titleWidth: the full title, measured; 0 for no title.
    ///   - available: what the item is given. Capped at
    ///     `statusItemMaxWidth`.
    static func resolve(
        leadingWidth: CGFloat, separatorWidth: CGFloat, titleWidth: CGFloat, available: CGFloat,
        maxWidth: CGFloat = Tokens.Size.statusItemMaxWidth,
        titleMinWidth: CGFloat = Tokens.Size.statusItemTitleMinWidth
    ) -> Result {
        let budget = min(available, maxWidth)
        let leftForTitle = budget - leadingWidth - separatorWidth
        guard titleWidth > 0, leftForTitle >= titleMinWidth else {
            // The time alone. Never truncated: if even the time is wider than
            // the budget, the item is as wide as the time.
            return Result(showsTitle: false, titleSlotWidth: 0, totalWidth: leadingWidth)
        }
        let title = min(titleWidth, leftForTitle)
        let slot = separatorWidth + title
        return Result(showsTitle: true, titleSlotWidth: slot, totalWidth: leadingWidth + slot)
    }
}
