import SkipTVKit
import SwiftUI

/// Poster grid of a movie or TV library.
struct LibraryView: View {
    @Environment(AppModel.self) private var app
    @Environment(Navigator.self) private var navigator
    let section: PlexLibrarySection

    @State private var items: [PlexItem] = []
    @State private var loading = true
    @State private var error: String?
    @State private var filter: Filter = .all

    enum Filter: String, CaseIterable, Identifiable {
        case all = "Все"
        case unwatched = "Непросмотренные"
        case recent = "Новые"

        var id: String { rawValue }
    }

    private var visible: [PlexItem] {
        switch filter {
        case .all: return items
        case .unwatched: return items.filter { !$0.isWatched }
        case .recent: return items.sorted { ($0.addedAt ?? 0) > ($1.addedAt ?? 0) }
        }
    }

    private let columns = [GridItem(.adaptive(minimum: Theme.posterSize.width, maximum: Theme.posterSize.width), spacing: 50)]

    var body: some View {
        Group {
            if loading && items.isEmpty {
                LoadingView()
            } else if let error, items.isEmpty {
                ErrorView(message: error) { Task { await load() } }
            } else {
                ScrollView {
                    VStack(alignment: .leading, spacing: 30) {
                        HStack(spacing: 20) {
                            Text(section.title)
                                .font(.system(size: 52, weight: .heavy))
                            Text("\(visible.count)")
                                .font(.system(size: 30))
                                .foregroundStyle(Theme.secondaryText)
                            Spacer()
                            ForEach(Filter.allCases) { option in
                                Button {
                                    filter = option
                                } label: {
                                    Text(option.rawValue)
                                        .fontWeight(filter == option ? .bold : .regular)
                                }
                                .buttonStyle(AccentButtonStyle())
                                .overlay(alignment: .bottom) {
                                    if filter == option {
                                        Capsule().fill(Theme.accent).frame(height: 4).padding(.horizontal, 30).offset(y: 10)
                                    }
                                }
                            }
                        }
                        .focusSection()

                        LazyVGrid(columns: columns, alignment: .leading, spacing: 60) {
                            ForEach(visible) { item in
                                PosterCard(item: item) { navigator.open(item, app: app) }
                            }
                        }
                    }
                    .padding(.horizontal, Theme.pageInset)
                    .padding(.vertical, 40)
                }
            }
        }
        .task(id: app.refreshID) { await load() }
    }

    private func load() async {
        guard let api = app.api else { return }
        loading = true
        defer { loading = false }
        do {
            items = try await api.items(section: section)
            error = nil
        } catch {
            self.error = "Не удалось загрузить «\(section.title)»: \(error.localizedDescription)"
        }
    }
}
