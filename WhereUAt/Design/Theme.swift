import SwiftUI

/// Palette + reusable surfaces lifted from the Where U At UI direction:
/// glassy aqua-to-indigo, soft light ground, one green for affirmative actions.
enum Theme {

    // MARK: Brand

    static let aqua   = Color(hex: 0x5FE0D8)
    static let sky    = Color(hex: 0x3AA9F5)
    static let indigo = Color(hex: 0x4C6FF5)
    static let mint   = Color(hex: 0x8FF0C4)

    static let affirmative = Color(hex: 0x22B04B)
    static let caution     = Color(hex: 0xFF6B5B)
    static let paused      = Color(hex: 0x9AA7B4)

    /// The pin / logo gradient. Top-lit aqua falling into deep blue.
    static let brand = LinearGradient(
        colors: [aqua, sky, indigo],
        startPoint: .topLeading,
        endPoint: .bottomTrailing
    )

    static let brandSoft = LinearGradient(
        colors: [aqua.opacity(0.35), sky.opacity(0.28), indigo.opacity(0.22)],
        startPoint: .topLeading,
        endPoint: .bottomTrailing
    )

    // MARK: Ground

    /// Light, watery backdrop used behind onboarding and sheets.
    static let ground = LinearGradient(
        colors: [Color(hex: 0xF2FBFD), Color(hex: 0xE6F4FB), Color(hex: 0xEFF1FE)],
        startPoint: .top,
        endPoint: .bottom
    )

    // MARK: Type

    static let ink       = Color(hex: 0x0E1B2A)
    static let inkMuted  = Color(hex: 0x6B7C8C)
    static let hairline  = Color(hex: 0x0E1B2A).opacity(0.07)

    /// Distinct, legible pin colours offered to people for their marker.
    static let pinChoices: [Color] = [
        Color(hex: 0x4C6FF5), Color(hex: 0x8B5CF6), Color(hex: 0xEC4899),
        Color(hex: 0xF97316), Color(hex: 0x22B04B), Color(hex: 0x06B6D4),
        Color(hex: 0xEAB308), Color(hex: 0xEF4444)
    ]
}

extension Color {
    init(hex: UInt32) {
        self.init(
            .sRGB,
            red:   Double((hex >> 16) & 0xFF) / 255,
            green: Double((hex >>  8) & 0xFF) / 255,
            blue:  Double( hex        & 0xFF) / 255,
            opacity: 1
        )
    }

    /// Round-trips through hex so a chosen pin colour survives CloudKit as a string.
    init?(hexString: String) {
        var s = hexString.trimmingCharacters(in: .whitespacesAndNewlines)
        if s.hasPrefix("#") { s.removeFirst() }
        guard s.count == 6, let v = UInt32(s, radix: 16) else { return nil }
        self.init(hex: v)
    }

    var hexString: String {
        let ui = UIColor(self)
        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        ui.getRed(&r, green: &g, blue: &b, alpha: &a)
        return String(format: "%02X%02X%02X",
                      Int((r * 255).rounded()),
                      Int((g * 255).rounded()),
                      Int((b * 255).rounded()))
    }
}

// MARK: - Surfaces

/// The floating translucent card the design leans on everywhere.
struct GlassCard<Content: View>: View {
    var cornerRadius: CGFloat = 22
    var padding: CGFloat = 16
    @ViewBuilder var content: Content

    var body: some View {
        content
            .padding(padding)
            .background {
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .fill(.ultraThinMaterial)
                    .overlay {
                        RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                            .strokeBorder(Color.white.opacity(0.55), lineWidth: 0.8)
                    }
                    .shadow(color: Theme.ink.opacity(0.10), radius: 18, y: 8)
            }
    }
}

/// Full-width primary action, brand gradient.
struct BrandButtonStyle: ButtonStyle {
    var tint: LinearGradient = Theme.brand

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 17, weight: .semibold))
            .foregroundStyle(.white)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 16)
            .background(tint, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            .shadow(color: Theme.sky.opacity(0.35), radius: 14, y: 6)
            .scaleEffect(configuration.isPressed ? 0.97 : 1)
            .animation(.spring(response: 0.28, dampingFraction: 0.7), value: configuration.isPressed)
    }
}

/// Quiet secondary action that still reads as tappable on a glass ground.
struct QuietButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 17, weight: .medium))
            .foregroundStyle(Theme.ink)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 16)
            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .strokeBorder(Theme.hairline, lineWidth: 1)
            }
            .scaleEffect(configuration.isPressed ? 0.97 : 1)
            .animation(.spring(response: 0.28, dampingFraction: 0.7), value: configuration.isPressed)
    }
}

// MARK: - Layout

extension View {
    /// Keeps single-column screens (onboarding, invitations) from stretching the
    /// full width of an iPad, where a 1000pt-wide button reads as a mistake.
    func readableColumn(_ maxWidth: CGFloat = 460) -> some View {
        self
            .frame(maxWidth: maxWidth)
            .frame(maxWidth: .infinity)
    }
}
