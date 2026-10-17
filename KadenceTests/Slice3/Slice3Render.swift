//
//  Slice3Render.swift
//  KadenceTests
//
//  Offscreen renders of the real slice 3 views (components.md §17.2 rule 3,
//  as slice 2's B55): the view drawn in a borderless window in the test
//  host at a pinned clock, then torn down. With `KADENCE_CAPTURE_DIR` set the
//  PNG is recorded as a test attachment `<name>-<suffix>.png`, which
//  `Scripts/capture-p3c-renders.sh` copies to `screenshots/3c/`. No app is
//  launched, no input is sent, no real service is built.
//

import SwiftUI
import AppKit
import Testing
@testable import Kadence

@MainActor
enum Slice3Render {
    /// Objects a rendered view observes, kept until the run ends.
    static var keep: [AnyObject] = []

    static var capturing: Bool {
        ProcessInfo.processInfo.environment["KADENCE_CAPTURE_DIR"].map { !$0.isEmpty } == true
    }

    @discardableResult
    static func render(_ name: String, _ view: some View, size: CGSize, dark: Bool = false, suffix: String,
                       directory: SourceDirectory? = nil) -> NSImage? {
        SourceCatalog.install(directory ?? .testTimetable)
        let host = NSHostingView(rootView: AnyView(view.environment(\.colorScheme, dark ? .dark : .light)))
        host.frame = CGRect(origin: .zero, size: size)
        let window = NSWindow(contentRect: host.frame, styleMask: [.borderless], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.appearance = NSAppearance(named: dark ? .darkAqua : .aqua)
        window.contentView = host
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
        if capturing, let png = rep.representation(using: .png, properties: [:]) {
            // Task 15 recaptures every frame under one suffix
            // (`KADENCE_RENDER_SUFFIX=p3ct15`).
            let suffix = ProcessInfo.processInfo.environment["KADENCE_RENDER_SUFFIX"].flatMap { $0.isEmpty ? nil : $0 } ?? suffix
            Attachment.record(png, named: "\(name)-\(suffix).png")
        }
        return image
    }

    /// A text file as an attachment (the plan dump, item 20).
    static func record(_ text: String, named name: String) {
        if capturing { Attachment.record(Data(text.utf8), named: name) }
    }
}
