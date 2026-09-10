//
//  DraftBindingTests.swift
//  KadenceTests
//
//  Regression cover for P2-T01: ⎋ and ↩ crashed the app while a draft was being
//  typed (interactions.md §3).
//
//  Root cause: `DayColumnView.draftBlock` handed `DraftBlockView` a binding made
//  with SwiftUI's `Binding.init?(_ base: Binding<Value?>)`. That initialiser
//  builds a `BindingOperations.ForceUnwrapping`, which unwraps in its *getter*,
//  on every read — not once at construction. Both keys that end a draft clear
//  `CalendarState.draft` from inside the draft field's own event handling, and
//  SwiftUI reads the field's bindings again while tearing the field down. Those
//  trailing reads unwrapped nil and trapped in
//  `BindingOperations.ForceUnwrapping.get(base:)`.
//
//  These tests drive the exact transition — make the binding, end the draft the
//  way ⎋ and ↩ each end it, then read and write through the binding that the
//  dying view still holds. Against the pre-fix code the first read is a hard
//  trap (EXC_BREAKPOINT), which takes the whole test process down; against the
//  fix they pass.
//

import Testing
import Foundation
import SwiftData
import SwiftUI
@testable import Kadence

private let draftStart = Calendar(identifier: .gregorian)
    .date(from: DateComponents(year: 2026, month: 9, day: 10, hour: 14, minute: 30)) ?? Date()

@MainActor
private func makeStore() throws -> EventStore {
    let container = try ModelContainer(
        for: Event.self, Place.self,
        configurations: ModelConfiguration(isStoredInMemoryOnly: true))
    return EventStore(context: ModelContext(container), undo: UndoStack())
}

@Suite("Draft binding survives the draft ending")
@MainActor
struct DraftBindingTests {

    @Test("The binding exists only while a draft does")
    func bindingTracksDraftPresence() {
        let state = CalendarState()
        #expect(state.draftBinding() == nil)

        state.beginDraft(at: draftStart)
        #expect(state.draftBinding() != nil)
    }

    @Test("Reading through the binding after ⎋ does not trap")
    func readAfterEscapeDiscard() {
        let state = CalendarState()
        state.beginDraft(at: draftStart)
        guard let binding = state.draftBinding() else {
            Issue.record("no draft binding while a draft exists"); return
        }
        binding.wrappedValue.title = "Gym"

        // ⎋ — DraftBlockView.onExitCommand / focus loss -> discardDraft().
        state.discardDraft()

        // The view is still alive for the rest of this update pass and reads its
        // bindings again. Pre-fix, this line trapped.
        #expect(binding.wrappedValue.title == "Gym")
        #expect(binding.wrappedValue.start == draftStart)
        #expect(state.draft == nil)
    }

    @Test("Reading through the binding after ↩ commits does not trap")
    func readAfterReturnCommit() throws {
        let store = try makeStore()
        let state = CalendarState()
        state.beginDraft(at: draftStart)
        guard let binding = state.draftBinding() else {
            Issue.record("no draft binding while a draft exists"); return
        }
        binding.wrappedValue.title = "Gym"

        // ↩ — DayColumnView.commitDraft(): persist, select, then discard.
        let draft = try #require(state.draft)
        let event = store.commit(draft)
        state.selectedEventID = event?.id
        state.discardDraft()

        #expect(event?.title == "Gym")
        #expect(state.draft == nil)
        // Pre-fix, this line trapped.
        #expect(binding.wrappedValue.title == "Gym")
    }

    @Test("A write arriving after the draft ended is dropped, not resurrected")
    func writeAfterDiscardIsDropped() {
        let state = CalendarState()
        state.beginDraft(at: draftStart)
        guard let binding = state.draftBinding() else {
            Issue.record("no draft binding while a draft exists"); return
        }

        state.discardDraft()
        // A text field flushing its last value on the way out must not bring
        // back a block the user just cancelled (interactions.md §3).
        binding.wrappedValue.title = "ghost"

        #expect(state.draft == nil)
    }

    @Test("⎋ then ↩ then ⎋ in a row leaves no draft and no stale write")
    func repeatedEndings() throws {
        let store = try makeStore()
        let state = CalendarState()

        for round in 0..<3 {
            state.beginDraft(at: draftStart)
            guard let binding = state.draftBinding() else {
                Issue.record("no draft binding on round \(round)"); return
            }
            binding.wrappedValue.title = "Round \(round)"

            if round == 1 {
                let draft = try #require(state.draft)
                _ = store.commit(draft)
            }
            state.discardDraft()

            _ = binding.wrappedValue          // trailing read
            binding.wrappedValue.title = "x"  // trailing write
            #expect(state.draft == nil)
        }
    }
}

// MARK: - The trap this replaced

@Suite("Why not Binding($state.draft)")
@MainActor
struct ForceUnwrappingBindingTests {

    /// Documents the SwiftUI behaviour the fix exists to avoid, so that anyone
    /// tempted to "simplify" `draftBinding()` back into `Binding($state.draft)`
    /// has the reason in front of them. Reading a force-unwrapping binding after
    /// its source goes nil is a trap, not a nil — it cannot be caught, which is
    /// why this asserts the shape rather than the crash.
    @Test("The safe binding keeps serving a value where a force-unwrap would trap")
    func safeBindingDoesNotDependOnTheSourceStillBeingThere() {
        let state = CalendarState()
        state.beginDraft(at: draftStart)
        let binding = state.draftBinding()
        state.draft = nil

        #expect(binding?.wrappedValue.start == draftStart)
    }
}
