import SkipTVKit
import SwiftUI

/// Show page: backdrop, description, seasons and episodes.
struct ShowView: View {
    @Environment(AppModel.self) private var app
    let showRatingKey: String
    let initialSeason: String?

    @State private var show: PlexItem?
    @State private var seasons: [PlexItem] = []
    @State private var selectedSeason: String?
    @State private var episodes: [PlexItem] = []
    @State private var allEpisodes: [PlexItem] = []
    @State private var focusedEpisode: PlexItem?
    @State private var error: String?
    @FocusState private var focus: String?

    private var resumeTarget: PlexItem? { EpisodeNavigator.resumeEpisode(in: allEpisodes) }

    var body: some View {
        ZStack(alignment: .topLeading) {
            Backdrop(url: app.api?.imageURL(show?.art, width: 1920, height: 1080))

            if let show {
                ScrollView(.vertical) {
                    VStack(alignment: .leading, spacing: 40) {
                        header(show)
                            .padding(.horizontal, Theme.pageInset)

                        if seasons.count > 1 {
                            ScrollView(.horizontal, showsIndicators: false) {
                                HStack(spacing: 20) {
                                    ForEach(seasons) { season in
                                        Button {
                                            select(season.ratingKey)
                                        } label: {
                                            HStack(spacing: 10) {
                                                Text(season.title)
                                                if season.isWatched { Image(systemName: "checkmark.circle.fill") }
                                            }
                                        }
                                        .buttonStyle(AccentButtonStyle())
                                        .overlay(alignment: .bottom) {
                                            if season.ratingKey == selectedSeason {
                                                Capsule().fill(Theme.accent).frame(height: 4).padding(.horizontal, 30).offset(y: 10)
                                            }
                                        }
                                    }
                                }
                                .padding(.horizontal, Theme.pageInset)
                                .padding(.vertical, 20)
                            }
                            .focusSection()
                        }

                        ScrollView(.horizontal, showsIndicators: false) {
                            LazyHStack(alignment: .top, spacing: 44) {
                                ForEach(episodes) { episode in
                                    LandscapeCard(
                                        item: episode,
                                        title: "\(episode.index.map { "\($0). " } ?? "")\(episode.title)",
                                        subtitle: TimeFormat.runtime(milliseconds: episode.duration)
                                    ) {
                                        app.requestPlay(episode)
                                    }
                                    .focused($focus, equals: episode.ratingKey)
                                    .contextMenu {
                                        Button(episode.isWatched ? "Отметить непросмотренной" : "Отметить просмотренной") {
                                            Task { await app.setWatched(episode, !episode.isWatched) }
                                        }
                                    }
                                }
                            }
                            .padding(.horizontal, Theme.pageInset)
                            .padding(.vertical, 30)
                        }
                        .scrollClipDisabled()
                        .focusSection()

                        if let episode = focusedEpisode {
                            VStack(alignment: .leading, spacing: 10) {
                                Text(episode.displaySubtitle ?? episode.title)
                                    .font(.system(size: 30, weight: .semibold))
                                Text(episode.summary ?? "")
                                    .font(.system(size: 24))
                                    .foregroundStyle(Theme.secondaryText)
                                    .lineLimit(4)
                                    .frame(maxWidth: 1300, alignment: .leading)
                            }
                            .padding(.horizontal, Theme.pageInset)
                        }
                    }
                    .padding(.bottom, 80)
                }
            } else if let error {
                ErrorView(message: error) { Task { await load() } }
            } else {
                LoadingView()
            }
        }
        .onChange(of: focus) { _, key in
            if let key, let episode = episodes.first(where: { $0.ratingKey == key }) {
                focusedEpisode = episode
            }
        }
        .task(id: app.refreshID) { await load() }
    }

    private func header(_ show: PlexItem) -> some View {
        VStack(alignment: .leading, spacing: 18) {
            Text(show.title)
                .font(.system(size: 72, weight: .heavy))
                .lineLimit(2)
            HStack(spacing: 18) {
                if let year = show.year { Text(String(year)) }
                if let rating = show.contentRating { Text(rating) }
                if let count = show.leafCount { Text("\(count) серий") }
                if let left = show.unwatchedLeafCount, left > 0 {
                    Text("осталось \(left)").foregroundStyle(Theme.accent)
                }
            }
            .font(.system(size: 26, weight: .medium))
            .foregroundStyle(Theme.secondaryText)
            Text(show.summary ?? "")
                .font(.system(size: 26))
                .lineLimit(4)
                .frame(maxWidth: 1200, alignment: .leading)
            if let target = resumeTarget {
                Button {
                    app.requestPlay(target)
                } label: {
                    Label(playTitle(target), systemImage: "play.fill")
                }
                .buttonStyle(AccentButtonStyle())
                .padding(.top, 10)
            }
        }
        .padding(.top, 60)
    }

    private func playTitle(_ episode: PlexItem) -> String {
        let label = episode.episodeLabel ?? episode.title
        return episode.progress != nil ? "Продолжить \(label)" : "Смотреть \(label)"
    }

    private func select(_ season: String) {
        guard season != selectedSeason else { return }
        selectedSeason = season
        Task { await loadEpisodes() }
    }

    private func load() async {
        guard let api = app.api else { return }
        do {
            async let showItem = api.item(ratingKey: showRatingKey)
            async let seasonItems = api.children(ratingKey: showRatingKey)
            async let leaves = api.allEpisodes(showRatingKey: showRatingKey)
            show = try await showItem
            seasons = try await seasonItems.filter { $0.type == .season }
            allEpisodes = (try? await leaves) ?? []
            if selectedSeason == nil {
                selectedSeason = initialSeason
                    ?? seasons.first(where: { $0.ratingKey == resumeTarget?.parentRatingKey })?.ratingKey
                    ?? seasons.first(where: { $0.index != 0 })?.ratingKey
                    ?? seasons.first?.ratingKey
            }
            await loadEpisodes()
            error = nil
        } catch {
            self.error = "Не удалось загрузить сериал: \(error.localizedDescription)"
        }
    }

    private func loadEpisodes() async {
        guard let api = app.api, let season = selectedSeason else { return }
        episodes = (try? await api.children(ratingKey: season)) ?? []
        focusedEpisode = episodes.first(where: { $0.ratingKey == resumeTarget?.ratingKey }) ?? episodes.first
    }
}
