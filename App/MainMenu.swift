import AppKit

/// The commands the main menu sends to the app. Every keyboard shortcut in the library window is one of
/// these menu items, so it can be found in the menu bar; whether it applies right now is decided where the
/// items are validated.
@MainActor
@objc protocol MainMenuActions: AnyObject {
    func showAbout()
    func checkForUpdates()
    func showSettings()

    func importVideos()
    func scanForNewVideos()
    func createRootTag()
    func saveAsSmartCollection()

    func undoLastMutation()
    func focusFilenameSearch()
    func presentAddFilterMenu()

    func openSelectedVideos()
    func quickLookSelectedVideos()
    func revealSelectedVideos()
    func copySelectedVideoPaths()
    func addTagsToSelectedVideos()
    func exportSelectedVideosToEditor(_ sender: NSMenuItem)
    func removeSelectedVideos()

    func showAllVideos()
    func showRecentVideos()
    func showUntaggedVideos()
    func showUnavailableVideos()
    func zoomInThumbnails()
    func zoomOutThumbnails()
    func resetThumbnailSize()
    func toggleLibrarySidebar()
    func toggleLibraryInspector()

    func showLibraryWindow()
}

@MainActor
enum MainMenu {
    static func make(target: MainMenuActions?, includesCheckForUpdates: Bool) -> NSMenu {
        let mainMenu = NSMenu()
        for submenu in [
            appMenu(target: target, includesCheckForUpdates: includesCheckForUpdates),
            fileMenu(target: target),
            editMenu(target: target),
            videoMenu(target: target),
            viewMenu(target: target),
            windowMenu(target: target),
        ] {
            let item = NSMenuItem()
            item.submenu = submenu
            mainMenu.addItem(item)
        }
        return mainMenu
    }

    /// The Services submenu of the app menu, which AppKit fills with the system's services.
    static func servicesMenu(in mainMenu: NSMenu) -> NSMenu? {
        mainMenu.items.first?.submenu?.items.first { $0.submenu != nil }?.submenu
    }

    /// The Window menu, which AppKit fills with the list of open windows.
    static func windowMenu(in mainMenu: NSMenu) -> NSMenu? {
        mainMenu.items.last?.submenu
    }

    private static func item(
        _ title: String,
        _ action: Selector,
        _ key: String = "",
        _ modifiers: NSEvent.ModifierFlags = [.command],
        target: AnyObject?
    ) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: key)
        item.keyEquivalentModifierMask = modifiers
        item.target = target
        return item
    }

    private static func appMenu(target: MainMenuActions?, includesCheckForUpdates: Bool) -> NSMenu {
        let menu = NSMenu(title: AppConfiguration.displayName)
        menu.addItem(item(
            String(localized: .menuAbout(AppConfiguration.displayName)),
            #selector(MainMenuActions.showAbout),
            target: target
        ))
        if includesCheckForUpdates {
            menu.addItem(item(
                String(localized: .menuCheckForUpdates),
                #selector(MainMenuActions.checkForUpdates),
                target: target
            ))
        }
        menu.addItem(.separator())
        menu.addItem(item(
            String(localized: .menuSettings),
            #selector(MainMenuActions.showSettings),
            ",",
            target: target
        ))
        menu.addItem(.separator())
        let services = NSMenuItem(title: String(localized: "menu.services", defaultValue: "Services"), action: nil, keyEquivalent: "")
        services.submenu = NSMenu(title: services.title)
        menu.addItem(services)
        menu.addItem(.separator())
        menu.addItem(item(
            String(localized: "menu.hide", defaultValue: "Hide \(AppConfiguration.displayName)"),
            #selector(NSApplication.hide(_:)),
            "h",
            target: nil
        ))
        menu.addItem(item(
            String(localized: "menu.hideOthers", defaultValue: "Hide Others"),
            #selector(NSApplication.hideOtherApplications(_:)),
            "h", [.command, .option],
            target: nil
        ))
        menu.addItem(item(
            String(localized: "menu.showAll", defaultValue: "Show All"),
            #selector(NSApplication.unhideAllApplications(_:)),
            target: nil
        ))
        menu.addItem(.separator())
        menu.addItem(item(
            String(localized: .menuQuit(AppConfiguration.displayName)),
            #selector(NSApplication.terminate(_:)),
            "q",
            target: nil
        ))
        return menu
    }

    private static func fileMenu(target: MainMenuActions?) -> NSMenu {
        let menu = NSMenu(title: String(localized: .menuFile))
        menu.addItem(item(
            String(localized: .menuFileImport),
            #selector(MainMenuActions.importVideos),
            "i", [.command, .shift],
            target: target
        ))
        menu.addItem(item(
            String(localized: "scan.action", defaultValue: "Scan for New Videos"),
            #selector(MainMenuActions.scanForNewVideos),
            "r",
            target: target
        ))
        menu.addItem(.separator())
        menu.addItem(item(
            String(localized: .menuFileNewTag),
            #selector(MainMenuActions.createRootTag),
            "n", [.command, .shift],
            target: target
        ))
        menu.addItem(item(
            String(localized: "filter.saveSmartCollection", defaultValue: "Save as Smart Collection…"),
            #selector(MainMenuActions.saveAsSmartCollection),
            "s",
            target: target
        ))
        menu.addItem(.separator())
        menu.addItem(item(
            String(localized: .menuFileCloseWindow),
            #selector(NSWindow.performClose(_:)),
            "w",
            target: nil
        ))
        return menu
    }

    private static func editMenu(target: MainMenuActions?) -> NSMenu {
        let menu = NSMenu(title: String(localized: .menuEdit))
        menu.addItem(item(
            String(localized: .menuUndoLastAction),
            #selector(MainMenuActions.undoLastMutation),
            "z",
            target: target
        ))
        menu.addItem(.separator())
        StandardEditMenu.items().forEach(menu.addItem)
        menu.addItem(.separator())
        menu.addItem(item(
            String(localized: "menu.searchFilenames", defaultValue: "Search Filenames"),
            #selector(MainMenuActions.focusFilenameSearch),
            "f",
            target: target
        ))
        menu.addItem(item(
            String(localized: "menu.addFilterCondition", defaultValue: "Add Filter Condition"),
            #selector(MainMenuActions.presentAddFilterMenu),
            "f", [.command, .shift],
            target: target
        ))
        return menu
    }

    /// Acts on the videos selected in the grid, like the grid's shortcut menu.
    private static func videoMenu(target: MainMenuActions?) -> NSMenu {
        let menu = NSMenu(title: String(localized: "menu.video", defaultValue: "Video"))
        menu.addItem(item(
            String(localized: .videoActionOpen),
            #selector(MainMenuActions.openSelectedVideos),
            "o",
            target: target
        ))
        menu.addItem(item(
            String(localized: "menu.video.quickLook", defaultValue: "Quick Look"),
            #selector(MainMenuActions.quickLookSelectedVideos),
            "y",
            target: target
        ))
        menu.addItem(item(
            String(localized: .videoActionReveal),
            #selector(MainMenuActions.revealSelectedVideos),
            "r", [.command, .shift],
            target: target
        ))
        menu.addItem(item(
            String(localized: .videoActionCopyPath),
            #selector(MainMenuActions.copySelectedVideoPaths),
            "c", [.command, .option],
            target: target
        ))
        menu.addItem(.separator())
        menu.addItem(item(
            String(localized: "menu.video.addTags", defaultValue: "Add Tags"),
            #selector(MainMenuActions.addTagsToSelectedVideos),
            "k",
            target: target
        ))
        let exportItem = EditorExportMenu.item(
            scope: nil,
            isEnabled: true,
            target: target,
            action: #selector(MainMenuActions.exportSelectedVideosToEditor(_:))
        )
        // Enabled with the selection, through the same validation as the other Video items.
        exportItem.submenu?.autoenablesItems = true
        menu.addItem(exportItem)
        menu.addItem(.separator())
        menu.addItem(item(
            String(localized: .videoRemoveMenuSingle),
            #selector(MainMenuActions.removeSelectedVideos),
            "\u{8}",
            target: target
        ))
        return menu
    }

    private static func viewMenu(target: MainMenuActions?) -> NSMenu {
        let menu = NSMenu(title: String(localized: "menu.view", defaultValue: "View"))
        menu.addItem(item(
            String(localized: .libraryAllVideos),
            #selector(MainMenuActions.showAllVideos),
            "1",
            target: target
        ))
        menu.addItem(item(
            String(localized: .libraryRecent),
            #selector(MainMenuActions.showRecentVideos),
            "2",
            target: target
        ))
        menu.addItem(item(
            String(localized: .libraryUntagged),
            #selector(MainMenuActions.showUntaggedVideos),
            "3",
            target: target
        ))
        menu.addItem(item(
            String(localized: "library.unavailable", defaultValue: "Unavailable Videos"),
            #selector(MainMenuActions.showUnavailableVideos),
            "4",
            target: target
        ))
        menu.addItem(.separator())
        menu.addItem(item(
            String(localized: "menu.view.zoomIn", defaultValue: "Zoom In"),
            #selector(MainMenuActions.zoomInThumbnails),
            "+",
            target: target
        ))
        // ⌘= without Shift also zooms in, as in other Mac apps; the menu shows ⌘+ only.
        let zoomInWithoutShift = item(
            String(localized: "menu.view.zoomIn", defaultValue: "Zoom In"),
            #selector(MainMenuActions.zoomInThumbnails),
            "=",
            target: target
        )
        zoomInWithoutShift.isHidden = true
        zoomInWithoutShift.allowsKeyEquivalentWhenHidden = true
        menu.addItem(zoomInWithoutShift)
        menu.addItem(item(
            String(localized: "menu.view.zoomOut", defaultValue: "Zoom Out"),
            #selector(MainMenuActions.zoomOutThumbnails),
            "-",
            target: target
        ))
        menu.addItem(item(
            String(localized: "menu.view.actualSize", defaultValue: "Actual Size"),
            #selector(MainMenuActions.resetThumbnailSize),
            "0",
            target: target
        ))
        menu.addItem(.separator())
        menu.addItem(item(
            String(localized: "menu.view.hideSidebar", defaultValue: "Hide Sidebar"),
            #selector(MainMenuActions.toggleLibrarySidebar),
            "s", [.command, .control],
            target: target
        ))
        menu.addItem(item(
            String(localized: "menu.view.hideInspector", defaultValue: "Hide Inspector"),
            #selector(MainMenuActions.toggleLibraryInspector),
            "i", [.command, .option],
            target: target
        ))
        menu.addItem(.separator())
        // The window gives these two their current title, such as Hide Toolbar or Exit Full Screen.
        menu.addItem(item(
            String(localized: "menu.view.hideToolbar", defaultValue: "Hide Toolbar"),
            #selector(NSWindow.toggleToolbarShown(_:)),
            "t", [.command, .option],
            target: nil
        ))
        menu.addItem(item(
            String(localized: "menu.view.enterFullScreen", defaultValue: "Enter Full Screen"),
            #selector(NSWindow.toggleFullScreen(_:)),
            "f", [.command, .control],
            target: nil
        ))
        return menu
    }

    private static func windowMenu(target: MainMenuActions?) -> NSMenu {
        let menu = NSMenu(title: String(localized: .menuWindow))
        menu.addItem(item(
            String(localized: .menuMinimize),
            #selector(NSWindow.performMiniaturize(_:)),
            "m",
            target: nil
        ))
        menu.addItem(item(
            String(localized: "menu.window.zoom", defaultValue: "Zoom"),
            #selector(NSWindow.performZoom(_:)),
            target: nil
        ))
        menu.addItem(.separator())
        // Tagivy has one main window; ⌘0 stays with View → Actual Size.
        menu.addItem(item(
            String(localized: "menu.window.showMainWindow", defaultValue: "Show Main Window"),
            #selector(MainMenuActions.showLibraryWindow),
            target: target
        ))
        menu.addItem(.separator())
        menu.addItem(item(
            String(localized: "menu.window.bringAllToFront", defaultValue: "Bring All to Front"),
            #selector(NSApplication.arrangeInFront(_:)),
            target: nil
        ))
        return menu
    }
}

/// Return on a selected tag or smart collection in the sidebar starts renaming it, as in Finder.
enum SidebarRenameKey {
    static let returnKeyCode: UInt16 = 36

    static func matches(_ event: NSEvent) -> Bool {
        event.type == .keyDown
            && event.keyCode == returnKeyCode
            && event.modifierFlags.intersection([.command, .control, .option, .shift]).isEmpty
    }
}

/// Command-Down Arrow in the grid opens the selected videos, as in Finder.
enum VideoGridOpenKey {
    static let downArrowKeyCode: UInt16 = 125

    static func matches(_ event: NSEvent) -> Bool {
        event.type == .keyDown
            && event.keyCode == downArrowKeyCode
            && event.modifierFlags.intersection([.command, .control, .option, .shift]) == [.command]
    }
}
