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

    @MainActor
    func testGridGlidesStayingThumbnailsAndFadesInOnlyNewOnes() throws {
        guard NSWorkspace.shared.accessibilityDisplayShouldReduceMotion == false else { return }
        let (grid, window, collection) = try makeHostedGrid(thumbnailURL: { _ in nil })
        defer { window.close() }
        grid.setVideos(ids(0...11).map(video))
        collection.layoutSubtreeIfNeeded()

        grid.setVideos(["v0", "new1", "v2", "v4", "new2", "v5"].map(video), isFilterChange: true)

        let staying: Set = ["v0", "v2", "v4", "v5"]
        var seen = Set<String>()
        for item in collection.visibleItems() {
            let id = try videoID(shownBy: item)
            seen.insert(id)
            let keys = item.view.layer?.animationKeys() ?? []
            if staying.contains(id) {
                XCTAssertFalse(keys.contains(FilterResultTransition.insertionAnimationKey), "\(id) stays at full opacity")
            } else {
                XCTAssertEqual(keys, [FilterResultTransition.insertionAnimationKey], "\(id) fades in")
            }
        }
        XCTAssertEqual(seen, staying.union(["new1", "new2"]))
        let overlay = try XCTUnwrap(grid.view.descendants.first { $0 is FilterResultOverlayView })
        XCTAssertEqual(overlay.layer?.sublayers?.count, 8, "one snapshot per removed thumbnail")
    }

    @MainActor
    func testQuickSecondChangeLandsAWaitingNewThumbnailAtFullOpacity() throws {
        guard NSWorkspace.shared.accessibilityDisplayShouldReduceMotion == false else { return }
        // A missing file keeps each new thumbnail waiting for an image that never arrives.
        let missing = FileManager.default.temporaryDirectory.appendingPathComponent("missing-\(UUID().uuidString).jpg")
        let (grid, window, collection) = try makeHostedGrid(thumbnailURL: { _ in missing })
        defer { window.close() }
        grid.setVideos(ids(0...3).map(video))
        collection.layoutSubtreeIfNeeded()

        grid.setVideos(["v0", "new1", "v1"].map(video), isFilterChange: true)
        grid.setVideos(["v0", "new1"].map(video), isFilterChange: true)
        RunLoop.main.run(until: Date().addingTimeInterval(0.1))

        let new = try XCTUnwrap(collection.visibleItems().first { try videoID(shownBy: $0) == "new1" })
        XCTAssertNil(new.view.layer?.animation(forKey: FilterResultTransition.insertionAnimationKey))
    }

    @MainActor
    private func makeHostedGrid(
        thumbnailURL: @escaping (VideoRecord) -> URL?
    ) throws -> (VideoGridViewController, NSWindow, NSCollectionView) {
        let suiteName = "FilterResultTransitionTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        addTeardownBlock { defaults.removePersistentDomain(forName: suiteName) }
        defaults.set(180.0, forKey: "VideoGridItemWidth")
        let grid = VideoGridViewController(
            onOpenVideo: { _ in }, onRevealVideo: { _ in }, onCopyPath: { _ in },
            onRelinkVideo: { _ in }, onRetryRelinkVideo: { _ in }, onPreviewVideos: { _ in },
            onSelectionChanged: { _ in }, thumbnailURL: thumbnailURL, resolveVideos: { _ in .empty },
            onAssignTagID: { _, _ in },
            onCancelImport: {}, onImportDroppedItems: { _ in }, onRemoveVideos: { _, _ in },
            onUndoLastMutation: {}, onDismissNotification: {},
            defaults: defaults
        )
        let window = NSWindow(
            contentRect: CGRect(x: 0, y: 0, width: 1000, height: 800),
            styleMask: [.titled], backing: .buffered, defer: false
        )
        window.isReleasedWhenClosed = false
        window.contentViewController = grid
        window.setContentSize(NSSize(width: 1000, height: 800))
        let collection = try XCTUnwrap(grid.view.descendants.compactMap { $0 as? NSCollectionView }.first)
        return (grid, window, collection)
    }

    private func video(_ id: String) -> VideoRecord {
        VideoRecord(
            id: id, libraryID: "test", relativePath: "\(id).mov", filename: "\(id).mov",
            fileExtension: "mov", fileSize: 1, creationDate: nil, modificationDate: nil,
            duration: 1, width: 320, height: 180, thumbnailID: nil, metadataStatus: .completed,
            thumbnailStatus: .completed, firstIndexedAt: .distantPast, availability: .available
        )
    }

    @MainActor
    private func videoID(shownBy item: NSCollectionViewItem) throws -> String {
        try XCTUnwrap(item.view.descendants.compactMap { ($0 as? NSTextField)?.stringValue }
            .first { $0.hasSuffix(".mov") }).replacingOccurrences(of: ".mov", with: "")
    }
}

private extension NSView {
    var descendants: [NSView] { subviews + subviews.flatMap(\.descendants) }
}
