//
//  Phase3Render.swift
//  KadenceTests
//
//  Offscreen renders of the real Phase 3 views (components.md §17.2 rule 3,
//  §22 items 9, 10, 17, 20). `ImageRenderer` cannot draw AppKit-backed
//  controls (checkboxes, spinners, buttons), so the view is hosted in an
//  offscreen window and its layer is cached. With `KADENCE_CAPTURE_DIR` set
//  (passed to the runner as `TEST_RUNNER_KADENCE_CAPTURE_DIR`), each render is
//  written as a PNG to the test host's temporary directory, under
//  `kadence-captures/`, from where `Scripts/capture-p3-renders.sh` copies it.
//

import SwiftUI
import AppKit
import SwiftData
@testable import Kadence

@MainActor
enum Phase3Render {
    /// Kept alive for the run (see PopoverCaptureTests' note on containers).
    static var keep: [AnyObject] = []

    @discardableResult
    static func render(_ name: String, _ view: some View, size: CGSize, dark: Bool = false,
                       suffix: String = "p3") -> NSImage? {
        let host = NSHostingView(rootView: view.environment(\.colorScheme, dark ? .dark : .light))
        host.frame = CGRect(origin: .zero, size: size)
        let window = NSWindow(contentRect: host.frame, styleMask: [.borderless], backing: .buffered, defer: false)
        window.appearance = NSAppearance(named: dark ? .darkAqua : .aqua)
        window.contentView = host
        host.layoutSubtreeIfNeeded()
        RunLoop.current.run(until: Date().addingTimeInterval(0.4))
        host.layoutSubtreeIfNeeded()
        guard let rep = host.bitmapImageRepForCachingDisplay(in: host.bounds) else { return nil }
        host.cacheDisplay(in: host.bounds, to: rep)
        keep.append(window)
        let image = NSImage(size: host.bounds.size)
        image.addRepresentation(rep)
        if ProcessInfo.processInfo.environment["KADENCE_CAPTURE_DIR"].map({ !$0.isEmpty }) == true,
           let png = rep.representation(using: .png, properties: [:]) {
            let directory = FileManager.default.temporaryDirectory.appendingPathComponent("kadence-captures")
            try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            try? png.write(to: directory.appendingPathComponent("\(name)-\(suffix).png"))
        }
        return image
    }
}
