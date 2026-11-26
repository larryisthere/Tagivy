import XCTest
@testable import Tagivy

final class SidebarModelTests: XCTestCase {
    func testLibraryFiltersPreserveAssociatedTagIdentity() {
        XCTAssertEqual(LibraryFilter.all, .all)
        XCTAssertEqual(LibraryFilter.untagged, .untagged)
        XCTAssertEqual(LibraryFilter.recent, .recent)
        XCTAssertEqual(LibraryFilter.tag("tag-id"), .tag("tag-id"))
        XCTAssertEqual(LibraryFilter.tags(["one", "two"]), .tags(["one", "two"]))
    }

    func testTagNodeKeepsTagAndChildren() {
        let parent = TagNode(tag: makeTag(id: "parent", name: "父级"))
        let child = TagNode(tag: makeTag(id: "child", name: "子级", parentID: "parent"))
        parent.children.append(child)

        XCTAssertEqual(parent.tag.id, "parent")
        XCTAssertEqual(parent.children.map(\.tag.id), ["child"])
    }

    func testCountRollsUpWhenItGrowsAndDownWhenItShrinks() {
        XCTAssertEqual(CountRoll(from: "3", to: "4"), .up)
        XCTAssertEqual(CountRoll(from: "10", to: "9"), .down)
    }

    func testUnchangedOrNonNumericTextDoesNotRoll() {
        XCTAssertNil(CountRoll(from: "4", to: "4"))
        XCTAssertNil(CountRoll(from: nil, to: "4"))
        XCTAssertNil(CountRoll(from: "4", to: "⌘1"))
    }

    func testClickedRowInsideSelectionTargetsWholeSelectionWithoutNestedTags() {
        let travel = makeTag(id: "travel", name: "旅行")
        let coast = makeTag(id: "coast", name: "海边", parentID: "travel")
        let people = makeTag(id: "people", name: "人物")
        let favorites = makeSmartCollection(id: "favorites")
        let allTags = [travel, coast, people]

        let targets = SidebarTargets(
            clicked: .tag(coast),
            selection: [.tag(travel), .tag(coast), .tag(people), .smartCollection(favorites)],
            allTags: allTags
        )

        XCTAssertEqual(targets.tags.map(\.id), ["travel", "people"], "海边 is inside 旅行, which already includes its videos")
        XCTAssertEqual(targets.smartCollections.map(\.id), ["favorites"])
        XCTAssertEqual(targets.items.count, 4)
        XCTAssertEqual(targets.scopes, [.tags([travel, people]), .smartCollection(favorites)])
    }

    func testClickedRowOutsideSelectionTargetsOnlyThatRow() {
        let travel = makeTag(id: "travel", name: "旅行")
        let coast = makeTag(id: "coast", name: "海边", parentID: "travel")
        let people = makeTag(id: "people", name: "人物")

        let targets = SidebarTargets(clicked: .tag(coast), selection: [.tag(travel), .tag(people)], allTags: [travel, coast, people])

        XCTAssertEqual(targets.tags.map(\.id), ["coast"])
        XCTAssertEqual(targets.smartCollections, [])
    }

    func testDraggedRowsActOnPreparedVideosRegardlessOfNestedRowsAndOrder() {
        let travel = makeTag(id: "travel", name: "旅行")
        let coast = makeTag(id: "coast", name: "海边", parentID: "travel")
        let favorites = makeSmartCollection(id: "favorites")
        let allTags = [travel, coast]

        let prepared = SidebarTargets(items: [.tag(travel), .smartCollection(favorites)], allTags: allTags)
        let dragged = SidebarTargets(items: [.smartCollection(favorites), .tag(coast), .tag(travel)], allTags: allTags)

        XCTAssertTrue(prepared.actsOnSameVideos(as: dragged))
        XCTAssertFalse(prepared.actsOnSameVideos(as: SidebarTargets(items: [.tag(travel)], allTags: allTags)))
    }

    private func makeSmartCollection(id: String) -> SmartCollectionRecord {
        SmartCollectionRecord(
            id: id,
            libraryID: LibraryRecord.primaryID,
            name: id,
            rule: .standard,
            sortOrder: 0,
            createdAt: Date(timeIntervalSince1970: 0),
            updatedAt: Date(timeIntervalSince1970: 0)
        )
    }

    private func makeTag(id: String, name: String, parentID: String? = nil) -> TagRecord {
        TagRecord(
            id: id,
            libraryID: LibraryRecord.primaryID,
            name: name,
            parentID: parentID,
            color: nil,
            sortOrder: 0,
            source: "user",
            videoCount: 0
        )
    }
}
