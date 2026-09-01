import SwiftUI

/// Tapping your own bubble on the map. Big status, quick pauses, and the
/// per-person list so you never have to disappear from everyone just to hide
/// from one person.
struct MySharingSheet: View {
    @Environment(AppState.self) private var state
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ZStack {
                Theme.ground.ignoresSafeArea()

                ScrollView {
                    VStack(spacing: 18) {
                        statusCard
                        if state.effectivelySharing { pauseOptions } else { resumeButton }
                        perPersonList
                    }
                    .padding(.horizontal, 20)
                    .padding(.vertical, 16)
                }
            }
            .navigationTitle("My Location")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) { Button("Done") { dismiss() } }
            }
        }
        .presentationDetents([.medium, .large])
    }

    private var statusCard: some View {
        GlassCard(padding: 20) {
            VStack(spacing: 10) {
                Avatar(profile: state.myProfile, size: 72)
                HStack(spacing: 8) {
                    Circle()
                        .fill(state.effectivelySharing ? Theme.affirmative : Theme.paused)
                        .frame(width: 11, height: 11)
                    Text(state.effectivelySharing ? "Sharing Location" : state.sharingStatus.label)
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundStyle(Theme.ink)
                }
                Text(state.effectivelySharing
                     ? "\(state.peopleWhoCanSeeMe.count) \(state.peopleWhoCanSeeMe.count == 1 ? "person" : "people") can see where you are."
                     : "Nobody can see where you are.")
                    .font(.system(size: 13.5))
                    .foregroundStyle(Theme.inkMuted)
            }
            .frame(maxWidth: .infinity)
        }
    }

    private var pauseOptions: some View {
        VStack(spacing: 8) {
            SectionHeader(title: "Pause for")
            pauseRow("1 hour")        { .pausedUntil(Date().addingTimeInterval(3600)) }
            pauseRow("Until tonight") { .pausedUntil(Calendar.current.date(bySettingHour: 20, minute: 0, second: 0, of: Date()) ?? Date().addingTimeInterval(3600 * 6)) }
            pauseRow("Until tomorrow"){ .pausedUntil(Calendar.current.startOfDay(for: Date().addingTimeInterval(86_400))) }
            pauseRow("Until I turn it back on") { .off }
        }
    }

    private func pauseRow(_ title: String, status: @escaping () -> SharingStatus) -> some View {
        Button {
            state.setSharing(status())
        } label: {
            HStack {
                Text(title).font(.system(size: 15.5, weight: .medium)).foregroundStyle(Theme.ink)
                Spacer()
                Image(systemName: "pause.circle").foregroundStyle(Theme.inkMuted)
            }
            .padding(14)
            .background(.white.opacity(0.78), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        }
        .buttonStyle(.plain)
    }

    private var resumeButton: some View {
        Button("Resume Sharing") { state.setSharing(.on) }
            .buttonStyle(BrandButtonStyle(
                tint: LinearGradient(colors: [Theme.affirmative, Theme.affirmative.opacity(0.85)],
                                     startPoint: .top, endPoint: .bottom)
            ))
    }

    private var perPersonList: some View {
        VStack(spacing: 8) {
            SectionHeader(title: "Sharing with \(state.outgoingPairingIDs.count) people")

            ForEach(state.connections.filter { $0.outgoingZoneID != nil }) { connection in
                HStack(spacing: 12) {
                    Avatar(profile: connection.profile, size: 38)
                    Text(connection.displayName)
                        .font(.system(size: 15, weight: .medium))
                        .foregroundStyle(Theme.ink)
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
                .opacity(state.effectivelySharing ? 1 : 0.5)
            }
        }
    }
}
