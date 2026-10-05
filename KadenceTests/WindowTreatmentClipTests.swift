//
//  WindowTreatmentClipTests.swift
//  KadenceTests
//
//  Task P2-F05 (PHASE2-REVIEW.md §6 item 5; components.md §7 rule 1,
//  amended 2026-10-05). A window paints only inside its own spans: one
//  weekday's column-wide rect plus the gutter strip. The 2026-10-05 captures
//  showed the `Low energy` hatch (Mon–Fri) spilling past Friday into Saturday.
//

import Testing
import Foundation
import CoreGraphics
import SwiftUI
@testable import Kadence

private let calendar = Calendar.current
/// Monday 5 … Sunday 11 October 2026.
private func october(_ day: Int) -> Date {
    calendar.date(from: DateComponents(year: 2026, month: 10, day: day))!
}

@Suite("Window treatments are clipped to their spans (P2-F05)")
@MainActor
struct WindowTreatmentClipTests {

    /// The lines' centre-lines end on the rect's edges, so only the stroke's
    /// half-width (½pt for 1pt lines) can reach past them — the layer's
    /// `.clipped()` takes that. The old shape overran by the span's HEIGHT.
    @Test("The hatch shape never leaves its rect (beyond half a line width), however tall the span")
    func hatchConfined() {
        for (w, h) in [(104.0, 66.0), (104.0, 400.0), (52.0, 1056.0), (126.0, 10.0)] {
            let rect = CGRect(x: 0, y: 0, width: w, height: h)
            let bounds = HatchPattern(pitch: 6, lineWidth: 1).path(in: rect).boundingRect
            #expect(bounds.minX >= rect.minX - 0.5 && bounds.maxX <= rect.maxX + 0.5,
                    "\(w)×\(h): hatch spans x \(bounds.minX)…\(bounds.maxX)")
            #expect(bounds.minY >= rect.minY - 0.5 && bounds.maxY <= rect.maxY + 0.5)
            // Still a hatch, not nothing: lines cover the rect's width.
            #expect(bounds.width >= w - 1)
        }
    }

    @Test("`Low energy`'s spans are its five weekdays and nothing else (main fixture and Routines model)")
    func lowEnergyDays() {
        let fixtureDays = (5...11).filter {
            !WindowSpanResolver.spans(for: .lowEnergy, in: MockData.timeWindows,
                                      on: october($0), showsPeakFocus: false).isEmpty
        }
        let modelDays = (5...11).filter {
            !WindowSpanResolver.spans(for: .lowEnergy, in: MockData.makeTimeWindows(),
                                      on: october($0), showsPeakFocus: true).isEmpty
        }
        #expect(fixtureDays == [5, 6, 7, 8, 9])
        #expect(modelDays == [5, 6, 7, 8, 9])
    }

    /// Friday's and Saturday's columns side by side, drawn by the layer both
    /// the main Week grid (`TimedCanvasView`) and the Routines canvas use.
    /// Saturday has no low-energy span, so its column must have no ink at all
    /// between 13:00 and 14:30 — where Friday's hatch used to spill.
    @Test("No hatch pixel lands in Saturday's column", arguments: [104.0, 126.0])
    func noInkInSaturday(columnWidth: Double) throws {
        let width = CGFloat(columnWidth)
        let hourHeight = Tokens.Size.hourHeightWeek
        let lowEnergyOnly = MockData.timeWindows.filter { $0.kind == .lowEnergy }
        func column(_ day: Date) -> some View {
            BackgroundWindowsLayer(
                windows: lowEnergyOnly,
                day: day,
                geometry: TimeGeometry(dayStart: calendar.startOfDay(for: day), hourHeight: hourHeight))
                .frame(width: width, height: hourHeight * 24, alignment: .top)
        }
        let scene = HStack(spacing: 0) {
            column(october(9))
            column(october(10))
        }
        .frame(width: width * 2, height: hourHeight * 24, alignment: .topLeading)

        let renderer = ImageRenderer(content: scene)
        renderer.scale = 1
        let image = try #require(renderer.cgImage)
        let (friday, saturday) = try inkCounts(image, split: Int(width))
        #expect(friday > 0, "Friday must carry the hatch — otherwise this test proves nothing")
        #expect(saturday == 0, "\(saturday) inked pixels in Saturday's column")
        // And Friday's is a HATCH, not a fill: 1pt lines at a 6pt pitch ink
        // roughly a quarter of the 13:00–14:30 band, never most of it.
        let band = Double(width) * Double(hourHeight) * 1.5
        #expect(Double(friday) < band * 0.6, "Friday's band is \(friday)/\(Int(band)) inked — a fill, not a hatch")
    }

    /// Pixels with any alpha left / right of `split`.
    private func inkCounts(_ image: CGImage, split: Int) throws -> (Int, Int) {
        let w = image.width, h = image.height
        var data = [UInt8](repeating: 0, count: w * h * 4)
        let context = try #require(CGContext(
            data: &data, width: w, height: h, bitsPerComponent: 8, bytesPerRow: w * 4,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
        context.draw(image, in: CGRect(x: 0, y: 0, width: w, height: h))
        var left = 0, right = 0
        for y in 0..<h {
            for x in 0..<w where data[(y * w + x) * 4 + 3] > 0 {
                if x < split { left += 1 } else { right += 1 }
            }
        }
        return (left, right)
    }
}
