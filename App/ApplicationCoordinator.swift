import AppKit
import CoreGraphics
import QuickLook
import QuickLookUI
import SwiftUI

@MainActor
final class ApplicationCoordinator: NSObject, NSMenuItemValidation, MainMenuActions {
    private static let userActivityEventTypes: [CGEventType] = [
        .keyDown,
        .flagsChanged,
        .leftMouseDown,
        .rightMouseDown,
        .otherMouseDown,
        .mouseMoved,
        .leftMouseDragged,
        .rightMouseDragged,
        .otherMouseDragged,
        .scrollWheel,
    ]

    private let preferencesStore: PreferencesStore
    private let updateController: AppUpdateController
    private let updateStatusView = UpdateStatusView()
    private let lockCoordinator: LockCoordinator
    private let databaseStore: DatabaseStore?
    private let windowController = MainWindowController()
    private let quickLookCoordinator = QuickLookPreviewCoordinator()
    private var tagDeletionNotice: (undoID: TagMutationUndoID, notice: TransientNotice.ID)?
    private let folderImportMethodPresenter = FolderImportMethodPresenter()
    private let editorExportPresenter = EditorExportPresenter()
    private var privacyShield: NSView?
    private var idleTimer: Timer?
    private var modifierFlagsMonitor: Any?

    private lazy var libraryViewController = LibrarySplitViewController(
        onCancelImport: { [weak self] in self?.libraryAccessCoordinator?.cancelImport() },
        onImportDroppedItems: { [weak self] urls in self?.libraryAccessCoordinator?.importDroppedItems(urls) },
        onScanForNewVideos: { [weak self] in self?.libraryAccessCoordinator?.scanForNewVideos() },
        onChooseAdditionalScanFolders: { [weak self] in
            self?.libraryAccessCoordinator?.chooseAdditionalScanFolders()
        },
        onImportScannedVideos: { [weak self] ids in
            self?.libraryAccessCoordinator?.importScannedVideos(ids: ids)
        },
        onClearScanResults: { [weak self] in
            self?.libraryAccessCoordinator?.clearScanResults()
        },
        onRemoveVideos: { [weak self] videoIDs, completion in
            guard let coordinator = self?.libraryAccessCoordinator else {
                completion(false)
                return
            }
            coordinator.removeVideos(ids: videoIDs, completion: completion)
        },
        onRelinkVideo: { [weak self] video in
            self?.libraryAccessCoordinator?.relinkVideo(video)
        },
        onRetryRelinkVideo: { [weak self] videoID in
            self?.libraryAccessCoordinator?.retryRelinkVideo(id: videoID)
        },
        onUndoLastMutation: { [weak self] in self?.libraryAccessCoordinator?.undoLastMutation() },
        onEndVideoRemovalUndo: { [weak self] in
            self?.libraryAccessCoordinator?.discardVideoRemovalUndo()
        },
        onOpenVideo: { [weak self] video in self?.openVideo(video) },
        onRevealVideos: { [weak self] videos in self?.revealVideos(videos) },
        onCopyPaths: { [weak self] videos in self?.copyPaths(videos) },
        onPreviewVideos: { [weak self] videos in self?.previewVideos(videos) },
        thumbnailURL: { [weak self] video in self?.libraryAccessCoordinator?.thumbnailURL(for: video) },
        resolveVideos: { [weak self] videos in
            self?.libraryAccessCoordinator?.resolveVideos(videos) ?? .empty
        },
        resolveVideosInScopes: { [weak self] scopes in
            guard let coordinator = self?.libraryAccessCoordinator else { return .empty }
            return (try? await coordinator.resolveVideos(in: scopes)) ?? .empty
        },
        filePath: { [weak self] video in self?.libraryAccessCoordinator?.displayPath(for: video) },
        offlineSourceName: { [weak self] video in
            self?.libraryAccessCoordinator?.offlineSourceName(for: video)
        },
        onQueryChanged: { [weak self] query, debounceSearch, generation in
            self?.libraryAccessCoordinator?.applyQuery(query, debounceSearch: debounceSearch, generation: generation)
        },
        onCreateSmartCollection: { [weak self] name, rule, completion in
            guard let coordinator = self?.libraryAccessCoordinator else {
                completion(nil)
                return
            }
            coordinator.createSmartCollection(
                name: name,
                rule: rule,
                completion: completion
            )
        },
        onUpdateSmartCollection: { [weak self] id, name, rule, completion in
            guard let coordinator = self?.libraryAccessCoordinator else {
                completion(nil)
                return
            }
            coordinator.updateSmartCollection(
                id: id,
                name: name,
                rule: rule,
                completion: completion
            )
        },
        onDeleteSmartCollection: { [weak self] id, completion in
            guard let coordinator = self?.libraryAccessCoordinator else {
                completion(false)
                return
            }
            coordinator.deleteSmartCollection(
                id: id,
                completion: completion
            )
        },
        onCreateTag: { [weak self] name, parentID in self?.libraryAccessCoordinator?.createTag(name: name, parentID: parentID) },
        onRenameTag: { [weak self] tag, name in self?.libraryAccessCoordinator?.renameTag(tag, name: name) },
        onDeleteTags: { [weak self] tags in self?.deleteTags(tags) },
        onMoveTags: { [weak self] tags, parentID, order in self?.libraryAccessCoordinator?.moveTags(tags, parentID: parentID, sortOrder: order) },
        onSetTagColor: { [weak self] tag, color in self?.libraryAccessCoordinator?.setTagColor(tag, color: color) },
        onMergeTag: { [weak self] source, target in self?.libraryAccessCoordinator?.mergeTag(source, into: target) },
        onAssignVideos: { [weak self] tag, videoIDs in self?.libraryAccessCoordinator?.setTagAssignment(tag, videoIDs: videoIDs, enabled: true) },
        onAssignTagID: { [weak self] tagID, videoIDs in self?.libraryAccessCoordinator?.setTagAssignment(tagID: tagID, videoIDs: videoIDs, enabled: true) },
        onApplyTagDraft: { [weak self] creations, assignments, videoIDs, completion in
            guard let coordinator = self?.libraryAccessCoordinator else {
                completion(false)
                return
            }
            coordinator.applyTagDraft(
                creations: creations,
                assignments: assignments,
                videoIDs: videoIDs,
                completion: completion
            )
        },
        loadTagStates: { [weak self] videoIDs, completion in self?.libraryAccessCoordinator?.tagAssignmentStates(videoIDs: videoIDs, completion: completion) }
    )

    private lazy var libraryAccessCoordinator: LibraryAccessCoordinator? = {
        guard let databaseStore else { return nil }
        return LibraryAccessCoordinator(
            database: databaseStore,
            resolveFolderImportMethod: { [weak self] in
                await self?.resolveFolderImportMethod()
            }
        )
    }()

    private lazy var settingsWindowController: NSWindowController = {
        let tabs = SettingsTabViewController(panes: SettingsPane.allCases.map { pane in
            (pane, settingsPaneController(pane))
        })
        let window = NSWindow(contentViewController: tabs)
        window.styleMask = [.titled, .closable]
        window.toolbarStyle = .preference
        window.isReleasedWhenClosed = false
        window.tabbingMode = .disallowed
        window.center()
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(settingsWindowWillClose(_:)),
            name: NSWindow.willCloseNotification,
            object: window
        )
        return NSWindowController(window: window)
    }()

    private func settingsPaneController(_ pane: SettingsPane) -> NSViewController {
        switch pane {
        case .importOptions:
            settingsHostingController(ImportSettingsView(preferences: preferencesStore))
        case .privacy:
            settingsHostingController(PrivacySettingsView(
                preferences: preferencesStore,
                setAuthenticationEnabled: { [weak self] enabled in
                    self?.setAuthenticationEnabled(enabled)
                }
            ))
        case .updates:
            settingsHostingController(UpdatesSettingsView(updates: updateController))
        }
    }

    private func settingsHostingController<Content: View>(_ view: Content) -> NSViewController {
        let controller = NSHostingController(rootView: view)
        controller.sizingOptions = .preferredContentSize
        return controller
    }

    private weak var presentedSettingsWindow: NSWindow?
    private var settingsWasKeyBeforePrivacyHide: Bool?

    override init() {
        let preferencesStore = PreferencesStore()
        self.preferencesStore = preferencesStore
        updateController = AppUpdateController(preferences: preferencesStore)
        lockCoordinator = LockCoordinator(
            isAuthenticationEnabled: preferencesStore.authenticationEnabled
        )

        do {
            databaseStore = try DatabaseStore.makeDefault()
        } catch {
            databaseStore = nil
            AppLogger.database.fault("Database initialization failed with category: \(String(describing: type(of: error)), privacy: .public)")
        }

        super.init()
        registerForPrivacyEvents()
        idleTimer = Timer.scheduledTimer(
            timeInterval: 5,
            target: self,
            selector: #selector(checkIdleLock),
            userInfo: nil,
            repeats: true
        )
    }

    func start() {
        lockCoordinator.onStateChange = { [weak self] state in
            self?.render(lockState: state)
        }
        libraryViewController.onExportToEditor = { [weak self] scope, format in
            self?.exportToEditor(scope, format: format)
        }

        libraryAccessCoordinator?.onVideosChanged = { [weak self] videos, queryGeneration in
            self?.libraryViewController.setVideos(videos, queryGeneration: queryGeneration)
        }
        libraryAccessCoordinator?.onSidebarFilterCountsChanged = { [weak self] counts in
            self?.libraryViewController.setSidebarFilterCounts(counts)
        }
        libraryAccessCoordinator?.onFilterChangedBySystem = { [weak self] filter in
            self?.libraryViewController.setFilterFromSystem(filter)
        }
        libraryAccessCoordinator?.mediaPriorityVideoIDs = { [weak self] in
            self?.libraryViewController.mediaPriorityVideoIDs() ?? []
        }
        libraryAccessCoordinator?.onVideoChanged = { [weak self] video in
            self?.libraryViewController.updateVideo(video)
        }
        libraryAccessCoordinator?.onImportStateChanged = { [weak self] state in
            guard let self else { return }
            libraryViewController.setImportState(state)
            switch state {
            case .completed, .cancelled, .failed:
                if libraryAccessCoordinator?.canUndoVideoRemoval == true {
                    libraryViewController.offerVideoRemovalUndoForCurrentStatus()
                }
            case .idle, .importing:
                break
            }
        }
        libraryAccessCoordinator?.onUndoHistoryChanged = { [weak self] in
            self?.dismissTagDeletionNoticeIfNoLongerUndoable()
        }
        libraryAccessCoordinator?.onScanStateChanged = { [weak self] state in
            self?.libraryViewController.setScanState(state)
        }
        libraryAccessCoordinator?.onTagsChanged = { [weak self] tags in
            self?.libraryViewController.setTags(tags)
        }
        libraryAccessCoordinator?.onSmartCollectionsChanged = { [weak self] collections in
            self?.libraryViewController.setSmartCollections(collections)
        }
        libraryAccessCoordinator?.onTagAssignmentsChanged = { [weak self] in
            self?.libraryViewController.refreshTagAssignments()
        }
        libraryAccessCoordinator?.onVideoRemovalRestored = { [weak self] videoIDs in
            self?.libraryViewController.showRestoredVideos(videoIDs)
        }
        libraryAccessCoordinator?.onVideoRemovalUndoDiscarded = { [weak self] in
            self?.libraryViewController.removeVideoRemovalUndoOffer()
        }
        libraryAccessCoordinator?.onError = { [weak self] message in
            self?.libraryViewController.setLibraryError(message)
        }
        libraryAccessCoordinator?.onOperationError = { [weak self] message in
            self?.libraryViewController.setOperationError(message)
        }
        libraryViewController.configureRecovery(
            onRecover: { [weak self] in self?.libraryAccessCoordinator?.recoverVideoAccess() },
            onStop: { [weak self] in self?.libraryAccessCoordinator?.stopAccessRecovery() },
            onDismiss: { [weak self] in self?.libraryAccessCoordinator?.dismissRecoveryResult() }
        )
        libraryAccessCoordinator?.onRecoveryChanged = { [weak self] status in
            self?.libraryViewController.setRecoveryStatus(status)
        }
        libraryAccessCoordinator?.onOperationStatusChanged = { [weak self] status in
            self?.libraryViewController.setOperationStatus(status)
        }
        libraryAccessCoordinator?.onRelinkingVideoChanged = { [weak self] videoID in
            self?.libraryViewController.setRelinkingVideoID(videoID)
        }

        installMainMenu()
        startUpdates()
        installModifierFlagsMonitor()
        quickLookCoordinator.install(in: windowController.window)
        render(lockState: lockCoordinator.state)
        windowController.window?.center()
        windowController.window?.makeKeyAndOrderFront(nil)
        libraryAccessCoordinator?.restoreLibrary()
        AppLogger.lifecycle.notice("Application started")
    }

    private func render(lockState: LockState) {
        switch lockState {
        case .unlocked:
            windowController.setRootViewController(libraryViewController)
        case .locked, .authenticating, .failed:
            settingsWasKeyBeforePrivacyHide = nil
            presentedSettingsWindow?.close()
            libraryViewController.setPresetShortcutHintsVisible(false)
            quickLookCoordinator.close()
            let view = LockView(
                state: lockState,
                unlock: { [weak self] in self?.lockCoordinator.unlock() }
            )
            windowController.setRootViewController(NSHostingController(rootView: view))
        }
    }

    @objc private func enableNativeFieldUndo(_ notification: Notification) {
        let editor = notification.userInfo?["NSFieldEditor"] as? NSTextView
            ?? (notification.object as? NSTextField)?.currentEditor() as? NSTextView
        editor?.allowsUndo = true
    }

    private func registerForPrivacyEvents() {
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(enableNativeFieldUndo(_:)),
            name: NSControl.textDidBeginEditingNotification,
            object: nil
        )
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(applicationWillResignActive),
            name: NSApplication.willResignActiveNotification,
            object: nil
        )
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(windowDidResignKey),
            name: NSWindow.didResignKeyNotification,
            object: windowController.window
        )
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(applicationDidBecomeActive),
            name: NSApplication.didBecomeActiveNotification,
            object: nil
        )
        NSWorkspace.shared.notificationCenter.addObserver(
            self,
            selector: #selector(workspaceRequiresLock),
            name: NSWorkspace.sessionDidResignActiveNotification,
            object: nil
        )
        NSWorkspace.shared.notificationCenter.addObserver(
            self,
            selector: #selector(workspaceRequiresLock),
            name: NSWorkspace.screensDidSleepNotification,
            object: nil
        )
        NSWorkspace.shared.notificationCenter.addObserver(
            self,
            selector: #selector(workspaceVolumeAvailabilityChanged(_:)),
            name: NSWorkspace.didMountNotification,
            object: nil
        )
        NSWorkspace.shared.notificationCenter.addObserver(
            self,
            selector: #selector(workspaceVolumeAvailabilityChanged(_:)),
            name: NSWorkspace.didUnmountNotification,
            object: nil
        )
    }

    @objc private func applicationWillResignActive() {
        libraryViewController.setPresetShortcutHintsVisible(false)
        guard lockCoordinator.isAuthenticationEnabled else { return }
        if let settings = presentedSettingsWindow, settings.isVisible, !settings.isMiniaturized {
            settingsWasKeyBeforePrivacyHide = settings.isKeyWindow
            settings.orderOut(nil)
        }
        installPrivacyShield()
        if preferencesStore.idleLockInterval == .immediately,
           lockCoordinator.state == .unlocked {
            lockCoordinator.lock()
        }
    }

    @objc private func applicationDidBecomeActive() {
        render(lockState: lockCoordinator.state)
        removePrivacyShield()
        guard let settingsWasKey = settingsWasKeyBeforePrivacyHide else { return }
        settingsWasKeyBeforePrivacyHide = nil
        guard lockCoordinator.state == .unlocked, let settings = presentedSettingsWindow else { return }
        if !settingsWasKey, let library = windowController.window, library.isKeyWindow {
            settings.order(.below, relativeTo: library.windowNumber)
        } else {
            settings.makeKeyAndOrderFront(nil)
        }
    }

    @objc private func settingsWindowWillClose(_ notification: Notification) {
        settingsWasKeyBeforePrivacyHide = nil
        presentedSettingsWindow = nil
    }

    @objc private func windowDidResignKey() {
        libraryViewController.setPresetShortcutHintsVisible(false)
    }

    private func installModifierFlagsMonitor() {
        guard modifierFlagsMonitor == nil else { return }
        modifierFlagsMonitor = NSEvent.addLocalMonitorForEvents(matching: .flagsChanged) {
            [weak self] event in
            guard let self else { return event }
            let commandIsPressed = event.modifierFlags
                .intersection(.deviceIndependentFlagsMask)
                .contains(.command)
            libraryViewController.setPresetShortcutHintsVisible(commandIsPressed)
            return event
        }
    }

    @objc private func workspaceRequiresLock() {
        guard lockCoordinator.isAuthenticationEnabled else { return }
        installPrivacyShield()
        lockCoordinator.lock()
    }

    @objc private func workspaceVolumeAvailabilityChanged(_ notification: Notification) {
        libraryAccessCoordinator?.refreshVolumeAvailability(
            interruptMediaProcessing: notification.name == NSWorkspace.didUnmountNotification
        )
    }

    @objc private func checkIdleLock() {
        guard lockCoordinator.isAuthenticationEnabled,
              lockCoordinator.state == .unlocked else { return }
        let interval = preferencesStore.idleLockInterval
        guard interval != .never, interval != .immediately else { return }
        guard let idleSeconds = systemIdleSeconds() else { return }
        if idleSeconds >= Double(interval.rawValue) { lockCoordinator.lock() }
    }

    private func systemIdleSeconds() -> TimeInterval? {
        Self.userActivityEventTypes.lazy
            .map {
                CGEventSource.secondsSinceLastEventType(
                    .combinedSessionState,
                    eventType: $0
                )
            }
            .filter { $0.isFinite && $0 >= 0 }
            .min()
    }

    private func startUpdates() {
        libraryViewController.setSidebarBottomAccessory(updateStatusView)
        updateStatusView.onInstall = { [weak self] in
            self?.updateController.installUpdate()
        }
        updateController.onShowLibraryWindow = { [weak self] in
            self?.showLibraryWindow()
        }
        updateController.onStatusChange = { [weak self] status in
            self?.updateStatusView.render(status)
        }
        updateController.start()
    }

    /// The app menu's update item, which installs instead once an update is ready to relaunch.
    @objc func checkForUpdates() {
        guard lockCoordinator.state == .unlocked else { return }
        switch updateController.status.menuCommand {
        case .checkForUpdates: updateController.checkForUpdates()
        case .relaunchToInstall: updateController.installUpdate()
        }
    }

    @objc func showSettings() {
        guard lockCoordinator.state == .unlocked else { return }
        settingsWasKeyBeforePrivacyHide = nil
        let controller = settingsWindowController
        presentedSettingsWindow = controller.window
        controller.showWindow(nil)
        controller.window?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    @objc func showAbout() {
        let version = AppConfiguration.version
        let credits = NSAttributedString(
            string: String(localized: .aboutLocalReadOnly),
            attributes: [
                .font: NSFont.systemFont(ofSize: NSFont.smallSystemFontSize),
                .foregroundColor: NSColor.secondaryLabelColor,
                .paragraphStyle: { () -> NSParagraphStyle in
                    let style = NSMutableParagraphStyle()
                    style.alignment = .center
                    return style
                }(),
            ]
        )
        var options: [NSApplication.AboutPanelOptionKey: Any] = [.credits: credits]
        if let displayVersion = version.displayVersion { options[.applicationVersion] = displayVersion }
        if let build = version.build { options[.version] = build }
        NSApp.orderFrontStandardAboutPanel(options: options)
        NSApp.activate(ignoringOtherApps: true)
    }

    @objc func showLibraryWindow() {
        windowController.showWindow(nil)
        guard let window = windowController.window else { return }
        if window.isMiniaturized { window.deminiaturize(nil) }
        window.makeKeyAndOrderFront(nil)
    }

    @objc func importVideos() {
        guard lockCoordinator.state == .unlocked else { return }
        guard let libraryAccessCoordinator else {
            libraryViewController.setLibraryError(String(localized: .errorDatabaseUnavailable))
            return
        }
        libraryAccessCoordinator.importVideos()
    }

    @objc func scanForNewVideos() {
        guard lockCoordinator.state == .unlocked,
              libraryViewController.canScanForNewVideos else { return }
        libraryAccessCoordinator?.scanForNewVideos()
    }

    private func resolveFolderImportMethod() async -> FolderImportMethod? {
        switch preferencesStore.folderImportPreference {
        case .direct:
            return .direct
        case .folderTags:
            return .folderTags(
                includeSelectedRoot: preferencesStore.includeSelectedFolderAsRootTag
            )
        case .ask:
            guard let window = windowController.window else { return nil }
            guard let decision = await folderImportMethodPresenter.present(
                on: window,
                includeSelectedRootByDefault: preferencesStore.includeSelectedFolderAsRootTag
            ) else {
                return nil
            }
            if decision.remember {
                switch decision.method {
                case .direct:
                    preferencesStore.folderImportPreference = .direct
                case let .folderTags(includeSelectedRoot):
                    preferencesStore.folderImportPreference = .folderTags
                    preferencesStore.includeSelectedFolderAsRootTag = includeSelectedRoot
                }
            }
            return decision.method
        }
    }

    /// Tags are deleted without asking; the notice offers the undo, and goes away once that undo no longer applies.
    private func deleteTags(_ tags: [TagRecord]) {
        guard let coordinator = libraryAccessCoordinator, let firstTag = tags.first else { return }
        coordinator.deleteTags(tags) { [weak self, weak coordinator] undoID in
            guard let self, let window = windowController.window else { return }
            let title = tags.count == 1
                ? String(localized: "tag.deleted.single", defaultValue: "Deleted “\(firstTag.name)”")
                : String(localized: "tag.deleted.multiple", defaultValue: "Deleted \(tags.count) Tags")
            let notice = TransientNotice.show(
                in: window,
                title: title,
                action: TransientNotice.Action(title: String(localized: .actionUndo)) {
                    coordinator?.undoTagMutation(undoID)
                }
            )
            tagDeletionNotice = (undoID, notice)
        }
    }

    private func dismissTagDeletionNoticeIfNoLongerUndoable() {
        guard let pending = tagDeletionNotice,
              libraryAccessCoordinator?.isLatestUndoableTagMutation(pending.undoID) != true else { return }
        TransientNotice.dismiss(pending.notice)
        tagDeletionNotice = nil
    }

    @objc func undoLastMutation() {
        guard lockCoordinator.state == .unlocked else { return }
        LibraryUndoRouting.perform(
            editingText: activeTextEditor != nil,
            textUndo: activeTextEditor?.undoManager,
            isLibraryKey: NSApp.keyWindow === windowController.window
        ) { [weak self] in
            self?.libraryAccessCoordinator?.undoLastMutation()
        }
    }

    private var activeTextEditor: NSTextView? {
        guard let editor = NSApp.keyWindow?.firstResponder as? NSTextView,
              editor.isEditable else { return nil }
        return editor
    }

    /// The library window is in front, unlocked, and its library loaded.
    private var libraryCommandsAvailable: Bool {
        lockCoordinator.state == .unlocked
            && NSApp.keyWindow === windowController.window
            && libraryViewController.canNavigateLibraryPresets
    }

    @objc func toggleLibrarySidebar() {
        guard libraryCommandsAvailable else { return }
        libraryViewController.toggleSidebar()
    }

    @objc func toggleLibraryInspector() {
        guard libraryCommandsAvailable else { return }
        libraryViewController.toggleInspector()
    }

    @objc func zoomInThumbnails() {
        guard libraryCommandsAvailable else { return }
        libraryViewController.adjustZoom(by: 10)
    }

    @objc func zoomOutThumbnails() {
        guard libraryCommandsAvailable else { return }
        libraryViewController.adjustZoom(by: -10)
    }

    @objc func resetThumbnailSize() {
        guard libraryCommandsAvailable else { return }
        libraryViewController.resetZoom()
    }

    @objc func saveAsSmartCollection() {
        guard libraryCommandsAvailable, databaseStore != nil else { return }
        libraryViewController.saveAsSmartCollection()
    }

    @objc func openSelectedVideos() {
        guard libraryCommandsAvailable else { return }
        libraryViewController.openSelectedVideos()
    }

    @objc func quickLookSelectedVideos() {
        guard lockCoordinator.state == .unlocked else { return }
        if quickLookCoordinator.isVisible {
            quickLookCoordinator.close()
            return
        }
        guard libraryCommandsAvailable else { return }
        libraryViewController.quickLookSelectedVideos()
    }

    @objc func revealSelectedVideos() {
        guard libraryCommandsAvailable else { return }
        libraryViewController.revealSelectedVideos()
    }

    @objc func copySelectedVideoPaths() {
        guard libraryCommandsAvailable else { return }
        libraryViewController.copySelectedVideoPaths()
    }

    @objc func addTagsToSelectedVideos() {
        guard libraryCommandsAvailable else { return }
        libraryViewController.focusTagInputForSelection()
    }

    @objc func exportSelectedVideosToEditor(_ sender: NSMenuItem) {
        guard libraryCommandsAvailable,
              let choice = sender.representedObject as? NLEExportMenuChoice else { return }
        libraryViewController.exportSelectedVideos(format: choice.format)
    }

    @objc func removeSelectedVideos() {
        guard libraryCommandsAvailable, activeTextEditor == nil else { return }
        libraryViewController.removeSelectedVideos()
    }

    @objc func createRootTag() {
        guard lockCoordinator.state == .unlocked else { return }
        libraryViewController.beginCreatingRootTag()
    }

    @objc func focusFilenameSearch() {
        guard lockCoordinator.state == .unlocked else { return }
        libraryViewController.focusFilenameSearch()
    }

    @objc func presentAddFilterMenu() {
        guard lockCoordinator.state == .unlocked else { return }
        libraryViewController.presentAddFilterMenu()
    }

    @objc func showAllVideos() {
        libraryViewController.navigateToPreset(.all)
    }

    @objc func showUntaggedVideos() {
        libraryViewController.navigateToPreset(.untagged)
    }

    @objc func showRecentVideos() {
        libraryViewController.navigateToPreset(.recent)
    }

    @objc func showUnavailableVideos() {
        libraryViewController.navigateToPreset(.unavailable)
    }

    private func openVideo(_ video: VideoRecord) {
        guard let url = libraryAccessCoordinator?.fileURL(for: video) else { return }
        NSWorkspace.shared.open(url)
    }

    private func revealVideos(_ videos: [VideoRecord]) {
        let urls = videos.compactMap { libraryAccessCoordinator?.fileURL(for: $0) }
        guard urls.isEmpty == false else { return }
        NSWorkspace.shared.activateFileViewerSelecting(urls)
    }

    private func exportToEditor(_ scope: VideoScope, format: NLEExportFormat) {
        guard lockCoordinator.state == .unlocked,
              let coordinator = libraryAccessCoordinator,
              let window = windowController.window else { return }
        let name = EditorExportPresenter.defaultName(for: scope)
        coordinator.nleExportPlan(for: scope, name: name) { [weak self] plan in
            guard let self else { return }
            guard let plan else {
                TransientNotice.show(in: window, title: String(localized: .exportEditorFailedTitle))
                return
            }
            self.editorExportPresenter.present(plan, format: format, on: window)
        }
    }

    /// One path per line when several videos are selected, as Finder copies them.
    private func copyPaths(_ videos: [VideoRecord]) {
        let paths = videos.compactMap { libraryAccessCoordinator?.fileURL(for: $0)?.path }
        guard paths.isEmpty == false else { return }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(paths.joined(separator: "\n"), forType: .string)
    }

    private func previewVideos(_ videos: [VideoRecord]) {
        let urls = videos.compactMap { libraryAccessCoordinator?.fileURL(for: $0) }
        quickLookCoordinator.toggle(urls: urls)
    }

    func validateMenuItem(_ menuItem: NSMenuItem) -> Bool {
        let libraryIsKey = NSApp.keyWindow === windowController.window
        if menuItem.action == #selector(importVideos) {
            return lockCoordinator.state == .unlocked && libraryIsKey && databaseStore != nil
        }
        if menuItem.action == #selector(scanForNewVideos) {
            return lockCoordinator.state == .unlocked && libraryIsKey
                && databaseStore != nil
                && libraryViewController.canScanForNewVideos
        }
        if menuItem.action == #selector(undoLastMutation) {
            guard lockCoordinator.state == .unlocked else { return false }
            if let editor = activeTextEditor {
                menuItem.title = String(localized: "menu.undoTyping", defaultValue: "Undo Typing")
                return editor.undoManager?.canUndo == true
            }
            menuItem.title = String(localized: .menuUndoLastAction)
            return NSApp.keyWindow === windowController.window
                && libraryAccessCoordinator?.canUndoLastMutation == true
        }
        switch menuItem.action {
        case #selector(toggleLibrarySidebar):
            menuItem.title = libraryViewController.isSidebarCollapsed
                ? String(localized: "menu.view.showSidebar", defaultValue: "Show Sidebar")
                : String(localized: "menu.view.hideSidebar", defaultValue: "Hide Sidebar")
            return libraryCommandsAvailable
        case #selector(toggleLibraryInspector):
            menuItem.title = libraryViewController.isInspectorCollapsed
                ? String(localized: "menu.view.showInspector", defaultValue: "Show Inspector")
                : String(localized: "menu.view.hideInspector", defaultValue: "Hide Inspector")
            return libraryCommandsAvailable
        case #selector(zoomInThumbnails):
            return libraryCommandsAvailable && libraryViewController.canZoomIn
        case #selector(zoomOutThumbnails):
            return libraryCommandsAvailable && libraryViewController.canZoomOut
        case #selector(resetThumbnailSize):
            return libraryCommandsAvailable && libraryViewController.canResetZoom
        case #selector(saveAsSmartCollection):
            return libraryCommandsAvailable && databaseStore != nil
                && libraryViewController.canSaveAsSmartCollection
        case #selector(openSelectedVideos), #selector(revealSelectedVideos),
             #selector(copySelectedVideoPaths), #selector(exportSelectedVideosToEditor(_:)):
            return libraryCommandsAvailable && libraryViewController.selectedVideosThatCanBeOpened.isEmpty == false
        case #selector(quickLookSelectedVideos):
            guard lockCoordinator.state == .unlocked else { return false }
            return quickLookCoordinator.isVisible
                || (libraryCommandsAvailable && libraryViewController.canQuickLookSelectedVideos)
        case #selector(addTagsToSelectedVideos):
            return libraryCommandsAvailable && libraryViewController.canFocusTagInputForSelection
        case #selector(removeSelectedVideos):
            if let title = libraryViewController.removeSelectedVideosTitle {
                menuItem.title = title
            }
            // Command-Delete edits text in a text field, and deletes tags when the sidebar has focus.
            return libraryCommandsAvailable && activeTextEditor == nil
                && libraryViewController.canRemoveSelectedVideos
        default:
            break
        }
        if menuItem.action == #selector(createRootTag) {
            return lockCoordinator.state == .unlocked && libraryIsKey
                && databaseStore != nil
                && libraryViewController.canBeginCreatingRootTag
        }
        if menuItem.action == #selector(focusFilenameSearch) {
            return lockCoordinator.state == .unlocked && libraryIsKey
                && databaseStore != nil
                && libraryViewController.canFocusFilenameSearch
        }
        if menuItem.action == #selector(presentAddFilterMenu) {
            return lockCoordinator.state == .unlocked && libraryIsKey
                && databaseStore != nil
                && libraryViewController.canUseRuleCommands
        }
        let presets: [Selector: LibraryFilter] = [
            #selector(showAllVideos): .all,
            #selector(showRecentVideos): .recent,
            #selector(showUntaggedVideos): .untagged,
            #selector(showUnavailableVideos): .unavailable,
        ]
        if let action = menuItem.action, let preset = presets[action] {
            return lockCoordinator.state == .unlocked && libraryIsKey
                && databaseStore != nil
                && libraryViewController.canNavigateToPreset(preset)
        }
        if menuItem.action == #selector(checkForUpdates) {
            let unlocked = lockCoordinator.state == .unlocked
            switch updateController.status.menuCommand {
            case .checkForUpdates:
                menuItem.title = String(localized: .menuCheckForUpdates)
                return unlocked && updateController.canCheckForUpdates
            case .relaunchToInstall:
                menuItem.title = String(localized: .menuRelaunchToInstallUpdate)
                return unlocked
            }
        }
        if menuItem.action == #selector(showSettings) {
            return lockCoordinator.state == .unlocked
        }
        return true
    }

    private func setAuthenticationEnabled(_ enabled: Bool) {
        Task {
            let accepted = await lockCoordinator.setAuthenticationEnabled(enabled)
            if accepted {
                preferencesStore.setAuthenticationEnabled(enabled)
                AppLogger.security.notice("Authentication preference changed: \(enabled, privacy: .public)")
            }
        }
    }

    private func installMainMenu() {
        let mainMenu = MainMenu.make(
            target: self,
            includesCheckForUpdates: AppUpdateController.isEnabledInThisBuild
        )
        NSApp.windowsMenu = MainMenu.windowMenu(in: mainMenu)
        NSApp.mainMenu = mainMenu
    }

    private func installPrivacyShield() {
        guard privacyShield == nil,
              let contentView = windowController.window?.contentView,
              let containerView = contentView.superview else { return }

        let shield = NSVisualEffectView(frame: contentView.convert(contentView.bounds, to: containerView))
        shield.autoresizingMask = [.width, .height]
        shield.material = .windowBackground
        shield.blendingMode = .withinWindow
        shield.state = .active

        let label = NSTextField(labelWithString: AppConfiguration.displayName)
        label.font = .systemFont(ofSize: 15, weight: .medium)
        label.textColor = .secondaryLabelColor
        label.translatesAutoresizingMaskIntoConstraints = false
        shield.addSubview(label)
        NSLayoutConstraint.activate([
            label.centerXAnchor.constraint(equalTo: shield.centerXAnchor),
            label.centerYAnchor.constraint(equalTo: shield.centerYAnchor),
        ])

        containerView.addSubview(shield, positioned: .above, relativeTo: contentView)
        privacyShield = shield
    }

    private func removePrivacyShield() {
        privacyShield?.removeFromSuperview()
        privacyShield = nil
    }
}

/// Cut, Copy, Paste and Select All go to whatever has focus: text fields edit text, and the video grid
/// selects every video it shows. Without these items their shortcuts do nothing anywhere in the app.
@MainActor
enum StandardEditMenu {
    static func items() -> [NSMenuItem] {
        [
            (String(localized: "menu.cut", defaultValue: "Cut"), #selector(NSText.cut(_:)), "x"),
            (String(localized: "menu.copy", defaultValue: "Copy"), #selector(NSText.copy(_:)), "c"),
            (String(localized: "menu.paste", defaultValue: "Paste"), #selector(NSText.paste(_:)), "v"),
            (String(localized: "menu.selectAll", defaultValue: "Select All"), #selector(NSText.selectAll(_:)), "a"),
        ].map { title, action, key in
            NSMenuItem(title: title, action: action, keyEquivalent: key)
        }
    }
}

@MainActor
enum LibraryUndoRouting {
    static func perform(editingText: Bool, textUndo: UndoManager?, isLibraryKey: Bool, catalogUndo: () -> Void) {
        if editingText {
            if textUndo?.canUndo == true { textUndo?.undo() }
        } else if isLibraryKey {
            catalogUndo()
        }
    }
}

@MainActor
private final class QuickLookPreviewCoordinator: NSResponder,
    @preconcurrency QLPreviewPanelDataSource {
    private var previewURLs: [URL] = []
    private weak var activePanel: QLPreviewPanel?
    private weak var hostWindow: NSWindow?
    private var escapeMonitor: Any?

    func install(in window: NSWindow?) {
        guard let window,
              hostWindow !== window else { return }
        if let hostWindow, hostWindow.nextResponder === self {
            hostWindow.nextResponder = nextResponder
        }
        hostWindow = window
        nextResponder = window.nextResponder
        window.nextResponder = self
        if escapeMonitor == nil {
            escapeMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) {
                [weak self] event in
                guard event.keyCode == 53,
                      self?.activePanel?.isVisible == true else { return event }
                self?.close()
                return nil
            }
        }
    }

    var isVisible: Bool { activePanel?.isVisible == true }

    func toggle(urls: [URL]) {
        guard urls.isEmpty == false, let panel = QLPreviewPanel.shared() else { return }
        if panel.isVisible {
            close()
            return
        }

        previewURLs = urls
        activePanel = panel
        panel.updateController()
        panel.makeKeyAndOrderFront(nil)
    }

    func close() {
        guard let panel = activePanel else {
            previewURLs = []
            return
        }
        panel.orderOut(nil)
        if panel.dataSource === self {
            panel.dataSource = nil
        }
        activePanel = nil
        previewURLs = []
    }

    override func acceptsPreviewPanelControl(_ panel: QLPreviewPanel!) -> Bool {
        previewURLs.isEmpty == false
    }

    override func beginPreviewPanelControl(_ panel: QLPreviewPanel!) {
        activePanel = panel
        panel.dataSource = self
        panel.currentPreviewItemIndex = 0
        panel.reloadData()
    }

    override func endPreviewPanelControl(_ panel: QLPreviewPanel!) {
        if panel.dataSource === self {
            panel.dataSource = nil
        }
        if activePanel === panel {
            activePanel = nil
            previewURLs = []
        }
    }

    func numberOfPreviewItems(in panel: QLPreviewPanel!) -> Int {
        previewURLs.count
    }

    func previewPanel(_ panel: QLPreviewPanel!, previewItemAt index: Int) -> QLPreviewItem! {
        guard previewURLs.indices.contains(index) else { return nil }
        return previewURLs[index] as NSURL
    }
}
