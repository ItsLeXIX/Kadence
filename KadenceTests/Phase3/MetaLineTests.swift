//
//  MetaLineTests.swift
//  KadenceTests
//
//  PHASE3-REVIEW.md fix 7 — components.md §3.4, amended 2026-10-10 (G-079;
//  DECISIONS 2026-10-10 "The room comes before the source on a block",
//  confirmed by Parsa). The `.full` meta line is `Location · Source`; the
//  location stays whole and the source truncates.
//

import Testing
import Foundation
import SwiftData
import CoreGraphics
@testable import Kadence

@MainActor
struct MetaLineTests {

    /// A lecture's model, as the Week grid builds it.
    private func lecture(_ title: String = "SWQM-ILV", room: String? = "HS_A3.15", online: Bool = false,
                         status: BlockStatus = .scheduled) -> GridBlockModel {
        let start = TestClock.date("2026-10-12 09:00")
        return GridBlockModel(id: UUID(), title: title, start: start, end: start.addingTimeInterval(5400),
                              locationName: room, kind: .fixedTimed, flexibility: .fixed, status: status,
                              source: .blue, sourceName: "University timetable", glyphOverride: "building.columns",
                              isMovable: false, importKind: .lecture, isOnline: online)
    }

    /// A lone block in a 124pt Week column: the column minus the 2pt inset on
    /// each side and the 2pt column gap, then — a `.fixedTimed` block has no
    /// rail — `size.blockPadding` on both sides.
    private var weekRow: CGFloat {
        let blockWidth = 124 - 2 * Tokens.Spacing.xxs - Tokens.Size.blockColumnGap
        return CompactRowLayout.rowWidth(blockWidth: blockWidth, hasRail: false)
    }

    private func width(_ text: String) -> CGFloat { CompactRowLayout.metaWidth(text) }

    @Test("At a 124pt Week column a .full lecture's meta starts with its room, whole, and ends with a truncated source name")
    func weekColumn() throws {
        #expect(weekRow == 108)
        // The engine's own frame for a lone block in that column agrees.
        let day = Calendar.current.startOfDay(for: TestClock.date("2026-10-12 09:00"))
        let item = LayoutItem(id: UUID(), start: TestClock.date("2026-10-12 09:00"), end: TestClock.date("2026-10-12 10:30"), title: "SWQM-ILV")
        let laidOut = try #require(DayLayoutEngine.layout(items: [item], columnWidth: 124,
                                                          geometry: TimeGeometry(dayStart: day, hourHeight: Tokens.Size.hourHeightWeek)).blocks.first)
        #expect(CompactRowLayout.rowWidth(blockWidth: laidOut.frame.width, hasRail: false) == weekRow)
        #expect(DensityTier(renderedHeight: laidOut.frame.height) == .full)   // 90 min at 44pt/h = 66pt

        let model = lecture()
        // The whole line does not fit a Week column — that is the case the
        // amendment is about.
        #expect(model.metaLine == "HS_A3.15 · University timetable")
        #expect(width(model.metaLine) > weekRow)
        let drawn = model.metaLine(fitting: weekRow)
        // It starts with the room, whole…
        #expect(drawn.hasPrefix("HS_A3.15 · "))
        // …and ends with a truncated source name.
        #expect(drawn.hasSuffix("…"))
        let head = String(drawn.dropFirst("HS_A3.15 · ".count).dropLast())
        #expect("University timetable".hasPrefix(head) && head != "University timetable")
        #expect(head.count >= MetaLineLayout.minimumSourceCharacters)
        #expect(!head.hasSuffix(" "))
        // It fits, and one more character of the source would not.
        #expect(width(drawn) <= weekRow)
        let next = "University timetable".prefix(head.count + 1)
        #expect(width("HS_A3.15 · \(next)…") > weekRow || next.hasSuffix(" "))
        // Never the old line.
        #expect(!drawn.hasPrefix("University"))
    }

    @Test("`Online` for an online event; every room of the real export stays whole at a Week column")
    func onlineAndTheExportsRooms() throws {
        let online = lecture("INNO3-EL", room: "WEBINAR01", online: true)
        #expect(online.metaLine == "Online · University timetable")
        let drawn = online.metaLine(fitting: weekRow)
        #expect(drawn.hasPrefix("Online · ") && drawn.hasSuffix("…") && width(drawn) <= weekRow)
        #expect(!drawn.contains("WEBINAR"))

        // The fixture's own events, through the derivation and the model.
        let context = ModelContext(try ModelContainer(for: Schema(KadenceSchema.models),
                                                      configurations: ModelConfiguration(isStoredInMemoryOnly: true)))
        ReviewMode.seedFresh(context: context, now: TestClock.now, secrets: InMemorySecretStore(), zone: TestClock.zone)
        let sources = SourceDirectory(try context.fetch(FetchDescriptor<Source>()))
        let events = try context.fetch(FetchDescriptor<Event>())
        #expect(events.count == 13)
        for event in events {
            let model = GridBlockModel(event: event, now: TestClock.date("2026-09-01 10:00"), sources: sources)
            let lead = try #require(model.metaLead)
            #expect(lead == (event.isOnline ? "Online" : event.location?.name))
            let line = model.metaLine(fitting: weekRow)
            #expect(line.hasPrefix(lead + " · "), "\(event.title): \(line)")
            #expect(line.contains("Univ") && width(line) <= weekRow)
        }
    }

    @Test("With no location, the source name alone; a cancelled block leads with `Cancelled`")
    func noLocationAndCancelled() {
        let none = lecture(room: nil)
        #expect(none.metaLead == nil)
        #expect(none.metaLine == "University timetable")
        #expect(none.metaLine(fitting: weekRow) == "University timetable")   // the view truncates its tail
        #expect(none.metaLine(fitting: 20) == "University timetable")
        let empty = lecture(room: "")
        #expect(empty.metaLine == "University timetable")
        // §6: `Cancelled · University timetable`, the same shape.
        let cancelled = lecture(status: .cancelled)
        #expect(cancelled.metaLine == "Cancelled · University timetable")
        #expect(cancelled.metaLine(fitting: weekRow).hasPrefix("Cancelled · "))
    }

    @Test("The source is dropped whole, with its separator, when fewer than 4 of its characters fit")
    func droppedWhole() {
        let model = lecture()
        let lead = "HS_A3.15"
        // Exactly four characters and the ellipsis fit: kept.
        let four = width("\(lead) · Univ…")
        #expect(model.metaLine(fitting: four) == "\(lead) · Univ…")
        // One point less: three would fit, which is not a name — dropped whole.
        #expect(width("\(lead) · Uni…") <= four - 1)
        #expect(model.metaLine(fitting: four - 1) == lead)
        #expect(model.metaLine(fitting: width(lead)) == lead)
        // Wide enough for everything: the whole line, no ellipsis.
        #expect(model.metaLine(fitting: width(model.metaLine)) == "HS_A3.15 · University timetable")
        #expect(model.metaLine(fitting: 400) == "HS_A3.15 · University timetable")
        // A short source name is never cut below itself.
        var short = model
        short.sourceName = "Mensa"
        #expect(short.metaLine(fitting: width("\(lead) · Mensa")) == "\(lead) · Mensa")
        // One point too narrow for it: `Mens…` if that fits (four characters), else nothing of it.
        let tight = short.metaLine(fitting: width("\(lead) · Mensa") - 1)
        #expect(tight == lead || tight == "\(lead) · Mens…")
        #expect(width(tight) <= width("\(lead) · Mensa") - 1)
        #expect(short.metaLine(fitting: min(width("\(lead) · Mens…"), width("\(lead) · Mensa")) - 1) == lead)
    }

    @Test("The rule itself, with a fixed-width measure: longest head ≥ 4, no space before the ellipsis")
    func pureRule() {
        // 1 unit per character.
        let measure: (String) -> CGFloat = { CGFloat($0.count) }
        func line(_ width: CGFloat) -> String {
            MetaLineLayout.resolve(lead: "R1", source: "University timetable", width: width, measure: measure)
        }
        #expect(line(25) == "R1 · University timetable")      // 5 + 20
        #expect(line(24) == "R1 · University timetab…")       // 5 + 18 + 1
        #expect(line(17) == "R1 · University…")               // "University " would leave a space: trimmed
        #expect(line(16) == "R1 · University…")
        #expect(line(15) == "R1 · Universit…")
        #expect(line(10) == "R1 · Univ…")
        #expect(line(9) == "R1")
        #expect(line(0) == "R1")
        #expect(MetaLineLayout.resolve(lead: nil, source: "University timetable", width: 3, measure: measure) == "University timetable")
        #expect(MetaLineLayout.resolve(lead: "", source: "X", width: 3, measure: measure) == "X")
    }

    @Test("Hover help and VoiceOver are unchanged; the menu bar popover keeps Source · Location")
    func theOtherCarriersAreUnchanged() {
        let model = lecture()
        #expect(model.hoverHelp == "SWQM-ILV · 09:00–10:30 · University timetable · Lecture")
        #expect(model.accessibilityLabel(presentation: []) == "SWQM-ILV, 09:00 to 10:30, lecture, University timetable")
        // §3.4: "The menu bar popover's meta line (§15) is not changed."
        #expect(model.popoverQualifier == "University timetable · HS_A3.15")
        #expect(lecture("INNO3-EL", room: "WEBINAR01", online: true).popoverQualifier == "University timetable · Online")
        #expect(lecture(room: nil).popoverQualifier == "University timetable")
    }
}
