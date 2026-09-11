//
//  BlockConfinementTests.swift
//  KadenceTests
//
//  Regression cover for P2-T05: two blocks that do not overlap in time were
//  drawn on top of each other (STATUS.md §1.7 symptom (a), DEVIATIONS B13/D4).
//
//  The ruling is design/GAPS.md G-011 — CLOSED, landed in components.md §3.1,
//  §3.3, §3.4 and the new §3.5. Two independent halves, and they fail
//  independently, so both are asserted here:
//
//    1. the LADDER — every tier's band bottom is at or above that tier's own
//       minimum, so the content set a height is assigned actually fits in it.
//       That is `DensityTier` + `BlockContentMetrics`, pure value types;
//    2. the CONFINEMENT invariant (§3.5) — a block paints only inside its own
//       laid-out frame, top-anchored, clipped at the bottom. The arithmetic half
//       is asserted here over the metrics; the modifier half (`.frame(height:
//       alignment: .top)` before `.clipShape`) is asserted through an
//       `NSHostingView` that measures what the view actually claims for itself.
//
//  The numbers below are the spec's own, from G-011's CLOSED table and §3.3.
//

import Testing
import Foundation
import CoreGraphics
import SwiftUI
import AppKit
@testable import Kadence

private let wednesday = Calendar(identifier: .gregorian).date(
    from: DateComponents(year: 2026, month: 9, day: 9))!

private func at(_ hour: Int, _ minute: Int = 0) -> Date {
    wednesday.addingTimeInterval(TimeInterval(hour * 3600 + minute * 60))
}

private let dayGeometry = TimeGeometry(dayStart: wednesday, hourHeight: Tokens.Size.hourHeightDay)
private let weekGeometry = TimeGeometry(dayStart: wednesday, hourHeight: Tokens.Size.hourHeightWeek)

// MARK: - The ladder

@Suite("Density ladder — G-011 bands")
struct DensityLadderRulingTests {

    @Test("The three boundaries are 18 / 28 / 53, not 16 / 28 / 44", arguments: [
        (11.0, DensityTier.glyphOnly),
        (17.0, DensityTier.glyphOnly),
        (17.9, DensityTier.glyphOnly),
        (18.0, DensityTier.titleOnly),
        (27.0, DensityTier.titleOnly),
        (28.0, DensityTier.compact),
        (52.0, DensityTier.compact),
        (52.9, DensityTier.compact),
        (53.0, DensityTier.full),
    ])
    func boundaries(height: Double, expected: DensityTier) {
        #expect(DensityTier(renderedHeight: CGFloat(height)) == expected)
    }

    @Test("§3.3 line heights are ceil(size × 1.2): 15 / 14 / 14")
    func lineHeights() {
        #expect(BlockLineHeights.standard.title == 15)
        #expect(BlockLineHeights.standard.titleCompact == 14)
        #expect(BlockLineHeights.standard.meta == 14)
    }

    @Test("Per-tier vertical padding matches G-011's table")
    func verticalPadding() {
        #expect(DensityTier.glyphOnly.verticalPadding == 0)
        #expect(DensityTier.titleOnly.verticalPadding == Tokens.Spacing.xxs)
        #expect(DensityTier.titleOnly.verticalPadding == 2)
        #expect(DensityTier.compact.verticalPadding == Tokens.Size.blockPadding)
        #expect(DensityTier.full.verticalPadding == Tokens.Size.blockPadding)
        #expect(DensityTier.full.verticalPadding == 5)
    }

    @Test("Each tier's minimum is G-011's arithmetic")
    func minima() {
        // 5 + 15 + 14 + 14 + 5 = 53
        #expect(DensityTier.full.minimumHeight() == 53)
        // 5 + 14 + 5 = 24
        #expect(DensityTier.compact.minimumHeight() == 24)
        // 2 + 14 + 2 = 18
        #expect(DensityTier.titleOnly.minimumHeight() == 18)
        // 0 + 11 + 0 = 11
        #expect(DensityTier.glyphOnly.minimumHeight() == 11)
        #expect(DensityTier.glyphOnly.minimumHeight() == Tokens.Size.blockMinRenderedHeight)
    }

    @Test("The invariant G-011 broke: a tier's band bottom is never below its own minimum")
    func bandBottomsCoverTheirMinima() {
        for tier in DensityTier.allCases {
            let bandBottom: CGFloat = switch tier {
            case .glyphOnly: 11
            case .titleOnly: 18
            case .compact: 28
            case .full: 53
            }
            #expect(
                tier.minimumHeight() <= bandBottom,
                "\(tier) is assigned at \(bandBottom)pt but needs \(tier.minimumHeight())pt")
        }
    }

    @Test("Every height from the floor up gets a content set that fits inside it")
    func contentNeverExceedsTheFrame() {
        var height = Tokens.Size.blockMinRenderedHeight
        while height <= 400 {
            let metrics = BlockContentMetrics.resolve(availableHeight: height)
            #expect(
                metrics.contentHeight <= height,
                "\(metrics.tier) needs \(metrics.contentHeight)pt in a \(height)pt frame")
            #expect(metrics.fits)
            height += 0.5
        }
    }

    @Test("The second title line is paid for: two lines only at 53 + lineHeight(blockTitle) = 68")
    func secondTitleLineIsPaidFor() {
        #expect(BlockContentMetrics.resolve(availableHeight: 53).titleLineLimit == 1)
        #expect(BlockContentMetrics.resolve(availableHeight: 67).titleLineLimit == 1)
        #expect(BlockContentMetrics.resolve(availableHeight: 68).titleLineLimit == 2)
        #expect(BlockContentMetrics.resolve(availableHeight: 68).contentHeight == 68)
        #expect(BlockContentMetrics.resolve(availableHeight: 200).titleLineLimit == 2)
    }

    @Test("Below the floor even glyph-only does not fit, and that is reported, not overflowed")
    func belowTheFloorIsReported() {
        // Only reachable through §4's short case, where the strip can leave less
        // than 11pt of content area. §3.5 rule 3: clip at the bottom, never grow.
        let metrics = BlockContentMetrics.resolve(availableHeight: 4)
        #expect(metrics.tier == .glyphOnly)
        #expect(metrics.fits == false)
    }

    @Test("Under Dynamic Type the minima grow and tier selection steps down (§3.3, §11)")
    func stepsDownWhenTheResolvedTextGrows() {
        // Bands do not move under Dynamic Type; minima do. At 1.6× the `.full`
        // content set needs more than a 60pt frame, so the ladder steps down
        // rather than drawing four lines into three lines' worth of space.
        let big = BlockLineHeights.scaled(by: 1.6)
        #expect(DensityTier.full.minimumHeight(lineHeights: big) > 60)
        let metrics = BlockContentMetrics.resolve(availableHeight: 60, lineHeights: big)
        #expect(metrics.tier < .full)
        #expect(metrics.contentHeight <= 60)
    }

    @Test("§3.1's compact radius follows the tier edge, not a second number")
    func compactRadiusFollowsTheTierEdge() {
        func radius(_ height: CGFloat) -> CGFloat {
            resolveBlockStyle(
                kind: .fixedTimed, flexibility: .fixed, status: .scheduled,
                presentation: [], source: .blue, renderedHeight: height).cornerRadius
        }
        #expect(radius(17) == Tokens.Radius.blockCompact)
        #expect(radius(18) == Tokens.Radius.block)
    }
}

// MARK: - §3.5 confinement, over the laid-out frames of the named fixtures

@Suite("Confinement — components.md §3.5")
struct BlockConfinementTests {

    /// The two fixtures G-011 names: MockData items 11.
    private func standUpAndCheckMail(_ geometry: TimeGeometry) -> [LaidOutBlock] {
        let items = [
            LayoutItem(id: UUID(), start: at(12, 30), end: at(12, 45), title: "Stand-up"),
            LayoutItem(id: UUID(), start: at(12, 50), end: at(13, 0), title: "Check mail"),
        ]
        return DayLayoutEngine
            .layout(items: items, columnWidth: 200, geometry: geometry)
            .blocks
            .sorted { $0.frame.minY < $1.frame.minY }
    }

    @Test("Stand-up and Check mail: distinct frames that do not overlap, in Day and Week")
    func theTwoFixturesDoNotOverlap() {
        for geometry in [dayGeometry, weekGeometry] {
            let blocks = standUpAndCheckMail(geometry)
            #expect(blocks.count == 2)
            let standUp = blocks[0].frame
            let checkMail = blocks[1].frame
            #expect(standUp.maxY <= checkMail.minY, "frames overlap before anything is drawn")
        }
    }

    @Test("Neither fixture's content set exceeds its own frame — the ~22pt bars are gone")
    func theTwoFixturesStayInsideTheirFrames() {
        for geometry in [dayGeometry, weekGeometry] {
            for block in standUpAndCheckMail(geometry) {
                let metrics = BlockContentMetrics.resolve(availableHeight: block.frame.height)
                // Day: 13pt and 11pt. Week: 11pt and 11pt. All `.glyphOnly`.
                #expect(metrics.tier == .glyphOnly)
                #expect(metrics.contentHeight <= block.frame.height)
                // 21pt is what the old ladder asked for — glyph + 2 × padding.
                #expect(metrics.contentHeight < 21)
            }
        }
    }

    @Test("A block draws at exactly its laid-out height, whatever its content wants")
    func hostedBlockIsExactlyItsFrameHeight() {
        for height in [11.0, 13.0, 17.0, 22.0, 30.0, 64.0] as [CGFloat] {
            let view = GridBlockView(
                model: sampleModel(),
                presentation: [],
                renderedHeight: height)
                .frame(width: 200)
            let hosting = NSHostingView(rootView: view)
            let fitting = hosting.fittingSize.height
            #expect(
                abs(fitting - height) < 0.01,
                "a \(height)pt block reports \(fitting)pt — it is not confined to its frame")
        }
    }

    /// The symptom Parsa reported, asserted in pixels: render the two fixtures
    /// at the frames `DayLayoutEngine` gives them and look for ink in the gap
    /// between them. Under the bug both drew ~22pt into 13pt and 11pt frames and
    /// spilled ~5pt each way, which closed the 7pt gap — that is what "two bars
    /// on top of each other" was. `ImageRenderer` is used rather than a window
    /// because this Mac does not vend windows (STATUS.md §1.7).
    @MainActor
    @Test("No ink lands between Stand-up and Check mail — the Day gap stays empty")
    func nothingIsDrawnInTheGapBetweenTheTwoFixtures() throws {
        let blocks = standUpAndCheckMail(dayGeometry)
        let standUp = blocks[0].frame
        let checkMail = blocks[1].frame
        let top = standUp.minY
        let canvasHeight = checkMail.maxY - top + 10
        let width: CGFloat = 200

        let scene = ZStack(alignment: .topLeading) {
            Color.clear
            GridBlockView(
                model: sampleModel(title: "Stand-up"),
                presentation: [],
                renderedHeight: standUp.height)
                .frame(width: width, height: standUp.height, alignment: .top)
                .offset(y: standUp.minY - top)
            GridBlockView(
                model: sampleModel(title: "Check mail"),
                presentation: [],
                renderedHeight: checkMail.height)
                .frame(width: width, height: checkMail.height, alignment: .top)
                .offset(y: checkMail.minY - top)
        }
        .frame(width: width, height: canvasHeight, alignment: .topLeading)

        let renderer = ImageRenderer(content: scene)
        renderer.scale = 2
        let image = try #require(renderer.cgImage)
        let inkedRows = try inkedRowsInPoints(of: image, scale: 2)

        // The gap is 12:45 → 12:50 minus the two frames: rows strictly between
        // the first frame's bottom and the second's top must be untouched.
        let gap = (standUp.height)..<(checkMail.minY - top)
        #expect(gap.lowerBound < gap.upperBound, "the fixtures must leave a real gap")
        for row in inkedRows {
            #expect(
                !gap.contains(row),
                "ink at y=\(row)pt, inside the \(gap.lowerBound)–\(gap.upperBound)pt gap")
        }
        // And nothing above the first frame or below the second one either.
        #expect(inkedRows.allSatisfy { $0 >= 0 && $0 < checkMail.maxY - top })
    }

    @Test("§3.5 rule 6 — a short-case travel strip comes out of the content area")
    func stripReducesTheContentArea() {
        // The Week case from STATUS.md §1.7 (c): "Datenmodellierung", 64pt frame,
        // 18pt strip. The old code picked `.full` on the remaining 46pt (44 by
        // 2pt) and then drew four lines needing ~73pt into 64, pushing the strip
        // above its own top edge. The moved boundary puts 46pt in `.compact`.
        let frame: CGFloat = 64
        let available = frame - Tokens.Size.travelBandHeight
        #expect(available == 46)
        let metrics = BlockContentMetrics.resolve(availableHeight: available)
        #expect(metrics.tier == .compact)
        #expect(metrics.contentHeight <= available)
        // And the whole stack — strip plus content — still fits the frame.
        #expect(Tokens.Size.travelBandHeight + metrics.contentHeight <= frame)
    }

    @Test("The strip is taken off the top even when what is left cannot hold a tier")
    func stripCanLeaveLessThanTheFloor() {
        let metrics = BlockContentMetrics.resolve(
            availableHeight: 22 - Tokens.Size.travelBandHeight)
        #expect(metrics.tier == .glyphOnly)
        #expect(metrics.fits == false, "clipped at the bottom (§3.5 rule 3), never grown")
    }
}

// MARK: - Fixture

private func sampleModel(
    title: String = "Datenmodellierung",
    kind: BlockKind = .fixedTimed
) -> GridBlockModel {
    GridBlockModel(
        id: UUID(),
        title: title,
        start: at(9, 0),
        end: at(10, 30),
        locationName: "FH B.2.09",
        kind: kind,
        flexibility: .fixed,
        status: .scheduled,
        source: .blue,
        sourceName: "University timetable",
        glyphOverride: "building.columns",
        isMovable: false)
}


// MARK: - Pixel helper

/// Every row (in points) of a rendered image that carries any non-transparent
/// pixel. Used to ask the one question §3.5 is about: where did the ink land?
private func inkedRowsInPoints(of image: CGImage, scale: CGFloat) throws -> [CGFloat] {
    let width = image.width
    let height = image.height
    var pixels = [UInt8](repeating: 0, count: width * height * 4)
    let context = try #require(CGContext(
        data: &pixels,
        width: width,
        height: height,
        bitsPerComponent: 8,
        bytesPerRow: width * 4,
        space: CGColorSpaceCreateDeviceRGB(),
        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
    context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))

    var rows: [CGFloat] = []
    for y in 0..<height {
        let hasInk = (0..<width).contains { x in
            // Alpha only: the canvas behind the blocks is Color.clear, so any
            // non-zero alpha in a row is a block having painted there.
            pixels[(y * width + x) * 4 + 3] > 8
        }
        if hasInk { rows.append(CGFloat(y) / scale) }
    }
    return rows
}
