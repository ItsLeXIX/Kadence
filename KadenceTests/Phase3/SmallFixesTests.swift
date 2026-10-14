//
//  SmallFixesTests.swift
//  KadenceTests
//
//  PHASE3-REVIEW.md fix 10 — three small things:
//  a. Edit ▸ Delete (interactions.md §2, §13.4; DEVIATIONS A38);
//  b. Settings' `Sync Now` is `.bordered` and not the default action
//     (layouts.md §11, clarified 2026-10-10);
//  c. focus stays in the grid after ⌘1 / ⌘2 / ⌘3 (interactions.md §1;
//     DECISIONS 2026-09-10) — the rule here, the live AX check in
//     `Scripts/check-view-switch-focus.sh`.
//

import Testing
import Foundation
import SwiftUI
import SwiftData
@testable import Kadence

@MainActor
struct SmallFixesTests {

    private func event(_ origin: EventOrigin, cancelled: Bool = false) -> Event {
        let start = TestClock.date("2026-10-12 09:00")
        let e = Event(title: "E", start: start, end: start.addingTimeInterval(3600), origin: origin,
                      sourceID: origin == .imported ? "timetable" : nil, externalID: origin == .imported ? "k" : nil)
        e.isCancelled = cancelled
        return e
    }

    // MARK: a. Edit ▸ Delete

    @Test("Edit ▸ Delete: present as `Delete` with ⌫; enabled for a deletable selection, disabled for none and for an imported event")
    func editDeleteMenuModel() {
        #expect(EditDeleteItem.title == "Delete")
        #expect(EditDeleteItem.key == KeyEquivalent.delete)
        // What the grid publishes for each kind of selection.
        var deleted: [UUID] = []
        func action(_ selection: Event?) -> GridDeleteAction {
            EditDeleteItem.action(selection: selection) { deleted.append($0.id) }
        }
        let manual = event(.manual), routine = event(.routine), planned = event(.planned)
        let imported = event(.imported), cancelled = event(.imported, cancelled: true)
        for deletable in [manual, routine, planned] {
            #expect(EditDeleteItem.canDelete(deletable))
            #expect(EditDeleteItem.isEnabled(action(deletable)))
        }
        // Nothing selected.
        #expect(!EditDeleteItem.canDelete(nil))
        #expect(!EditDeleteItem.isEnabled(action(nil)))
        // An imported event (§13.4: "disabled in the menu while an imported
        // event is selected, so the menu shows the rule before the key does").
        #expect(!EditDeleteItem.canDelete(imported) && !EditDeleteItem.isEnabled(action(imported)))
        #expect(!EditDeleteItem.canDelete(cancelled) && !EditDeleteItem.isEnabled(action(cancelled)))
        // The grid not focused: no action is published at all.
        #expect(!EditDeleteItem.isEnabled(nil))

        // Performing deletes the selection, and only a deletable one.
        action(manual).perform()
        #expect(deleted == [manual.id])
        action(imported).perform()
        action(nil).perform()
        #expect(deleted == [manual.id])
    }

    @Test("Edit ▸ Delete deletes exactly as ⌫ does: the event is gone, in one undo step")
    func editDeleteIsOneUndoStep() throws {
        let context = ModelContext(try ModelContainer(for: Schema(KadenceSchema.models),
                                                      configurations: ModelConfiguration(isStoredInMemoryOnly: true)))
        let undo = UndoStack()
        let store = EventStore(context: context, undo: undo)
        var draft = EventDraft(start: TestClock.date("2026-10-12 09:00"), end: TestClock.date("2026-10-12 10:00"))
        draft.title = "Dentist"
        let created = try #require(store.commit(draft))
        let steps = undo.undoSteps.count
        // The same call the grid's ⌫ makes (`MainWindow.deleteSelection`).
        EditDeleteItem.action(selection: created) { store.delete($0) }.perform()
        #expect(try context.fetchCount(FetchDescriptor<Event>()) == 0)
        #expect(undo.undoSteps.count == steps + 1)
        undo.undo()
        #expect(try context.fetch(FetchDescriptor<Event>()).map(\.title) == ["Dentist"])
        // An imported event: the item is disabled, and performing it anyway deletes nothing.
        let lecture = Event(title: "SWQM-ILV", start: draft.start, end: draft.end, origin: .imported, sourceKey: .blue,
                            sourceID: "timetable", externalID: "k")
        context.insert(lecture)
        try context.save()
        let item = EditDeleteItem.action(selection: lecture) { store.delete($0) }
        #expect(!EditDeleteItem.isEnabled(item))
        item.perform()
        #expect(try context.fetchCount(FetchDescriptor<Event>()) == 2)
    }

    @Test("The commands file puts Delete after the pasteboard group, with ⌫ and no modifiers")
    func editDeleteIsInTheEditMenu() throws {
        let source = try String(contentsOf: Fixture.repoRoot.appendingPathComponent("Kadence/Views/Chrome/KadenceCommands.swift"),
                                encoding: .utf8)
        let group = try #require(source.range(of: "CommandGroup(after: .pasteboard) {"))
        let body = source[group.upperBound...].prefix(260)
        #expect(body.contains("Button(EditDeleteItem.title)"))
        #expect(body.contains(".keyboardShortcut(EditDeleteItem.key, modifiers: [])"))
        #expect(body.contains(".disabled(!EditDeleteItem.isEnabled(gridDelete))"))
    }

    // MARK: b. Settings' Sync Now

    @Test("The status block's primary action is the default button in the source popover only — never in Settings ▸ Sources")
    func syncNowIsNotTheDefaultButtonInSettings() throws {
        // Settings (no `Settings…` button: you are there): no shortcut at
        // all, so ↩ in `Name` commits the name and cannot also sync.
        #expect(SourceStatusBlock.primaryShortcut(inPopover: false) == nil)
        // The popover (§19.3): the primary action is the default button.
        #expect(SourceStatusBlock.primaryShortcut(inPopover: true) == .defaultAction)
        // And the button is `.bordered` (never `.borderedProminent`) with that shortcut, in one place.
        let source = try String(contentsOf: Fixture.repoRoot.appendingPathComponent("Kadence/Views/Sources/SourcesSettings.swift"),
                                encoding: .utf8)
        #expect(!source.contains(".borderedProminent"))
        // No button in the file takes `.defaultAction` directly (comment lines aside).
        let code = source.split(separator: "\n").filter { !$0.trimmingCharacters(in: .whitespaces).hasPrefix("//") }
        #expect(!code.contains { $0.contains(".keyboardShortcut(.defaultAction)") })
        #expect(source.contains(".keyboardShortcut(Self.primaryShortcut(inPopover: showsSettingsButton))"))
        #expect(source.contains("SourceStatusBlock(source: source, showsSettingsButton: false"))
    }

    @Test("↩ in Name commits the name — and the commit does not sync")
    func nameCommitDoesNotSync() throws {
        let container = try ModelContainer(for: Schema(KadenceSchema.models),
                                           configurations: ModelConfiguration(isStoredInMemoryOnly: true))
        let context = ModelContext(container)
        let source = Source.connected(id: "timetable", displayName: "University timetable",
                                      serverURL: "https://cis.technikum-wien.at", username: "user01",
                                      principalHref: nil, calendarHomeHref: nil, calendars: [ReviewMode.calendar],
                                      capabilities: SourceCapabilities(), paletteKey: .blue)
        context.insert(source)
        try context.save()
        let secrets = InMemorySecretStore()
        try secrets.save(Password("x"), for: SecretAccount(host: "cis.technikum-wien.at", username: "user01"),
                         info: .forSource(id: source.id, displayName: source.displayName))
        let coordinator = SyncCoordinator(context: context, secrets: secrets, scheduling: FakeScheduling(), path: FakePath()) { _ in
            MockScheduleSource(result: .failure(.offline))
        }
        // What `TextField("Name").onSubmit` runs.
        let committed = SourcesSettingsModel.rename(source, to: "FH timetable", context: context, secrets: coordinator.secrets)
        #expect(committed == "FH timetable" && source.displayName == "FH timetable")
        #expect(coordinator.fetchCount == 0 && !coordinator.isSyncing(source))
        #expect(source.lastAttemptAt == nil)
        // An empty field reverts to the last name (layouts.md §11).
        #expect(SourcesSettingsModel.rename(source, to: "   ", context: context, secrets: coordinator.secrets) == "FH timetable")
    }

    // MARK: c. Focus after a view change

    @Test("After ⌘1 / ⌘2 / ⌘3, focus that was in the canvas goes back to the grid; the sidebar and inspector keep theirs; the toolbar is never a stop")
    func focusAfterViewChange() {
        typealias Region = CalendarState.FocusRegion
        #expect(Region.grid.regionToRestoreAfterViewChange == .grid)
        #expect(Region.allDayRow.regionToRestoreAfterViewChange == .grid)
        #expect(Region.toolbar.regionToRestoreAfterViewChange == .grid)
        #expect(Region.sidebar.regionToRestoreAfterViewChange == nil)
        #expect(Region.inspector.regionToRestoreAfterViewChange == nil)
        // No region is ever restored *to* the toolbar.
        #expect(Region.allCases.allSatisfy { $0.regionToRestoreAfterViewChange != .toolbar })
        // A fresh window starts with the grid as its region, so the very
        // first ⌘3 — the review's Day frame — restores it too.
        #expect(CalendarState().focusedRegion == .grid)
    }
}
