import Foundation
import CloudKit
import CoreLocation
import UIKit
import os

private let log = Logger(subsystem: "com.oanarinaldi.WhereUAt", category: "CloudKit")

enum CloudKitError: LocalizedError {
    case noAccount
    case restricted
    case couldNotDetermineAccount
    case shareMissing
    case zoneMissing

    var errorDescription: String? {
        switch self {
        case .noAccount:
            return "Sign in to iCloud in Settings to use Where U At. Your iCloud account is what connects you to other people — there is no separate account to create."
        case .restricted:
            return "iCloud is restricted on this device, so Where U At can't connect you with anyone."
        case .couldNotDetermineAccount:
            return "Couldn't reach iCloud. Check your connection and try again."
        case .shareMissing:
            return "That invitation is no longer available."
        case .zoneMissing:
            return "That connection has been removed."
        }
    }
}

/// All CloudKit access. There is no sign-up and no password anywhere in the app:
/// identity is the iCloud account already on the device, and the only thing that
/// ever crosses between two people is a `CKShare` they each explicitly accept.
actor CloudKitService {

    static let shared = CloudKitService()

    private let container = CK.container
    var privateDB: CKDatabase { container.privateCloudDatabase }
    var sharedDB: CKDatabase { container.sharedCloudDatabase }

    private var cachedUserRecordID: CKRecord.ID?

    // MARK: - Account

    func accountStatus() async throws -> CKAccountStatus {
        try await container.accountStatus()
    }

    /// Throws a human-readable error when the device can't do CloudKit at all.
    func requireAccount() async throws {
        switch try await container.accountStatus() {
        case .available:            return
        case .noAccount:            throw CloudKitError.noAccount
        case .restricted:           throw CloudKitError.restricted
        case .couldNotDetermine:    throw CloudKitError.couldNotDetermineAccount
        case .temporarilyUnavailable: throw CloudKitError.couldNotDetermineAccount
        @unknown default:           throw CloudKitError.couldNotDetermineAccount
        }
    }

    func userRecordID() async throws -> CKRecord.ID {
        if let cachedUserRecordID { return cachedUserRecordID }
        let id = try await container.userRecordID()
        cachedUserRecordID = id
        return id
    }

    // MARK: - Inviting someone

    /// Creates a fresh private zone for one person, writes my profile into it,
    /// and returns a share the invitee can accept.
    ///
    /// One zone per person is what buys per-person privacy controls later: a
    /// zone-wide share is all-or-nothing, so pausing for one person without
    /// disappearing from everybody means giving each person their own zone.
    func createInvitation(myProfile: PersonProfile) async throws -> (share: CKShare, pairingID: UUID) {
        try await requireAccount()

        let pairingID = UUID()
        let zoneID = CKRecordZone.ID(zoneName: Schema.connectionZoneName(pairingID: pairingID),
                                     ownerName: CKCurrentUserDefaultName)
        let zone = CKRecordZone(zoneID: zoneID)
        _ = try await privateDB.modifyRecordZones(saving: [zone], deleting: [])

        let profileRecord = makeProfileRecord(myProfile, pairingID: pairingID, in: zoneID)

        let share = CKShare(recordZoneID: zoneID)
        share[CKShare.SystemFieldKey.title] = "\(myProfile.displayName) on Where U At" as CKRecordValue
        // Read-only: a participant sees where I am, and never writes into my zone.
        share.publicPermission = .none

        let result = try await privateDB.modifyRecords(saving: [profileRecord, share],
                                                       deleting: [],
                                                       savePolicy: .changedKeys,
                                                       atomically: true)
        for (_, r) in result.saveResults { _ = try r.get() }

        log.info("Created invitation zone \(zoneID.zoneName, privacy: .public)")
        return (share, pairingID)
    }

    // MARK: - Accepting an invitation

    /// Accepts an incoming share, then — because sharing is mutual by design —
    /// creates my own zone with the *same* pairing ID and shares it straight back
    /// to the person who invited me. That is what makes the connection two-way
    /// without a second round of invitations.
    @discardableResult
    func acceptInvitation(_ metadata: CKShare.Metadata, myProfile: PersonProfile) async throws -> UUID {
        try await requireAccount()

        let acceptedShare = try await container.accept(metadata)
        let theirZoneID = acceptedShare.recordID.zoneID

        guard let pairingID = Schema.pairingID(fromZoneName: theirZoneID.zoneName) else {
            throw CloudKitError.shareMissing
        }
        log.info("Accepted share for pairing \(pairingID.uuidString, privacy: .public)")

        // Share back so they can see me too.
        if let ownerID = metadata.ownerIdentity.userRecordID {
            try? await shareBack(to: ownerID, pairingID: pairingID, myProfile: myProfile)
        }
        return pairingID
    }

    /// Builds my half of the connection and adds exactly one participant.
    func shareBack(to ownerUserRecordID: CKRecord.ID,
                   pairingID: UUID,
                   myProfile: PersonProfile) async throws {
        let zoneID = CKRecordZone.ID(zoneName: Schema.connectionZoneName(pairingID: pairingID),
                                     ownerName: CKCurrentUserDefaultName)

        // Already shared back (e.g. re-accepting the same link) — nothing to do.
        if let existing = try? await privateDB.recordZone(for: zoneID), existing.zoneID == zoneID,
           (try? await fetchShare(for: zoneID)) != nil {
            return
        }

        _ = try await privateDB.modifyRecordZones(saving: [CKRecordZone(zoneID: zoneID)], deleting: [])

        let profileRecord = makeProfileRecord(myProfile, pairingID: pairingID, in: zoneID)

        let share = CKShare(recordZoneID: zoneID)
        share[CKShare.SystemFieldKey.title] = "\(myProfile.displayName) on Where U At" as CKRecordValue
        share.publicPermission = .none

        let participant = try await container.shareParticipant(forUserRecordID: ownerUserRecordID)
        participant.permission = .readOnly
        participant.role = .privateUser
        share.addParticipant(participant)

        let result = try await privateDB.modifyRecords(saving: [profileRecord, share],
                                                       deleting: [],
                                                       savePolicy: .changedKeys,
                                                       atomically: true)
        for (_, r) in result.saveResults { _ = try r.get() }
        log.info("Shared back to owner for pairing \(pairingID.uuidString, privacy: .public)")
    }

    func fetchShare(for zoneID: CKRecordZone.ID) async throws -> CKShare? {
        let shareID = CKRecord.ID(recordName: CKRecordNameZoneWideShare, zoneID: zoneID)
        do {
            return try await privateDB.record(for: shareID) as? CKShare
        } catch let error as CKError where error.code == .unknownItem {
            return nil
        }
    }

    // MARK: - Publishing my location

    /// Writes my current fix into every zone I am actively sharing.
    ///
    /// `pausedPairingIDs` are skipped entirely rather than written with a flag,
    /// so a paused person's copy simply stops moving — nothing new about me is
    /// uploaded anywhere they can read.
    func publish(presence: Presence,
                 to pairingIDs: [UUID],
                 pausedPairingIDs: Set<UUID>) async {
        for pairingID in pairingIDs {
            let zoneID = CKRecordZone.ID(zoneName: Schema.connectionZoneName(pairingID: pairingID),
                                         ownerName: CKCurrentUserDefaultName)
            let recordID = CKRecord.ID(recordName: Schema.RecordName.presence, zoneID: zoneID)
            let record = CKRecord(recordType: Schema.RecordType.presence, recordID: recordID)

            let paused = pausedPairingIDs.contains(pairingID)
            record[Schema.Presence.isSharing] = (paused ? 0 : 1) as CKRecordValue

            if !paused {
                record[Schema.Presence.location] = CLLocation(
                    coordinate: presence.coordinate,
                    altitude: 0,
                    horizontalAccuracy: presence.horizontalAccuracy,
                    verticalAccuracy: -1,
                    timestamp: presence.capturedAt
                )
                record[Schema.Presence.capturedAt] = presence.capturedAt as CKRecordValue
                record[Schema.Presence.battery] = (presence.battery ?? -1) as CKRecordValue
                record[Schema.Presence.deviceName] = (presence.deviceName ?? "") as CKRecordValue
            }

            do {
                _ = try await privateDB.modifyRecords(saving: [record],
                                                      deleting: [],
                                                      savePolicy: .allKeys,
                                                      atomically: true)
            } catch let error as CKError where error.code == .zoneNotFound {
                log.error("Zone gone for pairing \(pairingID.uuidString, privacy: .public); skipping")
            } catch {
                log.error("Publish failed: \(error.localizedDescription, privacy: .public)")
            }
        }
    }

    /// Pushes my name/photo/colour into every connection zone I own.
    func publishProfile(_ profile: PersonProfile, to pairingIDs: [UUID]) async {
        for pairingID in pairingIDs {
            let zoneID = CKRecordZone.ID(zoneName: Schema.connectionZoneName(pairingID: pairingID),
                                         ownerName: CKCurrentUserDefaultName)
            let record = makeProfileRecord(profile, pairingID: pairingID, in: zoneID)
            _ = try? await privateDB.modifyRecords(saving: [record], deleting: [],
                                                   savePolicy: .allKeys, atomically: true)
        }
    }

    private func makeProfileRecord(_ profile: PersonProfile,
                                   pairingID: UUID,
                                   in zoneID: CKRecordZone.ID) -> CKRecord {
        let recordID = CKRecord.ID(recordName: Schema.RecordName.profile, zoneID: zoneID)
        let record = CKRecord(recordType: Schema.RecordType.profile, recordID: recordID)
        record[Schema.Profile.displayName] = profile.displayName as CKRecordValue
        record[Schema.Profile.pinColor]    = profile.pinColorHex as CKRecordValue
        record[Schema.Profile.emoji]       = (profile.emoji ?? "") as CKRecordValue
        record[Schema.Profile.pairingID]   = pairingID.uuidString as CKRecordValue
        record[Schema.Profile.updatedAt]   = Date() as CKRecordValue
        if let data = profile.avatarData, let asset = CKAsset.temporary(data: data) {
            record[Schema.Profile.avatar] = asset
        }
        return record
    }
}

// MARK: - Helpers

extension CKAsset {
    /// CKAsset needs a file on disk; write one into the caches directory.
    static func temporary(data: Data) -> CKAsset? {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString + ".jpg")
        do {
            try data.write(to: url)
            return CKAsset(fileURL: url)
        } catch {
            return nil
        }
    }
}
