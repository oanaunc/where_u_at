import SwiftUI
import CloudKit

/// What the invitee sees when they open a link. Deliberately blunt about what
/// accepting means, and the decline path is just as easy to reach as accept.
struct InvitationScreen: View {
    @Environment(AppState.self) private var state
    @Environment(\.dismiss) private var dismiss

    let metadata: CKShare.Metadata

    @State private var isAccepting = false
    @State private var accepted = false

    private var inviterName: String {
        if let title = metadata.share[CKShare.SystemFieldKey.title] as? String,
           let name = title.components(separatedBy: " on Where U At").first,
           !name.isEmpty {
            return name
        }
        let components = metadata.ownerIdentity.nameComponents
        if let components {
            let formatted = PersonNameComponentsFormatter.localizedString(from: components, style: .default)
            if !formatted.isEmpty { return formatted }
        }
        return "Someone"
    }

    var body: some View {
        ZStack {
            Theme.ground.ignoresSafeArea()

            Group {
                if accepted {
                    successView
                } else {
                    invitationView
                }
            }
            .readableColumn()
        }
        .interactiveDismissDisabled(isAccepting)
        .animation(.smooth, value: accepted)
    }

    // MARK: Ask

    private var invitationView: some View {
        VStack(spacing: 0) {
            Spacer(minLength: 30)

            ZStack {
                Circle().fill(Theme.brandSoft).frame(width: 150, height: 150).blur(radius: 12)
                Image(systemName: "person.crop.circle.badge.plus")
                    .font(.system(size: 62))
                    .foregroundStyle(Theme.brand)
            }

            Text("\(inviterName)\nwants to connect")
                .font(.system(size: 26, weight: .bold, design: .rounded))
                .multilineTextAlignment(.center)
                .foregroundStyle(Theme.ink)
                .padding(.top, 24)

            Text("If you accept, \(inviterName) can see your location and you can see \(inviterName)'s.")
                .font(.system(size: 15))
                .foregroundStyle(Theme.inkMuted)
                .multilineTextAlignment(.center)
                .padding(.top, 12)
                .padding(.horizontal, 34)
                .fixedSize(horizontal: false, vertical: true)

            Text("You'll share location only after you accept. You can pause or stop at any time.")
                .font(.system(size: 13))
                .foregroundStyle(Theme.inkMuted.opacity(0.85))
                .multilineTextAlignment(.center)
                .padding(.top, 14)
                .padding(.horizontal, 34)
                .fixedSize(horizontal: false, vertical: true)

            Spacer()

            VStack(spacing: 12) {
                Button {
                    accept()
                } label: {
                    if isAccepting {
                        ProgressView().tint(.white)
                    } else {
                        Label("Accept & Share Location", systemImage: "checkmark")
                    }
                }
                .buttonStyle(BrandButtonStyle(
                    tint: LinearGradient(colors: [Theme.affirmative, Theme.affirmative.opacity(0.85)],
                                         startPoint: .top, endPoint: .bottom)
                ))
                .disabled(isAccepting)

                Button("Decline") { dismiss() }
                    .buttonStyle(QuietButtonStyle())
                    .disabled(isAccepting)
            }
            .padding(.horizontal, 24)
            .padding(.bottom, 36)
        }
    }

    // MARK: Confirm

    private var successView: some View {
        VStack(spacing: 0) {
            Spacer()

            Text("🎉").font(.system(size: 62))

            Text("You're connected")
                .font(.system(size: 27, weight: .bold, design: .rounded))
                .foregroundStyle(Theme.ink)
                .padding(.top, 14)

            Text("You and \(state.lastAcceptedName ?? inviterName) can now see each other.")
                .font(.system(size: 15))
                .foregroundStyle(Theme.inkMuted)
                .multilineTextAlignment(.center)
                .padding(.top, 8)
                .padding(.horizontal, 34)

            Spacer()

            Button("View on Map") { dismiss() }
                .buttonStyle(BrandButtonStyle())
                .padding(.horizontal, 24)
                .padding(.bottom, 40)
        }
    }

    private func accept() {
        isAccepting = true
        Task {
            await state.accept(metadata)
            isAccepting = false
            if state.errorMessage == nil {
                accepted = true
                // Sharing only starts once location permission actually exists.
                if !state.location.hasAnyPermission { state.location.requestWhenInUse() }
            } else {
                dismiss()
            }
        }
    }
}
