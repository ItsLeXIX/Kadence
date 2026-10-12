//
//  MetaLineLayout.swift
//  Kadence
//
//  PHASE3-REVIEW.md fix 7 — components.md §3.4, amended 2026-10-10 (GAPS
//  G-079; DECISIONS 2026-10-10 "The room comes before the source on a block",
//  confirmed by Parsa): the `.full` tier's meta line is **`Location ·
//  Source`**, and it is the source that gives way.
//
//    1. The location is never truncated while any of the source name is
//       still drawn.
//    2. The source name tail-truncates (`HS_A3.15 · Universit…`).
//    3. It is dropped whole, with its separator, only when fewer than 4 of
//       its characters would fit.
//    4. With no location the line is just the source name.
//
//  The rule before this was the reverse — source first, location truncating —
//  written when source names were short fixtures. A real source is called
//  `University timetable`, which fills a Week column by itself: every lecture
//  read `University timetabl…` and none showed its room.
//
//  Pure arithmetic over a width and a text-measuring function, so it is
//  tested without rendering (as `CompactRowLayout` is).
//

import CoreGraphics
import Foundation

enum MetaLineLayout {
    static let separator = " · "
    static let ellipsis = "…"
    /// Rule 3: fewer than this many characters of the source name is not a
    /// name any more.
    static let minimumSourceCharacters = 4

    /// What the meta line draws in `width`.
    ///
    /// - Parameters:
    ///   - lead: what comes first — the location (`HS_A3.15`), `Online`, or
    ///     §6's `Cancelled`. Nil or empty: the source name alone.
    ///   - source: the source's display name.
    ///   - width: the content row's width.
    ///   - measure: the natural width of a string in `typography.blockMeta`.
    static func resolve(lead: String?, source: String, width: CGFloat,
                        measure: (String) -> CGFloat = { CompactRowLayout.metaWidth($0) }) -> String {
        // Rule 4. SwiftUI truncates a lone source name's tail itself.
        guard let lead, !lead.isEmpty else { return source }
        let full = lead + separator + source
        if measure(full) <= width { return full }
        // Rule 2: the longest head of the source name that fits with its `…`.
        let characters = Array(source)
        var count = characters.count - 1
        while count >= minimumSourceCharacters {
            // No space left hanging before the ellipsis (`University…`).
            let head = String(characters.prefix(count)).trimmingCharacters(in: .whitespaces)
            if head.count >= minimumSourceCharacters, measure(lead + separator + head + ellipsis) <= width {
                return lead + separator + head + ellipsis
            }
            count -= 1
        }
        // Rule 3: dropped whole, separator included. (If even the location
        // does not fit, the view truncates its tail — there is nothing left
        // to give way.)
        return lead
    }
}
