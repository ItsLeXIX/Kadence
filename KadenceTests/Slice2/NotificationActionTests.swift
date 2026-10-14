//
//  NotificationActionTests.swift
//  KadenceTests
//
//  PHASE3-SLICE2-PLAN.md task 10 — components.md §27.7, interactions.md
//  §14.1, §30.1 "Actions": responses simulated by calling the router with an
//  action and the identifier's subject (§27.10: no real response object).
//

import Testing
import Foundation
import SwiftData
@testable import Kadence

@MainActor
@Suite(.serialized)
struct NotificationActionTests {

    func router(_ rig: NotificationRig, state: CalendarState? = nil, sources: SourcesRouter? = nil) -> NotificationActionRouter {
        let router = NotificationActionRouter(context: rig.travel.context, undo: rig.travel.undo, centre: rig.centre,
                                              clock: rig.travel.clock, calendar: TravelFixtures.calendar)
        router.calendarState = state
        router.sourcesRouter = sources
        return router
    }

    func response(_ prefix: String, _ event: Event?, _ action: NotificationResponse.Action,
                  _ category: NotificationCategory) -> NotificationResponse {
        let id = event?.id.uuidString ?? UUID().uuidString
        return NotificationResponse(identifier: "\(prefix).\(id)", action: action, subjectID: id, category: category)
    }

    @Test("Done on start.{REQEN-EXAM} → .done, one `Mark Done` step; again → nothing; the next pass removes only it")
    func done() async throws {
        let rig = try NotificationRig(now: TravelFixtures.m(3, "06:00"))
        await rig.launch()
        let reqen = try require(rig.travel.event("REQEN-EXAM", day: 3))
        let actions = router(rig)
        await actions.handle(response("start", reqen, .done, .readOnly))
        #expect(reqen.status == .done)
        #expect(rig.travel.undo.undoActionName == "Mark Done")
        await actions.handle(response("start", reqen, .done, .readOnly))
        #expect(reqen.status == .done)
        await rig.centre.resetCounters()
        rig.travel.coordinator.recompute()
        await rig.run(for: 5)
        #expect(await rig.centre.removeCalls == ["start.\(reqen.id.uuidString)"])
        #expect(await rig.centre.addCalls.isEmpty)
        // One step: undoing it leaves nothing to undo.
        rig.travel.undo.undo()
        #expect(reqen.status == .scheduled && !rig.travel.undo.canUndo)
    }

    @Test("Snooze on leave.{Dinner} at Thu 17:41 → 18:45–20:15, one `Snooze` step, N5 at once; leave.{Dinner} → 17:55, `Leave by 18:00`")
    func snoozeMoved() async throws {
        let rig = try NotificationRig(now: TravelFixtures.m(3, "17:41"))
        await rig.launch()
        let dinner = try require(rig.travel.event("Dinner with flatmates", day: 3))
        let actions = router(rig)
        await actions.handle(response("leave", dinner, .snooze, .event))
        #expect(dinner.start == TravelFixtures.m(3, "18:45") && dinner.end == TravelFixtures.m(3, "20:15"))
        #expect(rig.travel.undo.undoActionName == "Snooze")
        let result = try require(await rig.centre.addCalls.last)
        #expect(result.identifier.hasPrefix("result.\(dinner.id.uuidString)."))
        #expect(result.title == "Dinner with flatmates moved to 18:45")
        #expect(result.body == "Snoozed from 18:30 · ⌘Z in Kadence undoes it")
        #expect(result.category == .result && !result.playsSound && result.atOnce && result.interruption == .active)
        // The recompute (the new slot answered by the mock through the queue)
        // and the pass.
        await rig.run(for: 60)
        let leave = try require(await rig.pending()["leave.\(dinner.id.uuidString)"])
        #expect(leave.fireAt == TravelFixtures.m(3, "17:55"))
        #expect(leave.title == "Leave by 18:00 for Dinner with flatmates")
        rig.travel.undo.undo()
        #expect(dinner.start == TravelFixtures.m(3, "18:30") && !rig.travel.undo.canUndo)
    }

    @Test("Snooze on start.{Late call} at Sat 23:01 → refused: nothing written, no undo step, N6 exact")
    func snoozeRefused() async throws {
        let rig = try NotificationRig(now: TravelFixtures.m(5, "23:01"))
        await rig.launch()
        let call = try require(rig.travel.event("Late call", day: 5))
        await router(rig).handle(response("start", call, .snooze, .event))
        #expect(call.start == TravelFixtures.m(5, "23:15"))
        #expect(!rig.travel.undo.canUndo)
        let result = try require(await rig.centre.addCalls.last)
        #expect(result.title == "Late call not moved")
        #expect(result.body == "23:30 is inside Sleep (protected)")
        #expect(result.category == .result && !result.playsSound)
    }

    @Test("readOnly has no Snooze (a Snooze on one does nothing); result none; source only Open")
    func categories() async throws {
        let byID = Dictionary(uniqueKeysWithValues: NotificationCategorySpec.all.map { ($0.identifier, $0.actions.map(\.identifier)) })
        #expect(byID["kadence.event"] == ["done", "snooze", "open"])
        #expect(byID["kadence.readOnly"] == ["done", "open"])
        #expect(byID["kadence.result"] == [])
        #expect(byID["kadence.source"] == ["open"])
        let rig = try NotificationRig(now: TravelFixtures.m(3, "06:00"))
        await rig.launch()
        let epc = try require(rig.travel.event("EPC-ILV", day: 3))
        let before = await rig.centre.addCalls.count
        await router(rig).handle(response("leave", epc, .snooze, .readOnly))
        #expect(epc.start == TravelFixtures.m(3, "13:00") && !rig.travel.undo.canUndo)
        #expect(await rig.centre.addCalls.count == before)
    }

    @Test("Open / default select the event and page to its day; unknown id → today, nothing selected; Done / Snooze unknown → nothing")
    func open() async throws {
        let rig = try NotificationRig(now: TravelFixtures.m(3, "06:00"))
        await rig.launch()
        let state = CalendarState()
        state.anchor = TravelFixtures.m(-20, "12:00")
        let actions = router(rig, state: state)
        let swrm = try require(rig.travel.event("SWRM-ILV", day: 4))
        await actions.handle(response("leave", swrm, .open, .readOnly))
        #expect(state.selectedEventID == swrm.id)
        #expect(state.visibleDays.contains { TravelFixtures.calendar.isDate($0, inSameDayAs: swrm.start) })
        #expect(actions.openHistory == [.event(swrm.id)])
        // A click on a result opens too.
        state.selectedEventID = nil
        await actions.handle(response("result", swrm, .open, .result))
        #expect(state.selectedEventID == swrm.id)
        // Unknown id.
        await actions.handle(response("leave", nil, .open, .event))
        #expect(state.selectedEventID == nil)
        #expect(Calendar.current.isDate(state.anchor, inSameDayAs: Date()))
        #expect(actions.openHistory.last == .event(nil))
        // Done and Snooze on an unknown id do nothing.
        let adds = await rig.centre.addCalls.count
        await actions.handle(response("leave", nil, .done, .event))
        await actions.handle(response("leave", nil, .snooze, .event))
        #expect(!rig.travel.undo.canUndo)
        #expect(await rig.centre.addCalls.count == adds)
        // Dismiss does nothing.
        await actions.handle(response("leave", swrm, .dismiss, .readOnly))
        #expect(actions.openHistory.count == 3 && swrm.status == .scheduled)
    }

    @Test("Open on sync.{source} → the Settings-open request names Sources and the source id")
    func openSource() async throws {
        let rig = try NotificationRig(now: TravelFixtures.m(3, "06:00"))
        let sources = SourcesRouter()
        let actions = router(rig, sources: sources)
        await actions.handle(NotificationResponse(identifier: "sync.\(TravelDataset.sourceID)", action: .open,
                                                  subjectID: TravelDataset.sourceID, category: .source))
        #expect(actions.openHistory == [.settingsSources(sourceID: TravelDataset.sourceID)])
        #expect(actions.openHistory.first?.settingsTab == "Sources")
        #expect(sources.selectedSourceID == TravelDataset.sourceID)
        #expect(actions.pendingOpen == .settingsSources(sourceID: TravelDataset.sourceID))
    }

    @Test("Results carry no sound; N1–N4, N1e, N7 and N8 the default sound")
    func sounds() async throws {
        let rig = try NotificationRig(now: TravelFixtures.m(3, "06:00"), variant: .travelOffline)
        await rig.launch()
        let pending = await rig.pending().values
        #expect(!pending.isEmpty && pending.allSatisfy { $0.playsSound })
        let call = try NotificationRig(now: TravelFixtures.m(5, "23:01"))
        await call.launch()
        await router(call).handle(response("start", try require(call.travel.event("Late call", day: 5)), .snooze, .event))
        #expect(await call.centre.addCalls.filter { $0.category == .result }.allSatisfy { !$0.playsSound })
    }
}
