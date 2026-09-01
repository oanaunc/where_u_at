import Foundation
import CloudKit

/// Every record type / field name the app uses, in one place.
///
/// Sharing model, in short: a person does **not** share one zone with everybody.
/// Each connection gets its own private custom zone, shared with exactly one
/// participant. That is what makes "pause sharing with Maria, keep sharing with
/// Alex" possible — a zone-wide `CKShare` is all-or-nothing per zone, so
/// per-person control has to come from per-person zones.
enum Schema {

    /// Custom zone owned by me, holding what exactly one other person may read.
    /// Named `conn-<pairingID>` so both sides can match their two zones up.
    static let connectionZonePrefix = "conn-"

    static func connectionZoneName(pairingID: UUID) -> String {
        connectionZonePrefix + pairingID.uuidString
    }

    static func pairingID(fromZoneName name: String) -> UUID? {
        guard name.hasPrefix(connectionZonePrefix) else { return nil }
        return UUID(uuidString: String(name.dropFirst(connectionZonePrefix.count)))
    }

    // MARK: Record types

    enum RecordType {
        /// Who I am, as this one person sees me. One per connection zone.
        static let profile  = "Profile"
        /// Where I am, as this one person sees me. One per connection zone.
        static let presence = "Presence"
        /// A saved place. Private database, default zone — never shared.
        static let place    = "Place"
        /// An arrival/departure rule. Private database, default zone — never shared.
        static let notifyRule = "NotifyRule"
    }

    /// Fixed record names so each zone holds exactly one profile and one presence.
    enum RecordName {
        static let profile  = "profile"
        static let presence = "presence"
    }

    // MARK: Fields

    enum Profile {
        static let displayName = "displayName"
        static let pinColor    = "pinColor"     // 6-digit hex, no leading #
        static let emoji       = "emoji"
        static let avatar      = "avatar"       // CKAsset, JPEG
        static let pairingID   = "pairingID"    // links my zone to their zone
        static let updatedAt   = "updatedAt"
    }

    enum Presence {
        static let location   = "location"      // CLLocation
        static let capturedAt = "capturedAt"
        static let battery    = "battery"       // 0...1, -1 when unknown
        static let isSharing  = "isSharing"     // 1 sharing, 0 paused
        static let deviceName = "deviceName"
    }

    enum Place {
        static let name      = "name"
        static let symbol    = "symbol"         // SF Symbol name
        static let location  = "location"       // CLLocation (centre)
        static let radius    = "radius"         // metres
        static let createdAt = "createdAt"
    }

    enum NotifyRule {
        static let pairingID = "pairingID"      // which person this watches
        static let placeRef  = "placeRef"       // CKRecord.Reference to Place
        static let trigger   = "trigger"        // NotifyTrigger.rawValue
        static let enabled   = "enabled"
    }

    // MARK: Subscriptions

    enum SubscriptionID {
        static let sharedChanges  = "shared-db-changes"
        static let privateChanges = "private-db-changes"
    }
}

/// The container. Must match `WhereUAt.entitlements`.
enum CK {
    static let containerID = "iCloud.com.oanarinaldi.WhereUAt"
    static var container: CKContainer { CKContainer(identifier: containerID) }
}
