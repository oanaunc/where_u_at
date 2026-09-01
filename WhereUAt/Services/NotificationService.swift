import Foundation
import UserNotifications
import CoreLocation
import os

private let log = Logger(subsystem: "com.oanarinaldi.WhereUAt", category: "Notifications")

/// Local notifications only. Arrival and departure alerts are evaluated on this
/// device against places that never leave this device's private database, so
/// "notify me when Alex gets home" doesn't tell anyone — including Alex — that
/// the rule exists.
@MainActor
final class NotificationService {

    static let shared = NotificationService()

    private(set) var isAuthorized = false

    /// Remembers whether each watched person was inside each place last time we
    /// looked, so we can fire on the transition rather than on every update.
    private var insideState: [String: Bool] = [:]

    func requestAuthorization() async {
        do {
            isAuthorized = try await UNUserNotificationCenter.current()
                .requestAuthorization(options: [.alert, .sound, .badge])
        } catch {
            log.error("Notification auth failed: \(error.localizedDescription, privacy: .public)")
        }
    }

    func refreshAuthorizationStatus() async {
        let settings = await UNUserNotificationCenter.current().notificationSettings()
        isAuthorized = settings.authorizationStatus == .authorized
            || settings.authorizationStatus == .provisional
    }

    /// Called after each sync with everybody's newest position.
    func evaluate(rules: [NotifyRule], places: [Place], connections: [Connection]) {
        guard isAuthorized else { return }
        let placesByID = Dictionary(uniqueKeysWithValues: places.map { ($0.id, $0) })
        let connectionsByID = Dictionary(uniqueKeysWithValues: connections.map { ($0.pairingID, $0) })

        for rule in rules where rule.enabled {
            guard let place = placesByID[rule.placeID],
                  let connection = connectionsByID[rule.pairingID],
                  let presence = connection.presence, presence.isSharing else { continue }

            let centre = CLLocation(latitude: place.coordinate.latitude,
                                    longitude: place.coordinate.longitude)
            let distance = presence.location.distance(from: centre)
            let key = "\(rule.id)"

            let isInside: Bool
            switch rule.trigger {
            case .arrives, .leaves: isInside = distance <= place.radius
            case .nearby:           isInside = distance <= max(place.radius, 1000)
            }

            let wasInside = insideState[key]
            insideState[key] = isInside

            // No alert on the first observation — we'd be guessing at a transition.
            guard let wasInside, wasInside != isInside else { continue }

            let name = connection.displayName
            switch rule.trigger {
            case .arrives where isInside:
                post(title: "\(name) arrived", body: "\(name) is at \(place.name).")
            case .leaves where !isInside:
                post(title: "\(name) left", body: "\(name) left \(place.name).")
            case .nearby where isInside:
                post(title: "\(name) is nearby", body: "\(name) is close to \(place.name).")
            default:
                break
            }
        }
    }

    func postConnectionAccepted(name: String) {
        post(title: "You're connected", body: "You and \(name) can now see each other.")
    }

    private func post(title: String, body: String) {
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.sound = .default
        let request = UNNotificationRequest(identifier: UUID().uuidString,
                                            content: content,
                                            trigger: nil)
        UNUserNotificationCenter.current().add(request)
    }
}
