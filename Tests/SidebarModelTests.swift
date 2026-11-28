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

    func testRuleBarSaveFollowsClearOnTagScope() {
        var context = makeRuleBarContext(scopeTitle: "标签")
        XCTAssertFalse(context.hasUserAddedConditions)
        XCTAssertFalse(context.canSaveRuleAsSmartCollection)

        context.rule.conditions.append(.durationRange(min: 60, max: nil))
        XCTAssertTrue(context.hasUserAddedConditions)
        XCTAssertTrue(context.canSaveRuleAsSmartCollection)

        context.rule = .standard
        XCTAssertFalse(context.hasUserAddedConditions)
        XCTAssertFalse(context.canSaveRuleAsSmartCollection)
    }

    func testRuleBarFilenameSearchCountsAsUserCondition() {
        let context = makeRuleBarContext(scopeTitle: nil, temporarySearch: "clip")
        XCTAssertTrue(context.hasUserAddedConditions)
        XCTAssertTrue(context.canSaveRuleAsSmartCollection)
    }

    func testRuleBarWhitespaceOnlySearchIsNotUserCondition() {
        let context = makeRuleBarContext(scopeTitle: "标签", temporarySearch: "  \n")
        XCTAssertFalse(context.hasUserAddedConditions)
        XCTAssertFalse(context.canSaveRuleAsSmartCollection)
    }

    func testRuleBarUnsavableScopeKeepsSaveDisabledWithConditions() {
        var context = makeRuleBarContext(scopeTitle: "不可用", canSaveAsSmartCollection: false)
        context.rule.conditions.append(.untagged)
        XCTAssertTrue(context.hasUserAddedConditions)
        XCTAssertFalse(context.canSaveRuleAsSmartCollection)
    }

    private func makeRuleBarContext(
        scopeTitle: String?,
        temporarySearch: String = "",
        canSaveAsSmartCollection: Bool = true
    ) -> LibraryRuleBarContext {
        LibraryRuleBarContext(
            scopeTitle: scopeTitle,
            temporarySearch: temporarySearch,
            rule: .standard,
            presetSort: nil,
            tags: [makeTag(id: "tag", name: "标签")],
            smartCollection: nil,
            isDirty: false,
            canSaveAsSmartCollection: canSaveAsSmartCollection,
            grouping: .standard
        )
    }

    // Rows: 0 All Videos, 1 Recent, 2 smart collection, 3 tag A, 4 tag B, 5 tag C; nil rows are group headers.
    private let sidebarRowKinds: [SidebarRowKind?] = [.other, .other, .other, .tag, .tag, .tag, nil]

    private func allowedRows(_ proposed: [Int], current: [Int], actedOn: Int = -1) -> [Int] {
        Array(SidebarSelectionRule.allowedRows(
            proposed: IndexSet(proposed),
            current: IndexSet(current),
            actedOnRow: actedOn
        ) { row in
            sidebarRowKinds.indices.contains(row) ? sidebarRowKinds[row] : nil
        })
    }

    func testSeveralTagsCanBeSelectedTogether() {
        XCTAssertEqual(allowedRows([3, 5], current: [3], actedOn: 5), [3, 5])
        XCTAssertEqual(allowedRows([3, 4, 5], current: [3], actedOn: 5), [3, 4, 5])
    }

    func testSelectingAllSidebarRowsKeepsOnlyOneRow() {
        // What ⌘A would have proposed before the sidebar sent it to the grid.
        XCTAssertEqual(allowedRows([0, 1, 2, 3, 4, 5], current: [0]), [0])
        XCTAssertEqual(allowedRows([0, 1, 2, 3, 4, 5], current: [3]), [3, 4, 5])
    }

    func testCommandClickingAnotherKindReplacesTheSelection() {
        XCTAssertEqual(allowedRows([0, 4], current: [0], actedOn: 4), [4])
        XCTAssertEqual(allowedRows([2, 3, 4], current: [3, 4], actedOn: 2), [2])
        XCTAssertEqual(allowedRows([0, 2], current: [0], actedOn: 2), [2])
    }

    func testShiftClickRangeFromAFilterToATagKeepsTheTagsInRange() {
        XCTAssertEqual(allowedRows([1, 2, 3, 4], current: [1], actedOn: 4), [3, 4])
    }

    func testKeyboardExtensionUsesTheNewlyAddedRow() {
        XCTAssertEqual(allowedRows([2, 3], current: [3]), [2])
        XCTAssertEqual(allowedRows([2, 3], current: [2]), [3])
    }

    func testGroupHeadersAreNeverSelected() {
        XCTAssertEqual(allowedRows([4, 6], current: [4], actedOn: 6), [4])
        XCTAssertEqual(allowedRows([0], current: []), [0])
    }

    func testTagMenuActsOnTheSelectionOnlyWhenTheClickedTagIsInIt() {
        let first = makeTag(id: "first", name: "一")
        let second = makeTag(id: "second", name: "二")
        let outside = makeTag(id: "outside", name: "外")

        XCTAssertEqual(SidebarTagMenuTargets(clicked: second, selection: [first, second]).tags, [first, second])
        XCTAssertEqual(SidebarTagMenuTargets(clicked: outside, selection: [first, second]).tags, [outside])
        XCTAssertFalse(SidebarTagMenuTargets(clicked: outside, selection: [first, second]).isMultiple)
    }

    func testColorIsCheckedOnlyWhenEveryTargetSharesIt() {
        let red = makeTag(id: "red", name: "红", color: "red")
        let alsoRed = makeTag(id: "alsoRed", name: "也红", color: "red")
        let plain = makeTag(id: "plain", name: "无")
        let alsoPlain = makeTag(id: "alsoPlain", name: "也无")

        XCTAssertEqual(SidebarTagMenuTargets(clicked: red, selection: [red, alsoRed]).sharedColor, "red")
        XCTAssertNil(SidebarTagMenuTargets(clicked: red, selection: [red, plain]).sharedColor)
        XCTAssertEqual(SidebarTagMenuTargets(clicked: plain, selection: [plain, alsoPlain]).sharedColor, "")
    }

    func testMergeDestinationsLeaveOutTheTargetsAndTagsInsideThem() {
        let parent = makeTag(id: "parent", name: "父级")
        let child = makeTag(id: "child", name: "子级", parentID: "parent")
        let grandchild = makeTag(id: "grandchild", name: "孙级", parentID: "child")
        let other = makeTag(id: "other", name: "其他")
        let otherChild = makeTag(id: "otherChild", name: "其他子级", parentID: "other")
        let third = makeTag(id: "third", name: "第三")
        let allTags = [parent, child, grandchild, other, otherChild, third]

        let several = SidebarTagMenuTargets(clicked: parent, selection: [parent, other])
        XCTAssertEqual(several.mergeDestinations(in: allTags).map(\.id), ["third"])

        let single = SidebarTagMenuTargets(clicked: child, selection: [])
        XCTAssertEqual(single.mergeDestinations(in: allTags).map(\.id), ["parent", "other", "otherChild", "third"])
    }

    func testNewAndMovedTagsOpenTheirParents() {
        let parent = makeTag(id: "parent", name: "父级")
        let child = makeTag(id: "child", name: "子级", parentID: "parent")
        let other = makeTag(id: "other", name: "其他")
        let created = makeTag(id: "created", name: "新", parentID: "child")
        let moved = makeTag(id: "other", name: "其他", parentID: "parent")

        XCTAssertEqual(
            SidebarTagExpansion.parentsToReveal(previous: [parent, child, other], current: [parent, child, other, created]),
            ["child", "parent"]
        )
        XCTAssertEqual(
            SidebarTagExpansion.parentsToReveal(previous: [parent, child, other], current: [parent, child, moved]),
            ["parent"]
        )
    }

    func testRenamingOrRecoloringATagOpensNothing() {
        let parent = makeTag(id: "parent", name: "父级")
        let child = makeTag(id: "child", name: "子级", parentID: "parent")
        let renamed = makeTag(id: "child", name: "改名", parentID: "parent", color: "red")

        XCTAssertEqual(SidebarTagExpansion.parentsToReveal(previous: [parent, child], current: [parent, renamed]), [])
        XCTAssertEqual(SidebarTagExpansion.parentsToReveal(previous: [], current: [parent, child]), [])
    }

    private func makeTag(id: String, name: String, parentID: String? = nil, color: String? = nil) -> TagRecord {
        TagRecord(
            id: id,
            libraryID: LibraryRecord.primaryID,
            name: name,
            parentID: parentID,
            color: color,
            sortOrder: 0,
            source: "user",
            videoCount: 0
        )
    }
}

@MainActor
final class TagColorMenuTests: XCTestCase {
    func testStoredValuesMapToColors() {
        XCTAssertEqual(TagColor(storedValue: "red"), .red)
        XCTAssertEqual(TagColor(storedValue: "purple")?.color, .systemPurple)
        XCTAssertNil(TagColor(storedValue: nil))
        XCTAssertNil(TagColor(storedValue: ""))
        XCTAssertNil(TagColor(storedValue: "teal"))
    }

    func testColorMenuListsNoneThenEveryColorWithASwatch() {
        let menu = TagColor.menu(sharedStoredValue: "green", action: #selector(NSText.copy(_:)), target: nil) { $0 }

        XCTAssertEqual(menu.items.compactMap { $0.representedObject as? String }, ["", "red", "orange", "yellow", "green", "blue", "purple"])
        XCTAssertTrue(menu.items.allSatisfy { $0.image != nil && $0.image?.isTemplate == false })
        XCTAssertEqual(menu.items.filter { $0.state == .on }.compactMap { $0.representedObject as? String }, ["green"])
    }

    func testMixedColorsCheckNothingAndNoColorChecksNone() {
        let mixed = TagColor.menu(sharedStoredValue: nil, action: #selector(NSText.copy(_:)), target: nil) { $0 }
        XCTAssertTrue(mixed.items.allSatisfy { $0.state == .off })

        let none = TagColor.menu(sharedStoredValue: "", action: #selector(NSText.copy(_:)), target: nil) { $0 }
        XCTAssertEqual(none.items.first?.state, .on)
    }
}
