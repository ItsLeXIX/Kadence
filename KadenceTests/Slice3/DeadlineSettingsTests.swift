//
//  DeadlineSettingsTests.swift
//  KadenceTests
//
//  PHASE3-SLICE3-PLAN.md task 14 — layouts.md §19; components.md §40.1.
//  The Deadlines rows' model on slice 2's notification rig (the recording
//  centre, the manual clock); §43 item 19 as offscreen renders (`-p3ct14`).
//

import Testing
import Foundation
import SwiftUI
import SwiftData
@testable import Kadence

@MainActor
@Suite(.serialized)
struct DeadlineSettingsTests {
    typealias M = NotificationsSettingsModel
    static var kept: [AnyObject] = []

    func setup() async throws -> (NotificationRig, M, NotificationRule) {
        let rig = try NotificationRig(now: TravelFixtures.m(0, "06:00"), centre: RecordingNotificationCenter(authorization: .allowed))
        Self.kept.append(rig)
        await rig.scheduler.refreshPermission()
        let model = M(context: rig.travel.context, scheduler: rig.scheduler, openURL: { _ in })
        let rule = try #require(model.deadlineRule)
        return (rig, model, rule)
    }

    @Test("Pop-up items in order; each choice writes its field and triggers a pass")
    func popups() async throws {
        let (rig, m, rule) = try await setup()
        #expect(M.aheadChoices.map(M.aheadLabel) == ["Off", "The day before", "2 days before", "3 days before"])
        #expect(M.aheadTimeChoices.map(M.timeLabel) == ["08:00", "12:00", "18:00", "20:00"])
        #expect(M.finalChoices.map(M.finalLabel)
                == ["Off", "30 minutes before", "1 hour before", "2 hours before", "3 hours before", "6 hours before"])
        #expect(rule.aheadDays == 1 && rule.aheadMinuteOfDay == 1080 && rule.leadMinutes == 120 && rule.leadEnabled)
        #expect(M.finalValue(rule) == 120)
        func passes(_ change: () -> Void) async -> Bool {
            let before = rig.scheduler.passCount
            change()
            await rig.run(for: 3)
            return rig.scheduler.passCount > before
        }
        #expect(await passes { m.setAhead(3, for: rule) } && rule.aheadDays == 3)
        #expect(await passes { m.setAheadTime(8 * 60, for: rule) } && rule.aheadMinuteOfDay == 480)
        #expect(await passes { m.setFinal(360, for: rule) } && rule.leadMinutes == 360 && rule.leadEnabled)
        #expect(await passes { m.setFinal(nil, for: rule) } && !rule.leadEnabled && rule.leadMinutes == 360)
        #expect(M.finalValue(rule) == nil)
        // Values outside the choices are refused.
        m.setAhead(5, for: rule); m.setAheadTime(7 * 60, for: rule); m.setFinal(45, for: rule)
        #expect(rule.aheadDays == 3 && rule.aheadMinuteOfDay == 480 && !rule.leadEnabled)
    }

    @Test("Off disables the time pop-up and keeps its value; the rule off disables all three; the rows sit between Routine and Sync problems")
    func disabling() async throws {
        let (_, m, rule) = try await setup()
        #expect(M.isAheadTimeEnabled(rule))
        m.setAhead(0, for: rule)
        #expect(!M.isAheadTimeEnabled(rule) && rule.aheadMinuteOfDay == 1080)
        m.setAhead(1, for: rule)
        await m.setEnabled(false, for: rule)
        #expect(!M.isAheadTimeEnabled(rule) && !rule.isEnabled)
        #expect(m.rules.map(\.kind) == [.leaveBy, .timetableStart, .personalStart, .routineStart, .syncPaused])
        #expect(M.secondLine(.deadline) == "Moodle items with a due time")
        #expect(M.deadlineFooter == "Moodle doesn't tell Kadence what you've handed in: mark a deadline done and its reminders stop.")
    }

    @Test("VoiceOver labels and values, exact")
    func voiceOver() async throws {
        let (_, _, rule) = try await setup()
        #expect(M.deadlineSwitchLabel == "Deadline notifications")
        #expect(M.aheadAccessibilityLabel == "Early deadline reminder" && M.aheadLabel(rule.aheadDays) == "The day before")
        #expect(M.aheadTimeAccessibilityLabel == "Early deadline reminder time" && M.timeLabel(rule.aheadMinuteOfDay) == "18:00")
        #expect(M.finalAccessibilityLabel == "Final deadline reminder" && M.finalLabel(M.finalValue(rule)) == "2 hours before")
    }

    // MARK: §43 item 19 (`-p3ct14`)

    @Test("§43 item 19 renders: the Deadlines rows; the rule off; the early reminder Off")
    func renders() async throws {
        let (_, m, rule) = try await setup()
        func render(_ name: String) {
            let view = NotificationsSettingsForm(model: m).formStyle(.grouped)
                .frame(width: Tokens.Size.settingsWindowWidth)
            #expect(Slice3Render.render(name, view, size: CGSize(width: Tokens.Size.settingsWindowWidth,
                                                                 height: Tokens.Size.settingsWindowHeight + 120),
                                        suffix: "p3ct14") != nil)
        }
        render("settings-notifications-deadlines")
        m.setAhead(0, for: rule)
        render("settings-notifications-early-off")
        m.setAhead(1, for: rule)
        await m.setEnabled(false, for: rule)
        render("settings-notifications-deadlines-off")
    }
}
