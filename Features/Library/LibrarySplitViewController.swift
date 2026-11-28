import AppKit

@MainActor
final class LibrarySplitViewController: NSSplitViewController, NSToolbarDelegate, NSToolbarItemValidation {
    private enum NavigationTarget {
        case filter(LibraryFilter)
        case smartCollection(SmartCollectionRecord)
    }

    private static let toolbarIdentifier = NSToolbar.Identifier("LibraryToolbar")
    private static let searchItemIdentifier = NSToolbarItem.Identifier("LibrarySearch")
    private static let scanItemIdentifier = NSToolbarItem.Identifier("ScanForNewVideos")
    private static let zoomItemIdentifier = NSToolbarItem.Identifier("LibraryZoom")
    private static let zoomOutItemIdentifier = NSToolbarItem.Identifier("LibraryZoomOut")
    private static let zoomSliderItemIdentifier = NSToolbarItem.Identifier("LibraryZoomSlider")
    private static let zoomInItemIdentifier = NSToolbarItem.Identifier("LibraryZoomIn")
    private static let toggleSidebarItemIdentifier = NSToolbarItem.Identifier("ToggleLibrarySidebar")
    private static let toggleInspectorItemIdentifier = NSToolbarItem.Identifier("ToggleLibraryInspector")
    private static let contextTitleItemIdentifier = NSToolbarItem.Identifier("LibraryContextTitle")
    private static let splitViewAutosaveName = "MainLibrarySplitView"
    private static let splitViewAutosaveDefaultsKey = "NSSplitView Subview Frames \(splitViewAutosaveName)"

    private let videoGridViewController: VideoGridViewController
    private let scanResultsViewController: ScanResultsViewController
    private let ruleBarViewController = LibraryRuleBarViewController()
    private let libraryContentViewController: LibraryContentViewController
    private let inspectorViewController: InspectorViewController
    private let sidebarViewController: SidebarViewController
    var onExportToEditor: (VideoScope, NLEExportFormat) -> Void = { _, _ in } {
        didSet {
            sidebarViewController.onExportToEditor = onExportToEditor
            videoGridViewController.onExportToEditor = onExportToEditor
        }
    }
    /// The query, whether to debounce it, and its filter-change generation.
    private let onQueryChanged: (LibraryQueryRequest, Bool, Int) -> Void
    private let onCreateSmartCollection: (
        String,
        LibraryQueryRule,
        @escaping (SmartCollectionRecord?) -> Void
    ) -> Void
    private let onUpdateSmartCollection: (
        String,
        String?,
        LibraryQueryRule?,
        @escaping (SmartCollectionRecord?) -> Void
    ) -> Void
    private let onDeleteSmartCollection: (String, @escaping (Bool) -> Void) -> Void
    private let onEndVideoRemovalUndo: () -> Void
    private let onScanForNewVideos: () -> Void
    private let onChooseAdditionalScanFolders: () -> Void
    private let onImportScannedVideos: ([String]) -> Void
    private let onClearScanResults: () -> Void
    private var contextTitle = String(localized: .libraryAllVideos)
    private var contextTagID: String?
    private var contextStatus: String?
    private var isImporting = false
    private var isScanWorking = false
    private var isShowingScanResults = false
    private var currentScanResults: LibraryScanResults?
    private var scanSearchText = ""
    private var libraryVideoCount = 0
    private var sidebarFilterCounts = SidebarFilterCounts.zero
    private var contextBeforeScan: (title: String, tagID: String?, status: String?)?
    private var visibleVideoCount = 0
    private var tags: [TagRecord] = []
    private var smartCollections: [SmartCollectionRecord] = []
    private var currentBaseFilter: LibraryFilter = .all
    private var temporaryFilenameSearch = ""
    private var currentRule = LibraryQueryRule.standard
    private var currentGrouping = VideoGroupingPreference.persisted()
    private var groupingBeforeRecent: VideoGroupingPreference?
    private var selectedSmartCollection: SmartCollectionRecord?
    private var pendingNavigationTarget: NavigationTarget?
    private var isPresentingSmartCollectionAlert = false
    private var dropsConditionsOfRemovedSmartCollection = false
    private var pendingVideoRevealRequest: VideoRevealRequest?
    private var resetBrowsingStateForNextVideoUpdate = false
    private var filterQueryGenerations = FilterQueryGenerations()
    private var didApplyInitialLayout = false
    private var shouldApplyInitialLayout = false
    private var isLibraryAvailable = true
    private weak var searchToolbarItem: NSSearchToolbarItem?
    private weak var scanToolbarButton: NSButton?
    private weak var zoomSlider: NSSlider?
    private weak var zoomOutButton: NSButton?
    private weak var zoomInButton: NSButton?
    private weak var sidebarToggleButton: NSButton?
    private weak var inspectorToggleButton: NSButton?
    private weak var contextTitleView: ToolbarTitleView?
    private var sidebarSplitViewItem: NSSplitViewItem?
    private var inspectorSplitViewItem: NSSplitViewItem?
    private lazy var libraryToolbar: NSToolbar = {
        let toolbar = NSToolbar(identifier: Self.toolbarIdentifier)
        toolbar.delegate = self
        toolbar.displayMode = .iconOnly
        toolbar.allowsUserCustomization = false
        return toolbar
    }()
    init(
        onCancelImport: @escaping () -> Void,
        onImportDroppedItems: @escaping ([URL]) -> Void,
        onScanForNewVideos: @escaping () -> Void,
        onChooseAdditionalScanFolders: @escaping () -> Void,
        onImportScannedVideos: @escaping ([String]) -> Void,
        onClearScanResults: @escaping () -> Void,
        onRemoveVideos: @escaping ([String], @escaping (Bool) -> Void) -> Void,
        onRelinkVideo: @escaping (VideoRecord) -> Void,
        onRetryRelinkVideo: @escaping (String) -> Void,
        onUndoLastMutation: @escaping () -> Void,
        onEndVideoRemovalUndo: @escaping () -> Void,
        onOpenVideo: @escaping (VideoRecord) -> Void,
        onRevealVideos: @escaping ([VideoRecord]) -> Void,
        onCopyPaths: @escaping ([VideoRecord]) -> Void,
        onPreviewVideos: @escaping ([VideoRecord]) -> Void,
        thumbnailURL: @escaping (VideoRecord) -> URL?,
        resolveVideos: @escaping ([VideoRecord]) -> ResolvedVideos,
        resolveVideosInScopes: @escaping @MainActor ([VideoScope]) async -> ResolvedVideos,
        filePath: @escaping (VideoRecord) -> String?,
        offlineSourceName: @escaping (VideoRecord) -> String?,
        onQueryChanged: @escaping (LibraryQueryRequest, Bool, Int) -> Void,
        onCreateSmartCollection: @escaping (
            String,
            LibraryQueryRule,
            @escaping (SmartCollectionRecord?) -> Void
        ) -> Void,
        onUpdateSmartCollection: @escaping (
            String,
            String?,
            LibraryQueryRule?,
            @escaping (SmartCollectionRecord?) -> Void
        ) -> Void,
        onDeleteSmartCollection: @escaping (String, @escaping (Bool) -> Void) -> Void,
        onCreateTag: @escaping (String, String?) -> Void,
        onRenameTag: @escaping (TagRecord, String) -> Void,
        onDeleteTags: @escaping ([TagRecord]) -> Void,
        onMoveTags: @escaping ([TagRecord], String?, Int) -> Void,
        onSetTagColor: @escaping ([TagRecord], String?) -> Void,
        onMergeTags: @escaping ([TagRecord], TagRecord) -> Void,
        onAssignVideos: @escaping (TagRecord, [String]) -> Void,
        onAssignTagID: @escaping (String, [String]) -> Void,
        onApplyTagDraft: @escaping ([TagCreationDraft], [String: Bool], [String], @escaping (Bool) -> Void) -> Void,
        loadTagStates: @escaping ([String], @escaping ([String: TagAssignmentState]) -> Void) -> Void
    ) {
        self.onQueryChanged = onQueryChanged
        self.onCreateSmartCollection = onCreateSmartCollection
        self.onUpdateSmartCollection = onUpdateSmartCollection
        self.onDeleteSmartCollection = onDeleteSmartCollection
        self.onEndVideoRemovalUndo = onEndVideoRemovalUndo
        self.onScanForNewVideos = onScanForNewVideos
        self.onChooseAdditionalScanFolders = onChooseAdditionalScanFolders
        self.onImportScannedVideos = onImportScannedVideos
        self.onClearScanResults = onClearScanResults
        let inspector = InspectorViewController(
            onApplyTagDraft: onApplyTagDraft,
            loadTagStates: loadTagStates,
            filePath: filePath,
            offlineSourceName: offlineSourceName,
            onRelinkVideo: onRelinkVideo,
            onRemoveVideos: onRemoveVideos
        )
        inspectorViewController = inspector
        sidebarViewController = SidebarViewController(
            onFilterChanged: { _ in },
            onSmartCollectionSelected: { _ in },
            onRenameSmartCollection: { _, _ in },
            onDeleteSmartCollection: { _ in },
            onScanResultsSelected: {},
            onCloseScanResults: {},
            onCreateTag: onCreateTag,
            onRenameTag: onRenameTag,
            onDeleteTags: onDeleteTags,
            onMoveTags: onMoveTags,
            onSetColor: onSetTagColor,
            onMergeTags: onMergeTags,
            onAssignVideos: onAssignVideos
        )
        videoGridViewController = VideoGridViewController(
            onOpenVideo: onOpenVideo,
            onRevealVideos: onRevealVideos,
            onCopyPaths: onCopyPaths,
            onRelinkVideo: onRelinkVideo,
            onRetryRelinkVideo: onRetryRelinkVideo,
            onPreviewVideos: onPreviewVideos,
            onSelectionChanged: { [weak inspector] videos in inspector?.setSelection(videos) },
            thumbnailURL: thumbnailURL,
            resolveVideos: resolveVideos,
            onAssignTagID: onAssignTagID,
            onCancelImport: onCancelImport,
            onImportDroppedItems: onImportDroppedItems,
            onRemoveVideos: onRemoveVideos,
            onUndoLastMutation: onUndoLastMutation,
            onDismissNotification: onEndVideoRemovalUndo
        )
        let scanResults = ScanResultsViewController()
        scanResultsViewController = scanResults
        libraryContentViewController = LibraryContentViewController(
            ruleBarViewController: ruleBarViewController,
            videoGridViewController: videoGridViewController,
            scanResultsViewController: scanResults
        )
        super.init(nibName: nil, bundle: nil)
        sidebarViewController.resolveVideosInScopes = resolveVideosInScopes
        sidebarViewController.canSelectAllVideos = { [weak self] in
            guard let self else { return false }
            return showsLibraryGrid && videoGridViewController.hasVisibleVideos
        }
        sidebarViewController.onSelectAllVideos = { [weak self] in
            self?.videoGridViewController.selectAllVisibleVideosAndFocus()
        }
        inspectorViewController.onVideoRemoved = { [weak self] count in
            self?.videoGridViewController.showVideoRemovalUndo(videoCount: count)
        }
        videoGridViewController.onZoomChanged = { [weak self] in
            self?.updateZoomControls()
        }
        videoGridViewController.onSelectionChanged = { [weak self] videos in
            self?.inspectorViewController.setSelection(videos)
        }
        videoGridViewController.onViewVideos = { [weak self] request in
            self?.viewVideos(request)
        }
        sidebarViewController.setNavigationHandlers(
            filter: { [weak self] filter in self?.requestNavigation(to: .filter(filter)) },
            smartCollection: { [weak self] collection in
                self?.requestNavigation(to: .smartCollection(collection))
            },
            renameSmartCollection: { [weak self] collection, name in
                self?.renameSmartCollection(collection, to: name)
            },
            deleteSmartCollection: { [weak self] collection in
                self?.presentDeleteSmartCollection(collection)
            },
            scanResults: { [weak self] in self?.showCurrentScanResults() },
            closeScanResults: { [weak self] in self?.onClearScanResults() }
        )
        scanResultsViewController.onImportSelected = { [weak self] ids in
            self?.onImportScannedVideos(ids)
        }
        scanResultsViewController.onChooseFolders = { [weak self] in
            self?.onChooseAdditionalScanFolders()
        }
        scanResultsViewController.onCloseResults = { [weak self] in
            self?.onClearScanResults()
        }
        scanResultsViewController.onSelectionChanged = { [weak self] candidates in
            self?.inspectorViewController.setScannedCandidates(candidates)
        }
        configureRuleBarCallbacks()
    }

    func showRestoredVideos(_ videoIDs: [String]) {
        videoGridViewController.showRestoredVideos(videoIDs)
    }

    func offerVideoRemovalUndoForCurrentStatus() {
        videoGridViewController.offerVideoRemovalUndoForCurrentStatus()
    }

    func removeVideoRemovalUndoOffer() {
        videoGridViewController.removeVideoRemovalUndoOffer()
    }

    var canUseRuleCommands: Bool {
        isLibraryAvailable && isShowingScanResults == false
    }

    // Toolbar controls stay usable when the library fails to load; the failure is reported in the title.
    var canFocusFilenameSearch: Bool { true }

    func focusFilenameSearch() {
        guard canFocusFilenameSearch, let searchField = searchToolbarItem?.searchField else { return }
        view.window?.makeFirstResponder(searchField)
        searchField.selectText(nil)
    }

    func presentAddFilterMenu() {
        guard canUseRuleCommands else { return }
        ruleBarViewController.presentAddFilterMenu()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        videoGridViewController.setGrouping(currentGrouping)

        let sidebarItem = NSSplitViewItem(sidebarWithViewController: sidebarViewController)
        sidebarItem.minimumThickness = 190
        sidebarItem.maximumThickness = 320
        sidebarItem.preferredThicknessFraction = 0.2
        sidebarSplitViewItem = sidebarItem

        let gridItem = NSSplitViewItem(viewController: libraryContentViewController)
        gridItem.minimumThickness = 420

        let inspectorItem = NSSplitViewItem(inspectorWithViewController: inspectorViewController)
        inspectorItem.minimumThickness = 240
        inspectorItem.maximumThickness = 380
        inspectorItem.canCollapse = true
        inspectorItem.preferredThicknessFraction = 0.24
        inspectorItem.isCollapsed = false
        inspectorSplitViewItem = inspectorItem

        addSplitViewItem(sidebarItem)
        addSplitViewItem(gridItem)
        addSplitViewItem(inspectorItem)

        splitView.dividerStyle = .thin
        shouldApplyInitialLayout = UserDefaults.standard.object(forKey: Self.splitViewAutosaveDefaultsKey) == nil
        splitView.autosaveName = Self.splitViewAutosaveName
    }

    func configureRecovery(onRecover: @escaping () -> Void, onStop: @escaping () -> Void, onDismiss: @escaping () -> Void) {
        libraryContentViewController.onRecover = onRecover
        libraryContentViewController.onStopRecovery = onStop
        libraryContentViewController.onDismissRecovery = onDismiss
    }

    func setRecoveryStatus(_ status: RecoveryStatus) {
        libraryContentViewController.setRecoveryStatus(status)
    }

    func makeToolbar() -> NSToolbar { libraryToolbar }

    func setSidebarBottomAccessory(_ accessory: NSView) {
        sidebarViewController.setBottomAccessory(accessory)
    }

    override func viewDidLayout() {
        super.viewDidLayout()
        updateSplitViewToggleState()
        alignToolbarTitle()
    }

    override func viewDidAppear() {
        super.viewDidAppear()
        updateWindowTitle()
        guard didApplyInitialLayout == false else { return }
        didApplyInitialLayout = true
        guard shouldApplyInitialLayout else { return }

        let width = splitView.bounds.width
        guard width > 0 else { return }
        splitView.setPosition(220, ofDividerAt: 0)
        splitView.setPosition(max(640, width - 280), ofDividerAt: 1)
    }

    func setVideos(_ videos: [VideoRecord], queryGeneration: Int) {
        if isLibraryAvailable == false {
            // A later successful load recovers from an earlier library error.
            isLibraryAvailable = true
            setContextStatus(nil)
            updateGridEmptyContent()
            updateToolbarState()
        }
        visibleVideoCount = videos.count
        let resetBrowsingState = resetBrowsingStateForNextVideoUpdate
        resetBrowsingStateForNextVideoUpdate = false
        let isFilterChange = filterQueryGenerations.resultIsFilterChange(generation: queryGeneration)
        videoGridViewController.setVideos(
            videos,
            resetBrowsingState: resetBrowsingState,
            isFilterChange: isFilterChange
        )
        if let request = pendingVideoRevealRequest,
           videoGridViewController.selectAndRevealVideos(ids: request.videoIDs) {
            pendingVideoRevealRequest = nil
        }
        updateWindowTitle()
    }

    func setOperationStatus(_ status: LibraryOperationStatus?) {
        videoGridViewController.setOperationStatus(status)
    }

    func setRelinkingVideoID(_ videoID: String?) {
        videoGridViewController.setRelinkingVideoID(videoID)
        inspectorViewController.setRelinkingVideoID(videoID)
    }

    func setSidebarFilterCounts(_ counts: SidebarFilterCounts) {
        libraryVideoCount = counts.all + counts.unavailable
        updateGridEmptyContent()
        sidebarFilterCounts = counts
        sidebarViewController.setFilterCounts(counts)
        updateToolbarState()
        if !isShowingScanResults, selectedSmartCollection == nil,
           !isPresetVisible(currentBaseFilter) {
            requestNavigation(to: .filter(.all))
        }
    }

    var canScanForNewVideos: Bool {
        libraryVideoCount > 0
            && isImporting == false
            && isScanWorking == false
    }

    func setScanState(_ state: LibraryScanState) {
        switch state {
        case .idle:
            isScanWorking = false
            sidebarViewController.setScanResultsCloseEnabled(true)
            currentScanResults = nil
            sidebarViewController.setScanResultCount(nil)
            scanResultsViewController.reset()
            leaveScanResults()
        case let .scanning(title, detail):
            isScanWorking = true
            sidebarViewController.setScanResultsCloseEnabled(false)
            currentScanResults = nil
            sidebarViewController.setScanResultCount(nil)
            if isShowingScanResults == false { contextStatus = nil }
            enterScanResults(selectSidebar: false)
            contextTitle = title
            updateWindowTitle()
            scanResultsViewController.showScanning(title: title, detail: detail)
        case let .results(results):
            isScanWorking = false
            sidebarViewController.setScanResultsCloseEnabled(true)
            currentScanResults = results
            let keepsTemporaryGroup = results.candidates.isEmpty == false
                || results.notice != nil
            sidebarViewController.setScanResultCount(
                keepsTemporaryGroup ? results.candidates.count : nil
            )
            if keepsTemporaryGroup
                || results.uncheckedFolderCount > 0
                || results.failedFolderCount > 0 {
                enterScanResults(selectSidebar: keepsTemporaryGroup)
                scanResultsViewController.showResults(results)
            } else {
                leaveScanResults()
                setContextStatus(String(
                    localized: "scan.empty.title",
                    defaultValue: "No New Videos Found"
                ))
            }
        case let .importing(title, detail, results):
            isScanWorking = true
            sidebarViewController.setScanResultsCloseEnabled(false)
            currentScanResults = results
            sidebarViewController.setScanResultCount(results.candidates.count)
            enterScanResults(selectSidebar: true)
            contextTitle = title
            updateWindowTitle()
            scanResultsViewController.showImporting(
                title: title,
                detail: detail,
                results: results
            )
        case let .completed(completion):
            isScanWorking = false
            sidebarViewController.setScanResultsCloseEnabled(true)
            currentScanResults = nil
            sidebarViewController.setScanResultCount(nil)
            scanResultsViewController.reset()
            leaveScanResults()
            var seenVideoIDs = Set<String>()
            let targetVideoIDs = (completion.addedVideoIDs + completion.existingVideoIDs)
                .filter { seenVideoIDs.insert($0).inserted }
            if targetVideoIDs.isEmpty == false {
                viewVideos(VideoRevealRequest(
                    videoIDs: targetVideoIDs,
                    destination: completion.existingVideoIDs.isEmpty ? .recent : .all
                ))
            }
        case let .failed(message):
            isScanWorking = false
            sidebarViewController.setScanResultsCloseEnabled(true)
            currentScanResults = nil
            sidebarViewController.setScanResultCount(nil)
            scanResultsViewController.reset()
            leaveScanResults()
            setContextStatus(message)
        }
        updateToolbarState()
    }

    private func showCurrentScanResults() {
        guard let currentScanResults else { return }
        enterScanResults(selectSidebar: true)
        scanResultsViewController.showResults(currentScanResults)
    }

    private func enterScanResults(selectSidebar: Bool) {
        loadViewIfNeeded()
        if isShowingScanResults == false {
            contextBeforeScan = (contextTitle, contextTagID, contextStatus)
        }
        isShowingScanResults = true
        libraryContentViewController.setShowsScanResults(true)
        inspectorViewController.setBrowsingContext(.scanResults)
        inspectorViewController.setScannedCandidates([])
        contextTitle = String(
            localized: "scan.sidebar.pending",
            defaultValue: "Videos to Import"
        )
        contextTagID = nil
        contextStatus = nil
        searchToolbarItem?.searchField.stringValue = scanSearchText
        scanResultsViewController.setSearchText(scanSearchText)
        if selectSidebar { sidebarViewController.selectScanResults() }
        updateWindowTitle()
    }

    private func leaveScanResults() {
        guard isShowingScanResults else { return }
        isShowingScanResults = false
        libraryContentViewController.setShowsScanResults(false)
        if let previous = contextBeforeScan {
            contextTitle = previous.title
            contextTagID = previous.tagID
            contextStatus = previous.status
        }
        contextBeforeScan = nil
        searchToolbarItem?.searchField.stringValue = temporaryFilenameSearch
        updateInspectorBrowsingContext()
        restoreCurrentSidebarSelection()
        updateWindowTitle()
    }

    func setPresetShortcutHintsVisible(_ visible: Bool) {
        sidebarViewController.setPresetShortcutHintsVisible(visible)
    }

    var canNavigateLibraryPresets: Bool {
        isLibraryAvailable
    }

    /// Untagged and Unavailable Videos are in the sidebar only while they have videos.
    func canNavigateToPreset(_ filter: LibraryFilter) -> Bool {
        canNavigateLibraryPresets && isPresetVisible(filter)
    }

    // MARK: Video menu, acting on the grid's selection

    private var showsLibraryGrid: Bool {
        isLibraryAvailable && isShowingScanResults == false
    }

    var selectedVideosThatCanBeOpened: [VideoRecord] {
        showsLibraryGrid ? videoGridViewController.selectedVideosThatCanBeOpened : []
    }

    var selectedVideosThatCanBeExported: [VideoRecord] {
        showsLibraryGrid ? videoGridViewController.selectedVideosThatCanBeExported : []
    }

    var canQuickLookSelectedVideos: Bool {
        selectedVideosThatCanBeOpened.isEmpty == false
    }

    func openSelectedVideos() {
        guard showsLibraryGrid else { return }
        videoGridViewController.openSelectedVideos()
    }

    func quickLookSelectedVideos() {
        guard showsLibraryGrid else { return }
        videoGridViewController.previewSelection()
    }

    func revealSelectedVideos() {
        guard showsLibraryGrid else { return }
        videoGridViewController.revealSelectedVideos()
    }

    func copySelectedVideoPaths() {
        guard showsLibraryGrid else { return }
        videoGridViewController.copySelectedVideoPaths()
    }

    func exportSelectedVideos(format: NLEExportFormat) {
        guard showsLibraryGrid else { return }
        videoGridViewController.exportSelectedVideos(format: format)
    }

    var removeSelectedVideosTitle: String? {
        videoGridViewController.removeSelectedVideosTitle
    }

    /// Only while the grid has focus, so Command-Delete in the sidebar still deletes tags.
    var canRemoveSelectedVideos: Bool {
        showsLibraryGrid
            && videoGridViewController.hasKeyboardFocus
            && videoGridViewController.selectedVideos().isEmpty == false
    }

    func removeSelectedVideos() {
        guard canRemoveSelectedVideos else { return }
        videoGridViewController.requestRemoveSelectedVideos()
    }

    var canFocusTagInputForSelection: Bool {
        showsLibraryGrid && inspectorViewController.canFocusTagInput
    }

    /// Opens the inspector if it is hidden, then puts the cursor in its tag field.
    func focusTagInputForSelection() {
        guard canFocusTagInputForSelection, let inspectorSplitViewItem else { return }
        guard inspectorSplitViewItem.isCollapsed else {
            inspectorViewController.focusTagInput()
            return
        }
        inspectorToggleButton?.state = .on
        NSAnimationContext.runAnimationGroup { _ in
            inspectorSplitViewItem.animator().isCollapsed = false
        } completionHandler: { [weak self] in
            self?.inspectorViewController.focusTagInput()
        }
    }

    var canSaveAsSmartCollection: Bool {
        guard canUseRuleCommands else { return false }
        if selectedSmartCollection != nil { return smartCollectionIsDirty }
        return ruleBarContext.canSaveRuleAsSmartCollection
    }

    /// The same as Save in the search bar, or Save As… while a smart collection's rule is modified.
    func saveAsSmartCollection() {
        guard canSaveAsSmartCollection else { return }
        presentSaveSmartCollection()
    }

    private func isPresetVisible(_ filter: LibraryFilter) -> Bool {
        switch filter {
        case .untagged: sidebarFilterCounts.untagged > 0
        case .unavailable: sidebarFilterCounts.unavailable > 0
        default: true
        }
    }

    func navigateToPreset(_ filter: LibraryFilter) {
        guard canNavigateLibraryPresets, isPresetVisible(filter) else { return }
        requestNavigation(to: .filter(filter))
    }

    func setFilterFromSystem(_ filter: LibraryFilter) {
        if isSameNavigationTarget(.filter(filter)) == false {
            onEndVideoRemovalUndo()
            resetBrowsingStateForNextVideoUpdate = true
        }
        transitionGrouping(to: .filter(filter))
        currentBaseFilter = filter
        selectedSmartCollection = nil
        sidebarViewController.selectFilter(filter)
        updateContext(for: filter)
        updateInspectorBrowsingContext()
        refreshRuleBar()
    }

    func mediaPriorityVideoIDs() -> [String] {
        guard !isShowingScanResults else { return [] }
        return videoGridViewController.mediaPriorityVideoIDs()
    }

    func updateVideo(_ video: VideoRecord) {
        videoGridViewController.updateVideo(video)
    }

    func setTags(_ tags: [TagRecord]) {
        self.tags = tags
        if let contextTagID,
           let selectedTag = tags.first(where: { $0.id == contextTagID }) {
            contextTitle = selectedTag.name
        }
        sidebarViewController.setTags(tags)
        inspectorViewController.setTags(tags)
        refreshRuleBar()
        updateWindowTitle()
    }

    func setSmartCollections(_ collections: [SmartCollectionRecord]) {
        smartCollections = collections
        var needsQuery = false
        if let selected = selectedSmartCollection {
            if let updated = collections.first(where: { $0.id == selected.id }) {
                // An undo can put back the saved rule; follow it unless the filter has unsaved edits.
                if currentRule.normalized() == selected.rule.normalized(),
                   updated.rule.normalized() != selected.rule.normalized() {
                    currentRule = updated.rule
                    needsQuery = true
                }
                selectedSmartCollection = updated
                if updated.name != selected.name { setContextTitle(updated.name, tagID: nil) }
            } else {
                // Gone, for example by undoing its creation: show All Videos; an undo keeps its conditions
                // unsaved, a delete drops them.
                if dropsConditionsOfRemovedSmartCollection {
                    currentRule = .standard
                    setTemporaryFilenameSearch("", applyQuery: false)
                }
                dropsConditionsOfRemovedSmartCollection = false
                selectedSmartCollection = nil
                currentBaseFilter = .all
                updateContext(for: .all)
                updateInspectorBrowsingContext()
                needsQuery = true
            }
        }
        sidebarViewController.setSmartCollections(collections)
        if selectedSmartCollection == nil, needsQuery { sidebarViewController.selectFilter(.all) }
        refreshRuleBar()
        if needsQuery { applyCurrentQuery() }
    }

    private var smartCollectionIsDirty: Bool {
        guard let selectedSmartCollection else { return false }
        return currentRule.normalized() != selectedSmartCollection.rule.normalized()
    }

    private func configureRuleBarCallbacks() {
        ruleBarViewController.onRuleChanged = { [weak self] rule in
            guard let self else { return }
            currentRule = rule.normalized()
            refreshRuleBar()
            applyCurrentQuery(debounce: true)
        }
        ruleBarViewController.onClearTemporarySearch = { [weak self] in
            self?.setTemporaryFilenameSearch("")
        }
        ruleBarViewController.onClearRules = { [weak self] in
            guard let self else { return }
            currentRule = .standard
            setTemporaryFilenameSearch("", applyQuery: false)
            refreshRuleBar()
            applyCurrentQuery()
        }
        ruleBarViewController.onSaveAs = { [weak self] in
            self?.presentSaveSmartCollection()
        }
        ruleBarViewController.onRevert = { [weak self] in
            guard let self, let selectedSmartCollection else { return }
            currentRule = selectedSmartCollection.rule
            refreshRuleBar()
            applyCurrentQuery()
        }
        ruleBarViewController.onUpdate = { [weak self] in
            self?.updateCurrentSmartCollection()
        }
        ruleBarViewController.onGroupingChanged = { [weak self] grouping in
            guard let self else { return }
            currentGrouping = grouping
            if isBrowsingRecent == false {
                grouping.persist()
            }
            videoGridViewController.setGrouping(grouping)
            refreshRuleBar()
        }
    }

    private func updateGridEmptyContent() {
        let rule = currentRule.normalized()
        let hasConstraints = currentBaseFilter != .all || selectedSmartCollection != nil
            || !temporaryFilenameSearch.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            || !rule.conditions.isEmpty || !rule.requiredConditions.isEmpty
            || !rule.requiredTagIDs.isEmpty || !rule.filenameContains.isEmpty
        videoGridViewController.setEmptyContent(
            .resolve(libraryAvailable: isLibraryAvailable, hasConstraints: hasConstraints,
                     libraryCount: libraryVideoCount)
        )
    }

    private func refreshRuleBar() {
        updateGridEmptyContent()
        ruleBarViewController.configure(ruleBarContext)
    }

    private var ruleBarContext: LibraryRuleBarContext {
        LibraryRuleBarContext(
            scopeTitle: selectedSmartCollection == nil ? currentScopeTitle : nil,
            temporarySearch: temporaryFilenameSearch,
            rule: currentRule,
            presetSort: selectedSmartCollection == nil ? currentBaseFilter.presetSort : nil,
            tags: tags,
            smartCollection: selectedSmartCollection,
            isDirty: smartCollectionIsDirty,
            canSaveAsSmartCollection: canSaveCurrentContext,
            grouping: currentGrouping
        )
    }

    private var canSaveCurrentContext: Bool {
        selectedSmartCollection != nil || currentBaseFilter != .unavailable
    }

    private var currentScopeTitle: String? {
        switch currentBaseFilter {
        case let .tag(tagID):
            tags.first(where: { $0.id == tagID })?.name
        case let .tags(tagIDs):
            String(localized: .selectionTagCount(tagIDs.count))
        case .all:
            nil
        case .untagged:
            String(localized: .libraryUntagged)
        case .recent:
            String(localized: .libraryRecent)
        case .unavailable:
            String(localized: "library.unavailable", defaultValue: "Unavailable Videos")
        }
    }

    private func applyCurrentQuery(debounce: Bool = false) {
        onQueryChanged(
            LibraryQueryRequest(
                baseFilter: selectedSmartCollection == nil ? currentBaseFilter : .all,
                temporaryFilenameSearch: temporaryFilenameSearch,
                rule: currentRule
            ),
            debounce,
            filterQueryGenerations.next()
        )
    }

    private func setTemporaryFilenameSearch(
        _ value: String,
        applyQuery: Bool = true
    ) {
        temporaryFilenameSearch = value
        if searchToolbarItem?.searchField.stringValue != value {
            searchToolbarItem?.searchField.stringValue = value
        }
        refreshRuleBar()
        if applyQuery { applyCurrentQuery(debounce: true) }
    }

    private func requestNavigation(to target: NavigationTarget) {
        guard isSameNavigationTarget(target) == false else {
            if isShowingScanResults {
                leaveScanResults()
            } else {
                restoreCurrentSidebarSelection()
            }
            return
        }
        if smartCollectionIsDirty {
            pendingNavigationTarget = target
            restoreCurrentSidebarSelection()
            presentSmartCollectionLeaveConfirmation()
            return
        }
        performNavigation(to: target)
    }

    private func viewVideos(_ request: VideoRevealRequest) {
        guard request.videoIDs.isEmpty == false else { return }
        pendingVideoRevealRequest = request
        let target = NavigationTarget.filter(request.destination)
        if isSameNavigationTarget(target) {
            performNavigation(to: target)
            return
        }
        requestNavigation(to: target)
    }

    private func isSameNavigationTarget(_ target: NavigationTarget) -> Bool {
        switch target {
        case let .filter(filter):
            return selectedSmartCollection == nil && currentBaseFilter == filter
        case let .smartCollection(collection):
            return selectedSmartCollection?.id == collection.id
        }
    }

    private func performNavigation(to target: NavigationTarget) {
        leaveScanResults()
        pendingNavigationTarget = nil
        onEndVideoRemovalUndo()
        transitionGrouping(to: target)
        let isPendingVideoRevealTarget: Bool
        switch target {
        case let .filter(filter):
            isPendingVideoRevealTarget = pendingVideoRevealRequest?.destination == filter
        case .smartCollection:
            isPendingVideoRevealTarget = false
        }
        if isPendingVideoRevealTarget {
            currentRule = .standard
            setTemporaryFilenameSearch("", applyQuery: false)
        } else {
            pendingVideoRevealRequest = nil
            resetBrowsingStateForNextVideoUpdate = true
        }
        switch target {
        case let .filter(filter):
            if selectedSmartCollection != nil {
                currentRule = .standard
            }
            selectedSmartCollection = nil
            currentBaseFilter = filter
            sidebarViewController.selectFilter(filter)
            updateContext(for: filter)
        case let .smartCollection(collection):
            selectedSmartCollection = collection
            currentBaseFilter = .all
            currentRule = collection.rule
            setTemporaryFilenameSearch("", applyQuery: false)
            sidebarViewController.selectSmartCollection(id: collection.id)
            setContextTitle(collection.name, tagID: nil)
        }
        updateInspectorBrowsingContext()
        refreshRuleBar()
        applyCurrentQuery()
    }

    private var isBrowsingRecent: Bool {
        selectedSmartCollection == nil && currentBaseFilter == .recent
    }

    private func transitionGrouping(to target: NavigationTarget) {
        let willBrowseRecent: Bool
        switch target {
        case let .filter(filter):
            willBrowseRecent = filter == .recent
        case .smartCollection:
            willBrowseRecent = false
        }
        guard willBrowseRecent != isBrowsingRecent else { return }

        if willBrowseRecent {
            groupingBeforeRecent = currentGrouping
            currentGrouping = VideoGroupingPreference(key: .addedDate, direction: .descending)
        } else {
            currentGrouping = groupingBeforeRecent ?? VideoGroupingPreference.persisted()
            groupingBeforeRecent = nil
        }
        videoGridViewController.setGrouping(currentGrouping)
    }

    private func updateInspectorBrowsingContext() {
        inspectorViewController.setBrowsingContext(
            selectedSmartCollection == nil && currentBaseFilter == .unavailable
                ? .unavailable
                : .library
        )
    }

    private func restoreCurrentSidebarSelection() {
        if let selectedSmartCollection {
            sidebarViewController.selectSmartCollection(id: selectedSmartCollection.id)
        } else {
            sidebarViewController.selectFilter(currentBaseFilter)
        }
    }

    private func updateContext(for filter: LibraryFilter) {
        switch filter {
        case .all:
            setContextTitle(String(localized: .libraryAllVideos), tagID: nil)
        case .untagged:
            setContextTitle(String(localized: .libraryUntagged), tagID: nil)
        case .recent:
            setContextTitle(String(localized: .libraryRecent), tagID: nil)
        case .unavailable:
            setContextTitle(String(
                localized: "library.unavailable",
                defaultValue: "Unavailable Videos"
            ), tagID: nil)
        case let .tag(tagID):
            let title = tags.first(where: { $0.id == tagID })?.name
                ?? String(localized: "filter.deletedTag", defaultValue: "Deleted Tag")
            setContextTitle(title, tagID: tagID)
        case let .tags(tagIDs):
            setContextTitle(String(localized: .selectionTagCount(tagIDs.count)), tagID: nil)
        }
    }

    private func presentSmartCollectionLeaveConfirmation() {
        guard isPresentingSmartCollectionAlert == false,
              let selectedSmartCollection,
              let window = view.window else { return }
        isPresentingSmartCollectionAlert = true
        let alert = NSAlert()
        alert.messageText = String(
            localized: "smartCollection.leave.title",
            defaultValue: "Save changes to “\(selectedSmartCollection.name)”?"
        )
        alert.informativeText = String(
            localized: "smartCollection.leave.detail",
            defaultValue: "The current results use rules that have not been saved."
        )
        alert.addButton(withTitle: String(
            localized: "smartCollection.leave.update",
            defaultValue: "Update and Continue"
        ))
        alert.addButton(withTitle: String(
            localized: "smartCollection.leave.discard",
            defaultValue: "Discard Changes"
        ))
        alert.addButton(withTitle: String(localized: .actionCancel))
        alert.beginSheetModal(for: window) { [weak self] response in
            guard let self else { return }
            isPresentingSmartCollectionAlert = false
            switch response {
            case .alertFirstButtonReturn:
                updateCurrentSmartCollection { [weak self] succeeded in
                    guard let self else { return }
                    if succeeded, let target = pendingNavigationTarget {
                        performNavigation(to: target)
                    } else {
                        pendingNavigationTarget = nil
                        pendingVideoRevealRequest = nil
                        restoreCurrentSidebarSelection()
                    }
                }
            case .alertSecondButtonReturn:
                if let target = pendingNavigationTarget {
                    performNavigation(to: target)
                }
            default:
                pendingNavigationTarget = nil
                pendingVideoRevealRequest = nil
                restoreCurrentSidebarSelection()
            }
        }
    }

    private func ruleForSavingCurrentContext() -> LibraryQueryRule {
        var rule = currentRule
        if selectedSmartCollection == nil {
            switch currentBaseFilter {
            case let .tag(tagID):
                rule.requiredTagIDs.append(tagID)
            case let .tags(tagIDs):
                rule.requiredTagIDs.append(contentsOf: tagIDs)
            case .untagged:
                rule.requiredConditions.append(.untagged)
            case .recent:
                rule.requiredConditions.append(.addedWithinDays(30))
            case .all, .unavailable:
                break
            }
        }
        let search = temporaryFilenameSearch.trimmingCharacters(in: .whitespacesAndNewlines)
        if search.isEmpty == false {
            rule.filenameContains.append(search)
        }
        return rule.normalized()
    }

    private func presentSaveSmartCollection(
        suggestedName: String? = nil,
        validationMessage: String? = nil
    ) {
        guard canSaveCurrentContext else { return }
        guard let window = view.window else { return }
        let alert = NSAlert()
        alert.messageText = String(
            localized: "smartCollection.save.title",
            defaultValue: "Save as Smart Collection"
        )
        alert.informativeText = validationMessage ?? String(
            localized: "smartCollection.save.detail",
            defaultValue: "The current scope, filename search, filters, and sort order will be saved."
        )
        let field = NSTextField(string: suggestedName
            ?? selectedSmartCollection.map {
                String(
                    localized: "smartCollection.copyName",
                    defaultValue: "\($0.name) Copy"
                )
            }
            ?? String(localized: "smartCollection.defaultName", defaultValue: "New Smart Collection"))
        field.frame = NSRect(x: 0, y: 0, width: 300, height: 24)
        alert.accessoryView = field
        alert.addButton(withTitle: String(localized: .actionSave))
        alert.addButton(withTitle: String(localized: .actionCancel))
        alert.beginSheetModal(for: window) { [weak self] response in
            guard let self, response == .alertFirstButtonReturn else { return }
            let name = field.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
            let normalizedName = normalizedSmartCollectionName(name)
            let duplicate = smartCollections.contains {
                normalizedSmartCollectionName($0.name) == normalizedName
            }
            guard name.isEmpty == false, duplicate == false else {
                let message = name.isEmpty
                    ? String(localized: "smartCollection.name.empty", defaultValue: "Enter a name.")
                    : String(
                        localized: "smartCollection.name.duplicate",
                        defaultValue: "A smart collection with this name already exists."
                    )
                DispatchQueue.main.async { [weak self] in
                    self?.presentSaveSmartCollection(
                        suggestedName: name,
                        validationMessage: message
                    )
                }
                return
            }
            let savedRule = ruleForSavingCurrentContext()
            onCreateSmartCollection(name, savedRule) { [weak self] collection in
                guard let self, let collection else { return }
                selectedSmartCollection = collection
                currentBaseFilter = .all
                currentRule = collection.rule
                setTemporaryFilenameSearch("", applyQuery: false)
                sidebarViewController.selectSmartCollection(id: collection.id)
                setContextTitle(collection.name, tagID: nil)
                updateInspectorBrowsingContext()
                refreshRuleBar()
                applyCurrentQuery()
            }
        }
    }

    private func updateCurrentSmartCollection(
        completion: ((Bool) -> Void)? = nil
    ) {
        guard let selectedSmartCollection else {
            completion?(false)
            return
        }
        onUpdateSmartCollection(
            selectedSmartCollection.id,
            nil,
            currentRule
        ) { [weak self] collection in
            guard let self else {
                completion?(false)
                return
            }
            guard let collection else {
                completion?(false)
                return
            }
            self.selectedSmartCollection = collection
            currentRule = collection.rule
            refreshRuleBar()
            applyCurrentQuery()
            completion?(true)
        }
    }

    private func renameSmartCollection(_ collection: SmartCollectionRecord, to name: String) {
        onUpdateSmartCollection(collection.id, name, nil) { [weak self] updated in
            guard let self, let updated else { return }
            if selectedSmartCollection?.id == updated.id {
                selectedSmartCollection = updated
                setContextTitle(updated.name, tagID: nil)
            }
            refreshRuleBar()
        }
    }

    private func presentDeleteSmartCollection(_ collection: SmartCollectionRecord) {
        guard let window = view.window else { return }
        let alert = NSAlert()
        alert.messageText = String(
            localized: "smartCollection.delete.title",
            defaultValue: "Delete “\(collection.name)”?"
        )
        alert.informativeText = String(
            localized: "smartCollection.delete.detail",
            defaultValue: "Videos, files, and tags will not be changed."
        )
        alert.alertStyle = .warning
        alert.addButton(withTitle: String(
            localized: "smartCollection.delete.action",
            defaultValue: "Delete"
        ))
        alert.addButton(withTitle: String(localized: .actionCancel))
        alert.beginSheetModal(for: window) { [weak self] response in
            guard let self, response == .alertFirstButtonReturn else { return }
            if selectedSmartCollection?.id == collection.id {
                dropsConditionsOfRemovedSmartCollection = true
            }
            onDeleteSmartCollection(collection.id) { [weak self] _ in
                self?.dropsConditionsOfRemovedSmartCollection = false
            }
        }
    }

    func refreshTagAssignments() {
        inspectorViewController.refreshTagAssignments()
    }

    var canBeginCreatingRootTag: Bool {
        sidebarViewController.canBeginCreatingRootTag
    }

    func beginCreatingRootTag() {
        sidebarViewController.beginCreatingRootTag()
    }

    func setImportState(_ state: LibraryImportState) {
        switch state {
        case .idle:
            isImporting = false
        case .importing:
            isImporting = true
            if isShowingScanResults == false {
                clearSearchForImport()
            }
        case .completed, .cancelled, .failed:
            isImporting = false
        }
        videoGridViewController.setImportState(state)
        updateToolbarState()
    }

    func setLibraryError(_ message: String) {
        isLibraryAvailable = false
        updateGridEmptyContent()
        contextTitle = String(localized: .libraryAllVideos)
        contextTagID = nil
        setContextStatus(message)
        updateToolbarState()
    }

    func setOperationError(_ message: String) {
        setContextStatus(message)
    }

    func toolbarAllowedItemIdentifiers(_ toolbar: NSToolbar) -> [NSToolbarItem.Identifier] {
        return [
            Self.toggleSidebarItemIdentifier,
            .sidebarTrackingSeparator,
            Self.contextTitleItemIdentifier,
            .flexibleSpace,
            Self.zoomItemIdentifier,
            .space,
            Self.scanItemIdentifier,
            Self.searchItemIdentifier,
            .inspectorTrackingSeparator,
            .flexibleSpace,
            Self.toggleInspectorItemIdentifier,
        ]
    }

    func toolbarDefaultItemIdentifiers(_ toolbar: NSToolbar) -> [NSToolbarItem.Identifier] {
        return [
            Self.toggleSidebarItemIdentifier,
            .sidebarTrackingSeparator,
            Self.contextTitleItemIdentifier,
            .flexibleSpace,
            Self.zoomItemIdentifier,
            .space,
            Self.scanItemIdentifier,
            Self.searchItemIdentifier,
            .inspectorTrackingSeparator,
            .flexibleSpace,
            Self.toggleInspectorItemIdentifier,
        ]
    }

    func toolbar(
        _ toolbar: NSToolbar,
        itemForItemIdentifier itemIdentifier: NSToolbarItem.Identifier,
        willBeInsertedIntoToolbar flag: Bool
    ) -> NSToolbarItem? {
        switch itemIdentifier {
        case Self.toggleSidebarItemIdentifier:
            return makeSplitViewToggleToolbarItem(
                identifier: itemIdentifier,
                symbolName: "sidebar.left",
                label: String(localized: .toolbarHideShowSidebar),
                action: #selector(toggleSidebarFromToolbar(_:)),
                isOn: sidebarSplitViewItem?.isCollapsed == false,
                buttonStore: { [weak self] button in self?.sidebarToggleButton = button }
            )
        case Self.toggleInspectorItemIdentifier:
            return makeSplitViewToggleToolbarItem(
                identifier: itemIdentifier,
                symbolName: "sidebar.right",
                label: String(localized: .toolbarHideShowInspector),
                action: #selector(toggleInspectorFromToolbar(_:)),
                isOn: inspectorSplitViewItem?.isCollapsed == false,
                buttonStore: { [weak self] button in self?.inspectorToggleButton = button }
            )
        case Self.contextTitleItemIdentifier:
            return makeContextTitleToolbarItem(identifier: itemIdentifier)
        case Self.searchItemIdentifier:
            let item = NSSearchToolbarItem(itemIdentifier: itemIdentifier)
            item.label = String(localized: .toolbarSearch)
            item.paletteLabel = String(localized: .toolbarSearchVideos)
            item.toolTip = String(
                localized: "filter.searchShortcutTooltip",
                defaultValue: "Search filenames (⌘F)"
            )
            item.searchField.placeholderString = String(localized: .toolbarSearchFilename)
            item.searchField.sendsSearchStringImmediately = true
            item.searchField.stringValue = temporaryFilenameSearch
            item.searchField.target = self
            item.searchField.action = #selector(searchChanged(_:))
            item.searchField.widthAnchor.constraint(equalToConstant: 180).isActive = true
            searchToolbarItem = item
            return item
        case Self.scanItemIdentifier:
            let label = String(
                localized: "scan.action",
                defaultValue: "Scan for New Videos"
            )
            let button = makeToolbarIconButton(
                symbolName: "arrow.clockwise",
                label: label,
                target: self,
                action: #selector(scanForNewVideos(_:)),
                buttonType: .momentaryPushIn
            )
            button.isEnabled = canScanForNewVideos
            scanToolbarButton = button
            let item = NSToolbarItem(itemIdentifier: itemIdentifier)
            item.paletteLabel = label
            item.toolTip = label
            item.view = button
            return item
        case Self.zoomItemIdentifier:
            return makeZoomToolbarItem(identifier: itemIdentifier)
        default:
            return nil
        }
    }

    func validateToolbarItem(_ item: NSToolbarItem) -> Bool {
        switch item.itemIdentifier {
        case Self.searchItemIdentifier, Self.zoomItemIdentifier:
            true
        case Self.scanItemIdentifier:
            canScanForNewVideos
        default:
            super.validateUserInterfaceItem(item)
        }
    }

    private func makeZoomToolbarItem(identifier: NSToolbarItem.Identifier) -> NSToolbarItemGroup {
        let smallButton = makeToolbarIconButton(
            symbolName: "minus",
            label: String(localized: .toolbarThumbnailDecrease),
            target: self,
            action: #selector(decreaseZoom(_:)),
            buttonType: .momentaryPushIn
        )
        let largeButton = makeToolbarIconButton(
            symbolName: "plus",
            label: String(localized: .toolbarThumbnailIncrease),
            target: self,
            action: #selector(increaseZoom(_:)),
            buttonType: .momentaryPushIn
        )
        zoomOutButton = smallButton
        zoomInButton = largeButton

        // Positions 1…most columns, set by updateZoomControls() once the grid has a width.
        let slider = NSSlider(value: 1, minValue: 1, maxValue: 1, target: self, action: #selector(changeZoom(_:)))
        slider.controlSize = .small
        slider.toolTip = String(localized: .toolbarThumbnailSizeAdjust)
        slider.setAccessibilityLabel(String(localized: .toolbarThumbnailSize))
        slider.widthAnchor.constraint(equalToConstant: 70).isActive = true
        zoomSlider = slider
        updateZoomControls()

        let zoomOutItem = NSToolbarItem(itemIdentifier: Self.zoomOutItemIdentifier)
        zoomOutItem.label = String(localized: .toolbarThumbnailDecrease)
        zoomOutItem.toolTip = String(localized: .toolbarThumbnailDecrease)
        zoomOutItem.view = smallButton

        let sliderItem = NSToolbarItem(itemIdentifier: Self.zoomSliderItemIdentifier)
        sliderItem.label = String(localized: .toolbarThumbnailSize)
        sliderItem.toolTip = String(localized: .toolbarThumbnailSizeAdjust)
        sliderItem.view = slider

        let zoomInItem = NSToolbarItem(itemIdentifier: Self.zoomInItemIdentifier)
        zoomInItem.label = String(localized: .toolbarThumbnailIncrease)
        zoomInItem.toolTip = String(localized: .toolbarThumbnailIncrease)
        zoomInItem.view = largeButton

        let group = NSToolbarItemGroup(itemIdentifier: identifier)
        group.label = String(localized: .toolbarThumbnailSize)
        group.paletteLabel = String(localized: .toolbarThumbnailSize)
        group.toolTip = String(localized: .toolbarThumbnailSizeAdjust)
        group.controlRepresentation = .expanded
        group.subitems = [zoomOutItem, sliderItem, zoomInItem]
        return group
    }

    private func makeContextTitleToolbarItem(identifier: NSToolbarItem.Identifier) -> NSToolbarItem {
        let titleView = ToolbarTitleView()
        contextTitleView = titleView

        let item = NSToolbarItem(itemIdentifier: identifier)
        item.label = String(localized: .toolbarCurrentCategory)
        item.paletteLabel = String(localized: .toolbarCurrentCategory)
        item.isBordered = false
        if #available(macOS 26.0, *) {
            item.style = .plain
        }
        item.view = titleView
        updateWindowTitle()
        return item
    }

    private func makeSplitViewToggleToolbarItem(
        identifier: NSToolbarItem.Identifier,
        symbolName: String,
        label: String,
        action: Selector,
        isOn: Bool,
        buttonStore: (NSButton) -> Void
    ) -> NSToolbarItem {
        let button = makeToolbarIconButton(
            symbolName: symbolName,
            label: label,
            target: self,
            action: action,
            buttonType: .toggle
        )
        button.state = isOn ? .on : .off
        buttonStore(button)

        let item = NSToolbarItem(itemIdentifier: identifier)
        item.paletteLabel = label
        item.toolTip = label
        item.view = button
        return item
    }

    private func makeToolbarIconButton(
        symbolName: String,
        label: String,
        target: AnyObject?,
        action: Selector,
        buttonType: NSButton.ButtonType
    ) -> NSButton {
        let image = NSImage(systemSymbolName: symbolName, accessibilityDescription: label) ?? NSImage()
        let button = NSButton(image: image, target: target, action: action)
        button.title = ""
        button.imagePosition = .imageOnly
        button.bezelStyle = .toolbar
        button.setButtonType(buttonType)
        button.toolTip = label
        button.setAccessibilityLabel(label)
        return button
    }

    private func updateToolbarState() {
        scanToolbarButton?.isEnabled = canScanForNewVideos
        libraryToolbar.validateVisibleItems()
    }

    private func updateSplitViewToggleState() {
        if let sidebarSplitViewItem {
            sidebarToggleButton?.state = sidebarSplitViewItem.isCollapsed ? .off : .on
        }
        if let inspectorSplitViewItem {
            inspectorToggleButton?.state = inspectorSplitViewItem.isCollapsed ? .off : .on
        }
    }

    private func setContextStatus(_ message: String?) {
        contextStatus = message
        updateWindowTitle()
    }

    private func setContextTitle(_ title: String, tagID: String?) {
        contextTitle = title
        contextTagID = tagID
        videoGridViewController.endBrowsingContextNotificationLifecycle()
        if isImporting == false {
            contextStatus = nil
        }
        updateWindowTitle()
    }

    private func clearSearchForImport() {
        setTemporaryFilenameSearch("")
    }

    private func alignToolbarTitle() {
        guard let title = contextTitleView, let window = title.window,
              libraryContentViewController.viewIfLoaded?.window === window,
              let content = libraryContentViewController.viewIfLoaded else { return }
        let anchor = content.convert(NSPoint(x: VideoGridViewController.contentLeadingInset, y: 0), to: nil)
        title.alignLeading(toWindowX: anchor.x)
    }

    private func updateWindowTitle() {
        var subtitleParts: [String] = []
        if isLibraryAvailable {
            if isShowingScanResults {
                if let count = currentScanResults?.candidates.count {
                    subtitleParts.append(scanVideoCountDescription(count))
                }
            } else {
                subtitleParts.append(String(localized: .libraryVideoCount(visibleVideoCount)))
            }
        }
        if let contextStatus, contextStatus.isEmpty == false {
            subtitleParts.append(contextStatus)
        }
        let subtitle = subtitleParts.joined(separator: " · ")
        contextTitleView?.update(title: contextTitle, subtitle: subtitle)
        guard let window = viewIfLoaded?.window else { return }
        window.title = contextTitle
        window.subtitle = subtitle
        window.titleVisibility = .hidden
        alignToolbarTitle()
    }

    private func scanVideoCountDescription(_ count: Int) -> String {
        count == 1
            ? String(localized: "scan.videoCount.one", defaultValue: "1 video")
            : String(
                localized: "scan.videoCount.many",
                defaultValue: "\(count) videos"
            )
    }

    @objc private func searchChanged(_ sender: NSSearchField) {
        if isShowingScanResults {
            scanSearchText = sender.stringValue
            scanResultsViewController.setSearchText(scanSearchText)
            return
        }
        temporaryFilenameSearch = sender.stringValue
        refreshRuleBar()
        applyCurrentQuery(debounce: true)
    }

    @objc private func scanForNewVideos(_ sender: Any?) {
        guard canScanForNewVideos else { return }
        onScanForNewVideos()
    }

    var isSidebarCollapsed: Bool { sidebarSplitViewItem?.isCollapsed ?? false }
    var isInspectorCollapsed: Bool { inspectorSplitViewItem?.isCollapsed ?? false }

    /// From the View menu; the toolbar button follows.
    func toggleSidebar() {
        guard let item = sidebarSplitViewItem else { return }
        let collapse = !item.isCollapsed
        sidebarToggleButton?.state = collapse ? .off : .on
        item.animator().isCollapsed = collapse
    }

    var canFocusVideoGrid: Bool { showsLibraryGrid }

    /// View → Focus Video Grid.
    func focusVideoGrid() {
        guard canFocusVideoGrid else { return }
        videoGridViewController.focusGrid()
    }

    /// View → Focus Sidebar shows a hidden sidebar first.
    func focusSidebar() {
        if isSidebarCollapsed { toggleSidebar() }
        sidebarViewController.focusOutline()
    }

    func toggleInspector() {
        guard let item = inspectorSplitViewItem else { return }
        let collapse = !item.isCollapsed
        inspectorToggleButton?.state = collapse ? .off : .on
        item.animator().isCollapsed = collapse
    }

    @objc private func toggleSidebarFromToolbar(_ sender: NSButton) {
        guard let sidebarSplitViewItem else { return }
        sidebarSplitViewItem.animator().isCollapsed = sender.state == .off
    }

    @objc private func toggleInspectorFromToolbar(_ sender: NSButton) {
        guard let inspectorSplitViewItem else { return }
        inspectorSplitViewItem.animator().isCollapsed = sender.state == .off
    }

    @objc private func changeZoom(_ sender: NSSlider) {
        videoGridViewController.setColumnCount(GridColumns.columns(
            forSliderValue: sender.doubleValue,
            maximum: videoGridViewController.maximumColumnCount
        ))
        // Snap the knob to the column it chose.
        updateZoomControls()
    }

    @objc private func decreaseZoom(_ sender: NSButton) {
        zoomOut()
    }

    @objc private func increaseZoom(_ sender: NSButton) {
        zoomIn()
    }

    func zoomIn() { videoGridViewController.zoomIn() }
    func zoomOut() { videoGridViewController.zoomOut() }
    var canZoomIn: Bool { videoGridViewController.canZoomIn }
    var canZoomOut: Bool { videoGridViewController.canZoomOut }
    var canResetZoom: Bool { videoGridViewController.canResetZoom }

    /// Actual Size: as many columns as fit at the thumbnail size a new library starts with.
    func resetZoom() { videoGridViewController.resetZoom() }

    /// The slider has one stop per column count the grid can show at its current width.
    private func updateZoomControls() {
        let maximum = videoGridViewController.maximumColumnCount
        if let slider = zoomSlider {
            slider.maxValue = Double(maximum)
            slider.doubleValue = GridColumns.sliderValue(
                forColumns: videoGridViewController.displayedColumnCount,
                maximum: maximum
            )
            slider.isEnabled = maximum > 1
        }
        zoomInButton?.isEnabled = canZoomIn
        zoomOutButton?.isEnabled = canZoomOut
    }

}

@MainActor
private final class ToolbarTitleView: NSView {
    private let titleLabel = NSTextField(labelWithString: "")
    private let subtitleLabel = NSTextField(labelWithString: "")
    private var textLeading: NSLayoutConstraint?

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)

        let textContainer = NSView()
        textContainer.translatesAutoresizingMaskIntoConstraints = false

        titleLabel.translatesAutoresizingMaskIntoConstraints = false
        titleLabel.font = .systemFont(ofSize: 13, weight: .semibold)
        titleLabel.lineBreakMode = .byTruncatingTail
        titleLabel.maximumNumberOfLines = 1
        titleLabel.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)

        subtitleLabel.translatesAutoresizingMaskIntoConstraints = false
        subtitleLabel.font = .systemFont(ofSize: 11)
        subtitleLabel.textColor = .secondaryLabelColor
        subtitleLabel.lineBreakMode = .byTruncatingTail
        subtitleLabel.maximumNumberOfLines = 1

        addSubview(textContainer)
        textContainer.addSubview(titleLabel)
        textContainer.addSubview(subtitleLabel)
        let textLeading = textContainer.leadingAnchor.constraint(equalTo: leadingAnchor)
        self.textLeading = textLeading
        NSLayoutConstraint.activate([
            textLeading,
            textContainer.trailingAnchor.constraint(equalTo: trailingAnchor),
            textContainer.centerYAnchor.constraint(equalTo: centerYAnchor),
            textContainer.topAnchor.constraint(greaterThanOrEqualTo: topAnchor),
            textContainer.bottomAnchor.constraint(lessThanOrEqualTo: bottomAnchor),
            titleLabel.leadingAnchor.constraint(equalTo: textContainer.leadingAnchor),
            titleLabel.trailingAnchor.constraint(equalTo: textContainer.trailingAnchor),
            titleLabel.topAnchor.constraint(equalTo: textContainer.topAnchor),
            subtitleLabel.leadingAnchor.constraint(equalTo: textContainer.leadingAnchor),
            subtitleLabel.trailingAnchor.constraint(equalTo: textContainer.trailingAnchor),
            subtitleLabel.topAnchor.constraint(equalTo: titleLabel.bottomAnchor, constant: -1),
            subtitleLabel.bottomAnchor.constraint(equalTo: textContainer.bottomAnchor),
        ])
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override var intrinsicContentSize: NSSize {
        NSSize(width: 200, height: 36)
    }

    func alignLeading(toWindowX x: CGFloat) {
        let origin = convert(.zero, to: nil).x
        let inset = max(0, min(VideoGridViewController.contentLeadingInset, x - origin))
        guard let textLeading, abs(textLeading.constant - inset) > 0.5 else { return }
        textLeading.constant = inset
    }

    func update(title: String, subtitle: String) {
        titleLabel.stringValue = title
        subtitleLabel.stringValue = subtitle
        toolTip = subtitle.isEmpty ? nil : subtitle
    }
}
