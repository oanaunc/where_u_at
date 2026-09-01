import SwiftUI
import CloudKit
import UIKit
import CoreImage.CIFilterBuiltins

/// "Who do you want to find?" — creates a fresh one-person share and hands it to
/// the system share sheet, or shows it as a QR code when the two of you are
/// standing next to each other.
struct InviteScreen: View {
    @Environment(AppState.self) private var state
    @Environment(\.dismiss) private var dismiss

    @State private var share: CKShare?
    @State private var isPreparing = false
    @State private var showSystemShare = false
    @State private var showQR = false

    var body: some View {
        NavigationStack {
            ZStack {
                Theme.ground.ignoresSafeArea()

                VStack(spacing: 0) {
                    illustration
                        .padding(.top, 20)

                    Text("Invite a Friend")
                        .font(.system(size: 26, weight: .bold, design: .rounded))
                        .foregroundStyle(Theme.ink)
                        .padding(.top, 22)

                    Text("Share your link or QR code.\nThey'll only see you after you both connect.")
                        .font(.system(size: 14.5))
                        .foregroundStyle(Theme.inkMuted)
                        .multilineTextAlignment(.center)
                        .padding(.top, 8)
                        .padding(.horizontal, 30)

                    VStack(spacing: 10) {
                        option("link", "Share Link", "Send an invite link") {
                            prepare { showSystemShare = true }
                        }
                        option("qrcode", "Show QR Code", "Let them scan to connect") {
                            prepare { showQR = true }
                        }
                    }
                    .padding(.horizontal, 20)
                    .padding(.top, 28)

                    Spacer()

                    Text("Sharing is mutual. When they accept, you'll each be able to see the other — and either of you can stop at any time.")
                        .font(.system(size: 12.5))
                        .foregroundStyle(Theme.inkMuted)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 32)
                        .padding(.bottom, 24)
                }
                .readableColumn()
                .disabled(isPreparing)
                .overlay {
                    if isPreparing {
                        ProgressView().controlSize(.large)
                    }
                }
            }
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button { dismiss() } label: { Image(systemName: "xmark") }
                        .tint(Theme.inkMuted)
                }
            }
        }
        .sheet(isPresented: $showSystemShare) {
            if let share {
                CloudSharingSheet(share: share, container: CK.container) {
                    Task { await state.sync() }
                }
                .ignoresSafeArea()
            }
        }
        .sheet(isPresented: $showQR) {
            if let url = share?.url {
                QRCodeSheet(url: url, name: state.myProfile.displayName)
            }
        }
    }

    private var illustration: some View {
        HStack(spacing: -14) {
            Avatar(profile: state.myProfile, size: 78)
            ZStack {
                Circle().fill(Theme.brand).frame(width: 38, height: 38)
                Image(systemName: "link")
                    .font(.system(size: 15, weight: .bold))
                    .foregroundStyle(.white)
            }
            .zIndex(1)
            .shadow(color: Theme.sky.opacity(0.4), radius: 10, y: 4)

            ZStack {
                Circle().fill(Theme.brandSoft).frame(width: 78, height: 78)
                Image(systemName: "person.fill.questionmark")
                    .font(.system(size: 28))
                    .foregroundStyle(Theme.sky)
            }
        }
    }

    private func option(_ symbol: String, _ title: String, _ subtitle: String,
                        action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 14) {
                ZStack {
                    RoundedRectangle(cornerRadius: 11, style: .continuous)
                        .fill(Theme.brandSoft)
                        .frame(width: 40, height: 40)
                    Image(systemName: symbol)
                        .font(.system(size: 17, weight: .semibold))
                        .foregroundStyle(Theme.sky)
                }
                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(Theme.ink)
                    Text(subtitle)
                        .font(.system(size: 13))
                        .foregroundStyle(Theme.inkMuted)
                }
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(Theme.inkMuted.opacity(0.6))
            }
            .padding(14)
            .background(.white.opacity(0.78), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .strokeBorder(Theme.hairline, lineWidth: 1)
            }
        }
        .buttonStyle(.plain)
    }

    /// Each invitation gets its own zone and its own share, so the same link is
    /// never reused for two different people.
    private func prepare(then present: @escaping () -> Void) {
        guard !isPreparing else { return }
        isPreparing = true
        Task {
            share = await state.createInvitation()
            isPreparing = false
            if share != nil { present() }
        }
    }
}

// MARK: - System share sheet

/// `UICloudSharingController` is the only supported way to hand out a CKShare URL.
struct CloudSharingSheet: UIViewControllerRepresentable {
    let share: CKShare
    let container: CKContainer
    var onDismiss: () -> Void

    func makeCoordinator() -> Coordinator { Coordinator(onDismiss: onDismiss) }

    func makeUIViewController(context: Context) -> UICloudSharingController {
        let controller = UICloudSharingController(share: share, container: container)
        controller.availablePermissions = [.allowReadOnly, .allowPrivate]
        controller.delegate = context.coordinator
        return controller
    }

    func updateUIViewController(_ controller: UICloudSharingController, context: Context) { }

    final class Coordinator: NSObject, UICloudSharingControllerDelegate {
        let onDismiss: () -> Void
        init(onDismiss: @escaping () -> Void) { self.onDismiss = onDismiss }

        func itemTitle(for controller: UICloudSharingController) -> String? {
            "Where U At"
        }

        func cloudSharingController(_ controller: UICloudSharingController,
                                    failedToSaveShareWithError error: Error) { }

        func cloudSharingControllerDidSaveShare(_ controller: UICloudSharingController) {
            onDismiss()
        }

        func cloudSharingControllerDidStopSharing(_ controller: UICloudSharingController) {
            onDismiss()
        }
    }
}

// MARK: - QR code

struct QRCodeSheet: View {
    @Environment(\.dismiss) private var dismiss
    let url: URL
    let name: String

    var body: some View {
        NavigationStack {
            ZStack {
                Theme.ground.ignoresSafeArea()

                VStack(spacing: 20) {
                    Text("\(name) wants to connect\non Where U At")
                        .font(.system(size: 19, weight: .semibold, design: .rounded))
                        .multilineTextAlignment(.center)
                        .foregroundStyle(Theme.ink)
                        .padding(.top, 20)

                    if let image = QRCode.image(from: url) {
                        Image(uiImage: image)
                            .interpolation(.none)
                            .resizable()
                            .scaledToFit()
                            .frame(width: 250, height: 250)
                            .padding(18)
                            .background(.white, in: RoundedRectangle(cornerRadius: 24, style: .continuous))
                            .shadow(color: Theme.ink.opacity(0.12), radius: 20, y: 8)
                    }

                    Text("Point their camera at this code.")
                        .font(.system(size: 14))
                        .foregroundStyle(Theme.inkMuted)

                    Spacer()
                }
                .padding(.horizontal, 24)
            }
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }
}

enum QRCode {
    static func image(from url: URL) -> UIImage? {
        let context = CIContext()
        let filter = CIFilter.qrCodeGenerator()
        filter.message = Data(url.absoluteString.utf8)
        filter.correctionLevel = "M"
        guard let output = filter.outputImage?.transformed(by: CGAffineTransform(scaleX: 10, y: 10)),
              let cg = context.createCGImage(output, from: output.extent) else { return nil }
        return UIImage(cgImage: cg)
    }
}
