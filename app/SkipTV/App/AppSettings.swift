import Foundation
import Observation
import SkipTVKit

/// User preferences, persisted in UserDefaults.
@MainActor
@Observable
final class AppSettings {
    private let defaults: UserDefaults

    var skipMode: SkipMode {
        didSet { defaults.set(skipMode.rawValue, forKey: Keys.skipMode) }
    }

    /// Detector service base URL.
    var detectorURL: String {
        didSet { defaults.set(detectorURL, forKey: Keys.detectorURL) }
    }

    /// Seconds of the "Next episode" countdown.
    var nextEpisodeCountdown: Int {
        didSet { defaults.set(nextEpisodeCountdown, forKey: Keys.countdown) }
    }

    /// Autoplay the next episode when an episode ends (or its credits are auto-skipped).
    var autoplayNext: Bool {
        didSet { defaults.set(autoplayNext, forKey: Keys.autoplay) }
    }

    /// mpv `profile=fast`: cheaper scaling and tone mapping.
    var fastRendering: Bool {
        didSet { defaults.set(fastRendering, forKey: Keys.fast) }
    }

    /// Preferred server connection URL (empty: automatic).
    var preferredConnection: String {
        didSet { defaults.set(preferredConnection, forKey: Keys.connection) }
    }

    private enum Keys {
        static let skipMode = "skipMode"
        static let detectorURL = "detectorURL"
        static let countdown = "nextEpisodeCountdown"
        static let autoplay = "autoplayNext"
        static let fast = "fastRendering"
        static let connection = "preferredConnection"
    }

    static let countdownOptions = [5, 10, 15]

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        skipMode = defaults.string(forKey: Keys.skipMode).flatMap(SkipMode.init(rawValue:)) ?? .auto
        detectorURL = defaults.string(forKey: Keys.detectorURL) ?? DetectorClient.defaultBaseURL.absoluteString
        let countdown = defaults.integer(forKey: Keys.countdown)
        nextEpisodeCountdown = countdown > 0 ? countdown : 5
        autoplayNext = defaults.object(forKey: Keys.autoplay) as? Bool ?? true
        fastRendering = defaults.bool(forKey: Keys.fast)
        preferredConnection = defaults.string(forKey: Keys.connection) ?? ""
    }

    var detectorBaseURL: URL {
        let trimmed = detectorURL.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let url = URL(string: trimmed), url.scheme?.hasPrefix("http") == true else {
            return DetectorClient.defaultBaseURL
        }
        return url
    }
}
