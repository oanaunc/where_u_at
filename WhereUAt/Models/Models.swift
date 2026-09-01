import Foundation
import CoreLocation
import SwiftUI

// MARK: - Profile

/// How a person presents themselves: name, photo, pin colour.
struct PersonProfile: Identifiable, Hashable {
    var pairingID: UUID
    var displayName: String
    var pinColorHex: String
    var emoji: String?
    var avatarData: Data?
    var updatedAt: Date

    var id: UUID { pairingID }

    var pinColor: Color { Color(hexString: pinColorHex) ?? Theme.indigo }

    var initials: String {
        let parts = displayName.split(separator: " ").prefix(2)
        let letters = parts.compactMap { $0.first }.map(String.init)
        return letters.isEmpty ? "?" : letters.joined().uppercased()
    }

    static func blank(pairingID: UUID = UUID()) -> PersonProfile {
        PersonProfile(pairingID: pairingID,
                      displayName: "",
                      pinColorHex: Theme.pinChoices[0].hexString,
                      emoji: nil,
                      avatarData: nil,
                      updatedAt: Date())
    }
}

// MARK: - Presence

/// One person's most recent whereabouts. The app deliberately keeps only the
/// latest fix — there is no location history in v1, which is both simpler and a
/// much better privacy story.
struct Presence: Hashable {
    var coordinate: CLLocationCoordinate2D
    var horizontalAccuracy: CLLocationAccuracy
    var capturedAt: Date
    var battery: Double?      // 0...1
    var isSharing: Bool
    var deviceName: String?

    var location: CLLocation {
        CLLocation(latitude: coordinate.latitude, longitude: coordinate.longitude)
    }

    var isStale: Bool { Date().timeIntervalSince(capturedAt) > 60 * 30 }

    static func == (a: Presence, b: Presence) -> Bool {
        a.coordinate.latitude == b.coordinate.latitude &&
        a.coordinate.longitude == b.coordinate.longitude &&
        a.capturedAt == b.capturedAt &&
        a.isSharing == b.isSharing
    }

    func hash(into hasher: inout Hasher) {
        hasher.combine(coordinate.latitude)
        hasher.combine(coordinate.longitude)
        hasher.combine(capturedAt)
    }
}

// MARK: - Connection

/// A two-way link with one person.
///
/// Each side owns a zone the other can read, so a connection is really a pair of
/// zones matched by `pairingID`. Either half can be missing: an invitation I have
/// sent but nobody has accepted has only my outgoing zone; someone who has
/// paused sharing with me still has an incoming zone, just no fresh presence.
struct Connection: Identifiable, Hashable {
    var pairingID: UUID

    /// Zone I own and share with them. Present once I have invited them.
    var outgoingZoneID: CKRecordZoneIDBox?
    /// Zone they own and share with me. Present once we are both connected.
    var incomingZoneID: CKRecordZoneIDBox?

    /// Their profile, read from the zone they share with me.
    var profile: PersonProfile?
    /// Their latest whereabouts, read from the zone they share with me.
    var presence: Presence?

    /// Whether *I* am currently publishing my location into their view.
    var isSharingWithThem: Bool = true
    /// A locally chosen name that overrides theirs, e.g. "Mum".
    var nickname: String?

    var id: UUID { pairingID }

    var displayName: String {
        nickname ?? profile?.displayName ?? "Pending invite"
    }

    enum State {
        /// I sent an invitation, nobody has accepted it yet.
        case invited
        /// Both zones exist and they are publishing location.
        case connected
        /// Connected, but they have paused sharing with me.
        case theyPaused
        /// Connected, but I have paused sharing with them.
        case iPaused
    }

    var state: State {
        if incomingZoneID == nil { return .invited }
        if !isSharingWithThem { return .iPaused }
        if let p = presence, !p.isSharing { return .theyPaused }
        if presence == nil { return .theyPaused }
        return .connected
    }
}

/// `CKRecordZone.ID` is not `Hashable` in a way that plays nicely with value
/// semantics across versions, so connections carry a small equatable box.
struct CKRecordZoneIDBox: Hashable {
    var zoneName: String
    var ownerName: String
}

// MARK: - Places

struct Place: Identifiable, Hashable {
    var id: String                     // CKRecord.ID.recordName
    var name: String
    var symbol: String                 // SF Symbol
    var coordinate: CLLocationCoordinate2D
    var radius: CLLocationDistance     // metres
    var createdAt: Date

    static func == (a: Place, b: Place) -> Bool { a.id == b.id }
    func hash(into hasher: inout Hasher) { hasher.combine(id) }

    static let symbolChoices = [
        "house.fill", "briefcase.fill", "graduationcap.fill", "dumbbell.fill",
        "cart.fill", "fork.knife", "airplane", "heart.fill", "star.fill"
    ]
}

enum NotifyTrigger: String, CaseIterable, Identifiable {
    case arrives
    case leaves
    case nearby

    var id: String { rawValue }

    var label: String {
        switch self {
        case .arrives: return "When they arrive"
        case .leaves:  return "When they leave"
        case .nearby:  return "When they're nearby"
        }
    }
}

struct NotifyRule: Identifiable, Hashable {
    var id: String                     // CKRecord.ID.recordName
    var pairingID: UUID
    var placeID: String
    var trigger: NotifyTrigger
    var enabled: Bool
}

// MARK: - Sharing status

/// Global switch shown on the Privacy tab and behind your own map bubble.
enum SharingStatus: Equatable {
    case on
    case pausedUntil(Date)
    case off

    var isOn: Bool { if case .on = self { return true }; return false }

    var label: String {
        switch self {
        case .on: return "Sharing Location"
        case .pausedUntil(let d): return "Paused until \(d.formatted(date: .omitted, time: .shortened))"
        case .off: return "Not Sharing"
        }
    }
}
