//
//  NotificationsSettingsTests.swift
//  KadenceTests
//
//  PHASE3-SLICE2-PLAN.md task 15 — layouts.md §14; components.md §27.1,
//  §27.8; interactions.md §14.2; §29. The model over the scheduler and the
//  recording centre; offscreen renders of the real pane.
//

import Testing
import Foundation
import SwiftData
import SwiftUI
@testable import Kadence

@MainActor
@Suite(.serialized)
struct NotificationsSettingsTests {
    let now = TravelFixtures.m(3, "06:00")

    final class Opened { var urls: [URL] = [] }

    /// Rigs stay alive for the test: a model's context needs its container.
    static var kept: [NotificationRig] = []

    func model(_ rig: NotificationRig, opened: Opened = Opened()) -> NotificationsSettingsModel {
        Self.kept.append(rig)
        return NotificationsSettingsModel(context: rig.travel.context, scheduler: rig.scheduler,
                                   openURL: { opened.urls.append($0) })
    }

    func rig(_ authorization: NotificationAuthorization, asked: Bool = false) async throws -> NotificationRig {
        let rig = try NotificationRig(now: now, centre: RecordingNotificationCenter(authorization: authorization))
        TravelBuiltIns.settings(in: rig.travel.context).notificationsRequestedAt = asked ? now : nil
        await rig.scheduler.refreshPermission()
        return rig
    }

    @Test("off and notAllowedYet: §27.8's titles, bodies and buttons exact; allowed, notAsked, all rules off: no block")
    func blocks() async throws {
        let off = model(try await rig(.off))
        #expect(off.block?.title == "Notifications are off")
        #expect(off.block?.body == "macOS isn't showing notifications from Kadence, so it can't tell you when to leave or when something starts. Turn them on in System Settings ▸ Notifications ▸ Kadence.")
        #expect(off.block?.button.rawValue == "Open System Settings…")
        let notYet = model(try await rig(.notDetermined, asked: true))
        #expect(notYet.block?.title == "Notifications aren't allowed yet")
        #expect(notYet.block?.body == "Kadence needs your permission to tell you when to leave and when something starts.")
        #expect(notYet.block?.button.rawValue == "Allow Notifications…")
        #expect(model(try await rig(.allowed)).block == nil)
        #expect(model(try await rig(.notDetermined)).block == nil)
        let quiet = try await rig(.off)
        let m = model(quiet)
        for rule in m.rules { rule.isEnabled = false }
        #expect(m.block == nil)
    }

    @Test("Five rows in §27.1's order with layouts §14's lines and choices; Sync problems has no pop-up")
    func rows() async throws {
        let m = model(try await rig(.allowed))
        #expect(m.rules.map(\.kind.settingsLabel) == ["Leave by", "Timetable", "Personal events", "Routine", "Sync problems"])
        #expect(m.rules.map { NotificationsSettingsModel.secondLine($0.kind) } == [
            "Events at a place you travel to", "Lectures and exams with no travel", "Events you created, with no travel",
            "Routine blocks", "When a calendar stops syncing and needs you"])
        #expect(NotificationsSettingsModel.leadChoices(.leaveBy).map { NotificationsSettingsModel.leadLabel($0, kind: .leaveBy) }
                == ["At leave time", "5 minutes before", "10 minutes before", "15 minutes before", "30 minutes before"])
        #expect(NotificationsSettingsModel.leadChoices(.timetableStart).map { NotificationsSettingsModel.leadLabel($0, kind: .timetableStart) }
                == ["At start time", "5 minutes before", "10 minutes before", "15 minutes before", "30 minutes before", "1 hour before"])
        #expect(NotificationsSettingsModel.leadChoices(.syncPaused).isEmpty)
        #expect(NotificationsSettingsModel.footer == "Kadence stays quiet during Sleep and your other protected windows: a notification due then arrives when the window ends, unless the event itself is inside the window.")
    }

    @Test("Switch off keeps the lead; switch on while notAsked → one request; a lead change triggers a pass")
    func switches() async throws {
        let centre = RecordingNotificationCenter(authorization: .notDetermined)
        let rig = try NotificationRig(now: now, centre: centre)
        await rig.scheduler.refreshPermission()
        let m = model(rig)
        let timetable = try require(m.rules.first { $0.kind == .timetableStart })
        await m.setEnabled(false, for: timetable)
        #expect(!timetable.isEnabled && timetable.leadMinutes == 30)
        #expect(await centre.requestAuthorizationCalls == 0)
        await m.setEnabled(true, for: timetable)
        #expect(await centre.requestAuthorizationCalls == 1)
        let passes = rig.scheduler.passCount
        m.setLead(10, for: timetable)
        await rig.run(for: 3)
        #expect(timetable.leadMinutes == 10 && rig.scheduler.passCount > passes)
    }

    @Test("Allow Notifications… with a centre that answers without prompting → the opener gets the Notifications URL")
    func allow() async throws {
        let opened = Opened()
        let m = model(try await rig(.notDetermined, asked: true), opened: opened)
        await m.press(.allowNotifications)
        #expect(opened.urls.map(\.absoluteString)
                == ["x-apple.systempreferences:com.apple.Notifications-Settings.extension?id=XIX.Kadence"])
        let off = Opened()
        await model(try await rig(.off), opened: off).press(.openSystemSettings)
        #expect(off.urls.count == 1)
    }

    @Test("State → allowed on didBecomeActive: the block disappears and a pass runs")
    func recovery() async throws {
        let centre = RecordingNotificationCenter(authorization: .off)
        let rig = try NotificationRig(now: now, centre: centre)
        await rig.scheduler.refreshPermission()
        let m = model(rig)
        #expect(m.block != nil)
        await centre.set(authorization: .allowed)
        let passes = rig.scheduler.passCount
        await rig.scheduler.refreshPermission()
        #expect(m.block == nil)
        await rig.run(for: 3)
        #expect(rig.scheduler.passCount > passes)
    }

    @Test("§29: the switches and pop-ups")
    func voiceOver() {
        #expect(NotificationsSettingsModel.switchLabel(.leaveBy) == "Leave by notifications")
        #expect(NotificationsSettingsModel.popupLabel(.leaveBy) == "Leave by, notify")
        #expect(NotificationsSettingsModel.leadLabel(5, kind: .leaveBy) == "5 minutes before")
    }

    @Test("Task 15 renders: allowed, off, not allowed yet")
    func renders() async throws {
        for (name, auth, asked) in [("allowed", NotificationAuthorization.allowed, false), ("off", .off, false),
                                    ("not-allowed-yet", .notDetermined, true)] {
            let r = try await rig(auth, asked: asked)
            let m = model(r)
            if name != "allowed", let routine = m.rules.first(where: { $0.kind == .routineStart }) {
                // §30 item 4: one rule switched off, its pop-up disabled.
                routine.isEnabled = false
            }
            let view = NotificationsSettingsForm(model: m)
                .frame(width: Tokens.Size.settingsWindowWidth, height: 520)
            #expect(Slice2Render.render("settings-notifications-\(name)", view,
                                        size: CGSize(width: Tokens.Size.settingsWindowWidth, height: 520)) != nil)
        }
    }
}
