//
//  SystemLocationSource.swift
//  Kadence
//
//  Phase 3 slice 2 (PHASE3-SLICE2-PLAN.md task 7) — components.md §24.12:
//  where the Mac is, from CoreLocation. One-shot fixes only
//  (`requestLocation()`, accuracy a hundred metres, 10 s timeout). Asked
//  for permission only when `TravelCoordinator` first wants a fix, or from
//  Settings' `Allow Location…` — never at launch.
//
//  Constructed only by a normal launch (`LocationServices`). The only file
//  in the app that imports CoreLocation (a test scans the sources). Its only
//  tested part is the pure authorization mapping below.
//

import Foundation
import CoreLocation

@MainActor
final class SystemLocationSource: NSObject, LocationSource, CLLocationManagerDelegate {
    private let manager = CLLocationManager()
    private var authorizationWaiters: [CheckedContinuation<LocationAuthorization, Never>] = []
    private var fixWaiters: [CheckedContinuation<LocationFix?, Never>] = []

    override init() {
        super.init()
        manager.delegate = self
        manager.desiredAccuracy = kCLLocationAccuracyHundredMeters
    }

    // MARK: LocationSource

    nonisolated func authorization() async -> LocationAuthorization {
        await MainActor.run { current }
    }

    nonisolated func requestAuthorization() async -> LocationAuthorization {
        await withCheckedContinuation { continuation in
            Task { @MainActor in
                guard self.current == .notDetermined else { return continuation.resume(returning: self.current) }
                self.authorizationWaiters.append(continuation)
                self.manager.requestWhenInUseAuthorization()
            }
        }
    }

    nonisolated func currentFix(timeout: Duration) async -> LocationFix? {
        await withCheckedContinuation { continuation in
            Task { @MainActor in
                guard self.current == .allowed else { return continuation.resume(returning: nil) }
                self.fixWaiters.append(continuation)
                self.manager.requestLocation()
                // Live only: a normal launch's wall clock (tests never get here).
                Task { @MainActor in
                    try? await Task.sleep(for: timeout)
                    self.finishFix(nil)
                }
            }
        }
    }

    private var current: LocationAuthorization {
        Self.map(status: manager.authorizationStatus, servicesEnabled: CLLocationManager.locationServicesEnabled())
    }

    // MARK: Delegate

    nonisolated func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        Task { @MainActor in
            let state = self.current
            guard state != .notDetermined else { return }
            let waiters = self.authorizationWaiters
            self.authorizationWaiters = []
            for waiter in waiters { waiter.resume(returning: state) }
        }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        let fix = locations.last.map {
            LocationFix(latitude: $0.coordinate.latitude, longitude: $0.coordinate.longitude,
                        horizontalAccuracy: $0.horizontalAccuracy, timestamp: $0.timestamp)
        }
        Task { @MainActor in self.finishFix(fix) }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        Task { @MainActor in self.finishFix(nil) }
    }

    private func finishFix(_ fix: LocationFix?) {
        let waiters = fixWaiters
        fixWaiters = []
        for waiter in waiters { waiter.resume(returning: fix) }
    }

    // MARK: Pure mapping — tested

    /// §24.12: allowed / denied (incl. restricted) / servicesOff /
    /// notDetermined.
    nonisolated static func map(status: CLAuthorizationStatus, servicesEnabled: Bool) -> LocationAuthorization {
        guard servicesEnabled else { return .servicesOff }
        switch status {
        case .notDetermined: return .notDetermined
        case .denied, .restricted: return .denied
        default: return .allowed
        }
    }
}
