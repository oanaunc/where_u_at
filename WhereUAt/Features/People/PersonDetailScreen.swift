import SwiftUI
import MapKit
import CoreLocation

/// One person: where they are, when we last heard, and the controls that matter.
struct PersonDetailScreen: View {
    @Environment(AppState.self) private var state
    @Environment(\.dismiss) private var dismiss

    let pairingID: UUID

    @State private var confirmingRemove = false
    @State private var showNotifySheet = false
    @State private var editingNickname = false
    @State private var nicknameDraft = ""

    private var connection: Connection? { state.connection(for: pairingID) }

    var body: some View {
        ScrollView {
            if let connection {
                VStack(spacing: 20) {
                    header(connection)
                    if let presence = connection.presence, presence.isSharing {
                        mapPreview(presence)
                        actions(connection)
                        meta(presence)
                    } else {
                        pausedNotice(connection)
                    }
                    sharingBack(connection)
                    dangerZone(connection)
                }
                .padding(.horizontal, 20)
                .padding(.vertical, 16)
            } else {
                EmptyStateView(symbol: "person.slash",
                               title: "Connection removed",
                               message: "This person is no longer connected with you.")
                    .padding(.top, 60)
            }
        }
        .background(Theme.ground.ignoresSafeArea())
        .navigationBarTitleDisplayMode(.inline)
        .sheet(isPresented: $showNotifySheet) {
            if let connection { NotifyMeSheet(connection: connection) }
        }
    }

    // MARK: Pieces

    private func header(_ connection: Connection) -> some View {
        VStack(spacing: 10) {
            Avatar(profile: connection.profile, size: 104)

            Text(connection.displayName)
                .font(.system(size: 24, weight: .bold, design: .rounded))
                .foregroundStyle(Theme.ink)

            if let presence = connection.presence, presence.isSharing {
                Text(subtitle(presence))
                    .font(.system(size: 14))
                    .foregroundStyle(Theme.inkMuted)
            }

            Button {
                nicknameDraft = connection.nickname ?? ""
                editingNickname = true
            } label: {
                Label(connection.nickname == nil ? "Add a nickname" : "Edit nickname",
                      systemImage: "pencil")
                    .font(.system(size: 13, weight: .medium))
            }
            .buttonStyle(.plain)
            .foregroundStyle(Theme.sky)
            .alert("Nickname", isPresented: $editingNickname) {
                TextField("Nickname", text: $nicknameDraft)
                Button("Save") { state.setNickname(nicknameDraft, for: pairingID) }
                Button("Remove", role: .destructive) { state.setNickname(nil, for: pairingID) }
                Button("Cancel", role: .cancel) { }
            } message: {
                Text("Only you see this name.")
            }
        }
        .padding(.top, 8)
    }

    private func subtitle(_ presence: Presence) -> String {
        var parts = [RelativeTime.string(for: presence.capturedAt)]
        if let mine = state.location.lastFix {
            parts.append(DistanceText.string(metres: presence.location.distance(from: mine)))
        }
        return parts.joined(separator: " · ")
    }

    private func mapPreview(_ presence: Presence) -> some View {
        // The Map must not take the tap itself, so hit testing is disabled on it
        // and the Button wrapping it receives the gesture instead.
        Button(action: showOnMap) {
            Map(initialPosition: .region(MKCoordinateRegion(
                center: presence.coordinate,
                span: MKCoordinateSpan(latitudeDelta: 0.005, longitudeDelta: 0.005)
            ))) {
                Annotation("", coordinate: presence.coordinate, anchor: .bottom) {
                    PersonMarker(profile: connection?.profile, isStale: presence.isStale)
                }
            }
            .mapStyle(.standard(elevation: .flat))
            .frame(height: 190)
            .allowsHitTesting(false)
            .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 20, style: .continuous)
                    .strokeBorder(.white.opacity(0.7), lineWidth: 1)
            }
            .overlay(alignment: .bottomTrailing) {
                Label("Show on Map", systemImage: "arrow.up.left.and.arrow.down.right")
                    .font(.system(size: 12.5, weight: .semibold))
                    .foregroundStyle(Theme.sky)
                    .padding(.horizontal, 11)
                    .padding(.vertical, 7)
                    .background(.regularMaterial, in: Capsule())
                    .padding(10)
            }
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Show \(connection?.displayName ?? "them") on the map")
    }

    /// Hands the Map tab a target and gets out of the way — works whether this
    /// screen was pushed from People or presented as a sheet from the map.
    private func showOnMap() {
        dismiss()
        state.focusedPairingID = pairingID
    }

    private func actions(_ connection: Connection) -> some View {
        HStack(spacing: 10) {
            actionButton("arrow.triangle.turn.up.right.diamond.fill", "Directions") {
                openDirections(connection)
            }
            actionButton("bell.fill", "Notify Me") { showNotifySheet = true }
            actionButton("nosign", "Stop Sharing", tint: Theme.caution) {
                state.setSharing(false, with: pairingID)
            }
        }
    }

    private func actionButton(_ symbol: String, _ title: String,
                              tint: Color = Theme.sky,
                              action: @escaping () -> Void) -> some View {
        Button(action: action) {
            VStack(spacing: 7) {
                Image(systemName: symbol)
                    .font(.system(size: 18, weight: .semibold))
                Text(title)
                    .font(.system(size: 12, weight: .medium))
            }
            .foregroundStyle(tint)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 14)
            .background(.white.opacity(0.75), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .strokeBorder(Theme.hairline, lineWidth: 1)
            }
        }
        .buttonStyle(.plain)
    }

    private func meta(_ presence: Presence) -> some View {
        GlassCard {
            HStack {
                VStack(alignment: .leading, spacing: 3) {
                    Text("Last updated").font(.system(size: 12)).foregroundStyle(Theme.inkMuted)
                    Text(RelativeTime.string(for: presence.capturedAt))
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(Theme.ink)
                }
                Spacer()
                if let battery = presence.battery {
                    VStack(alignment: .trailing, spacing: 3) {
                        Text("Battery").font(.system(size: 12)).foregroundStyle(Theme.inkMuted)
                        Label("\(Int(battery * 100))%", systemImage: batterySymbol(battery))
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundStyle(battery < 0.2 ? Theme.caution : Theme.ink)
                    }
                }
            }
        }
    }

    private func batterySymbol(_ level: Double) -> String {
        switch level {
        case ..<0.15: return "battery.0percent"
        case ..<0.45: return "battery.25percent"
        case ..<0.8:  return "battery.75percent"
        default:      return "battery.100percent"
        }
    }

    private func pausedNotice(_ connection: Connection) -> some View {
        GlassCard {
            HStack(spacing: 12) {
                Image(systemName: "pause.circle.fill")
                    .font(.system(size: 26))
                    .foregroundStyle(Theme.paused)
                VStack(alignment: .leading, spacing: 3) {
                    Text(connection.state == .invited ? "Not connected yet" : "Location paused")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(Theme.ink)
                    Text(connection.state == .invited
                         ? "They haven't accepted your invitation yet."
                         : "\(connection.displayName) has paused sharing. You'll see them again when they turn it back on.")
                        .font(.system(size: 13))
                        .foregroundStyle(Theme.inkMuted)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 0)
            }
        }
    }

    /// The reciprocal half — what *they* can see of me.
    private func sharingBack(_ connection: Connection) -> some View {
        GlassCard {
            Toggle(isOn: Binding(
                get: { state.isSharing(with: pairingID) },
                set: { state.setSharing($0, with: pairingID) }
            )) {
                VStack(alignment: .leading, spacing: 3) {
                    Text("Share my location with \(connection.displayName)")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(Theme.ink)
                    Text(state.isSharing(with: pairingID)
                         ? "They can see where you are."
                         : "They can't see you. Everyone else is unaffected.")
                        .font(.system(size: 13))
                        .foregroundStyle(Theme.inkMuted)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .tint(Theme.affirmative)
        }
    }

    private func dangerZone(_ connection: Connection) -> some View {
        Button(role: .destructive) {
            confirmingRemove = true
        } label: {
            Text("Remove Connection")
                .font(.system(size: 16, weight: .medium))
                .foregroundStyle(Theme.caution)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 15)
                .background(.white.opacity(0.7), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        }
        .buttonStyle(.plain)
        .confirmationDialog("Remove \(connection.displayName)?",
                            isPresented: $confirmingRemove, titleVisibility: .visible) {
            Button("Remove", role: .destructive) {
                Task { await state.remove(connection); dismiss() }
            }
            Button("Cancel", role: .cancel) { }
        } message: {
            Text("You'll stop seeing each other. To reconnect, one of you has to send a new invitation.")
        }
    }

    private func openDirections(_ connection: Connection) {
        guard let presence = connection.presence else { return }
        let item = MKMapItem(placemark: MKPlacemark(coordinate: presence.coordinate))
        item.name = connection.displayName
        item.openInMaps(launchOptions: [MKLaunchOptionsDirectionsModeKey: MKLaunchOptionsDirectionsModeDriving])
    }
}
