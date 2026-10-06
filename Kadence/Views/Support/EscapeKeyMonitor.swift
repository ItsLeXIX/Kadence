//
//  EscapeKeyMonitor.swift
//  Kadence
//
//  components.md §13.4 (amended 2026-10-06, G-040; DEVIATIONS B34): `⎋`
//  dismisses the Re-sync popover whenever it is open — with key focus on the
//  button, on the popover, or anywhere inside it.
//
//  Why a monitor and not `.onExitCommand` / `.onKeyPress(.escape)`: those
//  only see a key while their view's window is key, and with this popover up
//  the Routines window usually stays key (measured live in P2-F20: `⎋` went
//  to the Routines window and the popover only redrew inactive). A *local*
//  event monitor sees every key event this app receives, in any window, so
//  `⎋` reaches the popover's owner wherever focus sits. It is installed only
//  while the popover is open and removed when it closes, so `⎋` keeps its
//  other meanings (the conflict panel's `⎋`) the rest of the time.
//
//  Java/C# note: `NSEvent.addLocalMonitorForEvents` is roughly an app-wide
//  message filter (`IMessageFilter` in WinForms): the handler runs before the
//  event is dispatched; returning `nil` swallows it, returning the event lets
//  it through.
//

import AppKit

@MainActor
final class EscapeKeyMonitor {
    private var token: Any?

    /// Starts swallowing a bare `⎋` and calling `onEscape` instead. Replaces
    /// any earlier handler.
    func start(_ onEscape: @escaping @MainActor () -> Void) {
        stop()
        token = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            // 53 is the Escape key's virtual key code (`kVK_Escape`). A
            // modified `⎋` (e.g. `⌘⎋`) is left alone.
            guard event.keyCode == 53,
                  event.modifierFlags.intersection(.deviceIndependentFlagsMask).isEmpty
            else { return event }
            // Local monitors run on the main thread; this tells the compiler
            // so (Swift 6 strict concurrency can't see it from the AppKit API).
            MainActor.assumeIsolated { onEscape() }
            return nil
        }
    }

    func stop() {
        if let token { NSEvent.removeMonitor(token) }
        token = nil
    }
}
