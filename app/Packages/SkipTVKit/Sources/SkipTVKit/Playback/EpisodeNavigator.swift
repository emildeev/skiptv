import Foundation

public enum EpisodeNavigator {
    /// Episodes sorted by season and episode number (specials, season 0, go last).
    public static func ordered(_ episodes: [PlexItem]) -> [PlexItem] {
        episodes
            .filter { $0.type == .episode }
            .enumerated()
            .sorted { lhs, rhs in
                let l = sortKey(lhs.element), r = sortKey(rhs.element)
                return (l.season, l.episode, lhs.offset) < (r.season, r.episode, rhs.offset)
            }
            .map(\.element)
    }

    private static func sortKey(_ item: PlexItem) -> (season: Int, episode: Int) {
        let season = item.parentIndex ?? Int.max
        return (season == 0 ? Int.max : season, item.index ?? Int.max)
    }

    /// Episode that follows `current` in the show, or nil for the last one.
    /// Specials (season 0) are never chosen as "next" for a regular episode.
    public static func next(after current: PlexItem, in episodes: [PlexItem]) -> PlexItem? {
        let list = ordered(episodes)
        guard let i = list.firstIndex(where: { $0.ratingKey == current.ratingKey }) else { return nil }
        guard i + 1 < list.count else { return nil }
        let candidate = list[i + 1]
        if (current.parentIndex ?? 1) != 0, candidate.parentIndex == 0 { return nil }
        return candidate
    }

    /// What "Play" on a show starts: the first in-progress or unwatched episode.
    public static func resumeEpisode(in episodes: [PlexItem]) -> PlexItem? {
        let list = ordered(episodes).filter { $0.parentIndex != 0 }
        if let inProgress = list.first(where: { $0.progress != nil }) { return inProgress }
        // First unwatched after the last watched one, so gaps from the past do not win.
        if let lastWatched = list.lastIndex(where: { ($0.viewCount ?? 0) > 0 }) {
            if lastWatched + 1 < list.count { return list[lastWatched + 1] }
            return list.first
        }
        return list.first
    }
}
