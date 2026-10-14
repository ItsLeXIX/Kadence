//
//  TravelPresentation.swift
//  Kadence
//
//  Phase 3 slice 2 (PHASE3-SLICE2-PLAN.md task 16) — components.md §25
//  (the band, live), §24.10 (failure copy), §29 (VoiceOver); layouts.md §6
//  (the inspector's `Place` and `Leave by` rows). Pure: a `TravelLeg`'s
//  values in, the words every surface draws out. Replaces the Phase 1
//  display fixture (`TravelFixture`, retired).
//

import Foundation

/// A band to draw: only a leg with a time (`ready` or `estimate`, §25.1).
nonisolated struct TravelBand: Equatable, Sendable {
    var eventID: UUID
    var departAt: Date
    /// Travel only, whole minutes (B48).
    var duration: TimeInterval
    var mode: TravelMode
    var isEstimate: Bool
    /// `Home`, `FH Technikum Wien`, or `where you are`.
    var originName: String
    var bufferMinutes: Int
    /// §24.10's short reason of an estimate (`offline`).
    var reasonShort: String?

    var minutes: Int { TravelCopy.minutes(duration) }
}

/// What a block shows and says about its leg.
nonisolated struct TravelInfo: Equatable, Sendable {
    var band: TravelBand?
    /// §25.3: appended to the block's hover help for a leg with no time.
    var helpSuffix: String?
    /// §29: folded into the block's label after the time.
    var spoken: String
}

enum TravelPresentation {

    // MARK: Building

    static func originName(_ leg: LegValues, placeNames: [String: String]) -> String {
        leg.originKind == .currentLocation ? TravelCopy.whereYouAre
            : leg.originPlaceID.flatMap { placeNames[$0] } ?? "Home"
    }

    static func shortReason(_ leg: LegValues, placeNames: [String: String], calendar: Calendar) -> String? {
        leg.reason.map {
            TravelCopy.shortReason($0, place: leg.reasonPlaceID.flatMap { placeNames[$0] }, mode: leg.mode,
                                   retryAt: leg.retryAt, calendar: calendar)
        }
    }

    static func info(_ leg: LegValues, placeNames: [String: String], calendar: Calendar) -> TravelInfo {
        let origin = originName(leg, placeNames: placeNames)
        let reason = shortReason(leg, placeNames: placeNames, calendar: calendar)
        if leg.hasTime, let departAt = leg.departAt, let duration = leg.duration {
            let band = TravelBand(eventID: leg.eventID, departAt: departAt, duration: duration, mode: leg.mode,
                                  isEstimate: leg.isEstimate, originName: origin,
                                  bufferMinutes: Int(leg.buffer / 60), reasonShort: leg.isEstimate ? reason : nil)
            return TravelInfo(band: band, helpSuffix: nil, spoken: spoken(band, calendar: calendar))
        }
        if leg.status == .pending || leg.reason == .pending || leg.reason == nil {
            return TravelInfo(band: nil, helpSuffix: "· Travel time from \(origin) not worked out yet",
                              spoken: "travel time from \(origin) not worked out yet")
        }
        let short = reason ?? "unavailable"
        return TravelInfo(band: nil, helpSuffix: "· Travel time from \(origin) unavailable: \(short)",
                          spoken: "travel time from \(origin) unavailable, \(short)")
    }

    // MARK: The band (§25.1)

    /// The label at a rendered height: at ≥ 18pt `Leave 08:15` and `·
    /// 35min` (`· ≈35min` for an estimate); below 18pt the minutes drop and
    /// `≈` moves before the time (`Leave ≈08:15`); below 14pt the glyph only.
    static func bandLabel(_ band: TravelBand, height: CGFloat, calendar: Calendar) -> (time: String?, minutes: String?) {
        let time = TravelCopy.time(band.departAt, calendar: calendar)
        guard height >= 14 else { return (nil, nil) }
        if height >= 18 {
            return ("Leave \(time)", "· \(band.isEstimate ? "≈" : "")\(band.minutes)min")
        }
        return ("Leave \(band.isEstimate ? "≈" : "")\(time)", nil)
    }

    /// §25.1's hover help.
    static func bandHelp(_ band: TravelBand, calendar: Calendar) -> String {
        let time = TravelCopy.time(band.departAt, calendar: calendar)
        let about = band.isEstimate ? "about " : ""
        var text = "Leave \(about)\(time) · \(about)\(band.minutes) min \(band.mode.copyPhrase) from \(band.originName)"
        if band.bufferMinutes > 0 { text += " · \(band.bufferMinutes) min buffer" }
        if band.isEstimate { text += " · estimate, \(band.reasonShort ?? "offline")" }
        return text
    }

    /// §29: `leave by 08:15, 35 minutes by public transport from Home`
    /// (the buffer is not spoken: the time includes it).
    static func spoken(_ band: TravelBand, calendar: Calendar) -> String {
        let time = TravelCopy.time(band.departAt, calendar: calendar)
        if band.isEstimate {
            return "leave by about \(time), about \(band.minutes) minutes \(band.mode.copyPhrase) from \(band.originName), estimate"
        }
        return "leave by \(time), \(band.minutes) minutes \(band.mode.copyPhrase) from \(band.originName)"
    }

    // MARK: The inspector's Leave by row (layouts.md §6, §24.10)

    struct LeaveByRow: Equatable, Sendable {
        enum Action: String, Equatable, Sendable {
            case addAddress = "Add Address…"
            case changeWay = "Change Way to Travel…"
            case tryAgain = "Try Again"
        }
        var value: String
        /// `Working out…` / `Unavailable` are secondary; a time is primary.
        var valueIsSecondary: Bool
        /// `estimate`, after the time.
        var word: String?
        var lines: [String]
        var action: Action?
        /// `Try Again` while the queue is paused: disabled, with this help.
        var disabledHelp: String?
        var spoken: String
    }

    /// §24.10's inspector sentence.
    static func sentence(_ reason: TravelReason, leg: LegValues, placeNames: [String: String], calendar: Calendar) -> String {
        switch reason {
        case .needsAddress:
            let place = leg.reasonPlaceID.flatMap { placeNames[$0] } ?? "this place"
            return "Add the address of \(place) in Settings ▸ Travel so Kadence can work out the trip."
        case .offline:
            return "This Mac is offline. Kadence will ask Apple Maps again when it's back online."
        case .noRoute:
            return "Apple Maps has no route \(leg.mode.copyPhrase) for this trip at this time. Choose another way to travel between these places in Settings ▸ Travel."
        case .paused:
            let retry = leg.retryAt.map { TravelCopy.time($0, calendar: calendar) } ?? "a later time"
            return "Kadence is waiting before it asks Apple Maps again, and will try at \(retry)."
        case .failed:
            return "Apple Maps didn't answer. Kadence will try again at the next refresh."
        case .pending:
            return "Kadence is asking Apple Maps for the trip from \(originName(leg, placeNames: placeNames))."
        }
    }

    static func action(for reason: TravelReason?) -> LeaveByRow.Action? {
        switch reason {
        case .needsAddress?: .addAddress
        case .noRoute?: .changeWay
        case .failed?: .tryAgain
        default: nil
        }
    }

    static func leaveBy(_ leg: LegValues, placeNames: [String: String], now: Date, pausedUntil: Date?,
                        calendar: Calendar) -> LeaveByRow {
        let origin = originName(leg, placeNames: placeNames)
        let bufferMinutes = Int(leg.buffer / 60)
        let buffer = bufferMinutes > 0 ? " · \(bufferMinutes) min buffer" : ""
        let spokenBuffer = bufferMinutes > 0 ? ", plus \(bufferMinutes) minutes buffer" : ""
        func disabled(_ action: LeaveByRow.Action?) -> String? {
            guard action == .tryAgain, let pausedUntil, pausedUntil > now else { return nil }
            return "Kadence will try at \(TravelCopy.time(pausedUntil, calendar: calendar))"
        }
        switch leg.status {
        case .ready, .estimate:
            let time = TravelCopy.time(leg.departAt ?? now, calendar: calendar)
            let minutes = TravelCopy.minutes(leg.duration ?? 0)
            let when = leg.computedAt.map { SourceStatusCopy.when($0, now: now, zone: calendar.timeZone) } ?? "earlier"
            let trip = "\(minutes) min \(leg.mode.copyPhrase) from \(origin)\(buffer)"
            if leg.status == .ready {
                let spokenWhen = leg.computedAt.map { calendar.isDate($0, inSameDayAs: now)
                    ? "at \(TravelCopy.time($0, calendar: calendar))" : when } ?? when
                return LeaveByRow(
                    value: time, valueIsSecondary: false, word: nil,
                    lines: [trip, "Worked out \(when) by Apple Maps."], action: nil, disabledHelp: nil,
                    spoken: "Leave by, \(time), \(minutes) minutes \(leg.mode.copyPhrase) from \(origin)\(spokenBuffer), worked out \(spokenWhen) by Apple Maps")
            }
            let reason = leg.reason ?? .offline
            var sentence = Self.sentence(reason, leg: leg, placeNames: placeNames, calendar: calendar)
            sentence = sentence.prefix(1).lowercased() + sentence.dropFirst()
            let short = shortReason(leg, placeNames: placeNames, calendar: calendar) ?? "offline"
            let action = reason == .failed ? LeaveByRow.Action.tryAgain : nil
            return LeaveByRow(
                value: time, valueIsSecondary: false, word: "estimate",
                lines: ["About \(trip)", "Last worked out \(when) by Apple Maps. Couldn't update: \(sentence)"],
                action: action, disabledHelp: disabled(action),
                spoken: "Leave by, about \(time), estimate, about \(minutes) minutes \(leg.mode.copyPhrase) from \(origin)\(spokenBuffer), last worked out \(when) by Apple Maps, couldn't update, \(short)")
        case .pending:
            return LeaveByRow(value: "Working out…", valueIsSecondary: true, word: nil,
                              lines: [sentence(.pending, leg: leg, placeNames: placeNames, calendar: calendar)],
                              action: nil, disabledHelp: nil, spoken: "Leave by, working out")
        case .unavailable:
            let reason = leg.reason ?? .failed
            let text = sentence(reason, leg: leg, placeNames: placeNames, calendar: calendar)
            let action = action(for: reason)
            return LeaveByRow(value: "Unavailable", valueIsSecondary: true, word: nil, lines: [text], action: action,
                              disabledHelp: disabled(action), spoken: "Leave by, unavailable, \(text)")
        }
    }

    /// layouts.md §6: `No travel needed after EPC-ILV` (the title of §24.2's
    /// `P`), when the event chains from its own place.
    static func noTravelLine(previousTitle: String) -> String { "No travel needed after \(previousTitle)" }
}
