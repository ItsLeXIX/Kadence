#!/usr/bin/env swift
//
//  generate-tokens.swift
//  Kadence — build tooling
//
//  Generates  Kadence/DesignSystem/Tokens.swift  from  design/tokens.json.
//
//  Tokens.swift is a build product. Never hand-edit it (CONTEXT.md → Hard rules).
//  To change a value, edit design/tokens.json and re-run this script.
//
//  Usage:
//    swift Scripts/generate-tokens.swift                 regenerate Tokens.swift
//    swift Scripts/generate-tokens.swift --check         verify only, write nothing
//    swift Scripts/generate-tokens.swift --input  <path> override the JSON path
//    swift Scripts/generate-tokens.swift --output <path> override the Swift path
//    swift Scripts/generate-tokens.swift --help
//
//  --check exits non-zero when Tokens.swift is missing, stale, or hand-edited.
//  Wire it into a pre-commit hook or an Xcode "Run Script" build phase.
//
//  This generator hardcodes NO token names and NO design values. It mirrors
//  whatever structure design/tokens.json happens to have, so the design side
//  owns the vocabulary and this script only owns the JSON → Swift mapping.
//  The mapping contract it does impose is documented in design/GAPS.md.
//
//  Swift notes for a Java/C# reader (this codebase is a Swift-learning project):
//    • A single .swift file run as `swift file.swift` is a *script*: top-level
//      statements execute in order, so all executable code lives at the bottom.
//      Type and function declarations are hoisted and may appear anywhere.
//    • `enum` with no cases is Swift's idiom for a namespace: it cannot be
//      instantiated, which is exactly what you want for a bag of constants.
//    • `throws` / `try` is Swift's checked-exception equivalent; `guard ... else`
//      is an early-exit that must leave the scope, which is why it reads
//      backwards compared to an `if`.
//    • No force-unwraps (`!`) here — project rule, and it applies to tooling too.
//

import Foundation

// MARK: - Errors

struct GeneratorError: Error, CustomStringConvertible {
    let description: String
    init(_ description: String) { self.description = description }
}

// MARK: - JSON

/// A strict JSON tree.
///
/// `JSONSerialization` hands back `NSNumber` for both `true` and `1`, and on
/// Linux even `as? Bool` cannot tell them apart — so tokens.json is decoded
/// through `Codable` instead, whose parser is exact about the six JSON types.
/// `indirect` is Swift's marker for a recursive enum (the cases hold values of
/// the enum's own type), analogous to a recursive sealed class in Java.
indirect enum JSONValue: Decodable {
    case object([String: JSONValue])
    case array([JSONValue])
    case string(String)
    case number(Double)
    case boolean(Bool)
    case null

    /// Token names are not known ahead of time, so decoding needs a coding key
    /// that accepts any string.
    struct AnyKey: CodingKey {
        let stringValue: String
        let intValue: Int? = nil
        init?(stringValue: String) { self.stringValue = stringValue }
        init?(intValue: Int) { nil }
    }

    init(from decoder: Decoder) throws {
        if let keyed = try? decoder.container(keyedBy: AnyKey.self) {
            var object: [String: JSONValue] = [:]
            for key in keyed.allKeys {
                object[key.stringValue] = try keyed.decode(JSONValue.self, forKey: key)
            }
            self = .object(object)
            return
        }
        if var unkeyed = try? decoder.unkeyedContainer() {
            var array: [JSONValue] = []
            while !unkeyed.isAtEnd {
                array.append(try unkeyed.decode(JSONValue.self))
            }
            self = .array(array)
            return
        }
        let single = try decoder.singleValueContainer()
        if single.decodeNil() { self = .null; return }
        // Bool before Double: the reverse order would swallow `true` as 1.
        if let boolean = try? single.decode(Bool.self) { self = .boolean(boolean); return }
        if let number = try? single.decode(Double.self) { self = .number(number); return }
        if let string = try? single.decode(String.self) { self = .string(string); return }
        throw DecodingError.dataCorruptedError(
            in: single,
            debugDescription: "Unsupported JSON value."
        )
    }
}

// MARK: - Colour

/// A colour resolved at generation time. Storing the 0–255 numerator keeps the
/// emitted Swift exact and traceable back to the hex string in the JSON.
struct RGBA255: Equatable {
    let red: Int
    let green: Int
    let blue: Int
    let alpha: Int

    /// Accepts #RGB, #RGBA, #RRGGBB and #RRGGBBAA (case-insensitive, `#` required).
    static func parse(_ raw: String) -> RGBA255? {
        guard raw.hasPrefix("#") else { return nil }
        let digits = Array(raw.dropFirst())
        guard digits.allSatisfy({ $0.isHexDigit }) else { return nil }

        func value(_ characters: ArraySlice<Character>) -> Int? {
            Int(String(characters), radix: 16)
        }
        // #ABC → #AABBCC: each nibble is doubled, not zero-padded.
        func expand(_ character: Character) -> Int? {
            guard let single = character.hexDigitValue else { return nil }
            return single * 16 + single
        }

        switch digits.count {
        case 3, 4:
            guard let r = expand(digits[0]),
                  let g = expand(digits[1]),
                  let b = expand(digits[2]) else { return nil }
            let a: Int
            if digits.count == 4 {
                guard let parsed = expand(digits[3]) else { return nil }
                a = parsed
            } else {
                a = 255
            }
            return RGBA255(red: r, green: g, blue: b, alpha: a)
        case 6, 8:
            guard let r = value(digits[0..<2]),
                  let g = value(digits[2..<4]),
                  let b = value(digits[4..<6]) else { return nil }
            let a: Int
            if digits.count == 8 {
                guard let parsed = value(digits[6..<8]) else { return nil }
                a = parsed
            } else {
                a = 255
            }
            return RGBA255(red: r, green: g, blue: b, alpha: a)
        default:
            return nil
        }
    }

    var swiftLiteral: String {
        "TokenSupport.RGBA(red: \(red), green: \(green), blue: \(blue), alpha: \(alpha))"
    }
}

// MARK: - Token model

/// One leaf value in tokens.json, already classified into the Swift type it maps to.
enum TokenValue {
    case color(RGBA255)
    /// A number that is a count, not a dimension. Named explicitly by
    /// `$meta.swiftMapping.integerLeaves` (GAPS.md G-008).
    case count(Int)
    case adaptiveColor(light: RGBA255, dark: RGBA255)
    case dimension(Double)
    case text(String)
    case flag(Bool)
    case dimensionList([Double])
    case textList([String])

    var swiftType: String {
        switch self {
        case .color, .adaptiveColor: return "SwiftUI.Color"
        case .count: return "Swift.Int"
        case .dimension: return "CoreGraphics.CGFloat"
        case .text: return "Swift.String"
        case .flag: return "Swift.Bool"
        case .dimensionList: return "[CoreGraphics.CGFloat]"
        case .textList: return "[Swift.String]"
        }
    }

    /// Colours are emitted as computed `var`s: they build an AppKit dynamic
    /// colour, which is not `Sendable`, and a stored `static let` of a
    /// non-Sendable type is an error under Swift 6 strict concurrency.
    /// Everything else is a plain `static let`.
    var isComputed: Bool {
        switch self {
        case .color, .adaptiveColor: return true
        default: return false
        }
    }

    var swiftExpression: String {
        switch self {
        case .color(let rgba):
            return "TokenSupport.color(\(rgba.swiftLiteral))"
        case .adaptiveColor(let light, let dark):
            return "TokenSupport.color(light: \(light.swiftLiteral), dark: \(dark.swiftLiteral))"
        case .count(let value):
            return String(value)
        case .dimension(let value):
            return SwiftEmit.number(value)
        case .text(let value):
            return SwiftEmit.string(value)
        case .flag(let value):
            return value ? "true" : "false"
        case .dimensionList(let values):
            return "[" + values.map(SwiftEmit.number).joined(separator: ", ") + "]"
        case .textList(let values):
            return "[" + values.map(SwiftEmit.string).joined(separator: ", ") + "]"
        }
    }

    /// Short human note appended as a trailing comment, so a reader can see the
    /// source value without opening the JSON.
    var provenanceComment: String? {
        switch self {
        case .color(let rgba):
            return "#\(SwiftEmit.hex(rgba))"
        case .adaptiveColor(let light, let dark):
            return "light #\(SwiftEmit.hex(light)) / dark #\(SwiftEmit.hex(dark))"
        default:
            return nil
        }
    }
}

struct Token {
    let jsonKey: String
    let swiftName: String
    let value: TokenValue
}

/// A nested object in tokens.json becomes a nested `enum` namespace in Swift.
struct Namespace {
    let jsonKey: String
    let swiftName: String
    var tokens: [Token]
    var children: [Namespace]
}

// MARK: - Swift emission helpers

enum SwiftEmit {
    static func hex(_ rgba: RGBA255) -> String {
        let base = String(format: "%02X%02X%02X", rgba.red, rgba.green, rgba.blue)
        return rgba.alpha == 255 ? base : base + String(format: "%02X", rgba.alpha)
    }

    static func number(_ value: Double) -> String {
        // Whole numbers read better without a trailing ".0"; everything else uses
        // Swift's shortest round-trippable description.
        if value == value.rounded(), abs(value) < 1e15 {
            return String(Int64(value))
        }
        return String(value)
    }

    static func string(_ value: String) -> String {
        var escaped = ""
        for character in value {
            switch character {
            case "\\": escaped += "\\\\"
            case "\"": escaped += "\\\""
            case "\n": escaped += "\\n"
            case "\r": escaped += "\\r"
            case "\t": escaped += "\\t"
            default: escaped.append(character)
            }
        }
        return "\"\(escaped)\""
    }

    static let reservedWords: Set<String> = [
        "associatedtype", "borrowing", "case", "catch", "class", "consuming",
        "continue", "default", "defer", "deinit", "do", "else", "enum", "extension",
        "fallthrough", "false", "fileprivate", "for", "func", "guard", "if",
        "import", "in", "init", "inout", "internal", "is", "let", "nil", "operator",
        "private", "protocol", "public", "repeat", "rethrows", "return", "self",
        "Self", "static", "struct", "subscript", "super", "switch", "throw",
        "throws", "true", "try", "typealias", "var", "where", "while", "Any",
        "Protocol", "Type", "as", "break",
    ]

    /// Maps a JSON key onto a Swift identifier.
    /// `uppercaseFirst` distinguishes namespaces (`UpperCamel`) from constants
    /// (`lowerCamel`). Separators are `-`, `_`, `.`, spaces and `/`.
    static func identifier(from key: String, uppercaseFirst: Bool, at path: [String]) throws -> String {
        let separators = CharacterSet(charactersIn: "-_. /")
        let words = key
            .components(separatedBy: separators)
            .filter { !$0.isEmpty }

        guard !words.isEmpty else {
            throw GeneratorError("""
                Key \(SwiftEmit.string(key)) at \(pathDescription(path)) has no usable \
                characters and cannot become a Swift identifier.
                """)
        }

        var identifier = ""
        for (index, word) in words.enumerated() {
            let sanitised = String(word.filter { $0.isLetter || $0.isNumber })
            guard !sanitised.isEmpty else { continue }
            if index == 0 && !uppercaseFirst {
                // Preserve an already-camelCased word ("backgroundPrimary") rather
                // than flattening it, but force the first character lowercase.
                identifier += sanitised.prefix(1).lowercased() + sanitised.dropFirst()
            } else {
                identifier += sanitised.prefix(1).uppercased() + sanitised.dropFirst()
            }
        }

        guard !identifier.isEmpty else {
            throw GeneratorError("""
                Key \(SwiftEmit.string(key)) at \(pathDescription(path)) contains no \
                letters or digits and cannot become a Swift identifier.
                """)
        }

        if let first = identifier.first, first.isNumber {
            identifier = "_" + identifier
        }
        if reservedWords.contains(identifier) {
            identifier = "`\(identifier)`"
        }
        return identifier
    }

    static func pathDescription(_ path: [String]) -> String {
        path.isEmpty ? "the top level of tokens.json" : "tokens.json → " + path.joined(separator: " → ")
    }
}

// MARK: - Parsing tokens.json into the model

enum TokenParser {
    /// Keys beginning with "$" are treated as metadata and skipped, so the design
    /// side can carry "$schema", "$version", "$description" and similar without
    /// polluting the generated API.
    static func isMetadata(_ key: String) -> Bool { key.hasPrefix("$") }

    /// Dot paths from `$meta.swiftMapping.integerLeaves` whose numbers are counts
    /// and must emit as `Int`. An explicit list rather than name-matching, so the
    /// generator never guesses from a suffix (GAPS.md G-008). `*` matches exactly
    /// one path segment.
    nonisolated(unsafe) static var integerLeafPatterns: [String] = []

    static func isIntegerLeaf(path: [String]) -> Bool {
        integerLeafPatterns.contains { pattern in
            let parts = pattern.split(separator: ".", omittingEmptySubsequences: false)
            guard parts.count == path.count else { return false }
            for (part, segment) in zip(parts, path) where part != "*" && part != segment {
                return false
            }
            return true
        }
    }

    static func namespace(named name: String, swiftName: String, from object: [String: JSONValue], at path: [String]) throws -> Namespace {
        var tokens: [Token] = []
        var children: [Namespace] = []
        var seenTokenNames: [String: String] = [:]      // swift name → json key
        var seenNamespaceNames: [String: String] = [:]

        // Sorted so the output is byte-for-byte deterministic run to run.
        for key in object.keys.sorted(by: stableOrder) {
            if isMetadata(key) { continue }
            guard let raw = object[key] else { continue }
            let childPath = path + [key]

            if let value = try tokenValue(from: raw, at: childPath) {
                let swiftName = try SwiftEmit.identifier(from: key, uppercaseFirst: false, at: path)
                if let existing = seenTokenNames[swiftName] {
                    throw GeneratorError("""
                        Keys \(SwiftEmit.string(existing)) and \(SwiftEmit.string(key)) at \
                        \(SwiftEmit.pathDescription(path)) both map to the Swift constant \
                        `\(swiftName)`. Rename one of them in design/tokens.json.
                        """)
                }
                seenTokenNames[swiftName] = key
                tokens.append(Token(jsonKey: key, swiftName: swiftName, value: value))
                continue
            }

            guard case .object(let nested) = raw else {
                throw GeneratorError("""
                    Value at \(SwiftEmit.pathDescription(childPath)) is not a token this \
                    generator understands and is not a nested object. Supported leaf shapes: \
                    a hex colour string ("#RRGGBB"), an object {"light": "#…", "dark": "#…"}, \
                    a number, a string, a boolean, or an array of numbers or strings.
                    """)
            }

            let childSwiftName = try SwiftEmit.identifier(from: key, uppercaseFirst: true, at: path)
            // A nested enum with the support type's name would shadow it for every
            // colour constant in the same scope, so reject it rather than emit
            // Swift that fails to compile in a confusing way.
            if childSwiftName == Renderer.supportEnumName {
                throw GeneratorError("""
                    Key \(SwiftEmit.string(key)) at \(SwiftEmit.pathDescription(path)) maps to \
                    `\(Renderer.supportEnumName)`, which is the name of the generated helper \
                    type and would shadow it. Rename it in design/tokens.json.
                    """)
            }
            if let existing = seenNamespaceNames[childSwiftName] {
                throw GeneratorError("""
                    Keys \(SwiftEmit.string(existing)) and \(SwiftEmit.string(key)) at \
                    \(SwiftEmit.pathDescription(path)) both map to the Swift namespace \
                    `\(childSwiftName)`. Rename one of them in design/tokens.json.
                    """)
            }
            seenNamespaceNames[childSwiftName] = key

            let child = try namespace(named: key, swiftName: childSwiftName, from: nested, at: childPath)
            if child.tokens.isEmpty && child.children.isEmpty {
                FileHandle.standardError.write(Data("""
                    warning: \(SwiftEmit.pathDescription(childPath)) is empty; skipping.

                    """.utf8))
                continue
            }
            children.append(child)
        }

        return Namespace(jsonKey: name, swiftName: swiftName, tokens: tokens, children: children)
    }

    /// Returns nil when `raw` is a nested namespace rather than a leaf token.
    static func tokenValue(from raw: JSONValue, at path: [String]) throws -> TokenValue? {
        switch raw {
        case .boolean(let value):
            return .flag(value)

        case .number(let value):
            if isIntegerLeaf(path: path) {
                guard value == value.rounded() else {
                    throw GeneratorError("""
                        \(SwiftEmit.pathDescription(path)) is listed in                         $meta.swiftMapping.integerLeaves but its value \(value) is not a                         whole number.
                        """)
                }
                return .count(Int(value))
            }
            return .dimension(value)

        case .string(let value):
            if let rgba = RGBA255.parse(value) {
                return .color(rgba)
            }
            if value.hasPrefix("#") {
                throw GeneratorError("""
                    Value \(SwiftEmit.string(value)) at \(SwiftEmit.pathDescription(path)) \
                    starts with "#" but is not a valid hex colour. Use #RGB, #RGBA, #RRGGBB \
                    or #RRGGBBAA.
                    """)
            }
            return .text(value)

        case .array(let elements):
            return try list(from: elements, at: path)

        case .object(let object):
            // Exactly {"light": …, "dark": …} is the appearance-adaptive colour
            // shape. Anything else is an ordinary nested namespace.
            let keys = Set(object.keys.filter { !isMetadata($0) })
            guard keys == ["light", "dark"] else { return nil }
            guard case .string(let lightRaw)? = object["light"],
                  case .string(let darkRaw)? = object["dark"] else {
                throw GeneratorError("""
                    The light/dark pair at \(SwiftEmit.pathDescription(path)) must hold hex \
                    colour strings.
                    """)
            }
            guard let light = RGBA255.parse(lightRaw), let dark = RGBA255.parse(darkRaw) else {
                throw GeneratorError("""
                    The light/dark pair at \(SwiftEmit.pathDescription(path)) holds a value \
                    that is not a valid hex colour (#RGB, #RGBA, #RRGGBB or #RRGGBBAA).
                    """)
            }
            return .adaptiveColor(light: light, dark: dark)

        case .null:
            throw GeneratorError("""
                Value at \(SwiftEmit.pathDescription(path)) is null. A token must have a value; \
                remove the key or give it one.
                """)
        }
    }

    static func list(from array: [JSONValue], at path: [String]) throws -> TokenValue {
        guard !array.isEmpty else {
            throw GeneratorError("""
                Array at \(SwiftEmit.pathDescription(path)) is empty, so its Swift element \
                type cannot be inferred.
                """)
        }

        var numbers: [Double] = []
        var strings: [String] = []
        for element in array {
            switch element {
            case .number(let value): numbers.append(value)
            case .string(let value): strings.append(value)
            default: break
            }
        }
        if numbers.count == array.count { return .dimensionList(numbers) }
        if strings.count == array.count { return .textList(strings) }

        throw GeneratorError("""
            Array at \(SwiftEmit.pathDescription(path)) mixes types or holds nested values. \
            Arrays must be all numbers or all strings.
            """)
    }

    /// Case-insensitive first, then case-sensitive, so ordering never depends on
    /// Foundation's locale or on Dictionary iteration order.
    static func stableOrder(_ lhs: String, _ rhs: String) -> Bool {
        let left = lhs.lowercased(), right = rhs.lowercased()
        return left == right ? lhs < rhs : left < right
    }
}

// MARK: - Rendering

enum Renderer {
    static let rootEnumName = "Tokens"
    static let supportEnumName = "TokenSupport"

    static func file(root: Namespace, inputDisplayPath: String, fingerprint: String, byteCount: Int) -> String {
        var out = ""
        out += """
            //
            //  Tokens.swift
            //  Kadence
            //
            //  GENERATED FILE — DO NOT EDIT.
            //
            //  Generated by Scripts/generate-tokens.swift from \(inputDisplayPath)
            //  Source fingerprint: \(fingerprint) (\(byteCount) bytes)
            //
            //  Every value below comes from \(inputDisplayPath). To change one, edit the
            //  JSON and re-run:
            //
            //      swift Scripts/generate-tokens.swift
            //
            //  Hand edits are overwritten on the next run and fail
            //  `swift Scripts/generate-tokens.swift --check`.
            //

            import SwiftUI

            #if canImport(AppKit)
            import AppKit
            #endif


            """
        out += render(namespace: root, name: rootEnumName, indent: 0, isRoot: true)
        out += "\n"
        out += support()
        return out
    }

    static func render(namespace: Namespace, name: String, indent: Int, isRoot: Bool) -> String {
        let pad = String(repeating: "    ", count: indent)
        let inner = String(repeating: "    ", count: indent + 1)
        var out = "\(pad)enum \(name) {\n"

        for token in namespace.tokens {
            let keyword = token.value.isComputed ? "static var" : "static let"
            let body = token.value.isComputed
                ? " { \(token.value.swiftExpression) }"
                : " = \(token.value.swiftExpression)"
            var line = "\(inner)\(keyword) \(token.swiftName): \(token.value.swiftType)\(body)"
            if let note = token.value.provenanceComment {
                line += "  // \(note)"
            }
            out += line + "\n"
        }

        if !namespace.tokens.isEmpty && !namespace.children.isEmpty {
            out += "\n"
        }

        for (index, child) in namespace.children.enumerated() {
            out += render(namespace: child, name: child.swiftName, indent: indent + 1, isRoot: false)
            if index < namespace.children.count - 1 {
                out += "\n"
            }
        }

        out += "\(pad)}\n"
        return out
    }

    static func support() -> String {
        """

        // MARK: - Support

        /// Runtime helpers for the generated constants above. Also generated —
        /// edit Scripts/generate-tokens.swift, not this file.
        enum TokenSupport {

            /// Colour components as they appear in the source hex string (0–255),
            /// kept integral so the emitted values are exact.
            struct RGBA: Sendable, Hashable {
                let red: Int
                let green: Int
                let blue: Int
                let alpha: Int

                var swiftUIColor: SwiftUI.Color {
                    SwiftUI.Color(
                        .sRGB,
                        red: Double(red) / 255.0,
                        green: Double(green) / 255.0,
                        blue: Double(blue) / 255.0,
                        opacity: Double(alpha) / 255.0
                    )
                }
            }

            /// A colour that is the same in both appearances.
            static func color(_ rgba: RGBA) -> SwiftUI.Color {
                rgba.swiftUIColor
            }

            /// A colour that resolves against the current appearance. Built as an
            /// AppKit dynamic colour so it also updates correctly inside AppKit-backed
            /// surfaces (the menu bar extra, NSHostingView) and not just in SwiftUI.
            static func color(light: RGBA, dark: RGBA) -> SwiftUI.Color {
                #if canImport(AppKit)
                return SwiftUI.Color(nsColor: DynamicColorCache.shared.color(light: light, dark: dark))
                #else
                return light.swiftUIColor
                #endif
            }
        }

        #if canImport(AppKit)
        /// Dynamic colours are cached by their light/dark pair, and the cache is
        /// load-bearing rather than an optimisation.
        ///
        /// `NSColor(name:dynamicProvider:)` returns a brand-new catalog colour on
        /// every call, and two such colours are never equal — so without this cache
        /// two reads of the *same* token compare unequal. That silently breaks
        /// `Equatable` on any type holding a `Color` (Kadence's `BlockStyle`, for one)
        /// and makes SwiftUI treat every render as a change.
        private final class DynamicColorCache: @unchecked Sendable {
            static let shared = DynamicColorCache()

            private struct Pair: Hashable {
                let light: TokenSupport.RGBA
                let dark: TokenSupport.RGBA
            }

            private let lock = NSLock()
            private var storage: [Pair: NSColor] = [:]

            func color(light: TokenSupport.RGBA, dark: TokenSupport.RGBA) -> NSColor {
                let key = Pair(light: light, dark: dark)
                lock.lock()
                defer { lock.unlock() }
                if let existing = storage[key] { return existing }
                let created = NSColor(name: nil) { appearance in
                    let isDark = appearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
                    let resolved = isDark ? dark : light
                    return NSColor(
                        srgbRed: CGFloat(resolved.red) / 255.0,
                        green: CGFloat(resolved.green) / 255.0,
                        blue: CGFloat(resolved.blue) / 255.0,
                        alpha: CGFloat(resolved.alpha) / 255.0
                    )
                }
                storage[key] = created
                return created
            }
        }
        #endif

        """
    }
}

// MARK: - Fingerprint

/// FNV-1a, 64-bit. Not cryptographic — it only answers "did tokens.json change".
/// Chosen over SHA-256 so the script needs nothing beyond Foundation and runs
/// identically on macOS and Linux.
func fingerprint(of data: Data) -> String {
    var hash: UInt64 = 0xcbf2_9ce4_8422_2325
    let prime: UInt64 = 0x0000_0100_0000_01B3
    for byte in data {
        hash ^= UInt64(byte)
        hash = hash &* prime
    }
    return "fnv1a64:" + String(format: "%016llx", hash)
}

// MARK: - Options

struct Options {
    var inputPath: String
    var outputPath: String
    var checkOnly: Bool
    var repoRoot: String

    static let helpText = """
        generate-tokens.swift — generate Kadence/DesignSystem/Tokens.swift from design/tokens.json

        USAGE
          swift Scripts/generate-tokens.swift [options]

        OPTIONS
          --check            Verify the checked-in Tokens.swift matches the JSON.
                             Writes nothing. Exits 1 if it is missing, stale or hand-edited.
          --input  <path>    Path to tokens.json    (default: <repo>/design/tokens.json)
          --output <path>    Path to Tokens.swift   (default: <repo>/Kadence/DesignSystem/Tokens.swift)
          --help, -h         Show this text.

        NOTES
          Tokens.swift is a build product and is never hand-edited (CONTEXT.md).
          This script hardcodes no token names and no design values: it mirrors the
          structure of tokens.json. The JSON shapes it understands are documented in
          design/GAPS.md.
        """

    static func parse(_ arguments: [String], scriptPath: String) throws -> Options {
        // Default to the repo root, i.e. the parent of the directory holding this
        // script, so the tool works regardless of the shell's working directory.
        let scriptURL = URL(fileURLWithPath: scriptPath).standardizedFileURL
        let repoRoot = scriptURL.deletingLastPathComponent().deletingLastPathComponent()

        var input: String? = nil
        var output: String? = nil
        var checkOnly = false

        var index = 0
        while index < arguments.count {
            let argument = arguments[index]
            switch argument {
            case "--check":
                checkOnly = true
            case "--input", "--output":
                guard index + 1 < arguments.count else {
                    throw GeneratorError("\(argument) needs a path.")
                }
                index += 1
                if argument == "--input" { input = arguments[index] } else { output = arguments[index] }
            case "--help", "-h":
                print(helpText)
                exit(0)
            default:
                throw GeneratorError("Unknown option \(SwiftEmit.string(argument)). Try --help.")
            }
            index += 1
        }

        func resolve(_ path: String?, default defaultComponents: [String]) -> String {
            if let path {
                return URL(fileURLWithPath: path, relativeTo: URL(fileURLWithPath: FileManager.default.currentDirectoryPath))
                    .standardizedFileURL.path
            }
            var url = repoRoot
            for component in defaultComponents { url.appendPathComponent(component) }
            return url.standardizedFileURL.path
        }

        return Options(
            inputPath: resolve(input, default: ["design", "tokens.json"]),
            outputPath: resolve(output, default: ["Kadence", "DesignSystem", "Tokens.swift"]),
            checkOnly: checkOnly,
            repoRoot: repoRoot.path
        )
    }
}

// MARK: - Driver

func displayPath(_ absolute: String, relativeTo root: String) -> String {
    let prefix = root.hasSuffix("/") ? root : root + "/"
    return absolute.hasPrefix(prefix) ? String(absolute.dropFirst(prefix.count)) : absolute
}

func generate(_ options: Options) throws -> String {
    let inputURL = URL(fileURLWithPath: options.inputPath)
    let shownInput = displayPath(options.inputPath, relativeTo: options.repoRoot)

    guard FileManager.default.fileExists(atPath: options.inputPath) else {
        throw GeneratorError("""
            No design tokens at \(shownInput).

            Tokens.swift is generated from that file, so nothing can be produced until
            the design side delivers it. See design/GAPS.md for the shapes this
            generator understands.
            """)
    }

    let data = try Data(contentsOf: inputURL)
    guard !data.isEmpty else {
        throw GeneratorError("""
            \(shownInput) is empty (0 bytes).

            The design token set has not been delivered yet, so there is nothing to
            generate. This is logged in design/GAPS.md. Nothing was written, on purpose:
            inventing token names or values here would put design decisions in the
            codebase where nobody would find them again.
            """)
    }

    let parsed: JSONValue
    do {
        parsed = try JSONDecoder().decode(JSONValue.self, from: data)
    } catch {
        throw GeneratorError("\(shownInput) is not valid JSON: \(error)")
    }

    guard case .object(let object) = parsed else {
        throw GeneratorError("\(shownInput) must contain a JSON object at the top level.")
    }

    // Must be read before the walk: the metadata that drives it is itself a "$"
    // key, which the walk skips.
    TokenParser.integerLeafPatterns = integerLeafPatterns(in: object)

    let root = try TokenParser.namespace(
        named: "",
        swiftName: Renderer.rootEnumName,
        from: object,
        at: []
    )

    guard !root.tokens.isEmpty || !root.children.isEmpty else {
        throw GeneratorError("\(shownInput) contains no tokens.")
    }

    return Renderer.file(
        root: root,
        inputDisplayPath: shownInput,
        fingerprint: fingerprint(of: data),
        byteCount: data.count
    )
}

/// Pulls `$meta.swiftMapping.integerLeaves` out of the document.
func integerLeafPatterns(in object: [String: JSONValue]) -> [String] {
    guard case .object(let meta)? = object["$meta"],
          case .object(let mapping)? = meta["swiftMapping"],
          case .array(let leaves)? = mapping["integerLeaves"] else { return [] }
    return leaves.compactMap { value in
        if case .string(let pattern) = value { return pattern }
        return nil
    }
}

func run() -> Int32 {
    let scriptPath = CommandLine.arguments.first ?? "Scripts/generate-tokens.swift"
    let arguments = Array(CommandLine.arguments.dropFirst())

    do {
        let options = try Options.parse(arguments, scriptPath: scriptPath)
        let generated = try generate(options)
        let shownOutput = displayPath(options.outputPath, relativeTo: options.repoRoot)
        let existing = try? String(contentsOf: URL(fileURLWithPath: options.outputPath), encoding: .utf8)

        if options.checkOnly {
            guard let existing else {
                FileHandle.standardError.write(Data("""
                    \(shownOutput) is missing. Run: swift Scripts/generate-tokens.swift

                    """.utf8))
                return 1
            }
            guard existing == generated else {
                FileHandle.standardError.write(Data("""
                    \(shownOutput) is out of date or was hand-edited.
                    Tokens.swift is generated; edit design/tokens.json instead, then run:
                        swift Scripts/generate-tokens.swift

                    """.utf8))
                return 1
            }
            print("\(shownOutput) is up to date.")
            return 0
        }

        if existing == generated {
            print("\(shownOutput) already up to date.")
            return 0
        }

        let outputURL = URL(fileURLWithPath: options.outputPath)
        try FileManager.default.createDirectory(
            at: outputURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try generated.write(to: outputURL, atomically: true, encoding: .utf8)
        print("Wrote \(shownOutput).")
        return 0
    } catch let error as GeneratorError {
        FileHandle.standardError.write(Data("error: \(error.description)\n".utf8))
        return 1
    } catch {
        FileHandle.standardError.write(Data("error: \(error.localizedDescription)\n".utf8))
        return 1
    }
}

exit(run())
