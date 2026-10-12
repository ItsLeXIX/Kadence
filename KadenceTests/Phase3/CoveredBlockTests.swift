//
//  CoveredBlockTests.swift
//  KadenceTests
//
//  PHASE3-REVIEW.md fix 6 — components.md §3.3 (the 2026-10-06 title-band
//  rule, required 2026-10-10: G-048, DEVIATIONS A35; and "a covering block is
//  separated from what it covers", G-078); layouts.md §3.3.
//
//  The regression is Parsa's Fri 2 Oct 2026, from
//  `fixtures/cis-2026WS-redacted.ics` through `reportCISOverlap`: `BPREF-Info`
//  18:35–20:15 under `BPREF-Info` 19:30–20:15 — two `.fixedTimed` blocks of
//  one source — drew as what looked like one block with two glyphs and one
//  title in its lower part.
//

import Testing
import Foundation
import SwiftData
import SwiftUI
import AppKit
@testable import Kadence

@MainActor
@Suite(.serialized)
struct CoveredBlockTests {

    /// Thu 1 Oct 2026 10:00 — 2 Oct is not history, so the blocks are solid.
    private let clock = TestClock.date("2026-10-01 10:00")
    private let gap = Tokens.Size.blockColumnGap

    private struct Friday {
        var long: Event
        var short: Event
        var sources: SourceDirectory
        var container: ModelContainer
    }

    /// Fri 2 Oct of `reportCISOverlap` (the `fresh` dataset).
    private func friday() throws -> Friday {
        let container = try ModelContainer(for: Schema(KadenceSchema.models),
                                           configurations: ModelConfiguration(isStoredInMemoryOnly: true))
        let context = ModelContext(container)
        ReviewMode.seedFresh(context: context, now: clock, secrets: InMemorySecretStore(), zone: TestClock.zone)
        let sessions = try context.fetch(FetchDescriptor<Event>()).filter { $0.title == "BPREF-Info" }.sorted { $0.start < $1.start }
        #expect(sessions.count == 2)
        return Friday(long: try #require(sessions.first), short: try #require(sessions.last),
                      sources: SourceDirectory(try context.fetch(FetchDescriptor<Source>())), container: container)
    }

    private func layout(_ events: [Event], columnWidth: CGFloat, hourHeight: CGFloat) -> (DayLayout, TimeGeometry) {
        let dayStart = Calendar.current.startOfDay(for: events[0].start)
        let geometry = TimeGeometry(dayStart: dayStart, hourHeight: hourHeight)
        let items = events.map { LayoutItem(id: $0.id, start: $0.start, end: $0.end, title: $0.title) }
        return (DayLayoutEngine.layout(items: items, columnWidth: columnWidth, geometry: geometry), geometry)
    }

    private func tier(_ block: LaidOutBlock, kind: BlockKind = .fixedTimed, presentation: Presentation = []) -> DensityTier {
        resolveBlockStyle(kind: kind, flexibility: .fixed, status: .scheduled, presentation: presentation, source: .blue,
                          renderedHeight: block.frame.height, visibleWidth: block.titleBandWidth,
                          isCovered: block.isCovered).contentTier
    }

    // MARK: The regression — Week, 124pt column

    @Test("Fri 2 Oct at a 124pt Week column: a cascade; the covered lecture keeps its title; the covering one has a 2pt gap")
    func weekColumn() throws {
        let f = try friday()
        let (layout, geometry) = layout([f.long, f.short], columnWidth: 124, hourHeight: Tokens.Size.hourHeightWeek)
        #expect(layout.blocks.count == 2 && layout.overflow.isEmpty)
        let block0 = try #require(layout.block(for: f.long.id)), block1 = try #require(layout.block(for: f.short.id))
        // A cascade: the slot would be (124 − 4) / 2 − 2 = 58 < 72.
        #expect(block0.isCascaded && block1.isCascaded)
        #expect(block0.zIndex < block1.zIndex)
        let indent = DayLayoutEngine.cascadeIndent(columnWidth: 124)
        #expect(indent == 22)

        // Block 0 — the 18:35 lecture, covered from 19:30 on.
        #expect(block0.frame.minX == 0 && block0.frame.width == 124)
        #expect(block0.isCovered)
        // Its title band (the top 5 + 14 = 19pt) is unobstructed at full
        // width: the 19:30 session starts 40pt further down.
        #expect(LaidOutBlock.titleBandHeight(forBlockHeight: block0.frame.height) == 19)
        #expect(block0.titleBandWidth == 124)
        // …so it draws the `.titleOnly` content set — its title — although
        // the narrowest strip of it is only one indent wide (the A35 reading,
        // which drew the glyph alone).
        #expect(block0.visibleWidth == indent)
        #expect(tier(block0) == .titleOnly)
        #expect(DensityTier(renderedHeight: block0.frame.height) == .full)   // never more than its height tier
        let model0 = GridBlockModel(event: f.long, now: clock, sources: f.sources)
        #expect(model0.title == "BPREF-Info" && model0.sourceName == "University timetable")

        // Block 1 — the 19:30 session, on top, indented, not covered.
        #expect(block1.frame.minX == indent && block1.frame.maxX == 124)
        #expect(abs(block1.frame.minY - geometry.y(for: f.short.start)) < 0.001)   // its frame did not move
        #expect(!block1.isCovered && block1.gapCuts.isEmpty && block1.titleBandWidth == block1.frame.width)
        #expect(tier(block1) == DensityTier(renderedHeight: block1.frame.height))
        #expect(tier(block1) == .compact)

        // The gap: 2pt of canvas along block 1's leading and top edges,
        // outside its frame. Block 0 is cut back there.
        let top = CGRect(x: block1.frame.minX - gap, y: block1.frame.minY - gap, width: block1.frame.width + gap, height: gap)
        let leading = CGRect(x: block1.frame.minX - gap, y: block1.frame.minY - gap, width: gap, height: block1.frame.height + gap)
        #expect(block0.gapCuts.count == 2)
        #expect(block0.gapCuts.contains(top) && block0.gapCuts.contains(leading))
        // Block 0's drawn area does not reach into the gap — at any point of it…
        var probed = 0
        for strip in [top, leading] {
            for x in stride(from: strip.minX + 0.5, to: strip.maxX, by: 1) {
                for y in stride(from: strip.minY + 0.5, to: strip.maxY, by: 1) {
                    let point = CGPoint(x: x, y: y)
                    #expect(!block0.draws(at: point))
                    #expect(!block1.frame.contains(point))   // nor is it part of block 1
                    probed += 1
                }
            }
        }
        #expect(probed > 250)
        // …while it still draws beside and above the covering block.
        #expect(block0.draws(at: CGPoint(x: 10, y: block1.frame.midY)))             // the visible strip
        #expect(block0.draws(at: CGPoint(x: 60, y: block1.frame.minY - gap - 1)))   // just above the gap
        #expect(block0.draws(at: CGPoint(x: 60, y: block0.frame.minY + 5)))         // the title band
    }

    // MARK: The regression — Day, 400pt column

    @Test("The same day at a 400pt Day column: packed in two slots, nothing covered, each at its height tier")
    func dayColumn() throws {
        let f = try friday()
        let (layout, _) = layout([f.long, f.short], columnWidth: 400, hourHeight: Tokens.Size.hourHeightDay)
        let block0 = try #require(layout.block(for: f.long.id)), block1 = try #require(layout.block(for: f.short.id))
        // Slot width (400 − 4) / 2 − 2 = 196 ≥ 72: packed, side by side.
        #expect(!block0.isCascaded && !block1.isCascaded)
        #expect(block0.frame.width == 196 && block1.frame.width == 196)
        #expect(block0.frame.maxX < block1.frame.minX)
        #expect(block1.frame.minX - block0.frame.maxX == gap)     // the 2pt of canvas packed neighbours have
        #expect(!block0.isCovered && !block1.isCovered)
        #expect(block0.gapCuts.isEmpty && block1.gapCuts.isEmpty)
        #expect(block0.titleBandWidth == 196 && block1.titleBandWidth == 196)
        #expect(tier(block0) == .full)       // 100 min at 60pt/h = 100pt
        #expect(tier(block1) == .compact)    // 45 min = 45pt
    }

    // MARK: The title-band rule (2026-10-06)

    private func block(_ title: String, _ start: String, _ end: String) -> Event {
        Event(title: title, start: TestClock.date("2026-10-07 \(start)"), end: TestClock.date("2026-10-07 \(end)"),
              origin: .manual)
    }

    @Test("Phase 2's conflict-panel-two-options case: Wednesday's Training (17:00–18:30), covered from 17:30, draws its title")
    func trainingKeepsItsTitle() throws {
        let training = block("Training", "17:00", "18:30"), meeting = block("Supervisor meeting", "17:30", "18:30")
        let (layout, _) = layout([training, meeting], columnWidth: 124, hourHeight: Tokens.Size.hourHeightWeek)
        let covered = try #require(layout.block(for: training.id)), covering = try #require(layout.block(for: meeting.id))
        #expect(covered.isCascaded && covered.isCovered && !covering.isCovered)
        // 30 min at 44pt/h = 22pt of uncovered strip above the meeting; the
        // title band needs 19, the gap takes 2.
        #expect(covering.frame.minY - covered.frame.minY == 22)
        #expect(covered.titleBandWidth == 124)
        #expect(tier(covered, kind: .routineTimed) == .titleOnly)
        // Conflicted, as in that frame: the badge takes the trailing corner
        // and the title is still drawn (§6).
        let style = resolveBlockStyle(kind: .routineTimed, flexibility: .shiftable, status: .scheduled,
                                      presentation: [.conflicted], source: .green, renderedHeight: covered.frame.height,
                                      visibleWidth: covered.titleBandWidth, isCovered: covered.isCovered)
        #expect(style.contentTier == .titleOnly && style.badge != nil)
        #expect(style.glyph == "repeat")   // the type glyph: the badge replaces it only at `.glyphOnly`
    }

    @Test("A title band the covering block crosses below 44pt is glyph-only; an uncovered block keeps its height tier", arguments: [
        ("17:00", 20.0, DensityTier.glyphOnly),   // same start: the band is covered from the indent − gap = 20pt
        ("17:15", 20.0, .glyphOnly),              // starts 11pt down, inside the 19pt band
        ("17:25", 20.0, .glyphOnly),              // 18.3pt down: its gap (from 16.3) still crosses the band
        ("17:30", 124.0, .titleOnly),             // 22pt down: clear of the band and its gap
        ("18:00", 124.0, .titleOnly),
    ])
    func titleBand(coverStart: String, bandWidth: Double, expected: DensityTier) throws {
        let under = block("Under", "17:00", "19:00"), over = block("Over", coverStart, "19:00")
        let (layout, _) = layout([under, over], columnWidth: 124, hourHeight: Tokens.Size.hourHeightWeek)
        // Paint order is layouts.md §3.3's sort; the earlier in it is the
        // covered one (with the same start and length, that is by title).
        let byZ = layout.blocks.sorted { $0.zIndex < $1.zIndex }
        let covered = try #require(byZ.first), onTop = try #require(byZ.last)
        #expect(byZ.count == 2 && (coverStart == "17:00" || covered.id == under.id))
        #expect(covered.isCovered && !onTop.isCovered)
        #expect(abs(covered.titleBandWidth - CGFloat(bandWidth)) < 0.001)
        #expect(tier(covered) == expected)
        #expect(tier(onTop) == DensityTier(renderedHeight: onTop.frame.height))   // on top: its own height tier
    }

    @Test("Blocks of one cascade cluster that do not overlap each other are not covered")
    func transitiveClusterIsNotCovering() throws {
        // A overlaps B, B overlaps C, A and C do not touch: one cluster of three.
        let a = block("A", "09:00", "10:30"), b = block("B", "10:00", "12:00"), c = block("C", "11:30", "13:00")
        let (layout, _) = layout([a, b, c], columnWidth: 124, hourHeight: Tokens.Size.hourHeightWeek)
        let la = try #require(layout.block(for: a.id)), lb = try #require(layout.block(for: b.id)), lc = try #require(layout.block(for: c.id))
        #expect(la.isCascaded && lb.isCascaded && lc.isCascaded)
        #expect(la.isCovered && lb.isCovered && !lc.isCovered)
        // A is covered by B only: C's gap never reaches it.
        #expect(la.gapCuts.count == 2 && lb.gapCuts.count == 2)
        #expect(la.gapCuts.allSatisfy { $0.minX == lb.frame.minX - gap })
        #expect(lb.gapCuts.allSatisfy { $0.minX == lc.frame.minX - gap })
        #expect(tier(la) == .titleOnly && tier(lb) == .titleOnly && tier(lc) == .full)
    }

    @Test("The resolver: covered + a readable band → titleOnly, capped by the height tier; an unreadable band → glyphOnly")
    func resolverRule() {
        func t(_ height: CGFloat, band: CGFloat, covered: Bool) -> DensityTier {
            resolveBlockStyle(kind: .fixedTimed, flexibility: .fixed, status: .scheduled, presentation: [], source: .blue,
                              renderedHeight: height, visibleWidth: band, isCovered: covered).contentTier
        }
        #expect(t(80, band: 124, covered: true) == .titleOnly)
        #expect(t(80, band: 44, covered: true) == .titleOnly)
        #expect(t(80, band: 43.9, covered: true) == .glyphOnly)
        #expect(t(40, band: 124, covered: true) == .titleOnly)     // compact by height, capped
        #expect(t(20, band: 124, covered: true) == .titleOnly)
        #expect(t(14, band: 124, covered: true) == .glyphOnly)     // never more than its height tier
        #expect(t(80, band: 124, covered: false) == .full)         // not covered: the ladder alone
        #expect(t(80, band: .infinity, covered: false) == .full)
    }

    // MARK: The gap, as drawn

    @Test("Render: the gap's pixels are surface.canvas; both blocks are drawn on either side of it")
    func gapIsCanvas() throws {
        let f = try friday()
        Phase3Render.keep.append(f.container)
        let (layout, _) = layout([f.long, f.short], columnWidth: 124, hourHeight: Tokens.Size.hourHeightWeek)
        let block0 = try #require(layout.block(for: f.long.id)), block1 = try #require(layout.block(for: f.short.id))
        let originY = block0.frame.minY - 10
        let size = CGSize(width: 150, height: block0.frame.height + 20)

        // The two blocks exactly as the day column draws them: the real
        // block view, the engine's frames, the same gap modifier.
        func drawn(_ event: Event, _ laidOut: LaidOutBlock) -> some View {
            GridBlockView(model: GridBlockModel(event: event, now: clock, sources: f.sources), presentation: [],
                          renderedHeight: laidOut.frame.height, visibleWidth: laidOut.titleBandWidth,
                          isCovered: laidOut.isCovered)
                .frame(width: laidOut.frame.width, height: laidOut.frame.height, alignment: .topLeading)
                .cascadeGapCuts(laidOut.gapCuts, origin: laidOut.frame.origin)
                .offset(x: laidOut.frame.minX, y: laidOut.frame.minY - originY)
        }
        let view = ZStack(alignment: .topLeading) {
            Tokens.Color.Surface.canvas
            drawn(f.long, block0)
            drawn(f.short, block1)
        }
        .frame(width: size.width, height: size.height, alignment: .topLeading)
        let image = try #require(Phase3Render.render("cascade-gap", view, size: size))
        let bitmap = try #require(image.representations.compactMap { $0 as? NSBitmapImageRep }.first)
        let scale = CGFloat(bitmap.pixelsWide) / size.width

        /// The colour at a point given in the day column's coordinates.
        func colour(_ x: CGFloat, _ y: CGFloat) throws -> [Int] {
            let c = try #require(bitmap.colorAt(x: Int((x * scale).rounded(.down)), y: Int(((y - originY) * scale).rounded(.down)))?
                .usingColorSpace(.sRGB))
            return [c.redComponent, c.greenComponent, c.blueComponent].map { Int(($0 * 255).rounded()) }
        }
        // Bare canvas, right of the 124pt column.
        let canvas = try colour(140, block1.frame.midY)
        // The solid fill, where each block is certainly drawn and has no text.
        let fill0 = try colour(8, block1.frame.maxY - 4)                       // block 0's visible strip, low down
        let fill1 = try colour(block1.frame.maxX - 6, block1.frame.maxY - 4)   // block 1's trailing bottom corner area
        #expect(fill0 != canvas && fill1 != canvas)
        #expect(fill0 == fill1)   // one source, one fill: this is why the gap is needed

        // The leading gap (x 20…22) beside block 1, and the top gap (y −2…0) above it.
        let leadingX = block1.frame.minX - gap / 2
        for y in [block1.frame.minY + 4, block1.frame.midY, block1.frame.maxY - 4] {
            #expect(try colour(leadingX, y) == canvas, "leading gap at y \(y)")
        }
        let topY = block1.frame.minY - gap / 2
        for x in [block1.frame.minX + 6, block1.frame.midX, block1.frame.maxX - 6] {
            #expect(try colour(x, topY) == canvas, "top gap at x \(x)")
        }
        // Either side of the gap is block: 3pt left of it and 3pt above it are block 0.
        #expect(try colour(block1.frame.minX - gap - 3, block1.frame.midY) == fill0)
        #expect(try colour(block1.frame.maxX - 6, block1.frame.minY - gap - 3) == fill0)
    }
}
