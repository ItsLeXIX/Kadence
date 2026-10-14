//
//  Slice2Render.swift
//  KadenceTests
//
//  Offscreen renders of the real slice 2 views (§17.2 rule 3), written like
//  `Phase3Render`'s — but the window is torn down after the capture: its
//  SwiftUI hierarchy (which observes the `@Model` objects it drew) is removed
//  and the window closed, so nothing outlives the test that drew it. A kept
//  hierarchy over a store-backed model trapped the test host later, during
//  another test's run-loop wait (found by task 13's renders; the same family
//  as PopoverCaptureTests' note).
//

import SwiftUI
import AppKit
@testable import Kadence

@MainActor
enum Slice2Render {
    @discardableResult
    static func render(_ name: String, _ view: some View, size: CGSize, dark: Bool = false) -> NSImage? {
        SourceCatalog.install(.testTimetable)
        let host = NSHostingView(rootView: AnyView(view.environment(\.colorScheme, dark ? .dark : .light)))
        host.frame = CGRect(origin: .zero, size: size)
        let window = NSWindow(contentRect: host.frame, styleMask: [.borderless], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.appearance = NSAppearance(named: dark ? .darkAqua : .aqua)
        window.contentView = host
        // No run-loop spin: spinning the main run loop here fires timers
        // other tests left behind (SwiftData's, on stores they deleted).
        // Layout and display are forced synchronously instead.
        for _ in 0..<3 {
            host.layoutSubtreeIfNeeded()
            host.displayIfNeeded()
        }
        defer {
            host.rootView = AnyView(EmptyView())
            window.contentView = nil
            window.close()
        }
        guard let rep = host.bitmapImageRepForCachingDisplay(in: host.bounds) else { return nil }
        host.cacheDisplay(in: host.bounds, to: rep)
        let image = NSImage(size: host.bounds.size)
        image.addRepresentation(rep)
        if ProcessInfo.processInfo.environment["KADENCE_CAPTURE_DIR"].map({ !$0.isEmpty }) == true,
           let png = rep.representation(using: .png, properties: [:]) {
            let directory = FileManager.default.temporaryDirectory.appendingPathComponent("kadence-captures")
            try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            try? png.write(to: directory.appendingPathComponent("\(name)-p3b.png"))
        }
        return image
    }
}
