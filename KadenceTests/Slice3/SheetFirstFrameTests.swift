//
//  SheetFirstFrameTests.swift
//  KadenceTests
//
//  P3S3-HF01 — the Connect Moodle sheet presented empty on a normal launch:
//  a 100×80 pt blank box with no title, field or button. The offscreen
//  renders drew `MoodleSheetContent` directly and never the outer
//  `MoodleSheet`, so they could not see it. Two kinds of check:
//  - presented: `SourcesSettingsView`'s own `.sheet(item:)` on a real
//    window, the router set, AppKit's sheet window measured. Before the fix
//    every request gave exactly 100×80 here;
//  - hosted: the outer sheets, built as that `.sheet` builds them, in an
//    `NSHostingView` inside a real `NSWindow` that starts at zero size —
//    `size.connectSheetWidth` wide, well over 100 pt tall, the secure field
//    there and the primary button live (Return reaches it).
//  No network, no Keychain; the Moodle URL is the mock's SENTINEL URL.
//

import Testing
import Foundation
import SwiftData
import SwiftUI
import AppKit
@testable import Kadence

@MainActor
struct SheetFirstFrameTests {
    private struct Rig {
        let container: ModelContainer
        let context: ModelContext
        let coordinator: SyncCoordinator
        let router = SourcesRouter()

        init() throws {
            container = try ModelContainer(for: Schema(KadenceSchema.models),
                                           configurations: ModelConfiguration(isStoredInMemoryOnly: true))
            context = container.mainContext
            BuiltInSource.ensure(in: context)
            coordinator = SyncCoordinator(context: context, secrets: InMemorySecretStore(), scheduling: FakeScheduling(),
                                          path: FakePath(), makeTransport: { RefusingTransport() },
                                          makeFeedTransport: { MockFeedTransport(case: .feedOffline) },
                                          makeSource: { _ in RefusingScheduleSource() })
            // What a re-evaluated view observes must outlive the test (a
            // released container traps SwiftData).
            Slice3Render.keep += [container, coordinator, router]
        }

        var sources: [Source] { (try? context.fetch(FetchDescriptor<Source>())) ?? [] }

        /// The sheet as `SourcesSettingsView`'s `.sheet(item:)` builds it.
        func sheet(_ request: SourcesRouter.Sheet) -> AnyView {
            request.isCalDAV
                ? AnyView(ConnectSheet(request: request, sources: sources, context: context, sync: coordinator))
                : AnyView(MoodleSheet(request: request, sources: sources, context: context, sync: coordinator))
        }

        func host(_ sheet: AnyView) -> Hosted {
            let view = NSHostingView(rootView: sheet
                .environment(coordinator)
                .environment(router)
                .modelContainer(container))
            // A sheet window sizes itself to its content: start from nothing
            // and let the content say how big it is.
            let window = NSWindow(contentRect: .zero, styleMask: [.titled], backing: .buffered, defer: false)
            window.isReleasedWhenClosed = false
            window.contentView = view
            // The very first measurement, before anything has appeared: what
            // a sheet is sized from.
            let first = view.fittingSize
            for _ in 0..<3 { view.layoutSubtreeIfNeeded(); view.displayIfNeeded() }
            Slice3Render.keep.append(window)
            return Hosted(window: window, host: view, first: first)
        }
    }

    private struct Hosted {
        let window: NSWindow
        let host: NSView
        let first: CGSize

        var views: [NSView] { Self.views(in: host) }
        private static func views(in view: NSView) -> [NSView] { [view] + view.subviews.flatMap(views(in:)) }

        /// Return, as the default-action key equivalent the sheet's primary
        /// button carries. (SwiftUI draws its buttons itself — no `NSButton`
        /// — and vends its accessibility tree only out of process, so the
        /// button is found by what it does.)
        func pressReturn() {
            let event = NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: [], timestamp: 0,
                                         windowNumber: window.windowNumber, context: nil, characters: "\r",
                                         charactersIgnoringModifiers: "\r", isARepeat: false, keyCode: 36)!
            _ = window.performKeyEquivalent(with: event)
        }
    }

    private func expectFirstFrame(_ hosted: Hosted) {
        for size in [hosted.first, hosted.host.fittingSize] {
            #expect(size.width == Tokens.Size.connectSheetWidth, "fitting width \(size.width)")
            #expect(size.height > 200, "fitting height \(size.height)")
        }
        #expect(hosted.views.contains { $0 is NSSecureTextField }, "no secure field")
    }

    // MARK: Presented by Settings

    /// The sheet's window once `SourcesSettingsView` presents `request`.
    /// AppKit attaches a sheet only to a window on screen: the host window
    /// is ordered in for the test and out again.
    private func presentedSize(_ request: SourcesRouter.Sheet, rig: Rig) -> CGSize? {
        let view = NSHostingView(rootView: SourcesSettingsView()
            .environment(rig.coordinator)
            .environment(rig.router)
            .environment(CalendarState())
            .environment(UndoStack())
            .modelContainer(rig.container))
        let window = NSWindow(contentRect: CGRect(x: 0, y: 0, width: 700, height: 500), styleMask: [.titled],
                              backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.contentView = view
        window.orderFrontRegardless()
        Slice3Render.keep.append(window)
        func pump(until done: () -> Bool) {
            for _ in 0..<60 where !done() { RunLoop.main.run(mode: .default, before: Date(timeIntervalSinceNow: 0.02)) }
        }
        pump { view.frame.width > 0 }
        rig.router.sheet = request
        // A sheet that sized itself to nothing stays that size: wait for it
        // to attach, then a few turns more for any resize.
        pump { window.attachedSheet != nil }
        for _ in 0..<5 { RunLoop.main.run(mode: .default, before: Date(timeIntervalSinceNow: 0.02)) }
        let size = window.attachedSheet?.frame.size
        rig.router.sheet = nil
        pump { window.attachedSheet == nil }
        window.orderOut(nil)
        return size
    }

    @Test(arguments: ["connectMoodle", "replaceMoodle", "connect"])
    func presentedSheetIsTheSheet(_ which: String) throws {
        let rig = try Rig()
        rig.context.insert(Source(id: "moodle-test", kind: .coursework, connection: .icsFeed, displayName: "Moodle"))
        let request: SourcesRouter.Sheet = switch which {
        case "connectMoodle": .connectMoodle
        case "replaceMoodle": .replaceMoodle(sourceID: "moodle-test")
        default: .connect
        }
        let size = try #require(presentedSize(request, rig: rig), "\(which): no sheet attached")
        #expect(size.width == Tokens.Size.connectSheetWidth, "\(which): \(size)")
        #expect(size.height > 200, "\(which): \(size)")
    }

    // MARK: The first frame, built as Settings builds it

    @Test func connectMoodleHasContentFromTheFirstFrame() throws {
        let rig = try Rig()
        expectFirstFrame(rig.host(rig.sheet(.connectMoodle)))
    }

    @Test func replaceMoodleHasContentFromTheFirstFrame() throws {
        let rig = try Rig()
        rig.context.insert(Source(id: "moodle-test", kind: .coursework, connection: .icsFeed, displayName: "Moodle"))
        expectFirstFrame(rig.host(rig.sheet(.replaceMoodle(sourceID: "moodle-test"))))
    }

    @Test func connectTimetableHasContentFromTheFirstFrame() throws {
        let rig = try Rig()
        expectFirstFrame(rig.host(rig.sheet(.connect)))
    }

    // MARK: The primary button is there and live

    @Test func moodlePrimaryButtonTakesReturn() throws {
        for replacing in [false, true] {
            let rig = try Rig()
            var source: Source?
            if replacing {
                let s = Source(id: "moodle-test", kind: .coursework, connection: .icsFeed, displayName: "Moodle")
                rig.context.insert(s)
                source = s
            }
            let model = MoodleSheetModel(replacing: source, context: rig.context, secrets: rig.coordinator.secrets,
                                         makeTransport: { MockFeedTransport(case: .feedOffline) }, sync: nil)
            Slice3Render.keep.append(model)
            model.urlText = MoodleMock.urlString
            #expect(model.canConnect)
            let hosted = rig.host(AnyView(MoodleSheet(model: model)))
            expectFirstFrame(hosted)
            hosted.pressReturn()
            #expect(model.phase == .connecting, "replacing \(replacing): Return did not reach Connect")
            model.cancelConnecting()
        }
    }

    @Test func timetablePrimaryButtonTakesReturn() throws {
        let rig = try Rig()
        let model = ConnectSheetModel(context: rig.context, secrets: rig.coordinator.secrets,
                                      makeTransport: { RefusingTransport() }, sync: nil)
        Slice3Render.keep.append(model)
        model.username = "user01"
        model.password = "filler-not-a-secret"
        #expect(model.canConnect)
        let hosted = rig.host(AnyView(ConnectSheet(model: model)))
        expectFirstFrame(hosted)
        hosted.pressReturn()
        #expect(model.phase == .connecting, "Return did not reach Connect")
        model.cancelConnecting()
    }
}
