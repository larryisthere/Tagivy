import AppKit
import XCTest
@testable import Tagivy

final class InspectorTagListTests: XCTestCase {
    func testClickingATagAddsItUnlessEveryVideoAlreadyHasIt() {
        XCTAssertEqual(InspectorTagList.toggledState(.off), .on)
        XCTAssertEqual(InspectorTagList.toggledState(.mixed), .on)
        XCTAssertEqual(InspectorTagList.toggledState(.on), .off)
    }

    func testCheckboxShowsTheSavedAssignmentState() {
        XCTAssertEqual(InspectorTagList.controlState(.off), .off)
        XCTAssertEqual(InspectorTagList.controlState(.mixed), .mixed)
        XCTAssertEqual(InspectorTagList.controlState(.on), .on)
    }

    func testTagsTheSelectionHasComeFirstInLibraryOrder() {
        let tags = ["a", "b", "c", "d"].map { makeTag(id: $0, name: $0) }
        let order = InspectorTagList.order(tags, states: ["c": .on, "b": .mixed, "d": .off])
        XCTAssertEqual(order.map(\.id), ["b", "c", "a", "d"])
    }

    func testVideoCountChangesDoNotRebuildTheTagList() {
        let before = [makeTag(id: "a", name: "Interview", videoCount: 1)]
        let after = [makeTag(id: "a", name: "Interview", videoCount: 2)]
        XCTAssertEqual(InspectorTagList.entries(before), InspectorTagList.entries(after))
    }

    func testRenamedAddedOrReorderedTagsRebuildTheTagList() {
        let tags = [makeTag(id: "a", name: "Interview"), makeTag(id: "b", name: "B-roll")]
        XCTAssertNotEqual(
            InspectorTagList.entries(tags),
            InspectorTagList.entries([makeTag(id: "a", name: "Interviews"), tags[1]])
        )
        XCTAssertNotEqual(InspectorTagList.entries(tags), InspectorTagList.entries(Array(tags.prefix(1))))
        XCTAssertNotEqual(InspectorTagList.entries(tags), InspectorTagList.entries(tags.reversed()))
    }

    private func makeTag(id: String, name: String, videoCount: Int = 0) -> TagRecord {
        TagRecord(
            id: id,
            libraryID: LibraryRecord.primaryID,
            name: name,
            parentID: nil,
            color: nil,
            sortOrder: 0,
            source: "user",
            videoCount: videoCount
        )
    }
}
