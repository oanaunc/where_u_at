import Foundation
import CoreLocation
import UIKit
import Combine
import os

private let log = Logger(subsystem: "com.oanarinaldi.WhereUAt", category: "Location")

/// Wraps Core Location.
///
/// The app asks for *When In Use* first and only explains and requests *Always*
/// once the person has seen the map work — Apple's guidance is to request a
/// permission at the moment its value is obvious, not on launch. Without Always,
/// friends only ever see where you were the last time you opened the app, which
/// the Location screen says in as many words.
@MainActor
@Observable
final class LocationService: NSObject {

    private let manager = CLLocationManager()

    private(set) var authorization: CLAuthorizationStatus = .notDetermined
    private(set) var lastFix: CLLocation?
    private(set) var isPreciseLocation: Bool = true

    /// Emits every accepted fix. `AppState` listens and publishes to CloudKit.
    let fixes = PassthroughSubject<CLLocation, Never>()

    /// Don't burn battery or CloudKit writes on jitter: ignore fixes that are
    /// close in both space and time to the last one we published.
    private var lastPublished: CLLocation?
    private let minimumDistance: CLLocationDistance = 60      // metres
    private let minimumInterval: TimeInterval = 45            // seconds

    override init() {
        super.init()
        manager.delegate = self
        manager.desiredAccuracy = kCLLocationAccuracyNearestTenMeters
        manager.distanceFilter = 40
        manager.pausesLocationUpdatesAutomatically = true
        manager.activityType = .other
        authorization = manager.authorizationStatus
        isPreciseLocation = manager.accuracyAuthorization == .fullAccuracy

        UIDevice.current.isBatteryMonitoringEnabled = true
    }

    var batteryLevel: Double? {
        let level = UIDevice.current.batteryLevel
        return level < 0 ? nil : Double(level)
    }

    var deviceName: String { UIDevice.current.name }

    // MARK: Permission

    func requestWhenInUse() {
        manager.requestWhenInUseAuthorization()
    }

    /// Only meaningful once When In Use has been granted.
    func requestAlways() {
        manager.requestAlwaysAuthorization()
    }

    var hasAnyPermission: Bool {
        authorization == .authorizedWhenInUse || authorization == .authorizedAlways
    }

    var hasBackgroundPermission: Bool {
        authorization == .authorizedAlways
    }

    // MARK: Updates

    func start() {
        guard hasAnyPermission else { return }

        // Background updates are only legal to enable with Always.
        if authorization == .authorizedAlways {
            manager.allowsBackgroundLocationUpdates = true
            manager.showsBackgroundLocationIndicator = false
            // Significant-change monitoring survives the app being terminated,
            // which is what keeps a friend's pin from going stale overnight.
            manager.startMonitoringSignificantLocationChanges()
        }
        manager.startUpdatingLocation()
        log.info("Location updates started (auth \(self.authorization.rawValue))")
    }

    func stop() {
        manager.allowsBackgroundLocationUpdates = false
        manager.stopUpdatingLocation()
        manager.stopMonitoringSignificantLocationChanges()
        log.info("Location updates stopped")
    }

    /// One-shot fix, used when the person taps "update now".
    func requestOneShot() {
        guard hasAnyPermission else { return }
        manager.requestLocation()
    }

    private func shouldPublish(_ location: CLLocation) -> Bool {
        guard let last = lastPublished else { return true }
        if location.distance(from: last) >= minimumDistance { return true }
        if location.timestamp.timeIntervalSince(last.timestamp) >= minimumInterval { return true }
        return false
    }
}

extension LocationService: CLLocationManagerDelegate {

    nonisolated func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        let status = manager.authorizationStatus
        let precise = manager.accuracyAuthorization == .fullAccuracy
        Task { @MainActor in
            self.authorization = status
            self.isPreciseLocation = precise
            if self.hasAnyPermission { self.start() }
        }
    }

    nonisolated func locationManager(_ manager: CLLocationManager,
                                     didUpdateLocations locations: [CLLocation]) {
        guard let newest = locations.last else { return }
        // Drop obviously bad fixes rather than showing a friend a wrong pin.
        guard newest.horizontalAccuracy > 0, newest.horizontalAccuracy < 200 else { return }

        Task { @MainActor in
            self.lastFix = newest
            guard self.shouldPublish(newest) else { return }
            self.lastPublished = newest
            self.fixes.send(newest)
        }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        log.error("Location failed: \(error.localizedDescription, privacy: .public)")
    }
}
