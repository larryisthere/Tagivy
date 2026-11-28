import AppKit
import XCTest
@testable import Tagivy

@MainActor
final class InspectorTagStateCacheTests: XCTestCase {
    func testAssignmentsChangedWhileNothingIsSelectedReloadWhenTheSameVideoIsSelectedAgain() {
        var loadedSelections: [[String]] = []
        let inspector = InspectorViewController(
            onApplyTagDraft: { _, _, _, completion in completion(true) },
            loadTagStates: { videoIDs, completion in
                loadedSelections.append(videoIDs)
                completion(["tag": .off])
            },
            filePath: { _ in nil },
            offlineSourceName: { _ in nil },
            onRelinkVideo: { _ in },
            onRemoveVideos: { _, completion in completion(false) }
        )
        inspector.loadViewIfNeeded()
        inspector.setTags([makeTag(id: "tag")])
        let video = makeVideo(id: "video")

        inspector.setSelection([video])
        drainMainQueue()
        XCTAssertEqual(loadedSelections, [["video"]])

        inspector.setSelection([])
        drainMainQueue()
        inspector.refreshTagAssignments()
        inspector.setSelection([video])
        drainMainQueue()

        XCTAssertEqual(loadedSelections, [["video"], ["video"]])
    }

    private func drainMainQueue() {
        RunLoop.main.run(until: Date().addingTimeInterval(0.05))
    }

    private func makeTag(id: String) -> TagRecord {
        TagRecord(
            id: id,
            libraryID: LibraryRecord.primaryID,
            name: id,
            parentID: nil,
            color: nil,
            sortOrder: 0,
            source: "user",
            videoCount: 0
        )
    }

    private func makeVideo(id: String) -> VideoRecord {
        VideoRecord(
            id: id, libraryID: LibraryRecord.primaryID, relativePath: "\(id).mov", filename: "\(id).mov",
            fileExtension: "mov", fileSize: 1, creationDate: nil, modificationDate: nil,
            duration: 1, width: 320, height: 180, thumbnailID: nil, metadataStatus: .completed,
            thumbnailStatus: .completed, firstIndexedAt: .distantPast, availability: .available
        )
    }
}
