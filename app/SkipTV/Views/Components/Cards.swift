import SkipTVKit
import SwiftUI

/// Vertical poster with title underneath (movies, shows, seasons).
struct PosterCard: View {
    @Environment(AppModel.self) private var app
    let item: PlexItem
    var action: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Button(action: action) {
                RemoteImage(url: app.api?.imageURL(item.posterPath, width: 500, height: 750))
                    .frame(width: Theme.posterSize.width, height: Theme.posterSize.height)
                    .overlay(alignment: .topTrailing) { badge.padding(12) }
                    .overlay(alignment: .bottom) {
                        if let progress = item.progress {
                            ProgressLine(progress: progress).padding(12)
                        }
                    }
            }
            .buttonStyle(.card)

            VStack(alignment: .leading, spacing: 4) {
                Text(item.type == .season ? item.displayTitle : item.title)
                    .font(.system(size: 24, weight: .medium))
                    .lineLimit(1)
                if let subtitle = item.type == .season ? item.title : item.year.map(String.init) {
                    Text(subtitle)
                        .font(.system(size: 20))
                        .foregroundStyle(Theme.secondaryText)
                        .lineLimit(1)
                }
            }
            .frame(width: Theme.posterSize.width, alignment: .leading)
        }
    }

    @ViewBuilder private var badge: some View {
        if item.isWatched {
            WatchedBadge()
        } else if item.type == .show || item.type == .season, let count = item.unwatchedLeafCount, count > 0 {
            CountBadge(count: count)
        }
    }
}

/// 16:9 card: episodes and "continue watching".
struct LandscapeCard: View {
    @Environment(AppModel.self) private var app
    let item: PlexItem
    var title: String
    var subtitle: String?
    var size: CGSize = Theme.landscapeSize
    var action: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Button(action: action) {
                RemoteImage(url: app.api?.imageURL(item.landscapePath, width: Int(size.width * 2), height: Int(size.height * 2)))
                    .frame(width: size.width, height: size.height)
                    .overlay(alignment: .topTrailing) {
                        if item.isWatched { WatchedBadge().padding(12) }
                    }
                    .overlay(alignment: .bottom) {
                        if let progress = item.progress {
                            ProgressLine(progress: progress).padding(14)
                        }
                    }
            }
            .buttonStyle(.card)

            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.system(size: 24, weight: .medium))
                    .lineLimit(1)
                if let subtitle {
                    Text(subtitle)
                        .font(.system(size: 20))
                        .foregroundStyle(Theme.secondaryText)
                        .lineLimit(1)
                }
            }
            .frame(width: size.width, alignment: .leading)
        }
    }
}

/// Horizontal shelf with a title.
struct Shelf<Content: View>: View {
    let title: String
    @ViewBuilder var content: () -> Content

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            Text(title)
                .font(.system(size: 34, weight: .semibold))
                .padding(.horizontal, Theme.pageInset)
            ScrollView(.horizontal, showsIndicators: false) {
                LazyHStack(alignment: .top, spacing: 44) {
                    content()
                }
                .padding(.horizontal, Theme.pageInset)
                .padding(.vertical, 30)
            }
            .scrollClipDisabled()
        }
    }
}

struct LoadingView: View {
    var text: String = "Загрузка…"

    var body: some View {
        VStack(spacing: 24) {
            ProgressView()
            Text(text).foregroundStyle(Theme.secondaryText)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

struct ErrorView: View {
    let message: String
    var retry: (() -> Void)?

    var body: some View {
        VStack(spacing: 30) {
            Image(systemName: "exclamationmark.triangle")
                .font(.system(size: 60))
                .foregroundStyle(Theme.accent)
            Text(message)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 1100)
            if let retry {
                Button("Повторить", action: retry)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
