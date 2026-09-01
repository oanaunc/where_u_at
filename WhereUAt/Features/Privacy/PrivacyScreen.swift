import SwiftUI

/// Answers "who can see where I am right now?" in the first screenful. This is
/// deliberately a top-level tab rather than something buried in Settings.
struct PrivacyScreen: View {
    @Environment(AppState.self) private var state

    var body: some View {
        NavigationStack {
            ZStack {
                Theme.ground.ignoresSafeArea()

                ScrollView {
                    VStack(spacing: 18) {
                        headline
                        whoCanSeeMe
                        controls
                        Spacer(minLength: 20)
                    }
                    .padding(.horizontal, 20)
                    .padding(.vertical, 14)
                }
            }
            .navigationTitle("Privacy")
        }
    }

    private var headline: some View {
        GlassCard(padding: 18) {
            HStack(spacing: 14) {
                ZStack {
                    Circle()
                        .fill(state.effectivelySharing ? AnyShapeStyle(Theme.brandSoft)
                                                       : AnyShapeStyle(Color.gray.opacity(0.18)))
                        .frame(width: 52, height: 52)
                    Image(systemName: state.effectivelySharing ? "eye.fill" : "eye.slash.fill")
                        .font(.system(size: 20, weight: .semibold))
                        .foregroundStyle(state.effectivelySharing ? Theme.sky : Theme.paused)
                }
                VStack(alignment: .leading, spacing: 4) {
                    Text(countLine)
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(Theme.ink)
                    Text("You choose who sees you, and for how long.")
                        .font(.system(size: 13))
                        .foregroundStyle(Theme.inkMuted)
                }
                Spacer(minLength: 0)
            }
        }
    }

    private var countLine: String {
        guard state.effectivelySharing else { return "Nobody can see you right now" }
        let n = state.peopleWhoCanSeeMe.count
        switch n {
        case 0:  return "Nobody can see you yet"
        case 1:  return "1 person can see your location"
        default: return "\(n) people can see your location"
        }
    }

    private var whoCanSeeMe: some View {
        VStack(spacing: 8) {
            SectionHeader(title: "Who can see me")

            if state.connections.filter({ $0.outgoingZoneID != nil }).isEmpty {
                Text("You haven't shared with anyone yet.")
                    .font(.system(size: 14))
                    .foregroundStyle(Theme.inkMuted)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(14)
                    .background(.white.opacity(0.7), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            }

            ForEach(state.connections.filter { $0.outgoingZoneID != nil }) { connection in
                HStack(spacing: 12) {
                    Avatar(profile: connection.profile, size: 40)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(connection.displayName)
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundStyle(Theme.ink)
                        Text(visibilityLine(connection))
                            .font(.system(size: 12.5))
                            .foregroundStyle(state.isSharing(with: connection.pairingID)
                                             ? Theme.affirmative : Theme.inkMuted)
                    }
                    Spacer()
                    Toggle("", isOn: Binding(
                        get: { state.isSharing(with: connection.pairingID) },
                        set: { state.setSharing($0, with: connection.pairingID) }
                    ))
                    .labelsHidden()
                    .tint(Theme.affirmative)
                    .disabled(!state.effectivelySharing)
                }
                .padding(12)
                .background(.white.opacity(0.78), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            }
        }
    }

    private func visibilityLine(_ connection: Connection) -> String {
        if !state.effectivelySharing { return "Paused — nobody can see you" }
        return state.isSharing(with: connection.pairingID)
            ? "Can see your location"
            : "Paused for this person"
    }

    private var controls: some View {
        VStack(spacing: 8) {
            SectionHeader(title: "Location sharing")

            GlassCard(padding: 0) {
                VStack(spacing: 0) {
                    Toggle(isOn: Binding(
                        get: { state.effectivelySharing },
                        set: { state.setSharing($0 ? .on : .off) }
                    )) {
                        Text("Share My Location").font(.system(size: 15.5, weight: .medium))
                    }
                    .tint(Theme.affirmative)
                    .padding(14)

                    Divider().overlay(Theme.hairline)

                    HStack {
                        Text("Precise Location").font(.system(size: 15.5, weight: .medium))
                        Spacer()
                        Text(state.location.isPreciseLocation ? "On" : "Off")
                            .font(.system(size: 15))
                            .foregroundStyle(Theme.inkMuted)
                    }
                    .padding(14)

                    Divider().overlay(Theme.hairline)

                    HStack {
                        Text("Background Location").font(.system(size: 15.5, weight: .medium))
                        Spacer()
                        Text(state.location.hasBackgroundPermission ? "Always" : "While Using")
                            .font(.system(size: 15))
                            .foregroundStyle(state.location.hasBackgroundPermission
                                             ? Theme.inkMuted : Theme.caution)
                    }
                    .padding(14)
                }
            }

            if !state.location.hasBackgroundPermission {
                Text("Without Always, people see where you were the last time you opened the app — not where you are now.")
                    .font(.system(size: 12.5))
                    .foregroundStyle(Theme.inkMuted)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 4)

                Button("Open Settings") { OpenSettings.app() }
                    .buttonStyle(QuietButtonStyle())
            }
        }
    }
}

enum OpenSettings {
    static func app() {
        guard let url = URL(string: UIApplication.openSettingsURLString) else { return }
        UIApplication.shared.open(url)
    }
}
