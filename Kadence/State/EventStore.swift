//
//  EventStore.swift
//  Kadence
//
//  Every mutation goes through here so that every mutation is undoable and
//  named (interactions.md §9): the Edit menu reads "Undo Move Event", not "Undo".
//

import Foundation
import SwiftData
import AppKit

@MainActor
struct EventStore {
    let context: ModelContext

    private var undoManager: UndoManager? { context.undoManager }

    private func named(_ name: String, _ body: () -> Void) {
        undoManager?.beginUndoGrouping()
        body()
        undoManager?.setActionName(name)
        undoManager?.endUndoGrouping()
        try? context.save()
    }

    // MARK: Create

    /// interactions.md §3 — a new event is 60 minutes and starts life with an
    /// inline title field. It is not persisted until the title is committed,
    /// which is enforced by `commitCreation` / `cancelCreation`.
    @discardableResult
    func create(at start: Date, duration: TimeInterval = 3600, title: String = "") -> Event {
        let event = Event(
            title: title,
            start: start,
            end: start.addingTimeInterval(duration),
            origin: .manual,
            sourceKey: .graphite)
        named("New Event") { context.insert(event) }
        return event
    }

    /// An event created with no title is never persisted.
    func commitCreation(_ event: Event, title: String) {
        let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty {
            cancelCreation(event)
        } else {
            named("New Event") { event.title = trimmed }
        }
    }

    func cancelCreation(_ event: Event) {
        context.delete(event)
        try? context.save()
        // Creation that never completed is not an undoable user action.
        undoManager?.removeAllActions()
    }

    // MARK: Mutate

    func delete(_ event: Event) {
        named("Delete Event") { context.delete(event) }
    }

    func move(_ event: Event, by offset: TimeInterval) {
        guard event.isMovable, offset != 0 else { return }
        named("Move Event") {
            event.start = event.start.addingTimeInterval(offset)
            event.end = event.end.addingTimeInterval(offset)
        }
    }

    func move(_ event: Event, toStart newStart: Date) {
        guard event.isMovable else { return }
        move(event, by: newStart.timeIntervalSince(event.start))
    }

    /// The drag clamps rather than inverting; minimum resulting duration is 15 min.
    func resize(_ event: Event, newStart: Date? = nil, newEnd: Date? = nil) {
        guard event.isMovable else { return }
        let minimum: TimeInterval = 15 * 60
        named("Resize Event") {
            if let newStart {
                event.start = min(newStart, event.end.addingTimeInterval(-minimum))
            }
            if let newEnd {
                event.end = max(newEnd, event.start.addingTimeInterval(minimum))
            }
        }
    }

    func duplicate(_ event: Event, at start: Date) -> Event {
        let copy = Event(
            title: event.title,
            start: start,
            end: start.addingTimeInterval(event.duration),
            isAllDay: event.isAllDay,
            origin: .manual,
            status: .scheduled,
            flexibility: event.flexibility,
            sourceKey: event.sourceKey,
            notes: event.notes)
        named("Duplicate Event") { context.insert(copy) }
        return copy
    }

    func retitle(_ event: Event, to title: String) {
        let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, trimmed != event.title else { return }
        named("Rename Event") { event.title = trimmed }
    }

    func setNotes(_ event: Event, to notes: String) {
        guard notes != event.notes else { return }
        named("Edit Notes") { event.notes = notes }
    }

    func toggleDone(_ event: Event) {
        named(event.status == .done ? "Mark Not Done" : "Mark Done") {
            event.status = event.status == .done ? .scheduled : .done
        }
    }

    /// Skipping puts the item back in the pool to be re-offered. It is never a
    /// failure state, which is why it is a sibling of done, not a worse one.
    func toggleSkipped(_ event: Event) {
        named(event.status == .skipped ? "Unskip" : "Skip") {
            event.status = event.status == .skipped ? .scheduled : .skipped
        }
    }
}
