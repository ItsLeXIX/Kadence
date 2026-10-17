//
//  ReviewEvidence.swift
//  Kadence
//
//  Phase 3 slice 2 (PHASE3-SLICE2-PLAN.md tasks 12, 18) — components.md §30
//  item 14, §27.10 ("Review mode … writes the recorded plan to a text file
//  for review"), §24.11 ("asserted as B45's store is"). Review launches
//  only: files in the sandbox's temporary directory, under
//  `kadence-review/`, read by the capture scripts. Type names, identifiers,
//  times and notification text only — never an address or a coordinate.
//

import Foundation

nonisolated enum ReviewEvidence {
    static var directory: URL {
        FileManager.default.temporaryDirectory.appendingPathComponent("kadence-review", isDirectory: true)
    }

    /// The services this launch's factories built, one type name per line.
    static func writeLaunchServices(_ names: [String]) {
        write("launch-services.txt", names.joined(separator: "\n") + "\n")
    }

    /// The plan of the last pass, one block per request.
    static func writePlan(_ plan: [PlannedNotification], calendar: Calendar = .current) {
        write("notification-plan-live.txt", NotificationPlanText.blocks(plan, names: [:], calendar: calendar))
    }

    private static func write(_ name: String, _ text: String) {
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try? Data(text.utf8).write(to: directory.appendingPathComponent(name))
    }
}

/// A plan as text (§30 item 14): identifier, fire date, title, body,
/// category, sound, level. `names` maps an event or source id to the name
/// written in braces (`leave.{EPC-ILV}`), as the spec's tables do.
nonisolated enum NotificationPlanText {
    static func blocks(_ plan: [PlannedNotification], names: [String: String], calendar: Calendar) -> String {
        let formatter = DateFormatter()
        formatter.calendar = calendar
        formatter.timeZone = calendar.timeZone
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "EEE d MMM HH:mm"
        return plan.map { item in
            // The subject id replaced in place, so `leave.{EPC-ILV}` reads as
            // before and a deadline's `due.{900005}.ahead` keeps its suffix.
            let shown = names[item.subjectID].map { item.identifier.replacingOccurrences(of: item.subjectID, with: "{\($0)}") }
                ?? item.identifier
            return [
                "identifier: \(shown)",
                "fire:       \(formatter.string(from: item.fireAt))\(item.atOnce ? " (at once, 1-second trigger)" : "")",
                "title:      \(item.text.title)",
                "body:       \(item.text.body)",
                "category:   \(item.category.rawValue)",
                "sound:      \(item.playsSound ? "default" : "none")",
                "level:      \(item.interruption.rawValue)",
            ].joined(separator: "\n")
        }.joined(separator: "\n\n") + "\n"
    }
}
