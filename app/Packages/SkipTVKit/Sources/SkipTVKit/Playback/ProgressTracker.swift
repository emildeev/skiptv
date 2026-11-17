import Foundation

/// Decides when to send Plex timeline updates and when an item counts as watched.
public struct ProgressTracker: Sendable {
    public enum Report: Equatable, Sendable {
        case timeline(PlaybackState, position: Double)
        case scrobble
    }

    /// Plex itself treats 90% as watched.
    public static let watchedFraction = 0.9
    public static let interval: TimeInterval = 10

    public private(set) var lastState: PlaybackState?
    public private(set) var lastReportAt: Date?
    public private(set) var scrobbled = false
    /// Start of final credits; reaching it marks the item watched.
    public var creditsStart: Double?

    public init(creditsStart: Double? = nil) {
        self.creditsStart = creditsStart
    }

    public func isWatched(position: Double, duration: Double?) -> Bool {
        if let creditsStart, position >= creditsStart { return true }
        guard let duration, duration > 0 else { return false }
        return position / duration >= Self.watchedFraction
    }

    /// Call on every tick and on state changes; returns what to send now.
    public mutating func update(state: PlaybackState, position: Double, duration: Double?, now: Date = Date()) -> [Report] {
        var reports: [Report] = []
        let stateChanged = state != lastState
        let due = lastReportAt.map { now.timeIntervalSince($0) >= Self.interval } ?? true
        if stateChanged || (due && state == .playing) {
            reports.append(.timeline(state, position: position))
            lastState = state
            lastReportAt = now
        }
        if !scrobbled, isWatched(position: position, duration: duration) {
            scrobbled = true
            reports.append(.scrobble)
        }
        return reports
    }
}
