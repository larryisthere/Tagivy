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

    func testResizeWithinTheSameColumnsAppliesAtOnce() {
        XCTAssertEqual(GridReflow.animationDuration(fromColumns: 5, toColumns: 5, remainingGlide: 0, reduceMotion: false), 0)
    }

    func testColumnChangeGlides() {
        XCTAssertEqual(GridReflow.animationDuration(fromColumns: 5, toColumns: 4, remainingGlide: 0, reduceMotion: false), GridReflow.duration)
        XCTAssertEqual(GridReflow.animationDuration(fromColumns: 4, toColumns: 5, remainingGlide: 0.1, reduceMotion: false), GridReflow.duration)
    }

    func testResizeDuringAGlideFinishesWithIt() {
        XCTAssertEqual(GridReflow.animationDuration(fromColumns: 4, toColumns: 4, remainingGlide: 0.1, reduceMotion: false), 0.1, accuracy: 0.0001)
    }

    func testReduceMotionNeverGlides() {
        XCTAssertEqual(GridReflow.animationDuration(fromColumns: 5, toColumns: 4, remainingGlide: 0, reduceMotion: true), 0)
        XCTAssertEqual(GridReflow.animationDuration(fromColumns: 4, toColumns: 4, remainingGlide: 0.1, reduceMotion: true), 0)
    }

    func testGlideIsShortEnoughNotToDelayResizing() {
        XCTAssertLessThanOrEqual(GridReflow.duration, 0.25)
    }
    @MainActor
    func testGridGlidesOnlyWhenTheColumnCountChanges() throws {
        guard NSWorkspace.shared.accessibilityDisplayShouldReduceMotion == false else { return }
        let widthKey = "VideoGridItemWidth"
        let savedWidth = UserDefaults.standard.object(forKey: widthKey)
        defer {
            if let savedWidth {
                UserDefaults.standard.set(savedWidth, forKey: widthKey)
            } else {
                UserDefaults.standard.removeObject(forKey: widthKey)
            }
        }
        UserDefaults.standard.set(180.0, forKey: widthKey)
        let grid = VideoGridViewController(
            onOpenVideo: { _ in }, onRevealVideo: { _ in }, onCopyPath: { _ in },
            onRelinkVideo: { _ in }, onRetryRelinkVideo: { _ in }, onPreviewVideos: { _ in },
            onSelectionChanged: { _ in }, thumbnailURL: { _ in nil }, resolveVideos: { _ in .empty },
            onAssignTagID: { _, _ in },
            onCancelImport: {}, onImportDroppedItems: { _ in }, onRemoveVideos: { _, _ in },
            onUndoLastMutation: {}, onDismissNotification: {}
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
        func glidingItemCount() -> Int {
            collection.layoutSubtreeIfNeeded()
            return collection.visibleItems().filter { $0.view.layer?.animation(forKey: "position") != nil }.count
        }
        XCTAssertEqual(glidingItemCount(), 0)

        grid.setGridItemWidth(185)
        XCTAssertEqual(glidingItemCount(), 0)

        grid.setGridItemWidth(250)
        XCTAssertGreaterThan(glidingItemCount(), 0)
    }
}

private extension NSView {
    var descendants: [NSView] { subviews + subviews.flatMap(\.descendants) }
}
