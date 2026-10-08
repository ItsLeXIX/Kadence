//
//  Fixture.swift
//  KadenceTests
//
//  Phase 3 test fixtures (KadenceTests/Fixtures/…), read from the test
//  bundle. Xcode's synchronized folder copies them into the bundle's
//  resources flat, by file name, so every fixture name is unique.
//

import Foundation

enum Fixture {
    /// Swift note: `Bundle(for:)` needs a class that lives in the test bundle;
    /// this empty one is only that anchor.
    private final class Anchor {}

    static var bundle: Bundle { Bundle(for: Anchor.self) }

    static func url(_ name: String) throws -> URL {
        let base = (name as NSString).deletingPathExtension
        let ext = (name as NSString).pathExtension
        guard let url = bundle.url(forResource: base, withExtension: ext.isEmpty ? nil : ext) else {
            throw CocoaError(.fileNoSuchFile, userInfo: [NSFilePathErrorKey: name])
        }
        return url
    }

    static func data(_ name: String) throws -> Data { try Data(contentsOf: url(name)) }

    static func text(_ name: String) throws -> String { String(decoding: try data(name), as: UTF8.self) }

    /// The repository root, from this file's compile-time path
    /// (KadenceTests/Phase3/Fixture.swift → ../..).
    static var repoRoot: URL {
        URL(fileURLWithPath: #filePath).deletingLastPathComponent()
            .deletingLastPathComponent().deletingLastPathComponent()
    }
}

/// PHASE3-PLAN.md: "The test clock is 2026-10-08 10:00 Europe/Vienna".
enum TestClock {
    static let zone = TimeZone(identifier: "Europe/Vienna")!

    /// `yyyy-MM-dd HH:mm` in Europe/Vienna.
    static func date(_ text: String) -> Date {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = zone
        f.dateFormat = "yyyy-MM-dd HH:mm"
        return f.date(from: text)!
    }

    static var now: Date { date("2026-10-08 10:00") }
}
