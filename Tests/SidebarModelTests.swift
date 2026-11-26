import AppKit
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

    func testDeleteKeyDeletesSelectedTagsWithoutRepeatingTheirDescendants() {
        let parent = makeTag(id: "parent", name: "父级")
        let middle = makeTag(id: "middle", name: "中间", parentID: "parent")
        let grandchild = makeTag(id: "grandchild", name: "孙级", parentID: "middle")
        let other = makeTag(id: "other", name: "其他")
        let allTags = [parent, middle, grandchild, other]

        let deletion = SidebarDeletion(
            selectedItems: [TagNode(tag: parent), TagNode(tag: grandchild), TagNode(tag: other)],
            allTags: allTags
        )

        XCTAssertEqual(deletion, .tags([parent, other]))
        XCTAssertEqual(
            SidebarDeletion(selectedItems: [TagNode(tag: middle)], allTags: allTags),
            .tags([middle])
        )
    }

    func testDeleteKeyDeletesOnlyASingleSelectedSmartCollection() {
        let collection = SmartCollectionRecord(
            id: "collection",
            libraryID: LibraryRecord.primaryID,
            name: "集合",
            rule: .standard,
            sortOrder: 0,
            createdAt: Date(timeIntervalSince1970: 0),
            updatedAt: Date(timeIntervalSince1970: 0)
        )
        let node = SmartCollectionNode(collection: collection)

        XCTAssertEqual(SidebarDeletion(selectedItems: [node], allTags: []), .smartCollection(collection))
        XCTAssertNil(SidebarDeletion(selectedItems: [node, SmartCollectionNode(collection: collection)], allTags: []))
    }

    func testDeleteKeyDeletesNothingForBuiltInRowsOrMixedSelections() {
        let tag = makeTag(id: "tag", name: "标签")
        let allVideos = SidebarFilterNode(title: "全部", systemImageName: "film", filter: .all, videoCount: 0)

        XCTAssertNil(SidebarDeletion(selectedItems: [], allTags: [tag]))
        XCTAssertNil(SidebarDeletion(selectedItems: [allVideos], allTags: [tag]))
        XCTAssertNil(SidebarDeletion(selectedItems: [TagNode(tag: tag), allVideos], allTags: [tag]))
    }

    func testDeleteAndCommandDeleteAreTheSidebarDeleteKeys() throws {
        XCTAssertTrue(SidebarDeleteKey.matches(try keyEvent(SidebarDeleteKey.deleteKeyCode)))
        XCTAssertTrue(SidebarDeleteKey.matches(try keyEvent(SidebarDeleteKey.deleteKeyCode, modifiers: .command)))
        XCTAssertTrue(SidebarDeleteKey.matches(try keyEvent(SidebarDeleteKey.forwardDeleteKeyCode)))
        XCTAssertFalse(SidebarDeleteKey.matches(try keyEvent(SidebarDeleteKey.deleteKeyCode, modifiers: .option)))
        XCTAssertFalse(SidebarDeleteKey.matches(try keyEvent(SidebarDeleteKey.deleteKeyCode, modifiers: [.command, .shift])))
        XCTAssertFalse(SidebarDeleteKey.matches(try keyEvent(0)))
    }

    @MainActor
    func testUndoNoticeIsTakenDownOnlyWhileItIsStillTheOneShown() {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 600, height: 400),
            styleMask: [.titled],
            backing: .buffered,
            defer: true
        )
        let deletion = TransientNotice.show(in: window, title: "已删除“标签”")
        XCTAssertTrue(TransientNotice.isShowing(deletion))

        TransientNotice.dismiss(deletion)
        XCTAssertFalse(TransientNotice.isShowing(deletion))

        let earlier = TransientNotice.show(in: window, title: "已删除 2 个标签")
        let newer = TransientNotice.show(in: window, title: "导出完成")
        XCTAssertFalse(TransientNotice.isShowing(earlier))
        TransientNotice.dismiss(earlier)
        XCTAssertTrue(TransientNotice.isShowing(newer))
        TransientNotice.dismiss(newer)
    }

    private func keyEvent(_ keyCode: UInt16, modifiers: NSEvent.ModifierFlags = []) throws -> NSEvent {
        try XCTUnwrap(NSEvent.keyEvent(
            with: .keyDown,
            location: .zero,
            modifierFlags: modifiers,
            timestamp: 0,
            windowNumber: 0,
            context: nil,
            characters: "",
            charactersIgnoringModifiers: "",
            isARepeat: false,
            keyCode: keyCode
        ))
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
