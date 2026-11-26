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
    func testGridGlidesOnlyWhenTheColumnCountChanges() throws {
        guard NSWorkspace.shared.accessibilityDisplayShouldReduceMotion == false else { return }
        let suiteName = "GridReflowTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        defaults.set(180.0, forKey: "VideoGridItemWidth")
        let grid = VideoGridViewController(
            onOpenVideo: { _ in }, onRevealVideo: { _ in }, onCopyPath: { _ in },
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

        grid.setGridItemWidth(185)
        let before = itemViews().mapValues(\.frame)
        XCTAssertTrue(itemViews().values.allSatisfy { $0.layer?.animationKeys() == nil })

        grid.setGridItemWidth(250)
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

private extension NSView {
    var descendants: [NSView] { subviews + subviews.flatMap(\.descendants) }
}
