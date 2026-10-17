//
//  FeedStatusCopy.swift
//  Kadence
//
//  Phase 3 slice 3 — components.md §34.3: a feed source's states use §19.1's
//  machinery with **their own copy** — a feed has no username, no calendars
//  and items, not events. Exact strings, tested. `{host}` is the URL's host,
//  never more of it (§33.4).
//

import Foundation

nonisolated enum FeedStatusCopy {
    /// §34.3: the noun is `items`.
    static func items(_ n: Int) -> String { n == 1 ? "1 item" : "\(n) items" }

    static func title(_ state: SourceState, host: String) -> String {
        switch state {
        case .upToDate: "Up to date"
        case .syncing: "Syncing…"
        case .neverSynced: "Waiting for first sync"
        case .offline: "Offline"
        case .unauthorized: "Calendar URL refused"
        case .forbidden: "Access refused"
        case .feedNotFound: "Calendar not found"
        case .notACalendar: "Not a calendar"
        case .urlMissing: "Calendar URL not found"
        case .redirected: "Redirected to another server"
        case .certificate: "Secure connection failed"
        case .partialImport: "Imported with problems"
        case .emptyFeed: "Moodle sent no items"
        case .unreachable: "Can't reach \(host)"
        case .serverError: "Server error"
        // CalDAV-only states never occur on a feed; §19.1's title stands.
        case .noCalDAV, .noCalendars, .calendarMissing, .fetchFailed, .passwordMissing:
            SourceStatusCopy.title(state, host: host)
        }
    }

    /// The body with `{next}`, `{last}` and `{until}` resolved by the caller
    /// (the stored detail keeps them as placeholders: they move with time).
    static func body(_ state: SourceState, _ f: StatusFacts, next: String, last: String, until: String) -> String? {
        switch state {
        case .upToDate, .syncing: return nil
        case .neverSynced: return "Kadence will sync as soon as \(f.host) can be reached."
        case .offline:
            return "Kadence will sync when this Mac is back online. Items from the last sync (\(last)) are still shown."
        case .unauthorized:
            return "\(f.host) didn't accept the calendar URL. Moodle makes a new URL when your password changes. Automatic sync is paused."
        case .forbidden:
            return "\(f.host) refused access to the calendar. Automatic sync is paused."
        case .feedNotFound:
            return "\(f.host) has no calendar at the saved URL. Items from the last sync are kept."
        case .notACalendar:
            return "\(f.host) sent a web page instead of the calendar — usually a sign-in or error page. If you changed your FH password, Moodle made a new calendar URL. Items from the last sync are kept."
        case .urlMissing:
            return "Kadence couldn't read the calendar URL for \(f.name) from the Keychain. Paste it again."
        case .redirected:
            if let other = f.otherHost {
                return "\(f.host) sent Kadence to \(other). Kadence didn't follow it, so nothing was sent there."
            }
            return "\(f.host) sent Kadence to an address without HTTPS. Kadence didn't follow it."
        case .certificate:
            return "The certificate for \(f.host) couldn't be verified, so Kadence sent nothing to it. Nothing was changed."
        case .partialImport:
            return "\(f.k) of \(items(f.n)) couldn't be read and were skipped. Nothing was removed."
        case .emptyFeed:
            return "\(f.host) sent an empty calendar, though it had \(items(f.n)) at the last sync. They are kept; if it still sends none after \(until), Kadence removes the ones from today on."
        case .unreachable:
            return "Kadence will try again at \(next). Items from the last sync (\(last)) are still shown."
        case .serverError:
            return "\(f.host) answered with an error (\(f.code.map(String.init) ?? "?")). Kadence will try again at \(next)."
        case .noCalDAV, .noCalendars, .calendarMissing, .fetchFailed, .passwordMissing:
            return SourceStatusCopy.body(state, f, next: next, last: last)
        }
    }

    static func primaryAction(_ state: SourceState) -> PrimaryAction? {
        switch state {
        case .syncing, .offline: nil
        case .unauthorized, .forbidden, .feedNotFound, .notACalendar, .urlMissing, .redirected: .replaceURL
        case .partialImport: .showDetails
        default: .syncNow
        }
    }

    /// `{until}` (§34.3): `emptySince + 12 h` in §19.5's in-sentence forms
    /// read forward — `today 23:07`, `tomorrow 01:07`, `Mon 01:07`.
    static func until(_ date: Date, now: Date, zone: TimeZone) -> String {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = zone
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_GB")
        f.timeZone = zone
        f.dateFormat = "HH:mm"
        let time = f.string(from: date)
        let days = cal.dateComponents([.day], from: cal.startOfDay(for: now), to: cal.startOfDay(for: date)).day ?? 0
        switch days {
        case ...0: return "today \(time)"
        case 1: return "tomorrow \(time)"
        case 2...6:
            f.dateFormat = "EEE"
            return "\(f.string(from: date)) \(time)"
        default:
            f.dateFormat = "d MMM"
            return "\(f.string(from: date)) \(time)"
        }
    }

    /// The stored detail: placeholders for what moves with time.
    static func storedDetail(_ state: SourceState, _ facts: StatusFacts) -> String? {
        body(state, facts, next: "{next}", last: "{last}", until: "{until}")
    }

    /// §34.3: `Last synced {last} · {count} items` (`Synced …` when up to date).
    static func statusLine(state: SourceState, lastSuccess: Date?, count: Int, now: Date, zone: TimeZone) -> String {
        guard let lastSuccess else { return "Never synced" }
        if state == .upToDate { return "Synced \(SourceStatusCopy.synced(lastSuccess, now: now, zone: zone)) · \(items(count))" }
        return "Last synced \(SourceStatusCopy.when(lastSuccess, now: now, zone: zone)) · \(items(count))"
    }
}
