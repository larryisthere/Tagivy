import XCTest
@testable import Tagivy

final class GridReflowTests: XCTestCase {
    func testColumnCountFitsItemsWithSpacingBetweenThem() {
        XCTAssertEqual(GridReflow.columnCount(availableWidth: 1000, itemWidth: 180, interitemSpacing: 16), 5)
        XCTAssertEqual(GridReflow.columnCount(availableWidth: 4 * 180 + 3 * 16, itemWidth: 180, interitemSpacing: 16), 4)
        XCTAssertEqual(GridReflow.columnCount(availableWidth: 4 * 180 + 3 * 16 - 1, itemWidth: 180, interitemSpacing: 16), 3)
    }

    func testNarrowGridStillShowsOneColumn() {
        XCTAssertEqual(GridReflow.columnCount(availableWidth: 100, itemWidth: 280, interitemSpacing: 16), 1)
        XCTAssertEqual(GridReflow.columnCount(availableWidth: 0, itemWidth: 150, interitemSpacing: 16), 1)
    }

    func testOnlyAColumnChangeGlides() {
        XCTAssertFalse(GridReflow.shouldGlide(fromColumns: 5, toColumns: 5, reduceMotion: false))
        XCTAssertTrue(GridReflow.shouldGlide(fromColumns: 5, toColumns: 4, reduceMotion: false))
        XCTAssertTrue(GridReflow.shouldGlide(fromColumns: 4, toColumns: 5, reduceMotion: false))
    }

    func testReduceMotionNeverGlides() {
        XCTAssertFalse(GridReflow.shouldGlide(fromColumns: 5, toColumns: 4, reduceMotion: true))
    }

    func testGlideIsShortEnoughNotToDelayResizing() {
        XCTAssertLessThanOrEqual(GridReflow.duration, 0.25)
    }

    @MainActor
    func testGlideMovesOnlyTheTopLeftCornerInAStraightLine() throws {
        let layer = CALayer()
        GridReflow.glide(layer, from: CGSize(width: 780, height: -222))
        let animation = try XCTUnwrap(layer.animation(forKey: GridReflow.glideAnimationKey) as? CABasicAnimation)
        XCTAssertEqual(animation.keyPath, "transform.translation")
        XCTAssertEqual((animation.fromValue as? NSValue)?.sizeValue, CGSize(width: 780, height: -222))
        XCTAssertEqual((animation.toValue as? NSValue)?.sizeValue, .zero)
        XCTAssertEqual(layer.animationKeys(), [GridReflow.glideAnimationKey])

        GridReflow.glide(layer, from: CGSize(width: 0.2, height: 0))
        XCTAssertNil(layer.animationKeys())
    }

    @MainActor
    func testResizingDoesNotGlideAndAZoomStepGlides() throws {
        guard NSWorkspace.shared.accessibilityDisplayShouldReduceMotion == false else { return }
        let suiteName = "GridReflowTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        defaults.set(180.0, forKey: "VideoGridItemWidth")
        let grid = VideoGridViewController(
            onOpenVideo: { _ in }, onRevealVideos: { _ in }, onCopyPaths: { _ in },
            onRelinkVideo: { _ in }, onRetryRelinkVideo: { _ in }, onPreviewVideos: { _ in },
            onSelectionChanged: { _ in }, thumbnailURL: { _ in nil }, resolveVideos: { _ in .empty },
            onAssignTagID: { _, _ in },
            onCancelImport: {}, onImportDroppedItems: { _ in }, onRemoveVideos: { _, _ in },
            onUndoLastMutation: {}, onDismissNotification: {},
            defaults: defaults
        )
        let window = NSWindow(
            contentRect: CGRect(x: 0, y: 0, width: 1000, height: 800),
            styleMask: [.titled], backing: .buffered, defer: false
        )
        window.contentViewController = grid
        window.setContentSize(NSSize(width: 1000, height: 800))
        grid.setVideos((0..<12).map { index in
            VideoRecord(
                id: "v\(index)", libraryID: "test", relativePath: "V\(index).mov", filename: "V\(index).mov",
                fileExtension: "mov", fileSize: 1, creationDate: nil, modificationDate: nil,
                duration: 1, width: 320, height: 180, thumbnailID: nil, metadataStatus: .completed,
                thumbnailStatus: .completed, firstIndexedAt: .distantPast, availability: .available
            )
        })
        let collection = try XCTUnwrap(grid.view.descendants.compactMap { $0 as? NSCollectionView }.first)
        func itemViews() -> [Int: NSView] {
            collection.layoutSubtreeIfNeeded()
            return Dictionary(uniqueKeysWithValues: collection.visibleItems().compactMap { item in
                collection.indexPath(for: item).map { ($0.item, item.view) }
            })
        }
        func glide(of view: NSView) -> CGSize? {
            (view.layer?.animation(forKey: GridReflow.glideAnimationKey) as? CABasicAnimation)
                .flatMap { $0.fromValue as? NSValue }?.sizeValue
        }

        // 960 points for thumbnails: a saved 180-point width becomes 4 columns, applied without gliding.
        let before = itemViews().mapValues(\.frame)
        XCTAssertEqual(grid.displayedColumnCount, 4)
        XCTAssertTrue(itemViews().values.allSatisfy { $0.layer?.animationKeys() == nil })

        grid.zoomIn()
        XCTAssertEqual(grid.displayedColumnCount, 3)
        let after = itemViews()
        XCTAssertGreaterThan(after.values.compactMap(glide(of:)).count, 0)
        for (index, view) in after {
            XCTAssertEqual(view.layer?.animationKeys() ?? [], glide(of: view) == nil ? [] : [GridReflow.glideAnimationKey])
            guard let start = before[index] else { continue }
            let travel = CGSize(width: start.minX - view.frame.minX, height: start.minY - view.frame.minY)
            XCTAssertEqual(glide(of: view) ?? .zero, travel, "item \(index)")
        }
        XCTAssertNil(glide(of: try XCTUnwrap(after[0])))
    }
}

@MainActor
final class GridColumnZoomTests: XCTestCase {
    func testItemWidthFillsTheRowExactly() {
        // 4 × 228 + 3 × 16 = 960
        XCTAssertEqual(GridColumns.itemWidth(columns: 4, availableWidth: 960, interitemSpacing: 16), 228)
        XCTAssertEqual(GridColumns.itemWidth(columns: 1, availableWidth: 960, interitemSpacing: 16), 960)
        // Fractions round down so the last thumbnail never wraps.
        XCTAssertEqual(GridColumns.itemWidth(columns: 3, availableWidth: 961, interitemSpacing: 16), 309)
        for columns in 1...6 {
            let width = GridColumns.itemWidth(columns: columns, availableWidth: 961, interitemSpacing: 16)
            XCTAssertEqual(GridReflow.columnCount(availableWidth: 961, itemWidth: width, interitemSpacing: 16), columns)
        }
    }

    func testMaximumColumnsKeepThumbnailsAtLeastTheMinimumWidth() {
        XCTAssertEqual(GridColumns.maximumCount(availableWidth: 960, minimumItemWidth: 150, interitemSpacing: 16), 5)
        XCTAssertEqual(GridColumns.maximumCount(availableWidth: 100, minimumItemWidth: 150, interitemSpacing: 16), 1)
    }

    func testZoomStepsOneColumnAndStopsAtTheEnds() {
        XCTAssertEqual(GridColumns.zoomedIn(from: 4, maximum: 5), 3)
        XCTAssertEqual(GridColumns.zoomedIn(from: 1, maximum: 5), 1)
        XCTAssertEqual(GridColumns.zoomedOut(from: 4, maximum: 5), 5)
        XCTAssertEqual(GridColumns.zoomedOut(from: 5, maximum: 5), 5)
        // A narrower window lowers the maximum; the count follows it down.
        XCTAssertEqual(GridColumns.zoomedOut(from: 7, maximum: 5), 5)
    }

    func testSliderRunsFromMostColumnsToOneAndSnaps() {
        XCTAssertEqual(GridColumns.columns(forSliderValue: 1, maximum: 5), 5)
        XCTAssertEqual(GridColumns.columns(forSliderValue: 5, maximum: 5), 1)
        XCTAssertEqual(GridColumns.columns(forSliderValue: 2.4, maximum: 5), 4)
        XCTAssertEqual(GridColumns.columns(forSliderValue: 2.6, maximum: 5), 3)
        for columns in 1...5 {
            XCTAssertEqual(GridColumns.columns(
                forSliderValue: GridColumns.sliderValue(forColumns: columns, maximum: 5),
                maximum: 5
            ), columns)
        }
    }

    func testResizingKeepsTheColumnCountAndFillsTheWidth() throws {
        let suiteName = "GridColumnZoomTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let (grid, window) = makeGrid(defaults: defaults, width: 1000)
        grid.setColumnCount(3)
        XCTAssertEqual(defaults.integer(forKey: "VideoGridColumnCount"), 3)

        window.setContentSize(NSSize(width: 1300, height: 800))
        XCTAssertEqual(grid.displayedColumnCount, 3)
        XCTAssertEqual(try itemWidth(grid), GridColumns.itemWidth(columns: 3, availableWidth: 1260, interitemSpacing: 16))

        // Too narrow for 3 thumbnails of the minimum width: fewer columns, and 3 again when it widens.
        window.setContentSize(NSSize(width: 400, height: 800))
        XCTAssertEqual(grid.displayedColumnCount, 2)
        window.setContentSize(NSSize(width: 1000, height: 800))
        XCTAssertEqual(grid.displayedColumnCount, 3)
    }

    func testSavedColumnCountIsRestored() throws {
        let suiteName = "GridColumnZoomTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        defaults.set(2, forKey: "VideoGridColumnCount")
        defaults.set(150.0, forKey: "VideoGridItemWidth")

        XCTAssertEqual(makeGrid(defaults: defaults, width: 1000).0.displayedColumnCount, 2)
    }

    func testActualSizeReturnsToTheDefaultWidthsColumns() throws {
        let suiteName = "GridColumnZoomTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let grid = makeGrid(defaults: defaults, width: 1000).0
        XCTAssertEqual(grid.displayedColumnCount, 4)
        XCTAssertFalse(grid.canResetZoom)

        grid.zoomOut()
        XCTAssertEqual(grid.displayedColumnCount, 5)
        XCTAssertFalse(grid.canZoomOut)
        XCTAssertTrue(grid.canResetZoom)

        grid.resetZoom()
        XCTAssertEqual(grid.displayedColumnCount, 4)
    }

    private func itemWidth(_ grid: VideoGridViewController) throws -> Double {
        let collection = try XCTUnwrap(grid.view.descendants.compactMap { $0 as? NSCollectionView }.first)
        return try XCTUnwrap(collection.collectionViewLayout as? NSCollectionViewFlowLayout).itemSize.width
    }

    private func makeGrid(defaults: UserDefaults, width: CGFloat) -> (VideoGridViewController, NSWindow) {
        let grid = VideoGridViewController(
            onOpenVideo: { _ in }, onRevealVideos: { _ in }, onCopyPaths: { _ in },
            onRelinkVideo: { _ in }, onRetryRelinkVideo: { _ in }, onPreviewVideos: { _ in },
            onSelectionChanged: { _ in }, thumbnailURL: { _ in nil }, resolveVideos: { _ in .empty },
            onAssignTagID: { _, _ in },
            onCancelImport: {}, onImportDroppedItems: { _ in }, onRemoveVideos: { _, _ in },
            onUndoLastMutation: {}, onDismissNotification: {},
            defaults: defaults
        )
        let window = NSWindow(
            contentRect: CGRect(x: 0, y: 0, width: width, height: 800),
            styleMask: [.titled, .resizable], backing: .buffered, defer: false
        )
        window.contentViewController = grid
        window.setContentSize(NSSize(width: width, height: 800))
        grid.view.layoutSubtreeIfNeeded()
        return (grid, window)
    }
}

private extension NSView {
    var descendants: [NSView] { subviews + subviews.flatMap(\.descendants) }
}
