import Foundation
import SwiftUI
import CloudKit
import CoreLocation
import Combine
import os

private let log = Logger(subsystem: "com.oanarinaldi.WhereUAt", category: "AppState")

@MainActor
@Observable
final class AppState {

    /// Opt-in, launch-argument-only data used to photograph the app for its
    /// App Store listing. Release builds can never enter this mode.
    let isScreenshotDemo: Bool

    // MARK: Stored on device only

    var myProfile: PersonProfile = .blank()
    var hasCompletedOnboarding = false

    /// Which version of the privacy terms this person agreed to, and when.
    /// Kept so a material change to the policy can ask again rather than
    /// assuming an old agreement still covers new processing.
    var consentVersion: String?
    var consentedAt: Date?
    var sharingStatus: SharingStatus = .on
    /// Pairing IDs I have individually paused. Persisted locally; the effect is
    /// simply that nothing new is written into those people's zones.
    var pausedPairingIDs: Set<UUID> = []
    var nicknames: [UUID: String] = [:]

    // MARK: Synced

    var connections: [Connection] = []
    var places: [Place] = []
    var notifyRules: [NotifyRule] = []

    // MARK: Transient UI

    var accountStatus: CKAccountStatus = .couldNotDetermine
    var isSyncing = false
    var errorMessage: String?
    /// Set when a share invitation arrives, so the UI can present the accept sheet.
    var pendingInvitation: CKShare.Metadata?
    /// A place the person tapped on the Places tab. Sends the Map tab to it and
    /// keeps it highlighted until another is chosen.
    var focusedPlaceID: String?
    /// A person the app should centre the map on, set from their detail screen.
    var focusedPairingID: UUID?
    var lastAcceptedName: String?

    let location = LocationService()
    // Lazy so the debug-only screenshot mode can run without constructing a
    // CloudKit container in an unsigned Simulator build.
    @ObservationIgnored private lazy var cloud = CloudKitService.shared
    private var cancellables = Set<AnyCancellable>()
    private var syncTask: Task<Void, Never>?

    init() {
        #if DEBUG
        isScreenshotDemo = ProcessInfo.processInfo.arguments.contains("-ui-screenshot-demo")
        #else
        isScreenshotDemo = false
        #endif

        loadLocal()
        if isScreenshotDemo { loadScreenshotDemo() }
        observeLocationFixes()
    }

    // MARK: - Consent

    /// True only when this person has agreed to the *current* terms.
    var hasCurrentConsent: Bool { consentVersion == Consent.currentVersion }

    func recordConsent() {
        consentVersion = Consent.currentVersion
        consentedAt = Date()
        saveLocal()
    }

    /// Withdrawal has to be as easy as agreeing, and it has to actually stop the
    /// processing — so it tears down every share and deletes the location other
    /// people could read, not just a flag.
    func withdrawConsent() async {
        await deleteAllData()
        consentVersion = nil
        consentedAt = nil
        saveLocal()
    }

    // MARK: - Derived

    /// Everyone whose zone I own — i.e. everyone I could be publishing to.
    var outgoingPairingIDs: [UUID] {
        connections.filter { $0.outgoingZoneID != nil }.map(\.pairingID)
    }

    var connectedPeople: [Connection] {
        connections.filter { $0.incomingZoneID != nil }
    }

    var pendingInvites: [Connection] {
        connections.filter { $0.incomingZoneID == nil }
    }

    /// Powers the Privacy tab's headline answer.
    var peopleWhoCanSeeMe: [Connection] {
        connections.filter { $0.outgoingZoneID != nil && !pausedPairingIDs.contains($0.pairingID) }
    }

    /// The global switch AND the per-person switch both have to allow it.
    var effectivelySharing: Bool {
        guard case .on = sharingStatus else {
            if case .pausedUntil(let until) = sharingStatus, until < Date() {
                return true    // pause has expired
            }
            return false
        }
        return true
    }

    func isSharing(with pairingID: UUID) -> Bool {
        effectivelySharing && !pausedPairingIDs.contains(pairingID)
    }

    func connection(for pairingID: UUID) -> Connection? {
        connections.first { $0.pairingID == pairingID }
    }

    // MARK: - Lifecycle

    func bootstrap() async {
        if isScreenshotDemo {
            accountStatus = .available
            return
        }

        // An expired pause quietly turns sharing back on.
        if case .pausedUntil(let until) = sharingStatus, until < Date() {
            sharingStatus = .on
            saveLocal()
        }

        do {
            accountStatus = try await cloud.accountStatus()
        } catch {
            accountStatus = .couldNotDetermine
        }
        // A missing iCloud account isn't an error to interrupt someone with —
        // it's a standing condition they have to leave the app to fix. The Map
        // and People screens carry a persistent inline notice instead; the modal
        // is reserved for operations that actually failed mid-action.
        guard accountStatus == .available else { return }

        await NotificationService.shared.refreshAuthorizationStatus()
        await cloud.ensureSubscriptions()

        // No consent, no processing — not even a local fix.
        if hasCurrentConsent, location.hasAnyPermission { location.start() }
        await sync()
    }

    /// Full refresh: connections, places, rules — then re-evaluate arrival alerts.
    func sync() async {
        if isScreenshotDemo { return }
        guard accountStatus == .available else { return }
        syncTask?.cancel()
        isSyncing = true
        defer { isSyncing = false }

        do {
            var fresh = try await cloud.loadConnections()

            // Fold in the purely local bits.
            for i in fresh.indices {
                let id = fresh[i].pairingID
                fresh[i].isSharingWithThem = isSharing(with: id)
                fresh[i].nickname = nicknames[id]
            }

            // Tell me when an invitation I sent finally gets picked up.
            let previouslyPending = Set(pendingInvites.map(\.pairingID))
            let nowConnected = fresh.filter { $0.incomingZoneID != nil }.map(\.pairingID)
            for id in nowConnected where previouslyPending.contains(id) {
                if let name = fresh.first(where: { $0.pairingID == id })?.displayName {
                    NotificationService.shared.postConnectionAccepted(name: name)
                }
            }

            connections = fresh
            places = (try? await cloud.loadPlaces()) ?? places
            NotificationService.shared.evaluate(rules: notifyRules,
                                                places: places,
                                                connections: connections)
        } catch {
            errorMessage = error.localizedDescription
            log.error("Sync failed: \(error.localizedDescription, privacy: .public)")
        }
    }

    // MARK: - Publishing my location

    private func observeLocationFixes() {
        location.fixes
            .sink { [weak self] fix in
                Task { @MainActor in await self?.publish(fix: fix) }
            }
            .store(in: &cancellables)
    }

    private func publish(fix: CLLocation) async {
        guard hasCurrentConsent, effectivelySharing else { return }
        let targets = outgoingPairingIDs
        guard !targets.isEmpty else { return }

        let presence = Presence(
            coordinate: fix.coordinate,
            horizontalAccuracy: fix.horizontalAccuracy,
            capturedAt: fix.timestamp,
            battery: location.batteryLevel,
            isSharing: true,
            deviceName: location.deviceName
        )
        await cloud.publish(presence: presence,
                            to: targets,
                            pausedPairingIDs: pausedPairingIDs)
    }

    /// Used when a switch is flipped: pushes the new state out immediately rather
    /// than leaving a stale pin visible until the next fix.
    func republishNow() async {
        if let fix = location.lastFix {
            await publish(fix: fix)
        }
        if !effectivelySharing {
            // Blank everyone out.
            let blank = Presence(coordinate: .init(latitude: 0, longitude: 0),
                                 horizontalAccuracy: -1,
                                 capturedAt: Date(),
                                 battery: nil,
                                 isSharing: false,
                                 deviceName: nil)
            await cloud.publish(presence: blank,
                                to: outgoingPairingIDs,
                                pausedPairingIDs: Set(outgoingPairingIDs))
        }
    }

    // MARK: - Inviting

    func createInvitation() async -> CKShare? {
        do {
            let (share, pairingID) = try await cloud.createInvitation(myProfile: myProfile)
            connections.append(Connection(pairingID: pairingID,
                                          outgoingZoneID: CKRecordZoneIDBox(
                                              zoneName: Schema.connectionZoneName(pairingID: pairingID),
                                              ownerName: CKCurrentUserDefaultName)))
            return share
        } catch {
            errorMessage = error.localizedDescription
            return nil
        }
    }

    func accept(_ metadata: CKShare.Metadata) async {
        do {
            let pairingID = try await cloud.acceptInvitation(metadata, myProfile: myProfile)
            pendingInvitation = nil
            await sync()
            lastAcceptedName = connection(for: pairingID)?.displayName
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func remove(_ connection: Connection) async {
        do {
            try await cloud.removeConnection(connection)
            connections.removeAll { $0.pairingID == connection.pairingID }
            notifyRules.removeAll { $0.pairingID == connection.pairingID }
            nicknames[connection.pairingID] = nil
            pausedPairingIDs.remove(connection.pairingID)
            saveLocal()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    // MARK: - Controls

    func setSharing(_ status: SharingStatus) {
        sharingStatus = status
        saveLocal()
        Task { await republishNow() }
    }

    func setSharing(_ on: Bool, with pairingID: UUID) {
        if on { pausedPairingIDs.remove(pairingID) } else { pausedPairingIDs.insert(pairingID) }
        if let i = connections.firstIndex(where: { $0.pairingID == pairingID }) {
            connections[i].isSharingWithThem = on
        }
        saveLocal()
        Task { await republishNow() }
    }

    func updateProfile(_ profile: PersonProfile) {
        myProfile = profile
        saveLocal()
        Task { await cloud.publishProfile(profile, to: outgoingPairingIDs) }
    }

    func setNickname(_ name: String?, for pairingID: UUID) {
        let trimmed = name?.trimmingCharacters(in: .whitespaces)
        nicknames[pairingID] = (trimmed?.isEmpty ?? true) ? nil : trimmed
        if let i = connections.firstIndex(where: { $0.pairingID == pairingID }) {
            connections[i].nickname = nicknames[pairingID]
        }
        saveLocal()
    }

    // MARK: - Places & rules

    func addPlace(name: String, symbol: String, coordinate: CLLocationCoordinate2D, radius: Double) async {
        let place = Place(id: UUID().uuidString, name: name, symbol: symbol,
                          coordinate: coordinate, radius: radius, createdAt: Date())
        do {
            _ = try await cloud.save(place: place)
            places.append(place)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func deletePlace(_ place: Place) async {
        await cloud.delete(placeID: place.id)
        places.removeAll { $0.id == place.id }
        notifyRules.removeAll { $0.placeID == place.id }
        saveLocal()
    }

    func setRule(pairingID: UUID, placeID: String, trigger: NotifyTrigger, enabled: Bool) {
        if let i = notifyRules.firstIndex(where: {
            $0.pairingID == pairingID && $0.placeID == placeID && $0.trigger == trigger
        }) {
            notifyRules[i].enabled = enabled
        } else if enabled {
            notifyRules.append(NotifyRule(id: UUID().uuidString, pairingID: pairingID,
                                          placeID: placeID, trigger: trigger, enabled: true))
        }
        saveLocal()
    }

    func rules(for pairingID: UUID) -> [NotifyRule] {
        notifyRules.filter { $0.pairingID == pairingID && $0.enabled }
    }

    // MARK: - Erase

    /// "Delete All App Data" in Settings. Removes every zone I own, which is the
    /// only copy of my location anyone else has.
    func deleteAllData() async {
        for connection in connections {
            try? await cloud.removeConnection(connection)
        }
        for place in places {
            await cloud.delete(placeID: place.id)
        }
        connections = []
        places = []
        notifyRules = []
        nicknames = [:]
        pausedPairingIDs = []
        myProfile = .blank()
        hasCompletedOnboarding = false
        location.stop()
        saveLocal()
    }
}

// MARK: - App Store screenshot data

private extension AppState {
    func loadScreenshotDemo() {
        let now = Date()
        let mine = UUID(uuidString: "02892D9E-F609-40AD-8327-FF00CA530008")!
        let maya = UUID(uuidString: "1BC7FB2C-5E36-41A2-B0B3-27C87E8C38A1")!
        let alex = UUID(uuidString: "31239A96-62A6-4C57-974D-36D07CC4A82B")!
        let sofia = UUID(uuidString: "4C2CAB08-F5A6-4074-B403-EBD97E5B1B92")!

        myProfile = PersonProfile(pairingID: mine, displayName: "Oana",
                                  pinColorHex: Theme.pinChoices[0].hexString,
                                  emoji: nil, avatarData: nil, updatedAt: now)
        hasCompletedOnboarding = true
        // The demo has to clear the consent gate too, or it lands on the
        // agreement screen instead of the app it is meant to photograph.
        consentVersion = Consent.currentVersion
        consentedAt = now
        sharingStatus = .on
        pausedPairingIDs = []
        nicknames = [:]

        func zone(_ id: UUID, owner: String) -> CKRecordZoneIDBox {
            CKRecordZoneIDBox(zoneName: Schema.connectionZoneName(pairingID: id),
                              ownerName: owner)
        }
        func portrait(_ name: String) -> Data? {
            UIImage(named: name)?.jpegData(compressionQuality: 0.9)
        }
        func profile(_ id: UUID, _ name: String, _ color: Color, _ image: String) -> PersonProfile {
            PersonProfile(pairingID: id, displayName: name, pinColorHex: color.hexString,
                          emoji: nil, avatarData: portrait(image), updatedAt: now)
        }
        func presence(_ latitude: Double, _ longitude: Double,
                      minutesAgo: Double, battery: Double) -> Presence {
            Presence(coordinate: .init(latitude: latitude, longitude: longitude),
                     horizontalAccuracy: 8,
                     capturedAt: now.addingTimeInterval(-minutesAgo * 60),
                     battery: battery, isSharing: true, deviceName: "iPhone")
        }

        connections = [
            Connection(pairingID: maya, outgoingZoneID: zone(maya, owner: CKCurrentUserDefaultName),
                       incomingZoneID: zone(maya, owner: "maya-demo"),
                       profile: profile(maya, "Maya", Theme.pinChoices[2], "DemoMaya"),
                       presence: presence(44.4408, 26.0977, minutesAgo: 1, battery: 0.86)),
            Connection(pairingID: alex, outgoingZoneID: zone(alex, owner: CKCurrentUserDefaultName),
                       incomingZoneID: zone(alex, owner: "alex-demo"),
                       profile: profile(alex, "Alex", Theme.pinChoices[4], "DemoAlex"),
                       presence: presence(44.4357, 26.1024, minutesAgo: 4, battery: 0.64)),
            Connection(pairingID: sofia, outgoingZoneID: zone(sofia, owner: CKCurrentUserDefaultName),
                       incomingZoneID: zone(sofia, owner: "sofia-demo"),
                       profile: profile(sofia, "Sofia", Theme.pinChoices[1], "DemoSofia"),
                       presence: presence(44.4328, 26.0942, minutesAgo: 8, battery: 0.73))
        ]

        places = [
            Place(id: "demo-home", name: "Home", symbol: "house.fill",
                  coordinate: .init(latitude: 44.4368, longitude: 26.0982),
                  radius: 180, createdAt: now),
            Place(id: "demo-work", name: "Work", symbol: "briefcase.fill",
                  coordinate: .init(latitude: 44.4401, longitude: 26.1018),
                  radius: 250, createdAt: now)
        ]
        notifyRules = [
            NotifyRule(id: "demo-rule", pairingID: maya, placeID: "demo-home",
                       trigger: .arrives, enabled: true)
        ]
    }
}

// MARK: - Local persistence

private enum Key {
    static let profile   = "myProfile"
    static let onboarded = "hasCompletedOnboarding"
    static let sharing   = "sharingStatus"
    static let pauseUntil = "sharingPausedUntil"
    static let paused    = "pausedPairingIDs"
    static let nicknames = "nicknames"
    static let rules     = "notifyRules"
    static let consentVersion = "consentVersion"
    static let consentedAt    = "consentedAt"
}

extension AppState {

    func saveLocal() {
        let d = UserDefaults.standard
        d.set(hasCompletedOnboarding, forKey: Key.onboarded)
        d.set(consentVersion, forKey: Key.consentVersion)
        d.set(consentedAt, forKey: Key.consentedAt)
        d.set(myProfile.displayName, forKey: Key.profile + ".name")
        d.set(myProfile.pinColorHex, forKey: Key.profile + ".color")
        d.set(myProfile.emoji, forKey: Key.profile + ".emoji")
        d.set(myProfile.pairingID.uuidString, forKey: Key.profile + ".id")
        d.set(myProfile.avatarData, forKey: Key.profile + ".avatar")

        switch sharingStatus {
        case .on:
            d.set("on", forKey: Key.sharing); d.removeObject(forKey: Key.pauseUntil)
        case .off:
            d.set("off", forKey: Key.sharing); d.removeObject(forKey: Key.pauseUntil)
        case .pausedUntil(let until):
            d.set("paused", forKey: Key.sharing); d.set(until, forKey: Key.pauseUntil)
        }

        d.set(pausedPairingIDs.map(\.uuidString), forKey: Key.paused)
        d.set(nicknames.reduce(into: [String: String]()) { $0[$1.key.uuidString] = $1.value },
              forKey: Key.nicknames)
        d.set(notifyRules.map { ["id": $0.id, "pairing": $0.pairingID.uuidString,
                                 "place": $0.placeID, "trigger": $0.trigger.rawValue,
                                 "enabled": $0.enabled ? "1" : "0"] },
              forKey: Key.rules)
    }

    func loadLocal() {
        let d = UserDefaults.standard
        hasCompletedOnboarding = d.bool(forKey: Key.onboarded)
        consentVersion = d.string(forKey: Key.consentVersion)
        consentedAt = d.object(forKey: Key.consentedAt) as? Date

        let id = UUID(uuidString: d.string(forKey: Key.profile + ".id") ?? "") ?? UUID()
        myProfile = PersonProfile(
            pairingID: id,
            displayName: d.string(forKey: Key.profile + ".name") ?? "",
            pinColorHex: d.string(forKey: Key.profile + ".color") ?? Theme.pinChoices[0].hexString,
            emoji: d.string(forKey: Key.profile + ".emoji"),
            avatarData: d.data(forKey: Key.profile + ".avatar"),
            updatedAt: Date()
        )

        switch d.string(forKey: Key.sharing) {
        case "off": sharingStatus = .off
        case "paused":
            if let until = d.object(forKey: Key.pauseUntil) as? Date, until > Date() {
                sharingStatus = .pausedUntil(until)
            } else {
                sharingStatus = .on
            }
        default: sharingStatus = .on
        }

        pausedPairingIDs = Set((d.stringArray(forKey: Key.paused) ?? []).compactMap(UUID.init))
        nicknames = (d.dictionary(forKey: Key.nicknames) as? [String: String] ?? [:])
            .reduce(into: [UUID: String]()) { acc, pair in
                if let u = UUID(uuidString: pair.key) { acc[u] = pair.value }
            }
        notifyRules = (d.array(forKey: Key.rules) as? [[String: String]] ?? []).compactMap { dict in
            guard let id = dict["id"],
                  let pairing = dict["pairing"].flatMap(UUID.init),
                  let place = dict["place"],
                  let trigger = dict["trigger"].flatMap(NotifyTrigger.init) else { return nil }
            return NotifyRule(id: id, pairingID: pairing, placeID: place,
                              trigger: trigger, enabled: dict["enabled"] == "1")
        }
    }
}
