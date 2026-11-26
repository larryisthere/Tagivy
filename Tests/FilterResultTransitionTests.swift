import XCTest
@testable import Tagivy

final class FilterResultTransitionTests: XCTestCase {
    private func ids(_ range: ClosedRange<Int>) -> [String] { range.map { "v\($0)" } }

    func testOnlyFilterChangesAnimate() {
        XCTAssertEqual(
            FilterResultTransition.style(isFilterChange: false, reduceMotion: false, oldVisibleIDs: ids(1...4), newIDs: ["v1"]),
            .instant
        )
        XCTAssertEqual(
            FilterResultTransition.style(isFilterChange: true, reduceMotion: false, oldVisibleIDs: ids(1...4), newIDs: ["v1"]),
            .animated
        )
    }

    func testReducedMotionCrossfadesInsteadOfMoving() {
        XCTAssertEqual(
            FilterResultTransition.style(isFilterChange: true, reduceMotion: true, oldVisibleIDs: ids(1...4), newIDs: ["v1"]),
            .crossfade
        )
    }

    func testNothingOnScreenBeforeOrAfterSwitchesAtOnce() {
        XCTAssertEqual(
            FilterResultTransition.style(isFilterChange: true, reduceMotion: false, oldVisibleIDs: [], newIDs: []),
            .instant
        )
    }

    func testTooManyOnScreenThumbnailsSwitchAtOnceBeforeAnySnapshot() {
        let onScreen = ids(1...(FilterResultTransition.maxAnimatedItemsPerRole + 1))
        XCTAssertEqual(
            FilterResultTransition.style(isFilterChange: true, reduceMotion: false, oldVisibleIDs: onScreen, newIDs: Set(onScreen)),
            .instant
        )
        XCTAssertEqual(
            FilterResultTransition.style(isFilterChange: true, reduceMotion: false, oldVisibleIDs: onScreen, newIDs: []),
            .instant
        )
    }

    func testNarrowingKeepsSurvivorsAndRemovesTheRest() {
        let plan = FilterResultTransition.plan(
            oldVisibleIDs: ids(1...6),
            newVisibleIDs: ["v2", "v5"],
            newIDs: ["v2", "v5", "v40"]
        )
        XCTAssertEqual(plan, .init(staying: ["v2", "v5"], removed: ["v1", "v3", "v4", "v6"], inserted: []))
    }

    func testWideningFadesInWhatWasNotOnScreen() {
        let plan = FilterResultTransition.plan(
            oldVisibleIDs: ["v2", "v5"],
            newVisibleIDs: ids(1...6),
            newIDs: Set(ids(1...20))
        )
        XCTAssertEqual(plan, .init(staying: ["v2", "v5"], removed: [], inserted: ["v1", "v3", "v4", "v6"]))
    }

    func testStayingVideoThatMovesOffScreenStillGlides() {
        let plan = FilterResultTransition.plan(oldVisibleIDs: ["v1", "v2"], newVisibleIDs: ["v9", "v1"], newIDs: ["v9", "v1", "v2"])
        XCTAssertEqual(plan, .init(staying: ["v1", "v2"], removed: [], inserted: ["v9"]))
    }

    func testMostlyReplacedScreenSwitchesAtOnce() {
        XCTAssertNil(FilterResultTransition.plan(oldVisibleIDs: ids(1...9), newVisibleIDs: ids(9...17), newIDs: Set(ids(9...17))))
        XCTAssertNotNil(FilterResultTransition.plan(oldVisibleIDs: ids(1...9), newVisibleIDs: ids(5...13), newIDs: Set(ids(5...13))))
    }

    func testTooManyArrivalsSwitchAtOnce() {
        let arriving = ids(1...(FilterResultTransition.maxAnimatedItemsPerRole + 2))
        XCTAssertNil(FilterResultTransition.plan(oldVisibleIDs: ["v1"], newVisibleIDs: arriving, newIDs: Set(arriving)))
    }
}
