import XCTest
@testable import SkipTVKit

final class SkipPolicyTests: XCTestCase {
    let intro = Segment(type: .intro, start: 17.5, end: 61.7)
    let credits = Segment(type: .credits, start: 2909.1, end: 2987.9)
    let recap = Segment(type: .recap, start: 0, end: 15)

    func context(
        _ mode: SkipMode = .auto,
        episode: Bool = true,
        first: Bool = false,
        next: Bool = true,
        duration: Double? = 2990
    ) -> SkipContext {
        SkipContext(mode: mode, isEpisode: episode, isFirstEpisodeOfSeason: first, hasNextEpisode: next, duration: duration)
    }

    // MARK: Policy

    func testAutoModeSkipsIntroAndCreditsOfRegularEpisode() {
        XCTAssertEqual(SkipPolicy.behavior(for: intro, in: context()), .auto)
        XCTAssertEqual(SkipPolicy.behavior(for: credits, in: context()), .auto)
        XCTAssertEqual(SkipPolicy.action(for: intro, in: context()), .seek(to: 61.7))
        XCTAssertEqual(SkipPolicy.action(for: credits, in: context()), .nextEpisode)
    }

    func testFirstEpisodeOfSeasonGetsButtons() {
        let ctx = context(first: true)
        XCTAssertEqual(SkipPolicy.behavior(for: intro, in: ctx), .button)
        XCTAssertEqual(SkipPolicy.behavior(for: credits, in: ctx), .button)
    }

    func testButtonMode() {
        XCTAssertEqual(SkipPolicy.behavior(for: intro, in: context(.button)), .button)
        XCTAssertEqual(SkipPolicy.behavior(for: credits, in: context(.button)), .button)
    }

    func testOffMode() {
        for segment in [intro, credits, recap] {
            XCTAssertEqual(SkipPolicy.behavior(for: segment, in: context(.off)), .none)
        }
    }

    func testRecapAndPreviewAreButtonOnly() {
        XCTAssertEqual(SkipPolicy.behavior(for: recap, in: context()), .button)
        XCTAssertEqual(SkipPolicy.behavior(for: Segment(type: .preview, start: 2988, end: 2990), in: context()), .button)
        XCTAssertEqual(SkipPolicy.title(for: recap, action: .seek(to: 15)), "Пропустить пересказ")
    }

    func testMoviesGetButtonsAndCreditsFinish() {
        let movie = context(episode: false, next: false, duration: 7200)
        let movieCredits = Segment(type: .credits, start: 6900, end: 7195)
        XCTAssertEqual(SkipPolicy.behavior(for: movieCredits, in: movie), .button)
        XCTAssertEqual(SkipPolicy.action(for: movieCredits, in: movie), .finish)
        XCTAssertEqual(SkipPolicy.title(for: movieCredits, action: .finish), "Пропустить титры")
    }

    func testLastEpisodeCreditsAreButtonThatFinishes() {
        let ctx = context(next: false)
        XCTAssertEqual(SkipPolicy.behavior(for: credits, in: ctx), .button)
        XCTAssertEqual(SkipPolicy.action(for: credits, in: ctx), .finish)
    }

    func testMidFileCreditsSeekToTheirEnd() {
        // Credits followed by a 3-minute post-credits scene.
        let early = Segment(type: .credits, start: 2600, end: 2810)
        XCTAssertEqual(SkipPolicy.action(for: early, in: context()), .seek(to: 2810))
        XCTAssertEqual(SkipPolicy.behavior(for: early, in: context()), .auto)
        XCTAssertEqual(SkipPolicy.title(for: early, action: .seek(to: 2810)), "Пропустить титры")
    }

    func testContextFromPlexItem() {
        let first = PlexItem(ratingKey: "1", type: .episode, title: "e", index: 1, parentIndex: 2, duration: 3_000_000)
        let ctx = SkipContext(mode: .auto, item: first, hasNextEpisode: true)
        XCTAssertTrue(ctx.isEpisode)
        XCTAssertTrue(ctx.isFirstEpisodeOfSeason)
        XCTAssertEqual(ctx.duration, 3000)

        let movie = PlexItem(ratingKey: "2", type: .movie, title: "m", index: 1)
        XCTAssertFalse(SkipContext(mode: .auto, item: movie, hasNextEpisode: false).isFirstEpisodeOfSeason)
    }

    // MARK: Controller

    func testAutoSkipIntroOnce() {
        let controller = SkipController(segments: [credits, intro], context: context())
        XCTAssertNil(controller.update(position: 5))
        XCTAssertNil(controller.prompt)

        XCTAssertEqual(controller.update(position: 18), .seek(to: 61.7))
        // Still inside while the seek happens: no button, no second command.
        XCTAssertNil(controller.update(position: 18.5))
        XCTAssertNil(controller.prompt)
        XCTAssertNil(controller.update(position: 62))
    }

    func testSeekBackIntoAutoSkippedIntroShowsButton() {
        let controller = SkipController(segments: [intro], context: context())
        XCTAssertEqual(controller.update(position: 20), .seek(to: 61.7))
        controller.update(position: 70)
        controller.userInteracted()
        XCTAssertNil(controller.update(position: 30), "never auto-skips twice")
        XCTAssertEqual(controller.prompt?.title, "Пропустить заставку")
        XCTAssertEqual(controller.prompt?.action, .seek(to: 61.7))
    }

    func testResumeInsideIntroSkips() {
        let controller = SkipController(segments: [intro], context: context())
        XCTAssertEqual(controller.update(position: 40), .seek(to: 61.7))
    }

    func testNoAutoSkipAtTheVeryEndOfSegment() {
        let controller = SkipController(segments: [intro], context: context())
        XCTAssertNil(controller.update(position: 61))
        XCTAssertEqual(controller.prompt?.action, .seek(to: 61.7), "button remains for the last moment")
    }

    func testFirstEpisodeShowsButtonsWithoutCommands() {
        let controller = SkipController(segments: [intro, credits], context: context(first: true))
        XCTAssertNil(controller.update(position: 20))
        XCTAssertEqual(controller.prompt, SkipPrompt(segment: intro, action: .seek(to: 61.7), title: "Пропустить заставку"))
        XCTAssertNil(controller.update(position: 100))
        XCTAssertNil(controller.prompt)
        XCTAssertNil(controller.update(position: 2910))
        XCTAssertEqual(controller.prompt?.action, .nextEpisode)
        XCTAssertEqual(controller.prompt?.title, "Следующая серия")
    }

    func testCreditsStartNextEpisodeCountdown() {
        let controller = SkipController(segments: [intro, credits], context: context())
        XCTAssertEqual(controller.update(position: 2909.5), .startNextEpisodeCountdown)
        XCTAssertNil(controller.update(position: 2911))
        XCTAssertNil(controller.prompt)
        // User cancels the countdown: credits keep playing with a button.
        controller.userInteracted()
        XCTAssertNil(controller.update(position: 2912))
        XCTAssertEqual(controller.prompt?.action, .nextEpisode)
    }

    func testOffModeDoesNothing() {
        let controller = SkipController(segments: [intro, credits], context: context(.off))
        XCTAssertNil(controller.update(position: 20))
        XCTAssertNil(controller.prompt)
        XCTAssertNil(controller.update(position: 2950))
        XCTAssertNil(controller.prompt)
    }

    func testNoSegmentsNoActions() {
        let controller = SkipController(segments: [], context: context())
        XCTAssertNil(controller.update(position: 20))
        XCTAssertNil(controller.prompt)
        XCTAssertNil(controller.watchedThreshold)
    }

    func testDurationRefinesFinalCredits() {
        // Item duration unknown: treated as final credits.
        let controller = SkipController(segments: [Segment(type: .credits, start: 2600, end: 2810)], context: context(duration: nil))
        controller.setDuration(3000)
        XCTAssertEqual(controller.update(position: 2601), .seek(to: 2810))
        XCTAssertNil(controller.watchedThreshold)
    }

    func testWatchedThreshold() {
        let controller = SkipController(segments: [intro, credits], context: context())
        XCTAssertEqual(controller.watchedThreshold, 2909.1)
    }
}
