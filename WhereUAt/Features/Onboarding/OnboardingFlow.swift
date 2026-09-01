import SwiftUI
import PhotosUI
import CoreLocation

/// Welcome → what it does → who you are → location. Nothing asks for an account,
/// because there isn't one: identity is the iCloud account already on the device.
struct OnboardingFlow: View {
    @Environment(AppState.self) private var state
    @State private var step: Step

    enum Step: Hashable { case welcome, explain, consent, profile, location }

    init() {
        // Someone who already onboarded but whose agreement predates a policy
        // change is asked again — and only for that, not the whole flow.
        _step = State(initialValue: .welcome)
    }

    var body: some View {
        ZStack {
            // The wash runs edge to edge; only the content is column-width.
            Theme.ground.ignoresSafeArea()

            Group {
                switch step {
                case .welcome:  WelcomeStep  { step = .explain }
                case .explain:  ExplainStep  { step = .consent }
                case .consent:  ConsentStep  { agreed() }
                case .profile:  ProfileStep  { step = .location }
                case .location: LocationStep { finish() }
                }
            }
            .readableColumn()
        }
        .onAppear {
            // Re-consent only: skip straight to the agreement.
            if state.hasCompletedOnboarding && !state.hasCurrentConsent { step = .consent }
        }
        .animation(.smooth(duration: 0.35), value: step)
    }

    private func agreed() {
        state.recordConsent()
        // A returning person re-agreeing doesn't need to redo their profile.
        step = state.hasCompletedOnboarding ? .location : .profile
        if state.hasCompletedOnboarding && state.location.hasAnyPermission { finish() }
    }

    private func finish() {
        state.hasCompletedOnboarding = true
        state.saveLocal()
        Task { await state.bootstrap() }
    }
}

// MARK: - 1. Welcome

private struct WelcomeStep: View {
    var next: () -> Void
    @State private var float = false

    var body: some View {
        VStack(spacing: 0) {
            Spacer()

            Text("Where U At")
                .font(.system(size: 40, weight: .bold, design: .rounded))
                .foregroundStyle(Theme.ink)

            Text("Find each other.\nOnly when you both want to.")
                .font(.system(size: 16))
                .foregroundStyle(Theme.inkMuted)
                .multilineTextAlignment(.center)
                .padding(.top, 10)

            ZStack {
                Circle()
                    .fill(Theme.brandSoft)
                    .frame(width: 260, height: 260)
                    .blur(radius: 30)

                Image("LogoMark")
                    .resizable()
                    .scaledToFit()
                    .frame(width: 190, height: 190)
                    // The source art is a squircle on white; clipping to the
                    // same squircle drops the corners rather than showing them.
                    .clipShape(RoundedRectangle(cornerRadius: 190 * 0.225, style: .continuous))
                    .shadow(color: Theme.sky.opacity(0.35), radius: 24, y: 12)
                    .offset(y: float ? -8 : 8)
            }
            .padding(.vertical, 30)
            .onAppear {
                withAnimation(.easeInOut(duration: 2.6).repeatForever(autoreverses: true)) {
                    float = true
                }
            }

            Spacer()

            Button("Get Started", action: next)
                .buttonStyle(BrandButtonStyle())
                .padding(.horizontal, 24)
                .padding(.bottom, 40)
        }
    }
}

// MARK: - 2. What it does

private struct ExplainStep: View {
    var next: () -> Void

    private let points: [(String, String, String)] = [
        ("person.2.fill", "Share with anyone",
         "Invite friends, partners or family. No Family Sharing required."),
        ("hand.raised.fill", "You're always in control",
         "Pause or stop sharing whenever you want, with everyone or just one person."),
        ("lock.fill", "Location stays private",
         "Only people you've accepted can see you. There's no history kept.")
    ]

    var body: some View {
        VStack(spacing: 0) {
            Spacer(minLength: 40)

            ZStack {
                Circle().fill(Theme.brandSoft).frame(width: 110, height: 110)
                Image(systemName: "location.fill")
                    .font(.system(size: 40, weight: .medium))
                    .foregroundStyle(Theme.brand)
            }

            Text("Share location\nwith people you trust")
                .font(.system(size: 26, weight: .bold, design: .rounded))
                .multilineTextAlignment(.center)
                .foregroundStyle(Theme.ink)
                .padding(.top, 22)

            VStack(spacing: 4) {
                ForEach(points, id: \.1) { symbol, title, body in
                    HStack(alignment: .top, spacing: 14) {
                        ZStack {
                            RoundedRectangle(cornerRadius: 11, style: .continuous)
                                .fill(Theme.brand)
                                .frame(width: 36, height: 36)
                            Image(systemName: symbol)
                                .font(.system(size: 16, weight: .semibold))
                                .foregroundStyle(.white)
                        }
                        VStack(alignment: .leading, spacing: 3) {
                            Text(title)
                                .font(.system(size: 15, weight: .semibold))
                                .foregroundStyle(Theme.ink)
                            Text(body)
                                .font(.system(size: 13.5))
                                .foregroundStyle(Theme.inkMuted)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        Spacer(minLength: 0)
                    }
                    .padding(.vertical, 12)

                    if title != points.last?.1 {
                        Divider().overlay(Theme.hairline)
                    }
                }
            }
            .padding(.horizontal, 4)
            .padding(.vertical, 4)
            .background {
                RoundedRectangle(cornerRadius: 22, style: .continuous)
                    .fill(.white.opacity(0.7))
                    .overlay {
                        RoundedRectangle(cornerRadius: 22, style: .continuous)
                            .strokeBorder(.white, lineWidth: 1)
                    }
                    .shadow(color: Theme.ink.opacity(0.07), radius: 16, y: 6)
            }
            .padding(.horizontal, 24)
            .padding(.top, 26)

            Spacer()

            Button("Continue", action: next)
                .buttonStyle(BrandButtonStyle())
                .padding(.horizontal, 24)
                .padding(.bottom, 40)
        }
    }
}

// MARK: - 3. Agreement

/// A distinct, unbundled, un-pre-ticked agreement. This is the point at which
/// Where U At is allowed to start processing anything, and the app enforces
/// that: without it, no location is read, published or stored.
private struct ConsentStep: View {
    @Environment(\.openURL) private var openURL
    var next: () -> Void

    @State private var agreed = false

    var body: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(spacing: 0) {
                    Text("Before we start")
                        .font(.system(size: 27, weight: .bold, design: .rounded))
                        .foregroundStyle(Theme.ink)
                        .padding(.top, 34)

                    Text("Where U At handles where you are, so here is\nexactly what that means.")
                        .font(.system(size: 14.5))
                        .foregroundStyle(Theme.inkMuted)
                        .multilineTextAlignment(.center)
                        .padding(.top, 8)

                    VStack(spacing: 0) {
                        ForEach(Array(Consent.points.enumerated()), id: \.offset) { index, point in
                            HStack(alignment: .top, spacing: 13) {
                                ZStack {
                                    Circle().fill(Theme.brandSoft).frame(width: 34, height: 34)
                                    Image(systemName: point.symbol)
                                        .font(.system(size: 14, weight: .semibold))
                                        .foregroundStyle(Theme.sky)
                                }
                                VStack(alignment: .leading, spacing: 3) {
                                    Text(point.title)
                                        .font(.system(size: 14.5, weight: .semibold))
                                        .foregroundStyle(Theme.ink)
                                    Text(point.detail)
                                        .font(.system(size: 13))
                                        .foregroundStyle(Theme.inkMuted)
                                        .fixedSize(horizontal: false, vertical: true)
                                }
                                Spacer(minLength: 0)
                            }
                            .padding(.vertical, 13)

                            if index < Consent.points.count - 1 {
                                Divider().overlay(Theme.hairline)
                            }
                        }
                    }
                    .padding(.horizontal, 15)
                    .background {
                        RoundedRectangle(cornerRadius: 20, style: .continuous)
                            .fill(.white.opacity(0.72))
                            .overlay {
                                RoundedRectangle(cornerRadius: 20, style: .continuous)
                                    .strokeBorder(Theme.hairline, lineWidth: 1)
                            }
                    }
                    .padding(.horizontal, 22)
                    .padding(.top, 24)

                    Button {
                        openURL(Consent.privacyPolicyURL)
                    } label: {
                        Label("Read the full Privacy Policy", systemImage: "arrow.up.right.square")
                            .font(.system(size: 13.5, weight: .medium))
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(Theme.sky)
                    .padding(.top, 18)
                }
            }
            .scrollBounceBehavior(.basedOnSize)

            VStack(spacing: 14) {
                // Deliberately starts off. Nothing here is pre-agreed.
                Button {
                    agreed.toggle()
                } label: {
                    HStack(alignment: .top, spacing: 11) {
                        ZStack {
                            RoundedRectangle(cornerRadius: 6, style: .continuous)
                                .fill(agreed ? AnyShapeStyle(Theme.brand) : AnyShapeStyle(Color.white.opacity(0.8)))
                                .frame(width: 23, height: 23)
                            RoundedRectangle(cornerRadius: 6, style: .continuous)
                                .strokeBorder(agreed ? Color.clear : Theme.inkMuted.opacity(0.4), lineWidth: 1.4)
                                .frame(width: 23, height: 23)
                            if agreed {
                                Image(systemName: "checkmark")
                                    .font(.system(size: 12, weight: .bold))
                                    .foregroundStyle(.white)
                            }
                        }
                        Text("I agree to my location being shared with the people I accept, as described in the Privacy Policy.")
                            .font(.system(size: 13.5))
                            .foregroundStyle(Theme.ink)
                            .multilineTextAlignment(.leading)
                            .fixedSize(horizontal: false, vertical: true)
                        Spacer(minLength: 0)
                    }
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(agreed ? [.isSelected] : [])

                Button("Agree & Continue", action: next)
                    .buttonStyle(BrandButtonStyle())
                    .disabled(!agreed)
                    .opacity(agreed ? 1 : 0.45)

                Text("You can withdraw this at any time in the You tab.")
                    .font(.system(size: 12))
                    .foregroundStyle(Theme.inkMuted)
            }
            .padding(.horizontal, 24)
            .padding(.top, 16)
            .padding(.bottom, 30)
        }
        .animation(.smooth(duration: 0.2), value: agreed)
    }
}

// MARK: - 4. Who you are

private struct ProfileStep: View {
    @Environment(AppState.self) private var state
    var next: () -> Void

    @State private var name = ""
    @State private var colorHex = Theme.pinChoices[0].hexString
    @State private var photoItem: PhotosPickerItem?
    @State private var photoData: Data?

    private var canContinue: Bool {
        !name.trimmingCharacters(in: .whitespaces).isEmpty
    }

    var body: some View {
        VStack(spacing: 0) {
            Spacer(minLength: 30)

            Text("Who are you?")
                .font(.system(size: 28, weight: .bold, design: .rounded))
                .foregroundStyle(Theme.ink)

            Text("This is the name and pin the people you\nconnect with will see.")
                .font(.system(size: 14.5))
                .foregroundStyle(Theme.inkMuted)
                .multilineTextAlignment(.center)
                .padding(.top, 8)

            PhotosPicker(selection: $photoItem, matching: .images) {
                ZStack(alignment: .bottomTrailing) {
                    Avatar(profile: previewProfile, size: 118)
                    ZStack {
                        Circle().fill(Theme.brand).frame(width: 34, height: 34)
                        Image(systemName: "camera.fill")
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundStyle(.white)
                    }
                    .overlay(Circle().strokeBorder(.white, lineWidth: 2))
                }
            }
            .padding(.top, 28)
            .onChange(of: photoItem) { _, item in
                Task {
                    if let data = try? await item?.loadTransferable(type: Data.self) {
                        photoData = ImageTools.squareJPEG(data, maxSide: 512)
                    }
                }
            }

            TextField("Your name", text: $name)
                .textInputAutocapitalization(.words)
                .font(.system(size: 17, weight: .medium))
                .foregroundStyle(Theme.ink)
                .tint(Theme.sky)
                .multilineTextAlignment(.center)
                .padding(.vertical, 15)
                .background(.white.opacity(0.8), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                .overlay {
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .strokeBorder(Theme.hairline, lineWidth: 1)
                }
                .padding(.horizontal, 24)
                .padding(.top, 26)

            VStack(spacing: 10) {
                Text("Your pin colour")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(Theme.inkMuted)

                HStack(spacing: 12) {
                    ForEach(Theme.pinChoices, id: \.hexString) { color in
                        Button {
                            colorHex = color.hexString
                        } label: {
                            Circle()
                                .fill(color)
                                .frame(width: 30, height: 30)
                                .overlay {
                                    Circle().strokeBorder(.white, lineWidth: colorHex == color.hexString ? 3 : 0)
                                }
                                .overlay {
                                    Circle().strokeBorder(color, lineWidth: colorHex == color.hexString ? 2 : 0)
                                        .padding(-3)
                                }
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
            .padding(.top, 22)

            Spacer()

            Button("Continue", action: save)
                .buttonStyle(BrandButtonStyle())
                .disabled(!canContinue)
                .opacity(canContinue ? 1 : 0.45)
                .padding(.horizontal, 24)
                .padding(.bottom, 40)
        }
    }

    private var previewProfile: PersonProfile {
        PersonProfile(pairingID: state.myProfile.pairingID,
                      displayName: name.isEmpty ? "You" : name,
                      pinColorHex: colorHex,
                      emoji: nil,
                      avatarData: photoData,
                      updatedAt: Date())
    }

    private func save() {
        var p = state.myProfile
        p.displayName = name.trimmingCharacters(in: .whitespaces)
        p.pinColorHex = colorHex
        p.avatarData = photoData
        state.myProfile = p
        state.saveLocal()
        next()
    }
}

// MARK: - 5. Location

private struct LocationStep: View {
    @Environment(AppState.self) private var state
    var done: () -> Void

    @State private var askedWhenInUse = false

    var body: some View {
        VStack(spacing: 0) {
            Spacer(minLength: 40)

            ZStack {
                Circle().fill(Theme.brandSoft).frame(width: 120, height: 120)
                Image(systemName: "location.circle.fill")
                    .font(.system(size: 56))
                    .foregroundStyle(Theme.brand)
            }

            Text(headline)
                .font(.system(size: 25, weight: .bold, design: .rounded))
                .multilineTextAlignment(.center)
                .foregroundStyle(Theme.ink)
                .padding(.top, 24)
                .padding(.horizontal, 30)

            Text(explanation)
                .font(.system(size: 15))
                .foregroundStyle(Theme.inkMuted)
                .multilineTextAlignment(.center)
                .padding(.top, 12)
                .padding(.horizontal, 34)
                .fixedSize(horizontal: false, vertical: true)

            Spacer()

            VStack(spacing: 12) {
                Button(primaryTitle, action: primaryAction)
                    .buttonStyle(BrandButtonStyle())

                Button("Not Now", action: done)
                    .buttonStyle(QuietButtonStyle())
            }
            .padding(.horizontal, 24)

            Text("You can change this later in Settings.")
                .font(.system(size: 12.5))
                .foregroundStyle(Theme.inkMuted)
                .padding(.top, 14)
                .padding(.bottom, 34)
        }
        .onChange(of: state.location.authorization) { _, status in
            // Once When In Use lands, immediately explain and offer Always.
            if status == .authorizedWhenInUse { askedWhenInUse = true }
            if status == .authorizedAlways { done() }
        }
    }

    private var needsAlways: Bool {
        state.location.authorization == .authorizedWhenInUse
    }

    private var headline: String {
        needsAlways ? "Keep your pin fresh" : "Allow Where U At to use your location"
    }

    private var explanation: String {
        needsAlways
        ? "With Always, the people you've accepted see where you are even when the app is closed. Without it, they'll only ever see where you were the last time you opened Where U At."
        : "Your location is shared only with people you've explicitly accepted, and you can pause it at any time."
    }

    private var primaryTitle: String {
        needsAlways ? "Allow Always" : "Allow While Using App"
    }

    private func primaryAction() {
        if needsAlways {
            state.location.requestAlways()
        } else {
            state.location.requestWhenInUse()
        }
    }
}

// MARK: - Image helper

enum ImageTools {
    /// Centre-crops to a square and compresses, so avatars stay small enough to
    /// ride along in every connection zone without bloating CloudKit.
    static func squareJPEG(_ data: Data, maxSide: CGFloat) -> Data? {
        guard let image = UIImage(data: data) else { return nil }
        let side = min(image.size.width, image.size.height)
        let origin = CGPoint(x: (image.size.width - side) / 2, y: (image.size.height - side) / 2)

        let format = UIGraphicsImageRendererFormat.default()
        format.scale = 1
        let target = min(maxSide, side)
        let renderer = UIGraphicsImageRenderer(size: CGSize(width: target, height: target), format: format)

        let output = renderer.image { _ in
            image.draw(in: CGRect(x: -origin.x * target / side,
                                  y: -origin.y * target / side,
                                  width: image.size.width * target / side,
                                  height: image.size.height * target / side))
        }
        return output.jpegData(compressionQuality: 0.82)
    }
}
