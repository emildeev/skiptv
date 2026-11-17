import XCTest
@testable import SkipTVKit

final class EpisodeNavigatorTests: XCTestCase {
    var episodes: [PlexItem] = []

    override func setUpWithError() throws {
        episodes = try JSONDecoder().decode(PlexResponse<MetadataContainer>.self, from: fixture("allLeaves")).mediaContainer.metadata
    }

    func episode(_ key: String) -> PlexItem {
        episodes.first { $0.ratingKey == key }!
    }

    func testNextWithinSeasonAndAcrossSeasons() {
        XCTAssertEqual(EpisodeNavigator.next(after: episode("101"), in: episodes)?.ratingKey, "102")
        XCTAssertEqual(EpisodeNavigator.next(after: episode("103"), in: episodes)?.ratingKey, "201")
    }

    func testLastEpisodeHasNoNextAndSpecialsAreSkipped() {
        XCTAssertNil(EpisodeNavigator.next(after: episode("202"), in: episodes), "specials are not next")
        XCTAssertNil(EpisodeNavigator.next(after: episode("900"), in: episodes))
    }

    func testUnknownEpisode() {
        XCTAssertNil(EpisodeNavigator.next(after: PlexItem(ratingKey: "x", type: .episode, title: ""), in: episodes))
    }

    func testOrderIgnoresInputOrder() {
        let shuffled = episodes.reversed() as [PlexItem]
        XCTAssertEqual(EpisodeNavigator.ordered(shuffled).map(\.ratingKey), ["101", "102", "103", "201", "202", "900"])
    }

    func testResumeEpisode() {
        XCTAssertEqual(EpisodeNavigator.resumeEpisode(in: episodes)?.ratingKey, "202", "in progress wins")
        let noProgress = episodes.filter { $0.ratingKey != "202" }
        XCTAssertEqual(EpisodeNavigator.resumeEpisode(in: noProgress)?.ratingKey, "103")
        let allWatched = noProgress.map { item -> PlexItem in
            var item = item
            item.viewCount = 1
            return item
        }
        XCTAssertEqual(EpisodeNavigator.resumeEpisode(in: allWatched)?.ratingKey, "101", "rewatch from the start")
    }
}

final class ProgressTrackerTests: XCTestCase {
    func testTimelineIntervalAndStateChanges() {
        var tracker = ProgressTracker()
        let t0 = Date(timeIntervalSince1970: 1000)
        XCTAssertEqual(tracker.update(state: .playing, position: 0, duration: 100, now: t0), [.timeline(.playing, position: 0)])
        XCTAssertEqual(tracker.update(state: .playing, position: 5, duration: 100, now: t0.addingTimeInterval(5)), [])
        XCTAssertEqual(tracker.update(state: .playing, position: 10, duration: 100, now: t0.addingTimeInterval(10)), [.timeline(.playing, position: 10)])
        XCTAssertEqual(tracker.update(state: .paused, position: 11, duration: 100, now: t0.addingTimeInterval(11)), [.timeline(.paused, position: 11)])
        XCTAssertEqual(tracker.update(state: .paused, position: 11, duration: 100, now: t0.addingTimeInterval(30)), [], "no periodic reports while paused")
    }

    func testScrobbleAtNinetyPercentOnce() {
        var tracker = ProgressTracker()
        let t0 = Date(timeIntervalSince1970: 0)
        _ = tracker.update(state: .playing, position: 0, duration: 100, now: t0)
        XCTAssertEqual(tracker.update(state: .playing, position: 89, duration: 100, now: t0.addingTimeInterval(1)), [])
        XCTAssertEqual(tracker.update(state: .playing, position: 90, duration: 100, now: t0.addingTimeInterval(2)), [.scrobble])
        XCTAssertEqual(tracker.update(state: .playing, position: 95, duration: 100, now: t0.addingTimeInterval(3)), [])
    }

    func testScrobbleAtCreditsStart() {
        var tracker = ProgressTracker(creditsStart: 2909)
        let t0 = Date(timeIntervalSince1970: 0)
        _ = tracker.update(state: .playing, position: 0, duration: 3500, now: t0)
        XCTAssertEqual(tracker.update(state: .playing, position: 2910, duration: 3500, now: t0.addingTimeInterval(1)), [.scrobble])
    }

    func testResumePolicy() {
        XCTAssertNil(ResumePolicy.resumePosition(for: PlexItem(ratingKey: "1", type: .movie, title: "")))
        XCTAssertNil(ResumePolicy.resumePosition(for: PlexItem(ratingKey: "1", type: .movie, title: "", duration: 6_000_000, viewOffset: 10_000)))
        XCTAssertEqual(ResumePolicy.resumePosition(for: PlexItem(ratingKey: "1", type: .movie, title: "", duration: 6_000_000, viewOffset: 615_000)), 615)
        XCTAssertNil(ResumePolicy.resumePosition(for: PlexItem(ratingKey: "1", type: .movie, title: "", duration: 6_000_000, viewOffset: 5_900_000)))
    }

    func testFormatting() {
        XCTAssertEqual(TimeFormat.clock(75), "1:15")
        XCTAssertEqual(TimeFormat.clock(3725), "1:02:05")
        XCTAssertEqual(TimeFormat.clock(-3), "0:00")
        XCTAssertEqual(TimeFormat.runtime(milliseconds: 6_720_000), "1 ч 52 мин")
        XCTAssertEqual(TimeFormat.runtime(milliseconds: 2_880_000), "48 мин")
        XCTAssertEqual(TimeFormat.runtime(milliseconds: 7_200_000), "2 ч")
        XCTAssertNil(TimeFormat.runtime(milliseconds: nil))
    }
}

final class TrackSelectorTests: XCTestCase {
    let engTrueHD = MediaTrack(id: 1, kind: .audio, language: "eng", codec: "truehd", channels: 8, isDefault: true)
    let rusAC3 = MediaTrack(id: 2, kind: .audio, language: "rus", title: "Дубляж", codec: "ac3", channels: 6)
    let rusMVO = MediaTrack(id: 3, kind: .audio, language: "ru", title: "MVO", codec: "aac", channels: 2)
    let rusForced = MediaTrack(id: 1, kind: .subtitle, language: "rus", codec: "subrip", isForced: true)
    let rusFull = MediaTrack(id: 2, kind: .subtitle, language: "rus", codec: "hdmv_pgs_subtitle")
    let engSubs = MediaTrack(id: 3, kind: .subtitle, language: "eng", codec: "subrip", isDefault: true)

    func testRussianAudioPreferredOverDefault() {
        XCTAssertEqual(TrackSelector.defaultAudio([engTrueHD, rusAC3, rusMVO]), rusAC3)
        var defaultMVO = rusMVO
        defaultMVO.isDefault = true
        XCTAssertEqual(TrackSelector.defaultAudio([engTrueHD, rusAC3, defaultMVO]), defaultMVO)
    }

    func testFallbackToFileDefault() {
        let jpn = MediaTrack(id: 2, kind: .audio, language: "jpn")
        XCTAssertEqual(TrackSelector.defaultAudio([jpn, engTrueHD]), engTrueHD)
        XCTAssertEqual(TrackSelector.defaultAudio([jpn]), jpn)
        XCTAssertNil(TrackSelector.defaultAudio([rusFull]))
    }

    func testSubtitlesWithRussianAudio() {
        let tracks = [engTrueHD, rusAC3, rusFull, rusForced, engSubs]
        XCTAssertEqual(TrackSelector.defaultSubtitle(tracks, audio: rusAC3), rusForced)
        XCTAssertNil(TrackSelector.defaultSubtitle([rusFull, engSubs], audio: rusAC3))
    }

    func testSubtitlesWithForeignAudio() {
        XCTAssertEqual(TrackSelector.defaultSubtitle([rusForced, rusFull, engSubs], audio: engTrueHD), rusFull)
        XCTAssertNil(TrackSelector.defaultSubtitle([engSubs], audio: engTrueHD))
    }

    func testDisplayName() {
        XCTAssertEqual(engTrueHD.displayName, "Английский · TrueHD 7.1")
        XCTAssertEqual(rusAC3.displayName, "Русский · AC3 5.1 · Дубляж")
        XCTAssertEqual(rusForced.displayName, "Русский · SRT · форсированные")
        XCTAssertEqual(MediaTrack(id: 4, kind: .subtitle, codec: "hdmv_pgs_subtitle").displayName, "Дорожка 4 · PGS")
    }
}
