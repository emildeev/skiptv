import Observation
import SkipTVKit
import SwiftUI

enum Route: Hashable {
    case movie(PlexItem)
    case show(ratingKey: String, seasonRatingKey: String?)
}

/// Navigation state of one tab.
@MainActor
@Observable
final class Navigator {
    var path = NavigationPath()

    /// Opens a card: details for movies/shows/seasons, playback for episodes.
    func open(_ item: PlexItem, app: AppModel) {
        switch item.type {
        case .movie:
            path.append(Route.movie(item))
        case .show:
            path.append(Route.show(ratingKey: item.ratingKey, seasonRatingKey: nil))
        case .season:
            if let show = item.parentRatingKey {
                path.append(Route.show(ratingKey: show, seasonRatingKey: item.ratingKey))
            }
        case .episode, .clip:
            app.requestPlay(item)
        case .other:
            break
        }
    }
}

/// NavigationStack with SkipTV routes.
struct TabStack<Root: View>: View {
    @State private var navigator = Navigator()
    @ViewBuilder var root: () -> Root

    var body: some View {
        NavigationStack(path: $navigator.path) {
            root()
                .navigationDestination(for: Route.self) { route in
                    switch route {
                    case .movie(let item):
                        MovieView(initial: item)
                    case .show(let key, let season):
                        ShowView(showRatingKey: key, initialSeason: season)
                    }
                }
        }
        .environment(navigator)
    }
}
