import SwiftUI
import CoreLocation

/// Circular photo with a coloured ring, falling back to initials.
struct Avatar: View {
    var profile: PersonProfile?
    var size: CGFloat = 44
    var ring: Bool = true

    private var tint: Color { profile?.pinColor ?? Theme.indigo }

    var body: some View {
        ZStack {
            if let data = profile?.avatarData, let image = UIImage(data: data) {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFill()
            } else {
                Theme.brandSoft
                Text(profile?.emoji ?? profile?.initials ?? "?")
                    .font(.system(size: size * 0.38, weight: .semibold))
                    .foregroundStyle(Theme.ink.opacity(0.75))
            }
        }
        .frame(width: size, height: size)
        .clipShape(Circle())
        .overlay {
            if ring {
                Circle().strokeBorder(tint, lineWidth: max(2, size * 0.05))
                Circle().strokeBorder(Color.white.opacity(0.9), lineWidth: max(1, size * 0.02))
                    .padding(max(2, size * 0.05))
            }
        }
        .shadow(color: Theme.ink.opacity(0.15), radius: size * 0.12, y: size * 0.05)
    }
}

/// Small green / grey dot that says whether someone is live right now.
struct StatusDot: View {
    var state: Connection.State

    private var color: Color {
        switch state {
        case .connected:  return Theme.affirmative
        case .invited:    return Theme.paused
        case .theyPaused, .iPaused: return Theme.paused
        }
    }

    var body: some View {
        Circle()
            .fill(color)
            .frame(width: 9, height: 9)
            .overlay(Circle().strokeBorder(.white, lineWidth: 1.5))
    }
}

/// One person as they appear in the People list.
struct PersonRow: View {
    var connection: Connection
    var distanceText: String?

    var body: some View {
        HStack(spacing: 12) {
            Avatar(profile: connection.profile, size: 46)

            VStack(alignment: .leading, spacing: 3) {
                Text(connection.displayName)
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(Theme.ink)

                Text(subtitle)
                    .font(.system(size: 13))
                    .foregroundStyle(Theme.inkMuted)
            }

            Spacer(minLength: 8)
            StatusDot(state: connection.state)
        }
        .padding(.vertical, 6)
    }

    private var subtitle: String {
        switch connection.state {
        case .invited:
            return "Invitation sent"
        case .iPaused:
            return "You paused sharing with them"
        case .theyPaused:
            return "Location paused"
        case .connected:
            let when = connection.presence.map { RelativeTime.string(for: $0.capturedAt) } ?? "—"
            if let distanceText { return "\(when) · \(distanceText)" }
            return when
        }
    }
}

enum RelativeTime {
    /// "Now", "2 min ago", "3 hr ago" — matching the reference UI's terseness.
    static func string(for date: Date) -> String {
        let seconds = Date().timeIntervalSince(date)
        switch seconds {
        case ..<60:      return "Now"
        case ..<3600:    return "\(Int(seconds / 60)) min ago"
        case ..<86_400:  return "\(Int(seconds / 3600)) hr ago"
        default:         return date.formatted(date: .abbreviated, time: .omitted)
        }
    }
}

enum DistanceText {
    static func string(metres: CLLocationDistance) -> String {
        let usesMetric = Locale.current.measurementSystem != .us
        if usesMetric {
            return metres < 1000
                ? "\(Int(metres.rounded())) m away"
                : String(format: "%.1f km away", metres / 1000)
        }
        let feet = metres * 3.28084
        return feet < 1000
            ? "\(Int(feet.rounded())) ft away"
            : String(format: "%.1f mi away", metres / 1609.34)
    }
}

/// The section header style used down the right-hand screens in the reference.
struct SectionHeader: View {
    var title: String
    var body: some View {
        Text(title.uppercased())
            .font(.system(size: 12, weight: .semibold))
            .kerning(0.6)
            .foregroundStyle(Theme.inkMuted)
            .frame(maxWidth: .infinity, alignment: .leading)
    }
}

/// Empty-state block: icon in a soft circle, headline, one line of explanation.
struct EmptyStateView: View {
    var symbol: String
    var title: String
    var message: String

    var body: some View {
        VStack(spacing: 14) {
            ZStack {
                Circle().fill(Theme.brandSoft).frame(width: 84, height: 84)
                Image(systemName: symbol)
                    .font(.system(size: 32, weight: .medium))
                    .foregroundStyle(Theme.sky)
            }
            Text(title)
                .font(.system(size: 19, weight: .semibold))
                .foregroundStyle(Theme.ink)
            Text(message)
                .font(.system(size: 15))
                .foregroundStyle(Theme.inkMuted)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.horizontal, 32)
    }
}
