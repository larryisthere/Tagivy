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

    func testOnlyTheFirstResultOfTheLatestFilterChangeAnimates() {
        var generations = FilterQueryGenerations()
        XCTAssertFalse(generations.resultIsFilterChange(generation: 0), "initial load")
        let first = generations.next()
        XCTAssertTrue(generations.resultIsFilterChange(generation: first))
        XCTAssertFalse(generations.resultIsFilterChange(generation: first), "a later refresh of the same filter")
    }

    func testRefreshFetchedBeforeTheFilterChangeDoesNotTakeItsTransition() {
        var generations = FilterQueryGenerations()
        let old = generations.next()
        XCTAssertTrue(generations.resultIsFilterChange(generation: old))
        let current = generations.next()
        XCTAssertFalse(generations.resultIsFilterChange(generation: old), "import refresh started under the old filter")
        XCTAssertTrue(generations.resultIsFilterChange(generation: current))
    }

    func testSupersededFilterChangeDoesNotAnimate() {
        var generations = FilterQueryGenerations()
        let superseded = generations.next()
        let latest = generations.next()
        XCTAssertFalse(generations.resultIsFilterChange(generation: superseded))
        XCTAssertTrue(generations.resultIsFilterChange(generation: latest))
    }

    func testExpectedScreenKeepsTheScrollPosition() {
        XCTAssertEqual(FilterResultTransition.expectedOnScreenRange(firstOldIndex: 20, onScreenCount: 12, newCount: 100), 20..<32)
        XCTAssertEqual(FilterResultTransition.expectedOnScreenRange(firstOldIndex: 20, onScreenCount: 12, newCount: 25), 20..<25)
        XCTAssertEqual(FilterResultTransition.expectedOnScreenRange(firstOldIndex: 20, onScreenCount: 12, newCount: 5), 5..<5)
    }

    func testOnlyLeavingThumbnailsAreSnapshotted() {
        let leaving = FilterResultTransition.idsExpectedToLeaveScreen(
            oldVisibleIDs: ["gone", "top", "middle", "pushedDown"],
            newIndices: ["top": 0, "middle": 5, "pushedDown": 40],
            expectedOnScreen: 0..<12,
            margin: 4
        )
        XCTAssertEqual(leaving, ["gone", "pushedDown"])
    }

    func testThumbnailsNearAScrolledScreenEdgeAreSnapshotted() {
        let leaving = FilterResultTransition.idsExpectedToLeaveScreen(
            oldVisibleIDs: ["firstRow", "middle", "lastRow"],
            newIndices: ["firstRow": 20, "middle": 26, "lastRow": 31],
            expectedOnScreen: 20..<32,
            margin: 4
        )
        XCTAssertEqual(leaving, ["firstRow", "lastRow"])
    }
}
