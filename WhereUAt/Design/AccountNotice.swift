import SwiftUI
import CloudKit

/// Shown on Map and People when there's no usable iCloud account. Where U At has
/// no account of its own, so this is the one external dependency worth naming
/// plainly rather than hiding behind a generic error.
struct AccountNotice: View {
    @Environment(AppState.self) private var state

    var body: some View {
        if state.accountStatus != .available {
            HStack(spacing: 12) {
                Image(systemName: "icloud.slash.fill")
                    .font(.system(size: 20, weight: .medium))
                    .foregroundStyle(Theme.caution)

                VStack(alignment: .leading, spacing: 3) {
                    Text("Sign in to iCloud")
                        .font(.system(size: 14.5, weight: .semibold))
                        .foregroundStyle(Theme.ink)
                    Text("Where U At uses your iCloud account to connect you with people. There's no separate account to create.")
                        .font(.system(size: 12.5))
                        .foregroundStyle(Theme.inkMuted)
                        .fixedSize(horizontal: false, vertical: true)
                }

                Spacer(minLength: 0)

                Button("Open") { OpenSettings.app() }
                    .font(.system(size: 14, weight: .semibold))
                    .buttonStyle(.borderless)
            }
            .padding(13)
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .strokeBorder(Theme.caution.opacity(0.35), lineWidth: 1)
            }
            .shadow(color: Theme.ink.opacity(0.1), radius: 12, y: 4)
        }
    }
}
