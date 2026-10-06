// kadence-guard.swift — P2-F21: the one place the UI scripts decide whether a
// pointer event may be sent. Compiled by each script into its work dir.
//
//   kguard park  PID      move (never click) the pointer to a point inside
//                         PID's frontmost window — its title-bar strip — so
//                         nothing in the content is hovered at baseline.
//   kguard check PID X Y  exit 0 only if the event at (X, Y) would reach PID.
//   kguard front PID      exit 0 only if PID is the frontmost application —
//                         the check for a key event, which goes to the
//                         frontmost app wherever the pointer is.
//
// "Would reach PID" means BOTH: PID is the frontmost application, AND the
// accessibility hit test at (X, Y) lands on an element PID owns. The second
// half matters because a click goes to whatever window is under the pointer,
// not to the frontmost app — a floating panel or another app's window over
// Kadence would receive it. Exit 1 (and a message on stderr) otherwise; the
// caller then sends nothing.
//
// Replaces the old `click 5 5` "park the pointer" step, which clicked the
// screen's top-left corner — the menu bar, outside Kadence (DEVIATIONS B32).
import AppKit
import ApplicationServices
import CoreGraphics
import Foundation

let args = CommandLine.arguments
func fail(_ s: String) -> Never {
    FileHandle.standardError.write("kguard: \(s) — no input sent\n".data(using: .utf8)!)
    exit(1)
}
guard args.count >= 3, let pid = pid_t(args[2]) else { fail("usage: kguard park PID | kguard check PID X Y | kguard front PID") }

// On-screen windows, front to back — used only to find PID's own window to
// park in; the hit test itself is ensureTopmostAt's.
let windows = (CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID)
               as? [[String: Any]]) ?? []
func bounds(_ w: [String: Any]) -> CGRect {
    let b = w[kCGWindowBounds as String] as? [String: Any] ?? [:]
    return CGRect(x: b["X"] as? Double ?? 0, y: b["Y"] as? Double ?? 0,
                  width: b["Width"] as? Double ?? 0, height: b["Height"] as? Double ?? 0)
}
func owner(_ w: [String: Any]) -> pid_t { (w[kCGWindowOwnerPID as String] as? Int).map(pid_t.init) ?? -1 }

func ensureFrontmost() {
    let front = NSWorkspace.shared.frontmostApplication
    guard front?.processIdentifier == pid else {
        fail("frontmost is '\(front?.localizedName ?? "?")' (pid \(front?.processIdentifier ?? -1)), not \(pid)")
    }
}
func ensureTopmostAt(_ p: CGPoint) {
    // The accessibility hit test answers "which element would a click at p
    // reach?" the way the window server does: it skips event-transparent
    // windows (the Dock keeps a full-display layer-20 one that a raw
    // CGWindowList walk mistakes for "on top"), and it returns the element's
    // owning process. Needs the same Accessibility permission the scripts
    // already need for their AX queries.
    var hit: AXUIElement?
    let err = AXUIElementCopyElementAtPosition(AXUIElementCreateSystemWide(), Float(p.x), Float(p.y), &hit)
    guard err == .success, let hit else { fail("no element under \(Int(p.x)),\(Int(p.y)) (AX error \(err.rawValue))") }
    var hitPID: pid_t = 0
    AXUIElementGetPid(hit, &hitPID)
    guard hitPID == pid else {
        let name = NSRunningApplication(processIdentifier: hitPID)?.localizedName ?? "?"
        fail("the element under \(Int(p.x)),\(Int(p.y)) belongs to '\(name)' (pid \(hitPID))")
    }
}

switch args[1] {
case "front":
    ensureFrontmost()
case "check":
    guard args.count >= 5, let x = Double(args[3]), let y = Double(args[4]) else { fail("usage: kguard check PID X Y") }
    ensureFrontmost()
    ensureTopmostAt(CGPoint(x: x, y: y))
case "park":
    ensureFrontmost()
    // The frontmost ordinary (layer 0) window of PID.
    guard let w = windows.first(where: { owner($0) == pid && ($0[kCGWindowLayer as String] as? Int) == 0 })
    else { fail("pid \(pid) has no on-screen window") }
    let r = bounds(w)
    let p = CGPoint(x: r.midX, y: r.minY + 6)   // title-bar strip, horizontally centred
    ensureTopmostAt(p)
    let e = CGEvent(mouseEventSource: CGEventSource(stateID: .hidSystemState), mouseType: .mouseMoved,
                    mouseCursorPosition: p, mouseButton: .left)
    e?.flags = []
    e?.post(tap: .cghidEventTap)
default:
    fail("unknown verb \(args[1])")
}
