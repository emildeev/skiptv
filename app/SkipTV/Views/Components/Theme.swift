import SwiftUI

/// SkipTV's own look: deep ink background with a warm amber accent.
enum Theme {
    static let background = Color(red: 0.035, green: 0.043, blue: 0.067)
    static let surface = Color(red: 0.09, green: 0.105, blue: 0.15)
    static let accent = Color(red: 1.0, green: 0.71, blue: 0.28)
    static let accentText = Color(red: 0.12, green: 0.08, blue: 0.02)
    static let secondaryText = Color.white.opacity(0.62)
    static let watched = Color(red: 0.45, green: 0.85, blue: 0.62)

    static let posterSize = CGSize(width: 250, height: 375)
    static let landscapeSize = CGSize(width: 420, height: 236)
    static let pageInset: CGFloat = 80
}

/// Full-bleed backdrop that fades into the background.
struct Backdrop: View {
    let url: URL?

    var body: some View {
        GeometryReader { proxy in
            RemoteImage(url: url, contentMode: .fill)
                .frame(width: proxy.size.width, height: proxy.size.height)
                .clipped()
                .overlay(
                    LinearGradient(
                        colors: [Theme.background.opacity(0.2), Theme.background.opacity(0.75), Theme.background],
                        startPoint: .top, endPoint: .bottom
                    )
                )
                .overlay(
                    LinearGradient(
                        colors: [Theme.background.opacity(0.9), .clear],
                        startPoint: .leading, endPoint: .trailing
                    )
                )
        }
        .ignoresSafeArea()
        .animation(.easeInOut(duration: 0.4), value: url)
    }
}

struct ProgressLine: View {
    let progress: Double

    var body: some View {
        GeometryReader { proxy in
            ZStack(alignment: .leading) {
                Capsule().fill(Color.white.opacity(0.25))
                Capsule().fill(Theme.accent).frame(width: proxy.size.width * progress)
            }
        }
        .frame(height: 6)
    }
}

struct WatchedBadge: View {
    var body: some View {
        Image(systemName: "checkmark")
            .font(.system(size: 20, weight: .bold))
            .foregroundStyle(Theme.accentText)
            .padding(8)
            .background(Circle().fill(Theme.watched))
    }
}

struct CountBadge: View {
    let count: Int

    var body: some View {
        Text("\(count)")
            .font(.system(size: 22, weight: .bold))
            .foregroundStyle(Theme.accentText)
            .padding(.horizontal, 12)
            .padding(.vertical, 4)
            .background(Capsule().fill(Theme.accent))
    }
}

/// Primary action button (Play / Resume).
struct AccentButtonStyle: ButtonStyle {
    @Environment(\.isFocused) private var isFocused

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 28, weight: .semibold))
            .padding(.horizontal, 36)
            .padding(.vertical, 18)
            .foregroundStyle(isFocused ? Theme.accentText : .white)
            .background(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(isFocused ? Theme.accent : Color.white.opacity(0.14))
            )
            .scaleEffect(isFocused ? 1.06 : (configuration.isPressed ? 0.97 : 1))
            .shadow(color: .black.opacity(isFocused ? 0.4 : 0), radius: 18, y: 10)
            .animation(.easeOut(duration: 0.15), value: isFocused)
    }
}

extension View {
    func pageBackground() -> some View {
        background(Theme.background.ignoresSafeArea())
    }
}
