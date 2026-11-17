import AVFoundation
import Foundation
import Observation
import SkipTVKit
import UIKit

/// Drives one playback session: mpv, detector segments, Plex progress and episode chaining.
@MainActor
@Observable
final class PlayerModel {
    struct NextEpisodeCard: Equatable {
        var item: PlexItem
        /// Seconds left before autoplay; nil when waiting for the user.
        var secondsLeft: Int?
    }

    // MARK: State for the UI

    private(set) var item: PlexItem
    private(set) var position: Double = 0
    private(set) var duration: Double = 0
    private(set) var isPaused = false
    private(set) var isBuffering = true
    private(set) var isLoading = true
    private(set) var errorMessage: String?
    private(set) var skipPrompt: SkipPrompt?
    private(set) var nextCard: NextEpisodeCard?
    private(set) var audioTracks: [MediaTrack] = []
    private(set) var subtitleTracks: [MediaTrack] = []
    private(set) var selectedAudio: Int?
    private(set) var selectedSubtitle: Int?
    private(set) var nextEpisode: PlexItem?
    /// Detected segments of the current file (shown on the progress bar).
    private(set) var segments: [Segment] = []
    var controlsVisible = true
    var tracksPanelVisible = false
    /// Set when the session is over and the screen should close.
    private(set) var finished = false

    // MARK: Dependencies

    let player: MPVPlayer
    private let api: PlexServerAPI
    private let detector: DetectorClient?
    private let settings: AppSettings
    private var startAt: Double?

    private var skip: SkipController?
    private var tracker = ProgressTracker()
    private var countdownTask: Task<Void, Never>?
    private var hideControlsTask: Task<Void, Never>?
    private var loadTask: Task<Void, Never>?
    private var pendingSeekTarget: Double?
    /// mpv pauses itself at the end of file (keep-open); that pause must not freeze the countdown.
    private var reachedEnd = false
    private var observers: [NSObjectProtocol] = []

    init(request: PlaybackRequest, api: PlexServerAPI, detector: DetectorClient?, settings: AppSettings) {
        item = request.item
        startAt = request.startAt
        self.api = api
        self.detector = detector
        self.settings = settings
        player = MPVPlayer(options: MPVOptions(fastRendering: settings.fastRendering))
        player.delegate = self
        observeAppState()
    }

    // MARK: Lifecycle

    func start() {
        try? AVAudioSession.sharedInstance().setCategory(.playback, mode: .moviePlayback)
        try? AVAudioSession.sharedInstance().setActive(true)
        UIApplication.shared.isIdleTimerDisabled = true
        load(item, startAt: startAt)
    }

    private func load(_ requested: PlexItem, startAt: Double?) {
        loadTask?.cancel()
        countdownTask?.cancel()
        nextCard = nil
        skipPrompt = nil
        reachedEnd = false
        isLoading = true
        isBuffering = true
        errorMessage = nil
        position = startAt ?? 0
        duration = requested.duration.map { Double($0) / 1000 } ?? 0
        item = requested
        audioTracks = []
        subtitleTracks = []
        segments = []
        skip = nil
        nextEpisode = nil
        showControls()

        loadTask = Task { [weak self] in
            guard let self else { return }
            let full = (try? await self.api.item(ratingKey: requested.ratingKey)) ?? requested
            guard !Task.isCancelled else { return }
            guard let part = full.primaryPart, let url = self.api.directPlayURL(part) else {
                self.errorMessage = "У этого элемента нет файла для воспроизведения."
                self.isLoading = false
                return
            }
            self.item = full

            async let segments = self.detector?.segments(ratingKey: full.ratingKey) ?? []
            async let next = self.findNextEpisode(after: full)
            let (found, nextItem) = await (segments, next)
            guard !Task.isCancelled else { return }

            self.nextEpisode = nextItem
            let context = SkipContext(mode: self.settings.skipMode, item: full, hasNextEpisode: nextItem != nil)
            let controller = SkipController(segments: found, context: context)
            self.skip = controller
            self.segments = controller.segments
            self.tracker = ProgressTracker(creditsStart: controller.watchedThreshold)
            self.player.load(url, start: startAt)
        }
    }

    private func findNextEpisode(after item: PlexItem) async -> PlexItem? {
        guard item.type == .episode, let show = item.grandparentRatingKey else { return nil }
        guard let episodes = try? await api.allEpisodes(showRatingKey: show) else { return nil }
        return EpisodeNavigator.next(after: item, in: episodes)
    }

    /// Stops playback, reports the final position and closes the screen.
    func close() {
        guard !finished else { return }
        finished = true
        reportStopped()
        teardown()
    }

    private func teardown() {
        loadTask?.cancel()
        countdownTask?.cancel()
        hideControlsTask?.cancel()
        for observer in observers {
            NotificationCenter.default.removeObserver(observer)
        }
        observers = []
        player.delegate = nil
        player.shutdown()
        UIApplication.shared.isIdleTimerDisabled = false
    }

    private func reportStopped() {
        let item = item
        let position = position
        let duration = duration
        let watched = tracker.isWatched(position: position, duration: duration)
        let alreadyScrobbled = tracker.scrobbled
        let api = api
        Task {
            try? await api.reportTimeline(item: item, state: .stopped, position: position, duration: duration)
            if watched, !alreadyScrobbled {
                try? await api.markWatched(ratingKey: item.ratingKey)
            }
        }
    }

    private func observeAppState() {
        let center = NotificationCenter.default
        observers.append(center.addObserver(forName: UIApplication.didEnterBackgroundNotification, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.player.pause()
                self?.player.setVideoEnabled(false)
            }
        })
        observers.append(center.addObserver(forName: UIApplication.willEnterForegroundNotification, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.player.setVideoEnabled(true)
            }
        })
    }

    // MARK: User actions

    func togglePause() {
        isPaused ? player.play() : player.pause()
        showControls()
    }

    func seek(by seconds: Double) {
        let base = pendingSeekTarget ?? position
        var target = base + seconds
        if duration > 0 { target = min(target, duration - 1) }
        target = max(0, target)
        pendingSeekTarget = target
        position = target
        skip?.userInteracted()
        player.seek(to: target)
        showControls()
    }

    func performSkip() {
        guard let prompt = skipPrompt else { return }
        skip?.userInteracted()
        perform(prompt.action)
    }

    private func perform(_ action: SkipAction) {
        switch action {
        case .seek(let to):
            pendingSeekTarget = to
            position = to
            skipPrompt = nil
            player.seek(to: to)
        case .nextEpisode:
            playNext()
        case .finish:
            markWatchedNow()
            close()
        }
    }

    func playNext() {
        guard let next = nextEpisode else {
            close()
            return
        }
        reportStopped()
        markWatchedNow()
        tracker = ProgressTracker()
        load(next, startAt: ResumePolicy.resumePosition(for: next))
    }

    /// The user dismissed the "Next episode" card: keep watching the credits.
    func cancelNextEpisode() {
        countdownTask?.cancel()
        countdownTask = nil
        nextCard = nil
        skip?.userInteracted()
        if let skip {
            skipPrompt = skip.prompt
        }
    }

    func selectAudio(_ track: MediaTrack?) {
        player.selectAudio(track?.id)
        selectedAudio = track?.id
    }

    func selectSubtitle(_ track: MediaTrack?) {
        player.selectSubtitle(track?.id)
        selectedSubtitle = track?.id
    }

    func showControls() {
        controlsVisible = true
        hideControlsTask?.cancel()
        hideControlsTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(5))
            guard !Task.isCancelled, let self, !self.isPaused, !self.tracksPanelVisible else { return }
            self.controlsVisible = false
        }
    }

    func hideControls() {
        hideControlsTask?.cancel()
        controlsVisible = false
    }

    private func markWatchedNow() {
        guard !tracker.scrobbled else { return }
        let api = api
        let key = item.ratingKey
        Task { try? await api.markWatched(ratingKey: key) }
    }

    // MARK: Countdown

    private func startNextEpisodeCountdown() {
        guard let next = nextEpisode else { return }
        guard settings.autoplayNext else {
            nextCard = NextEpisodeCard(item: next, secondsLeft: nil)
            return
        }
        let total = settings.nextEpisodeCountdown
        nextCard = NextEpisodeCard(item: next, secondsLeft: total)
        countdownTask?.cancel()
        countdownTask = Task { [weak self] in
            for remaining in stride(from: total - 1, through: 0, by: -1) {
                try? await Task.sleep(for: .seconds(1))
                guard !Task.isCancelled, let self else { return }
                // Pausing freezes the countdown.
                while self.isPaused, !self.reachedEnd {
                    try? await Task.sleep(for: .milliseconds(300))
                    if Task.isCancelled { return }
                }
                self.nextCard?.secondsLeft = remaining
            }
            guard !Task.isCancelled, let self else { return }
            self.playNext()
        }
    }

    // MARK: Ticks

    private func tick() {
        guard let skip, !isLoading else { return }
        if let command = skip.update(position: position) {
            switch command {
            case .seek(let to):
                perform(.seek(to: to))
            case .startNextEpisodeCountdown:
                startNextEpisodeCountdown()
            }
        }
        if nextCard == nil {
            skipPrompt = skip.prompt
        } else {
            skipPrompt = nil
        }
        report(isPaused ? .paused : (isBuffering ? .buffering : .playing))
    }

    private func report(_ state: PlaybackState) {
        let reports = tracker.update(state: state, position: position, duration: duration > 0 ? duration : nil)
        guard !reports.isEmpty else { return }
        let api = api
        let item = item
        let duration = duration
        Task {
            for report in reports {
                switch report {
                case .timeline(let state, let position):
                    try? await api.reportTimeline(item: item, state: state, position: position, duration: duration)
                case .scrobble:
                    try? await api.markWatched(ratingKey: item.ratingKey)
                }
            }
        }
    }

    private func applyDefaultTracks() {
        let tracks = player.tracks()
        audioTracks = tracks.filter { $0.kind == .audio }
        subtitleTracks = tracks.filter { $0.kind == .subtitle }
        let audio = TrackSelector.defaultAudio(tracks)
        let subtitle = TrackSelector.defaultSubtitle(tracks, audio: audio)
        selectAudio(audio)
        selectSubtitle(subtitle)
    }
}

extension PlayerModel: MPVPlayerDelegate {
    func mpvTimeChanged(_ position: Double) {
        guard position.isFinite else { return }
        if let target = pendingSeekTarget {
            // Ignore stale positions until the seek lands.
            if abs(position - target) > 2 { return }
            pendingSeekTarget = nil
        }
        self.position = position
        tick()
    }

    func mpvDurationChanged(_ duration: Double) {
        guard duration.isFinite, duration > 0 else { return }
        self.duration = duration
        skip?.setDuration(duration)
    }

    func mpvPauseChanged(_ paused: Bool) {
        isPaused = paused
        if paused { controlsVisible = true } else { showControls() }
        report(paused ? .paused : .playing)
    }

    func mpvBufferingChanged(_ buffering: Bool) {
        isBuffering = buffering
    }

    func mpvFileLoaded() {
        isLoading = false
        isBuffering = false
        applyDefaultTracks()
        player.play()
    }

    func mpvSeekFinished() {
        pendingSeekTarget = nil
        isBuffering = false
    }

    func mpvReachedEnd() {
        reachedEnd = true
        guard !isLoading, nextCard == nil else { return }
        markWatchedNow()
        if nextEpisode != nil, settings.autoplayNext {
            startNextEpisodeCountdown()
        } else if nextEpisode != nil {
            nextCard = NextEpisodeCard(item: nextEpisode!, secondsLeft: nil)
        } else {
            close()
        }
    }

    func mpvFailed(_ message: String) {
        isLoading = false
        errorMessage = "Не удалось воспроизвести файл: \(message)"
    }
}
