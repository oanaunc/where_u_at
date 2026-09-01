import Foundation
import CloudKit
import CoreLocation
import os

private let log = Logger(subsystem: "com.oanarinaldi.WhereUAt", category: "Sync")

/// What one sync pass discovered.
struct SyncResult {
    var connections: [Connection] = []
}

extension CloudKitService {

    // MARK: - Reading everything

    /// Rebuilds the full picture of who I'm connected to.
    ///
    /// Outgoing zones (mine, in the private database) tell me who I have invited
    /// and whether they have accepted. Incoming zones (theirs, in the shared
    /// database) carry their profile and their latest fix.
    func loadConnections() async throws -> [Connection] {
        try await requireAccount()

        var byPairing: [UUID: Connection] = [:]

        // --- My half: zones I own and share out.
        for zone in (try? await privateDB.allRecordZones()) ?? [] {
            guard let pairingID = Schema.pairingID(fromZoneName: zone.zoneID.zoneName) else { continue }
            var c = byPairing[pairingID] ?? Connection(pairingID: pairingID)
            c.outgoingZoneID = CKRecordZoneIDBox(zoneName: zone.zoneID.zoneName,
                                                 ownerName: zone.zoneID.ownerName)
            byPairing[pairingID] = c
        }

        // --- Their half: zones shared with me.
        for zone in (try? await sharedDB.allRecordZones()) ?? [] {
            guard let pairingID = Schema.pairingID(fromZoneName: zone.zoneID.zoneName) else { continue }
            var c = byPairing[pairingID] ?? Connection(pairingID: pairingID)
            c.incomingZoneID = CKRecordZoneIDBox(zoneName: zone.zoneID.zoneName,
                                                 ownerName: zone.zoneID.ownerName)

            let (profile, presence) = await readZoneContents(zone.zoneID, in: sharedDB, pairingID: pairingID)
            c.profile = profile
            c.presence = presence
            byPairing[pairingID] = c
        }

        return byPairing.values.sorted { a, b in
            a.displayName.localizedCaseInsensitiveCompare(b.displayName) == .orderedAscending
        }
    }

    /// Pulls the single profile + single presence record out of one zone.
    private func readZoneContents(_ zoneID: CKRecordZone.ID,
                                  in database: CKDatabase,
                                  pairingID: UUID) async -> (PersonProfile?, Presence?) {
        var profile: PersonProfile?
        var presence: Presence?

        let profileID  = CKRecord.ID(recordName: Schema.RecordName.profile,  zoneID: zoneID)
        let presenceID = CKRecord.ID(recordName: Schema.RecordName.presence, zoneID: zoneID)

        let results = try? await database.records(for: [profileID, presenceID])
        for (id, result) in results ?? [:] {
            guard let record = try? result.get() else { continue }
            if id.recordName == Schema.RecordName.profile {
                profile = Self.decodeProfile(record, pairingID: pairingID)
            } else if id.recordName == Schema.RecordName.presence {
                presence = Self.decodePresence(record)
            }
        }
        return (profile, presence)
    }

    nonisolated static func decodeProfile(_ record: CKRecord, pairingID: UUID) -> PersonProfile {
        var avatarData: Data?
        if let asset = record[Schema.Profile.avatar] as? CKAsset, let url = asset.fileURL {
            avatarData = try? Data(contentsOf: url)
        }
        let emoji = (record[Schema.Profile.emoji] as? String).flatMap { $0.isEmpty ? nil : $0 }
        return PersonProfile(
            pairingID: pairingID,
            displayName: record[Schema.Profile.displayName] as? String ?? "Someone",
            pinColorHex: record[Schema.Profile.pinColor] as? String ?? "4C6FF5",
            emoji: emoji,
            avatarData: avatarData,
            updatedAt: record[Schema.Profile.updatedAt] as? Date ?? Date()
        )
    }

    nonisolated static func decodePresence(_ record: CKRecord) -> Presence? {
        let isSharing = (record[Schema.Presence.isSharing] as? Int64 ?? 1) == 1
        guard let loc = record[Schema.Presence.location] as? CLLocation else {
            // Paused people publish no coordinate at all — that is the point.
            return nil
        }
        let battery = record[Schema.Presence.battery] as? Double
        let device  = (record[Schema.Presence.deviceName] as? String).flatMap { $0.isEmpty ? nil : $0 }
        return Presence(
            coordinate: loc.coordinate,
            horizontalAccuracy: loc.horizontalAccuracy,
            capturedAt: record[Schema.Presence.capturedAt] as? Date ?? loc.timestamp,
            battery: (battery ?? -1) < 0 ? nil : battery,
            isSharing: isSharing,
            deviceName: device
        )
    }

    // MARK: - Who can see me

    /// Participants on my outgoing share for one person, so the Privacy tab can
    /// answer "who can see where I am right now?" from the source of truth
    /// rather than from local bookkeeping.
    func participants(forPairing pairingID: UUID) async -> [CKShare.Participant] {
        let zoneID = CKRecordZone.ID(zoneName: Schema.connectionZoneName(pairingID: pairingID),
                                     ownerName: CKCurrentUserDefaultName)
        guard let share = try? await fetchShare(for: zoneID) else { return [] }
        return share.participants.filter { $0.role != .owner }
    }

    /// True once somebody has actually accepted my invitation.
    func invitationAccepted(pairingID: UUID) async -> Bool {
        await participants(forPairing: pairingID).contains { $0.acceptanceStatus == .accepted }
    }

    // MARK: - Ending a connection

    /// Deletes my zone (so they can no longer see me) and drops their zone from
    /// my shared database (so I can no longer see them).
    func removeConnection(_ connection: Connection) async throws {
        if let out = connection.outgoingZoneID {
            let zoneID = CKRecordZone.ID(zoneName: out.zoneName, ownerName: out.ownerName)
            _ = try? await privateDB.modifyRecordZones(saving: [], deleting: [zoneID])
        }
        if let inc = connection.incomingZoneID {
            // Leaving a share I participate in means deleting the zone-wide share record.
            let shareID = CKRecord.ID(recordName: CKRecordNameZoneWideShare,
                                      zoneID: CKRecordZone.ID(zoneName: inc.zoneName,
                                                              ownerName: inc.ownerName))
            _ = try? await sharedDB.modifyRecords(saving: [CKRecord](), deleting: [shareID],
                                                  savePolicy: CKModifyRecordsOperation.RecordSavePolicy.changedKeys,
                                                  atomically: false)
        }
        log.info("Removed connection \(connection.pairingID.uuidString, privacy: .public)")
    }

    // MARK: - Push subscriptions

    /// Silent pushes on the shared database are what make other people's pins
    /// move without the app being open.
    func ensureSubscriptions() async {
        await ensureDatabaseSubscription(id: Schema.SubscriptionID.sharedChanges, in: sharedDB)
        await ensureDatabaseSubscription(id: Schema.SubscriptionID.privateChanges, in: privateDB)
    }

    private func ensureDatabaseSubscription(id: String, in database: CKDatabase) async {
        if let existing = try? await database.subscription(for: id), existing.subscriptionID == id {
            return
        }
        let subscription = CKDatabaseSubscription(subscriptionID: id)
        let info = CKSubscription.NotificationInfo()
        info.shouldSendContentAvailable = true   // silent: no banner, just a wake-up
        subscription.notificationInfo = info
        do {
            _ = try await database.modifySubscriptions(saving: [subscription], deleting: [])
            log.info("Subscription \(id, privacy: .public) registered")
        } catch {
            log.error("Subscription \(id, privacy: .public) failed: \(error.localizedDescription, privacy: .public)")
        }
    }

    // MARK: - Places (private, never shared)

    func loadPlaces() async throws -> [Place] {
        let query = CKQuery(recordType: Schema.RecordType.place,
                            predicate: NSPredicate(value: true))
        query.sortDescriptors = [NSSortDescriptor(key: Schema.Place.createdAt, ascending: true)]
        let zone: CKRecordZone.ID? = nil
        let (matches, _) = try await privateDB.records(matching: query,
                                                       inZoneWith: zone,
                                                       desiredKeys: nil,
                                                       resultsLimit: CKQueryOperation.maximumResults)
        return matches.compactMap { _, result -> Place? in
            guard let r = try? result.get(),
                  let loc = r[Schema.Place.location] as? CLLocation else { return nil }
            return Place(id: r.recordID.recordName,
                         name: r[Schema.Place.name] as? String ?? "Place",
                         symbol: r[Schema.Place.symbol] as? String ?? "mappin.circle.fill",
                         coordinate: loc.coordinate,
                         radius: r[Schema.Place.radius] as? Double ?? 150,
                         createdAt: r[Schema.Place.createdAt] as? Date ?? Date())
        }
    }

    @discardableResult
    func save(place: Place) async throws -> Place {
        let record = CKRecord(recordType: Schema.RecordType.place,
                              recordID: CKRecord.ID(recordName: place.id))
        record[Schema.Place.name]   = place.name as CKRecordValue
        record[Schema.Place.symbol] = place.symbol as CKRecordValue
        record[Schema.Place.radius] = place.radius as CKRecordValue
        record[Schema.Place.location] = CLLocation(latitude: place.coordinate.latitude,
                                                   longitude: place.coordinate.longitude)
        record[Schema.Place.createdAt] = place.createdAt as CKRecordValue
        _ = try await privateDB.modifyRecords(saving: [record], deleting: [CKRecord.ID](),
                                              savePolicy: CKModifyRecordsOperation.RecordSavePolicy.allKeys,
                                              atomically: true)
        return place
    }

    func delete(placeID: String) async {
        _ = try? await privateDB.modifyRecords(saving: [CKRecord](),
                                               deleting: [CKRecord.ID(recordName: placeID)],
                                               savePolicy: CKModifyRecordsOperation.RecordSavePolicy.changedKeys,
                                               atomically: false)
    }
}
