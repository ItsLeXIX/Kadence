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
    /// nil when the leg's origin does not resolve: the clause is left out
    /// (§24.10), never filled in with `Home`.
    var originName: String?
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

    /// `{origin}`: the origin place's name, or `where you are`. nil when it
    /// does not resolve — §24.10 "No invented fact in the copy either".
    nonisolated static func originName(_ leg: LegValues, placeNames: [String: String]) -> String? {
        leg.originKind == .currentLocation ? TravelCopy.whereYouAre
            : leg.originPlaceID.flatMap { placeNames[$0] }
    }

    /// `Travel time` / `Travel time from Home`.
    static func travelTime(from origin: String?) -> String {
        "Travel time" + (origin.map { " from \($0)" } ?? "")
    }

    static func shortReason(_ leg: LegValues, placeNames: [String: String], calendar: Calendar) -> String? {
        leg.reason.flatMap {
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
        let travel = travelTime(from: origin)
        let spokenTravel = "travel time" + (origin.map { " from \($0)" } ?? "")
        if leg.status == .pending || leg.reason == .pending {
            return TravelInfo(band: nil, helpSuffix: "· \(travel) not worked out yet",
                              spoken: "\(spokenTravel) not worked out yet")
        }
        return TravelInfo(band: nil, helpSuffix: "· \(travel) unavailable" + (reason.map { ": \($0)" } ?? ""),
                          spoken: "\(spokenTravel) unavailable" + (reason.map { ", \($0)" } ?? ""))
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

    /// The label when the column is too narrow for the minutes: the short
    /// form, so an estimate keeps its `≈` on the time (§25).
    static func narrowBandLabel(_ band: TravelBand, height: CGFloat, calendar: Calendar) -> String? {
        bandLabel(band, height: min(height, 17), calendar: calendar).time
    }

    /// §25.1's hover help.
    static func bandHelp(_ band: TravelBand, calendar: Calendar) -> String {
        let time = TravelCopy.time(band.departAt, calendar: calendar)
        let about = band.isEstimate ? "about " : ""
        var text = "Leave \(about)\(time) · \(about)\(band.minutes) min \(band.mode.copyPhrase)"
        if let origin = band.originName { text += " from \(origin)" }
        if band.bufferMinutes > 0 { text += " · \(band.bufferMinutes) min buffer" }
        if band.isEstimate { text += " · estimate" + (band.reasonShort.map { ", \($0)" } ?? "") }
        return text
    }

    /// §29: `leave by 08:15, 35 minutes by public transport from Home`
    /// (the buffer is not spoken: the time includes it).
    static func spoken(_ band: TravelBand, calendar: Calendar) -> String {
        let time = TravelCopy.time(band.departAt, calendar: calendar)
        let from = band.originName.map { " from \($0)" } ?? ""
        if band.isEstimate {
            return "leave by about \(time), about \(band.minutes) minutes \(band.mode.copyPhrase)\(from), estimate"
        }
        return "leave by \(time), \(band.minutes) minutes \(band.mode.copyPhrase)\(from)"
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
            let place = leg.reasonPlaceID.flatMap { placeNames[$0] }
            return "Add the address\(place.map { " of \($0)" } ?? "") in Settings ▸ Travel so Kadence can work out the trip."
        case .offline:
            return "This Mac is offline. Kadence will ask Apple Maps again when it's back online."
        case .noRoute:
            return "Apple Maps has no route \(leg.mode.copyPhrase) for this trip at this time. Choose another way to travel between these places in Settings ▸ Travel."
        case .paused:
            let retry = leg.retryAt.map { ", and will try at \(TravelCopy.time($0, calendar: calendar))" } ?? ""
            return "Kadence is waiting before it asks Apple Maps again\(retry)."
        case .failed:
            return "Apple Maps didn't answer. Kadence will try again at the next refresh."
        case .pending:
            let origin = originName(leg, placeNames: placeNames)
            return "Kadence is asking Apple Maps for the trip\(origin.map { " from \($0)" } ?? "")."
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
        // §24.10 "No invented fact in the copy either": each clause is
        // stated only from what the leg carries, else left out.
        let from = origin.map { " from \($0)" } ?? ""
        switch leg.status {
        case .ready, .estimate:
            // A leg with no departure has no time to show: it reads as
            // unavailable, with nothing filled in (GAPS G-102).
            guard let departAt = leg.departAt else {
                return LeaveByRow(value: "Unavailable", valueIsSecondary: true, word: nil, lines: [], action: nil,
                                  disabledHelp: nil, spoken: "Leave by, unavailable")
            }
            let isEstimate = leg.status == .estimate
            let time = TravelCopy.time(departAt, calendar: calendar)
            let minutes = leg.duration.map(TravelCopy.minutes)
            let when = leg.computedAt.map { SourceStatusCopy.when($0, now: now, zone: calendar.timeZone) }
            let about = isEstimate ? "about " : ""
            let tripText = (minutes.map { "\(about)\($0) min " } ?? "") + "\(leg.mode.copyPhrase)\(from)\(buffer)"
            let trip = tripText.prefix(1).uppercased() + tripText.dropFirst()
            let spokenTrip = (minutes.map { "\(about)\($0) minutes " } ?? "") + "\(leg.mode.copyPhrase)\(from)\(spokenBuffer)"
            if !isEstimate {
                let spokenWhen = leg.computedAt.flatMap { calendar.isDate($0, inSameDayAs: now)
                    ? "at \(TravelCopy.time($0, calendar: calendar))" : when }
                return LeaveByRow(
                    value: time, valueIsSecondary: false, word: nil,
                    lines: [trip] + (when.map { ["Worked out \($0) by Apple Maps."] } ?? []), action: nil,
                    disabledHelp: nil,
                    spoken: "Leave by, \(time), \(spokenTrip)" + (spokenWhen.map { ", worked out \($0) by Apple Maps" } ?? ""))
            }
            let sentence = leg.reason.map {
                let text = Self.sentence($0, leg: leg, placeNames: placeNames, calendar: calendar)
                return text.prefix(1).lowercased() + text.dropFirst()
            }
            let short = shortReason(leg, placeNames: placeNames, calendar: calendar)
            let action = leg.reason == .failed ? LeaveByRow.Action.tryAgain : nil
            let last = [when.map { "Last worked out \($0) by Apple Maps." }, sentence.map { "Couldn't update: \($0)" }]
                .compactMap { $0 }.joined(separator: " ")
            let spokenLast = [when.map { "last worked out \($0) by Apple Maps" }, short.map { "couldn't update, \($0)" }]
                .compactMap { $0 }
            return LeaveByRow(
                value: time, valueIsSecondary: false, word: "estimate",
                lines: [trip] + (last.isEmpty ? [] : [last]),
                action: action, disabledHelp: disabled(action),
                spoken: (["Leave by, about \(time), estimate, \(spokenTrip)"] + spokenLast).joined(separator: ", "))
        case .pending:
            return LeaveByRow(value: "Working out…", valueIsSecondary: true, word: nil,
                              lines: [sentence(.pending, leg: leg, placeNames: placeNames, calendar: calendar)],
                              action: nil, disabledHelp: nil, spoken: "Leave by, working out")
        case .unavailable:
            guard let reason = leg.reason else {
                return LeaveByRow(value: "Unavailable", valueIsSecondary: true, word: nil, lines: [], action: nil,
                                  disabledHelp: nil, spoken: "Leave by, unavailable")
            }
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
