import AppKit
import XCTest
@testable import Tagivy

@MainActor
final class MainMenuTests: XCTestCase {
    private struct Shortcut: Hashable, CustomStringConvertible {
        let key: String
        let modifiers: NSEvent.ModifierFlags.RawValue

        init(_ key: String, _ modifiers: NSEvent.ModifierFlags) {
            self.key = key
            self.modifiers = modifiers.intersection(.deviceIndependentFlagsMask).rawValue
        }

        var description: String { "\(NSEvent.ModifierFlags(rawValue: modifiers)) \(key.debugDescription)" }
    }

    func testEveryCommandHasItsShortcut() throws {
        let expected: [(Selector, Shortcut)] = [
            (#selector(MainMenuActions.showSettings), Shortcut(",", [.command])),
            (#selector(NSApplication.terminate(_:)), Shortcut("q", [.command])),

            (#selector(MainMenuActions.importVideos), Shortcut("i", [.command, .shift])),
            (#selector(MainMenuActions.scanForNewVideos), Shortcut("r", [.command])),
            (#selector(MainMenuActions.createRootTag), Shortcut("n", [.command, .shift])),
            (#selector(MainMenuActions.saveAsSmartCollection), Shortcut("s", [.command])),
            (#selector(NSWindow.performClose(_:)), Shortcut("w", [.command])),

            (#selector(MainMenuActions.undoLastMutation), Shortcut("z", [.command])),
            (#selector(MainMenuActions.focusFilenameSearch), Shortcut("f", [.command])),
            (#selector(MainMenuActions.presentAddFilterMenu), Shortcut("f", [.command, .shift])),

            (#selector(MainMenuActions.openSelectedVideos), Shortcut("o", [.command])),
            (#selector(MainMenuActions.quickLookSelectedVideos), Shortcut("y", [.command])),
            (#selector(MainMenuActions.revealSelectedVideos), Shortcut("r", [.command, .shift])),
            (#selector(MainMenuActions.copySelectedVideoPaths), Shortcut("c", [.command, .option])),
            (#selector(MainMenuActions.addTagsToSelectedVideos), Shortcut("k", [.command])),
            (#selector(MainMenuActions.removeSelectedVideos), Shortcut("\u{8}", [.command])),

            (#selector(MainMenuActions.showAllVideos), Shortcut("1", [.command])),
            (#selector(MainMenuActions.showRecentVideos), Shortcut("2", [.command])),
            (#selector(MainMenuActions.showUntaggedVideos), Shortcut("3", [.command])),
            (#selector(MainMenuActions.showUnavailableVideos), Shortcut("4", [.command])),
            (#selector(MainMenuActions.zoomOutThumbnails), Shortcut("-", [.command])),
            (#selector(MainMenuActions.resetThumbnailSize), Shortcut("0", [.command])),
            (#selector(MainMenuActions.toggleLibrarySidebar), Shortcut("s", [.command, .control])),
            (#selector(MainMenuActions.toggleLibraryInspector), Shortcut("i", [.command, .option])),
            (#selector(NSWindow.toggleToolbarShown(_:)), Shortcut("t", [.command, .option])),
            (#selector(NSWindow.toggleFullScreen(_:)), Shortcut("f", [.command, .control])),

            (#selector(NSWindow.performMiniaturize(_:)), Shortcut("m", [.command])),
        ]
        let items = allItems()
        for (action, shortcut) in expected {
            let matching = items.filter { $0.action == action }
            XCTAssertEqual(matching.count, 1, "\(action)")
            let item = try XCTUnwrap(matching.first, "\(action)")
            XCTAssertEqual(Shortcut(item.keyEquivalent, item.keyEquivalentModifierMask), shortcut, "\(action)")
        }
    }

    func testZoomInShowsCommandPlusAndAlsoAnswersCommandEquals() {
        let zoomIn = allItems().filter { $0.action == #selector(MainMenuActions.zoomInThumbnails) }
        let visible = zoomIn.filter { $0.isHidden == false }
        let hidden = zoomIn.filter(\.isHidden)

        XCTAssertEqual(visible.map { Shortcut($0.keyEquivalent, $0.keyEquivalentModifierMask) }, [Shortcut("+", [.command])])
        XCTAssertEqual(hidden.map { Shortcut($0.keyEquivalent, $0.keyEquivalentModifierMask) }, [Shortcut("=", [.command])])
        XCTAssertTrue(hidden.allSatisfy(\.allowsKeyEquivalentWhenHidden))
    }

    func testNoTwoMenuItemsShareAShortcut() {
        var seen: [Shortcut: String] = [:]
        for item in allItems() where item.keyEquivalent.isEmpty == false {
            let shortcut = Shortcut(item.keyEquivalent, item.keyEquivalentModifierMask)
            XCTAssertNil(seen[shortcut], "\(shortcut) is used by both \(seen[shortcut] ?? "") and \(item.title)")
            seen[shortcut] = item.title
        }
    }

    func testVideoMenuSitsBetweenEditAndView() {
        let menu = MainMenu.make(target: nil, includesCheckForUpdates: false)
        let firstActions = menu.items.map { $0.submenu?.items.first(where: { $0.action != nil })?.action }

        XCTAssertEqual(firstActions.count, 6)
        XCTAssertEqual(firstActions[2], #selector(MainMenuActions.undoLastMutation))
        XCTAssertEqual(firstActions[3], #selector(MainMenuActions.openSelectedVideos))
        XCTAssertEqual(firstActions[4], #selector(MainMenuActions.showAllVideos))
        XCTAssertTrue(MainMenu.windowMenu(in: menu)?.items.contains {
            $0.action == #selector(NSApplication.arrangeInFront(_:))
        } == true)
    }

    func testSidebarShortcutHintsMatchTheViewMenu() {
        let items = allItems()
        let presets: [(LibraryFilter, Selector)] = [
            (.all, #selector(MainMenuActions.showAllVideos)),
            (.recent, #selector(MainMenuActions.showRecentVideos)),
            (.untagged, #selector(MainMenuActions.showUntaggedVideos)),
            (.unavailable, #selector(MainMenuActions.showUnavailableVideos)),
        ]
        for (filter, action) in presets {
            let node = SidebarFilterNode(title: "", systemImageName: "film", filter: filter, videoCount: 1)
            let key = items.first { $0.action == action }?.keyEquivalent ?? ""
            XCTAssertEqual(node.shortcutHint, "⌘\(key)")
        }
    }

    func testReturnWithoutModifiersRenamesInTheSidebar() throws {
        XCTAssertTrue(SidebarRenameKey.matches(try keyEvent(SidebarRenameKey.returnKeyCode)))
        XCTAssertFalse(SidebarRenameKey.matches(try keyEvent(SidebarRenameKey.returnKeyCode, modifiers: .command)))
        XCTAssertFalse(SidebarRenameKey.matches(try keyEvent(SidebarRenameKey.returnKeyCode, modifiers: .option)))
        XCTAssertFalse(SidebarRenameKey.matches(try keyEvent(SidebarDeleteKey.deleteKeyCode)))
    }

    func testCommandDownArrowOpensInTheGrid() throws {
        let code = VideoGridOpenKey.downArrowKeyCode
        // Arrow keys also carry the function and numeric pad flags.
        XCTAssertTrue(VideoGridOpenKey.matches(try keyEvent(code, modifiers: [.command, .function, .numericPad])))
        XCTAssertFalse(VideoGridOpenKey.matches(try keyEvent(code, modifiers: [.function, .numericPad])))
        XCTAssertFalse(VideoGridOpenKey.matches(try keyEvent(code, modifiers: [.command, .shift])))
    }

    func testOpeningMoreThanTenVideosAsksFirst() {
        XCTAssertFalse(OpenVideosConfirmation.isNeeded(count: 1))
        XCTAssertFalse(OpenVideosConfirmation.isNeeded(count: 10))
        XCTAssertTrue(OpenVideosConfirmation.isNeeded(count: 11))
    }

    private func allItems() -> [NSMenuItem] {
        func flatten(_ menu: NSMenu) -> [NSMenuItem] {
            menu.items.flatMap { item in [item] + (item.submenu.map(flatten) ?? []) }
        }
        return flatten(MainMenu.make(target: nil, includesCheckForUpdates: true))
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
}
