import XCTest
@testable import Tagivy

final class TagCapsulesTests: XCTestCase {
    func testCompactLayoutWrapsCapsulesThatDoNotFit() {
        let sizes = [CGSize(width: 50, height: 22), CGSize(width: 50, height: 22), CGSize(width: 50, height: 22)]
        let frames = TagFlowLayout.frames(for: sizes, width: 120, oneItemPerRow: false)
        XCTAssertEqual(frames.map(\.origin), [CGPoint(x: 0, y: 0), CGPoint(x: 56, y: 0), CGPoint(x: 0, y: 28)])
    }

    func testListLayoutPutsOneCapsulePerRow() {
        let sizes = [CGSize(width: 30, height: 22), CGSize(width: 30, height: 22)]
        let frames = TagFlowLayout.frames(for: sizes, width: 300, oneItemPerRow: true)
        XCTAssertEqual(frames.map(\.origin), [CGPoint(x: 0, y: 0), CGPoint(x: 0, y: 28)])
        XCTAssertEqual(TagFlowLayout.height(for: sizes, width: 300, oneItemPerRow: true), 50)
    }

    func testLongTagNamesShrinkToTheAvailableWidth() {
        let frames = TagFlowLayout.frames(for: [CGSize(width: 500, height: 22)], width: 200, oneItemPerRow: false)
        XCTAssertEqual(frames.first?.width, 200)
    }

    func testCompactGroupsKeepTopLevelTagsFirstThenEachParentsChildren() {
        let place = makeTag(id: "place", name: "Place")
        let mood = makeTag(id: "mood", name: "Mood")
        let city = makeTag(id: "city", name: "City", parentID: "place")
        let beach = makeTag(id: "beach", name: "Beach", parentID: "place")
        let calm = makeTag(id: "calm", name: "Calm", parentID: "mood")
        let all = [place, mood, city, beach, calm]
        let ordered = [beach, calm, place, mood, city]

        let groups = InspectorTagList.groups(ordered, allTags: all)

        XCTAssertEqual(groups.map { $0.parent?.id }, [nil, "place", "mood"])
        XCTAssertEqual(groups.map { $0.tags.map(\.id) }, [["place", "mood"], ["beach", "city"], ["calm"]])
    }

    func testTagLayoutIsRememberedAndDefaultsToCompact() throws {
        let defaults = try XCTUnwrap(UserDefaults(suiteName: "TagCapsulesTests"))
        defaults.removePersistentDomain(forName: "TagCapsulesTests")
        XCTAssertEqual(InspectorTagLayout.persisted(defaults: defaults), .compact)
        InspectorTagLayout.list.persist(defaults: defaults)
        XCTAssertEqual(InspectorTagLayout.persisted(defaults: defaults), .list)
        defaults.removePersistentDomain(forName: "TagCapsulesTests")
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
