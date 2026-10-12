//
//  CascadeGap.swift
//  Kadence
//
//  PHASE3-REVIEW.md fix 6 — components.md §3.3 "a covering block is separated
//  from what it covers" (added 2026-10-10; GAPS G-078; DECISIONS 2026-10-10
//  "A covered block keeps its title, and a covering block has a gap").
//
//  Found in real use: `BPREF-Info` 18:35–20:15 under `BPREF-Info` 19:30–20:15
//  read as one block with two glyphs. Two `.fixedTimed` blocks of one source
//  have the same fill, no rail and no border, and a cascaded block sat flush
//  on the one beneath it. Every block in a cascade with index ≥ 1 now has
//  `size.blockColumnGap` (2) of canvas along its leading and top edges,
//  outside its own frame: the covered block is cut back there, and the
//  covering block's frame does not move.
//
//  The gap is not painted. `DayLayoutEngine.applyCovering` gives each covered
//  block the strips to give up (`LaidOutBlock.gapCuts`), and this modifier
//  removes them from what the block draws — so what shows through is the
//  canvas itself, hour lines and window treatments included, exactly as
//  between packed neighbours.
//

import SwiftUI

private struct CascadeGapCuts: ViewModifier {
    /// The strips to remove, in the modified view's own coordinates.
    let cuts: [CGRect]

    func body(content: Content) -> some View {
        if cuts.isEmpty {
            content
        } else {
            // Swift note: `.mask` keeps the content only where the mask is
            // opaque. The mask is "everything" with the strips punched out:
            // `.destinationOut` erases what is already drawn beneath a shape,
            // and `compositingGroup()` makes the stack one image first, so
            // the erasing stays inside the mask.
            content.mask {
                ZStack(alignment: .topLeading) {
                    // Larger than the block: its selection ring and its
                    // shadow are drawn outside its frame and must survive.
                    Rectangle().padding(-Self.outset)
                    ForEach(cuts.indices, id: \.self) { index in
                        Rectangle()
                            .frame(width: cuts[index].width, height: cuts[index].height)
                            .offset(x: cuts[index].minX, y: cuts[index].minY)
                            .blendMode(.destinationOut)
                    }
                }
                .compositingGroup()
            }
        }
    }

    static let outset: CGFloat = 24
}

extension View {
    /// Removes a covering block's gap from this (covered) block.
    /// - Parameters:
    ///   - cuts: `LaidOutBlock.gapCuts`, in the day column's coordinates.
    ///   - origin: this view's top-leading corner in the same coordinates.
    func cascadeGapCuts(_ cuts: [CGRect], origin: CGPoint) -> some View {
        modifier(CascadeGapCuts(cuts: cuts.map { $0.offsetBy(dx: -origin.x, dy: -origin.y) }))
    }
}
