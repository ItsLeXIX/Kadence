//
//  AccessibilityTests.swift
//  KadenceTests
//
//  components.md §11: "Each block is one accessibility element", with a fixed
//  label order — and §1 leans on VoiceOver to carry kind and status *because*
//  they ride on shape rather than colour. That makes the accessibility tree a
//  correctness requirement here, not a nicety.
//
//  Two things have to hold, and they fail independently — A20 was the second
//  one failing silently while the first was fine:
//
//    1. the label text and its order are correct  — asserted here;
//    2. the element actually reaches the accessibility tree — asserted by
//       `Scripts/check-accessibility.sh`, which drives the *running* app.
//
//  (2) cannot be a unit test. SwiftUI on macOS builds its accessibility tree
//  lazily and vends it only to an out-of-process client, so an NSHostingView in
//  a test reports zero children even for a plain `Text` — I verified that before
//  relying on it. A harness like that would have passed happily while the app
//  was broken, which is worse than no test.
//

import Testing
import Foundation
import SwiftUI
import AppKit
@testable import Kadence


// MARK: - Fixtures

private func sampleModel(
    title: String = "Datenmodellierung",
    kind: BlockKind = .fixedTimed,
    status: BlockStatus = .scheduled,
    glyph: String? = "building.columns"
) -> GridBlockModel {
    let day = Calendar(identifier: .gregorian)
        .date(from: DateComponents(year: 2026, month: 9, day: 9)) ?? Date()
    return GridBlockModel(
        id: UUID(),
        title: title,
        start: day.addingTimeInterval(9 * 3600),
        end: day.addingTimeInterval(10 * 3600 + 30 * 60),
        locationName: "FH B.2.09",
        kind: kind,
        flexibility: .fixed,
        status: status,
        source: .blue,
        sourceName: "University timetable",
        glyphOverride: glyph,
        isMovable: false)
}

@Suite("Accessibility labels")
struct AccessibilityLabelTests {

    @Test("§11 label order: title, time range, kind, source, then status")
    func labelOrder() {
        let label = sampleModel().accessibilityLabel(presentation: [])
        #expect(label == "Datenmodellierung, 09:00 to 10:30, lecture, University timetable")
    }

    @Test("Kind and status are spoken, because shape carries them visually")
    func kindAndStatusAreSpoken() {
        let done = sampleModel(kind: .routineTimed, status: .done, glyph: nil)
            .accessibilityLabel(presentation: [])
        #expect(done.contains("routine block"))
        #expect(done.contains("done"))

        let skipped = sampleModel(kind: .routineTimed, status: .skipped, glyph: nil)
            .accessibilityLabel(presentation: [])
        #expect(skipped.contains("skipped, re-offered"),
                "a skipped item is re-offered, not failed — the label must say so")

        let running = sampleModel(status: .inProgress).accessibilityLabel(presentation: [])
        #expect(running.contains("in progress"))
    }

    @Test("A conflicted block says so, last")
    func conflictIsSpokenLast() {
        let label = sampleModel().accessibilityLabel(presentation: .conflicted)
        #expect(label.hasSuffix("conflicts with a protected window"))
    }

    @Test("Every block kind has a spoken name — none fall back to a raw case")
    func everyKindIsNamed() {
        for kind in BlockKind.allCases {
            let name = sampleModel(kind: kind, glyph: nil).accessibilityKindLabel
            #expect(!name.isEmpty)
            #expect(!name.contains("Timed") && !name.contains("AllDay"),
                    "\(kind) is speaking its raw case name")
        }
    }

    @Test("The source name is always in the label, at every density tier")
    func sourceIsAlwaysSpoken() {
        // §3.4: below tier 44 the source is not on the block, so VoiceOver and
        // hover help are the only carriers. The label must never drop it.
        let label = sampleModel().accessibilityLabel(presentation: [])
        #expect(label.contains("University timetable"))
    }

    @Test("Hover help carries Title · time · source · kind at every tier")
    func hoverHelp() {
        let help = sampleModel().hoverHelp
        #expect(help == "Datenmodellierung · 09:00–10:30 · University timetable · lecture")
    }

    @Test("The meta line is Source · Location, and just Source without one")
    func metaLine() {
        #expect(sampleModel().metaLine == "University timetable · FH B.2.09")
        var noLocation = sampleModel()
        noLocation.locationName = nil
        #expect(noLocation.metaLine == "University timetable")
    }
}
