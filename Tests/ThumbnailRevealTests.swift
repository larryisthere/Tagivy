import XCTest
@testable import Tagivy

final class ThumbnailRevealTests: XCTestCase {
    func testThumbnailReadyBeforeItWasSeenMissingAppearsAtOnce() {
        XCTAssertEqual(ThumbnailReveal.after(waiting: 0), .immediate)
        XCTAssertEqual(ThumbnailReveal.after(waiting: 0.03), .immediate)
    }

    func testThumbnailThatKeptTheViewerWaitingFadesIn() {
        XCTAssertEqual(ThumbnailReveal.after(waiting: ThumbnailReveal.longestUnnoticedWait), .fade)
        XCTAssertEqual(ThumbnailReveal.after(waiting: 2), .fade)
    }

    func testFadeIsShortEnoughNotToDelayBrowsing() {
        XCTAssertEqual(ThumbnailReveal.fadeDuration, 0.2, accuracy: 0.0001)
    }

    @MainActor
    func testFadeAddsOneCrossfadeAndImmediateRemovesIt() {
        let layer = CALayer()
        ThumbnailReveal.fade.prepare(layer)
        XCTAssertEqual(layer.animationKeys()?.count, 1)
        ThumbnailReveal.immediate.prepare(layer)
        XCTAssertNil(layer.animationKeys())
    }
}
