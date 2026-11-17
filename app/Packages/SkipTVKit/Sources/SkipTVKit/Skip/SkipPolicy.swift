import Foundation

/// User setting: what to do with detected intros/credits.
public enum SkipMode: String, Codable, CaseIterable, Sendable {
    /// Skip automatically (except the first episode of a season, where a button is shown).
    case auto
    /// Always show a "Skip" button.
    case button
    /// Do nothing.
    case off

    public var title: String {
        switch self {
        case .auto: return "Автоматически"
        case .button: return "Кнопкой"
        case .off: return "Выключено"
        }
    }
}

/// What is being played, as far as skipping is concerned.
public struct SkipContext: Equatable, Sendable {
    public var mode: SkipMode
    public var isEpisode: Bool
    /// Episode 1 of a season: the intro is usually new, so it's never skipped silently.
    public var isFirstEpisodeOfSeason: Bool
    public var hasNextEpisode: Bool
    /// File duration in seconds, if known.
    public var duration: Double?

    public init(mode: SkipMode, isEpisode: Bool, isFirstEpisodeOfSeason: Bool, hasNextEpisode: Bool, duration: Double?) {
        self.mode = mode
        self.isEpisode = isEpisode
        self.isFirstEpisodeOfSeason = isFirstEpisodeOfSeason
        self.hasNextEpisode = hasNextEpisode
        self.duration = duration
    }

    public init(mode: SkipMode, item: PlexItem, hasNextEpisode: Bool) {
        self.init(
            mode: mode,
            isEpisode: item.type == .episode,
            isFirstEpisodeOfSeason: item.type == .episode && item.index == 1,
            hasNextEpisode: hasNextEpisode,
            duration: item.duration.map { Double($0) / 1000 }
        )
    }
}

public enum SkipBehavior: Equatable, Sendable {
    case auto, button, none
}

/// What a skip does.
public enum SkipAction: Equatable, Sendable {
    /// Jump to a position in the current file.
    case seek(to: Double)
    /// Start the next episode.
    case nextEpisode
    /// Close the player (end credits of the last episode or a movie).
    case finish
}

/// The "Skip …" button currently offered to the user.
public struct SkipPrompt: Equatable, Sendable {
    public var segment: Segment
    public var action: SkipAction
    public var title: String
}

public enum SkipPolicy {
    /// Credits ending closer than this to the end of the file are "final":
    /// skipping them means moving on, not seeking to a post-credits scene.
    public static let finalCreditsTolerance: Double = 20

    public static func behavior(for segment: Segment, in context: SkipContext) -> SkipBehavior {
        guard context.mode != .off else { return .none }
        switch segment.type {
        case .recap, .preview:
            return .button
        case .intro:
            return canAutoSkip(context) ? .auto : .button
        case .credits:
            guard canAutoSkip(context) else { return .button }
            // Auto-skip of final credits means "play next"; without a next episode
            // closing the player on its own would be rude, so offer a button.
            if isFinalCredits(segment, in: context), !context.hasNextEpisode { return .button }
            return .auto
        }
    }

    public static func action(for segment: Segment, in context: SkipContext) -> SkipAction {
        if segment.type == .credits, isFinalCredits(segment, in: context) {
            return context.hasNextEpisode ? .nextEpisode : .finish
        }
        return .seek(to: segment.end)
    }

    public static func title(for segment: Segment, action: SkipAction) -> String {
        switch action {
        case .nextEpisode: return "Следующая серия"
        case .finish: return "Пропустить титры"
        case .seek:
            switch segment.type {
            case .intro: return "Пропустить заставку"
            case .credits: return "Пропустить титры"
            case .recap: return "Пропустить пересказ"
            case .preview: return "Пропустить анонс"
            }
        }
    }

    static func canAutoSkip(_ context: SkipContext) -> Bool {
        context.mode == .auto && context.isEpisode && !context.isFirstEpisodeOfSeason
    }

    static func isFinalCredits(_ segment: Segment, in context: SkipContext) -> Bool {
        guard segment.type == .credits else { return false }
        guard let duration = context.duration, duration > 0 else { return true }
        return duration - segment.end <= finalCreditsTolerance
    }
}

/// Commands the player must execute.
public enum SkipCommand: Equatable, Sendable {
    case seek(to: Double)
    /// Show the "Next episode" card with a countdown, then play the next episode.
    case startNextEpisodeCountdown
}

/// Tracks playback position against detected segments and decides when to
/// auto-skip and which button to show. Pure state machine, driven by `update`.
public final class SkipController {
    enum SegmentState {
        case pending
        /// Skipped automatically; no button while still inside.
        case autoFired
        /// Auto-skip happened, then the user moved back or cancelled: button only.
        case manual
    }

    public private(set) var segments: [Segment]
    public private(set) var context: SkipContext
    public private(set) var prompt: SkipPrompt?
    private var states: [SegmentState]

    /// Do not auto-skip when less than this remains of the segment.
    public static let minimumRemaining: Double = 1.5

    public init(segments: [Segment], context: SkipContext) {
        self.segments = DetectorClient.sanitize(segments)
        self.context = context
        self.states = Array(repeating: .pending, count: self.segments.count)
    }

    /// Updates duration once the player knows it exactly.
    public func setDuration(_ duration: Double) {
        guard duration > 0 else { return }
        context.duration = duration
    }

    /// Call on every position tick. Returns a command to run at most once per segment.
    @discardableResult
    public func update(position: Double) -> SkipCommand? {
        guard let i = segments.firstIndex(where: { $0.contains(position) && $0.end - position > 0.25 }) else {
            prompt = nil
            return nil
        }
        let segment = segments[i]
        let behavior = SkipPolicy.behavior(for: segment, in: context)
        let action = SkipPolicy.action(for: segment, in: context)

        if behavior == .none {
            prompt = nil
            return nil
        }

        if behavior == .auto, states[i] == .pending, segment.end - position > Self.minimumRemaining {
            states[i] = .autoFired
            prompt = nil
            switch action {
            case .seek(let to): return .seek(to: to)
            case .nextEpisode: return .startNextEpisodeCountdown
            case .finish:
                // Not produced by the policy for .auto, keep the button just in case.
                states[i] = .manual
            }
        }

        if states[i] == .autoFired {
            prompt = nil
            return nil
        }

        prompt = SkipPrompt(segment: segment, action: action, title: SkipPolicy.title(for: segment, action: action))
        return nil
    }

    /// The user seeked or cancelled the countdown: never auto-skip a segment twice,
    /// but show the button again for segments that were auto-skipped.
    public func userInteracted() {
        for i in states.indices where states[i] == .autoFired {
            states[i] = .manual
        }
    }

    /// Position from which progress counts as "watched": start of the final credits, if known.
    public var watchedThreshold: Double? {
        segments.first { SkipPolicy.isFinalCredits($0, in: context) }?.start
    }
}
