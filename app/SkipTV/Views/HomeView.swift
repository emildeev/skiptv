import SkipTVKit
import SwiftUI

struct HomeView: View {
    @Environment(AppModel.self) private var app
    @Environment(Navigator.self) private var navigator

    @State private var onDeck: [PlexItem] = []
    struct RecentShelf: Identifiable {
        var section: PlexLibrarySection
        var items: [PlexItem]
        var id: String { section.id }
    }

    @State private var recent: [RecentShelf] = []
    @State private var loading = true
    @State private var error: String?
    @FocusState private var focused: String?

    private var allItems: [PlexItem] { onDeck + recent.flatMap(\.items) }

    private var heroItem: PlexItem? {
        if let focused, let item = allItems.first(where: { "\($0.ratingKey)" == focused.split(separator: "|").last.map(String.init) }) {
            return item
        }
        return onDeck.first ?? recent.first?.items.first
    }

    var body: some View {
        ZStack(alignment: .topLeading) {
            Backdrop(url: app.api?.imageURL(heroItem?.backdropPath, width: 1920, height: 1080))

            if loading && allItems.isEmpty {
                LoadingView()
            } else if let error, allItems.isEmpty {
                ErrorView(message: error) { Task { await load() } }
            } else {
                ScrollView(.vertical) {
                    VStack(alignment: .leading, spacing: 50) {
                        if let hero = heroItem {
                            HeroHeader(item: hero)
                                .padding(.horizontal, Theme.pageInset)
                                .padding(.top, 20)
                        }
                        if !onDeck.isEmpty {
                            Shelf(title: "Продолжить просмотр") {
                                ForEach(onDeck) { item in
                                    LandscapeCard(
                                        item: item,
                                        title: item.displayTitle,
                                        subtitle: item.type == .episode ? item.displaySubtitle : remaining(item),
                                        focus: CardFocus(binding: $focused, id: "deck|\(item.ratingKey)")
                                    ) {
                                        app.requestPlay(item)
                                    }
                                }
                            }
                        }
                        ForEach(recent) { entry in
                            if !entry.items.isEmpty {
                                Shelf(title: "Недавно добавлено · \(entry.section.title)") {
                                    ForEach(entry.items) { item in
                                        PosterCard(
                                            item: item,
                                            focus: CardFocus(binding: $focused, id: "\(entry.section.id)|\(item.ratingKey)")
                                        ) {
                                            navigator.open(item, app: app)
                                        }
                                    }
                                }
                            }
                        }
                    }
                    .padding(.bottom, 80)
                }
            }
        }
        .animation(.easeInOut(duration: 0.3), value: heroItem?.ratingKey)
        .task(id: app.refreshID) { await load() }
    }

    private func remaining(_ item: PlexItem) -> String? {
        guard let duration = item.duration, let offset = item.viewOffset else { return item.year.map(String.init) }
        return TimeFormat.runtime(milliseconds: duration - offset).map { "Осталось \($0)" }
    }

    private func load() async {
        guard let api = app.api else { return }
        loading = true
        defer { loading = false }
        do {
            async let deck = api.onDeck()
            let sections = app.sections
            var loaded: [RecentShelf] = []
            for section in sections {
                let items = (try? await api.recentlyAdded(section: section)) ?? []
                loaded.append(RecentShelf(section: section, items: Self.collapse(items)))
            }
            onDeck = try await deck
            recent = loaded
            error = nil
        } catch {
            self.error = "Не удалось загрузить главную: \(error.localizedDescription)"
        }
    }

    /// Recently added TV episodes become one card per show season.
    static func collapse(_ items: [PlexItem]) -> [PlexItem] {
        var seen = Set<String>()
        var result: [PlexItem] = []
        for item in items {
            let key = item.type == .episode ? (item.parentRatingKey ?? item.ratingKey) : item.ratingKey
            guard seen.insert(key).inserted else { continue }
            if item.type == .episode, let season = item.parentRatingKey {
                var seasonItem = item
                seasonItem.type = .season
                seasonItem.ratingKey = season
                seasonItem.title = item.parentTitle ?? "Сезон \(item.parentIndex ?? 0)"
                seasonItem.thumb = item.parentThumb ?? item.grandparentThumb
                seasonItem.parentRatingKey = item.grandparentRatingKey
                seasonItem.parentTitle = item.grandparentTitle
                seasonItem.viewCount = nil
                seasonItem.viewOffset = nil
                result.append(seasonItem)
            } else {
                result.append(item)
            }
        }
        return result
    }
}

/// Title and description of the focused item above the shelves.
private struct HeroHeader: View {
    let item: PlexItem

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(item.displayTitle)
                .font(.system(size: 64, weight: .heavy))
                .lineLimit(1)
                .shadow(radius: 10)
            if let subtitle = item.displaySubtitle {
                Text(subtitle)
                    .font(.system(size: 30, weight: .medium))
                    .foregroundStyle(Theme.accent)
                    .lineLimit(1)
            }
            Text(item.summary ?? " ")
                .font(.system(size: 26))
                .foregroundStyle(Theme.secondaryText)
                .lineLimit(3)
                .frame(maxWidth: 1100, alignment: .leading)
        }
        .frame(height: 300, alignment: .bottomLeading)
    }
}
