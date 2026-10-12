//
//  CanvasRenderTests.swift
//  KadenceTests
//
//  Task 15's offscreen render (§22 item 20, §17.2 rule 3): the `cancelled`
//  block — no review source sends `STATUS:CANCELLED` — built from
//  `edge-cases.ics`'s cancelled event through the real derivation and views.
//

import Testing
import Foundation
import SwiftData
import SwiftUI
@testable import Kadence

@MainActor
@Suite(.serialized)
struct CanvasRenderTests {

    static func cancelledEvent() throws -> Event {
        let feed = FeedDerivation.derive([FeedObject(calendarHref: "", objectHref: "",
                                                     calendar: CISFeed.parse(try Fixture.text("edge-cases.ics")))],
                                         today: TestClock.now, zone: TestClock.zone)
        let upstream = try #require(feed.events.first { $0.isCancelled })
        let event = Event(title: upstream.title, start: upstream.start, end: upstream.end, origin: .imported,
                          sourceKey: .blue, sourceID: "timetable", externalID: upstream.externalID)
        event.applyUpstream(upstream)
        return event
    }

    @Test("Item 20: the cancelled block at .full, from edge-cases.ics")
    func cancelledBlock() throws {
        let event = try Self.cancelledEvent()
        #expect(event.isCancelled && event.title == "Statistik")
        let model = GridBlockModel(event: event, now: TestClock.now, sources: .testTimetable)
        #expect(model.status == .cancelled && model.metaLine == "Cancelled · University timetable")
        let view = GridBlockView(model: model, presentation: [], renderedHeight: 66)
            .frame(width: 180, height: 66)
            .padding(12)
            .background(Tokens.Color.Surface.canvas)
        #expect(Phase3Render.render("cancelled-block", view, size: CGSize(width: 204, height: 90)) != nil)
    }
}
