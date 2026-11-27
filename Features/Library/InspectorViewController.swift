import AppKit

enum InspectorBrowsingContext: Equatable {
    case library
    case unavailable
    case scanResults
}

@MainActor
final class InspectorViewController: NSViewController {
    private enum Mode {
        case tags
        case resolve
        case details
    }

    private enum DetailSection: Int, CaseIterable {
        case file
        case video
        case audio

        var title: String {
            switch self {
            case .file: String(localized: .detailSectionFile)
            case .video: String(localized: .detailSectionVideo)
            case .audio: String(localized: .detailSectionAudio)
            }
        }
    }

    private static let horizontalInset: CGFloat = 16
    private static let documentTopInset: CGFloat = 10
    private static let documentBottomInset: CGFloat = 16

    private let stack = NSStackView()
    private let contentScrollView = NSScrollView()
    private let scrollDocument = InspectorScrollDocumentView()
    private let contentStack = NSStackView()
    private lazy var contentWidth = contentStack.widthAnchor.constraint(equalToConstant: 1)
    private lazy var sectionControl: NSSegmentedControl = {
        let control = NSSegmentedControl(
            labels: [
                String(localized: .inspectorTags),
                String(localized: .inspectorDetails),
            ],
            trackingMode: .selectOne,
            target: self,
            action: #selector(changeSection(_:))
        )
        control.segmentStyle = .rounded
        control.selectedSegment = 0
        control.setAccessibilityLabel(String(localized: .accessibilityInspectorContent))
        return control
    }()
    private lazy var tagSearchField: NSSearchField = {
        let field = NSSearchField()
        field.placeholderString = String(localized: .tagSearch)
        field.target = self
        field.action = #selector(searchTags(_:))
        field.sendsSearchStringImmediately = true
        return field
    }()
    private lazy var tagLayoutControl: NSSegmentedControl = {
        let control = NSSegmentedControl(
            images: [
                NSImage(systemSymbolName: "list.bullet", accessibilityDescription: String(localized: "inspector.tagLayout.list", defaultValue: "List")) ?? NSImage(),
                NSImage(systemSymbolName: "square.grid.2x2", accessibilityDescription: String(localized: "inspector.tagLayout.compact", defaultValue: "Compact")) ?? NSImage(),
            ],
            trackingMode: .selectOne,
            target: self,
            action: #selector(changeTagLayout(_:))
        )
        control.segmentStyle = .roundRect
        control.setToolTip(String(localized: "inspector.tagLayout.list", defaultValue: "List"), forSegment: 0)
        control.setToolTip(String(localized: "inspector.tagLayout.compact", defaultValue: "Compact"), forSegment: 1)
        control.setAccessibilityLabel(String(localized: "inspector.tagLayout", defaultValue: "Tag Layout"))
        control.selectedSegment = tagLayout == .list ? 0 : 1
        control.setContentHuggingPriority(.required, for: .horizontal)
        return control
    }()
    private lazy var tagToolbar: NSStackView = {
        let row = NSStackView(views: [tagSearchField, tagLayoutControl])
        row.orientation = .horizontal
        row.alignment = .centerY
        row.spacing = 6
        row.isHidden = true
        return row
    }()
    private var tagLayout = InspectorTagLayout.persisted()
    private let onApplyTagDraft: ([TagCreationDraft], [String: Bool], [String], @escaping (Bool) -> Void) -> Void
    private let loadTagStates: ([String], @escaping ([String: TagAssignmentState]) -> Void) -> Void
    private let filePath: (VideoRecord) -> String?
    private let offlineSourceName: (VideoRecord) -> String?
    private let onRelinkVideo: (VideoRecord) -> Void
    private let onRemoveVideos: ([String], @escaping (Bool) -> Void) -> Void
    private var selectedVideo: VideoRecord?
    private var selectedVideos: [VideoRecord] = []
    private var scannedCandidates: [ScannedVideoCandidate] = []
    private var tags: [TagRecord] = []
    private var tagStates: [String: TagAssignmentState] = [:]
    private var tagStateVideoIDs: [String] = []
    private var tagStateRequestRevision = 0
    private var tagCapsules: [String: TagCapsuleButton] = [:]
    private var tagCapsuleFocusOrder: [TagCapsuleButton] = []
    /// Tags the selected videos have come first. The order is set when a selection's states load,
    /// and clicks within that selection leave rows where they are, so a row never moves under the pointer.
    private var tagOrderIDs: [String] = []
    private var isShowingTagList = false
    private var tagListWasOnScreen = false
    private var tagSearchText = ""
    private var newTagPopover: NSPopover?
    private var collapsedDetailSections: Set<DetailSection> = []
    private var browsingContext: InspectorBrowsingContext = .library
    private var relinkingVideoID: String?
    var onVideoRemoved: ((Int) -> Void)?
    var selectedVideoIDs: [String] { selectedVideos.map(\.id) }

    init(
        onApplyTagDraft: @escaping ([TagCreationDraft], [String: Bool], [String], @escaping (Bool) -> Void) -> Void,
        loadTagStates: @escaping ([String], @escaping ([String: TagAssignmentState]) -> Void) -> Void,
        filePath: @escaping (VideoRecord) -> String?,
        offlineSourceName: @escaping (VideoRecord) -> String?,
        onRelinkVideo: @escaping (VideoRecord) -> Void,
        onRemoveVideos: @escaping ([String], @escaping (Bool) -> Void) -> Void
    ) {
        self.onApplyTagDraft = onApplyTagDraft
        self.loadTagStates = loadTagStates
        self.filePath = filePath
        self.offlineSourceName = offlineSourceName
        self.onRelinkVideo = onRelinkVideo
        self.onRemoveVideos = onRemoveVideos
        super.init(nibName: nil, bundle: nil)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func loadView() {
        let container = NSView()
        stack.translatesAutoresizingMaskIntoConstraints = false
        stack.orientation = .vertical
        stack.alignment = .centerX
        stack.spacing = 12
        contentStack.translatesAutoresizingMaskIntoConstraints = false
        contentStack.orientation = .vertical
        contentStack.alignment = .leading
        contentStack.spacing = 9
        scrollDocument.addSubview(contentStack)
        NSLayoutConstraint.activate([
            contentStack.leadingAnchor.constraint(equalTo: scrollDocument.leadingAnchor,
                                                  constant: Self.horizontalInset),
            contentStack.topAnchor.constraint(equalTo: scrollDocument.topAnchor,
                                              constant: Self.documentTopInset),
            contentWidth,
        ])
        contentScrollView.translatesAutoresizingMaskIntoConstraints = false
        contentScrollView.hasVerticalScroller = true
        contentScrollView.hasHorizontalScroller = false
        contentScrollView.autohidesScrollers = true
        contentScrollView.drawsBackground = false
        contentScrollView.documentView = scrollDocument
        contentScrollView.setContentHuggingPriority(.defaultLow, for: .vertical)
        contentScrollView.setContentCompressionResistancePriority(.defaultLow, for: .vertical)
        stack.addArrangedSubview(sectionControl)
        stack.addArrangedSubview(tagToolbar)
        stack.addArrangedSubview(contentScrollView)
        // The document owns the body padding so the end of the list scrolls clear of the viewport edge.
        stack.setCustomSpacing(0, after: tagToolbar)
        container.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: container.trailingAnchor),
            stack.topAnchor.constraint(equalTo: container.safeAreaLayoutGuide.topAnchor, constant: 16),
            stack.bottomAnchor.constraint(equalTo: container.safeAreaLayoutGuide.bottomAnchor),
            sectionControl.leadingAnchor.constraint(equalTo: stack.leadingAnchor, constant: Self.horizontalInset),
            sectionControl.trailingAnchor.constraint(equalTo: stack.trailingAnchor, constant: -Self.horizontalInset),
            tagToolbar.leadingAnchor.constraint(equalTo: sectionControl.leadingAnchor),
            tagToolbar.trailingAnchor.constraint(equalTo: sectionControl.trailingAnchor),
            contentScrollView.widthAnchor.constraint(equalTo: stack.widthAnchor),
        ])
        view = container
        setSelection([])
    }

    override func viewDidLayout() {
        super.viewDidLayout()
        updateScrollDocumentSize()
    }

    func setSelection(_ videos: [VideoRecord]) {
        let selectionChanged = selectedVideos.map(\.id) != videos.map(\.id)
        selectedVideos = videos
        selectedVideo = videos.count == 1 ? videos[0] : nil
        if selectionChanged {
            closeNewTagPopover()
        }
        // Clicking another video deselects the old one before selecting the new one. Hold the tag list
        // through that momentary empty selection; show the empty state only if it is still empty after.
        if videos.isEmpty, isShowingTagList, browsingContext != .scanResults, mode == .tags {
            DispatchQueue.main.async { [weak self] in
                guard let self, self.selectedVideos.isEmpty else { return }
                self.renderSelection()
            }
            return
        }
        // The tag list does not depend on which videos are selected; only the check marks do.
        if keepsTagListAcrossSelection {
            if selectionChanged {
                refreshTagAssignments()
            }
            return
        }
        renderSelection()
        scheduleInitialTagStateLoadIfNeeded()
    }

    private var keepsTagListAcrossSelection: Bool {
        isShowingTagList
            && browsingContext != .scanResults
            && mode == .tags
            && selectedVideos.isEmpty == false
    }

    func setScannedCandidates(_ candidates: [ScannedVideoCandidate]) {
        scannedCandidates = candidates
        renderSelection()
    }

    func setBrowsingContext(_ context: InspectorBrowsingContext) {
        guard browsingContext != context else { return }
        browsingContext = context
        closeNewTagPopover()
        sectionControl.isHidden = context == .scanResults
        sectionControl.setLabel(
            context == .unavailable
                ? String(localized: "inspector.resolve", defaultValue: "Resolve")
                : String(localized: .inspectorTags),
            forSegment: 0
        )
        sectionControl.selectedSegment = 0
        renderSelection()
        scheduleInitialTagStateLoadIfNeeded()
    }

    func setRelinkingVideoID(_ videoID: String?) {
        guard relinkingVideoID != videoID else { return }
        relinkingVideoID = videoID
        renderSelection()
    }

    func setTags(_ tags: [TagRecord]) {
        let listChanged = InspectorTagList.entries(tags) != InspectorTagList.entries(self.tags)
        self.tags = tags
        if listChanged || keepsTagListAcrossSelection == false {
            renderSelection()
        }
        scheduleInitialTagStateLoadIfNeeded()
    }

    func refreshTagAssignments() {
        let videoIDs = selectedVideos.map(\.id)
        guard mode == .tags, videoIDs.isEmpty == false else {
            // Assignments changed while Tags isn't showing them: forget the cached states so they load again.
            tagStateRequestRevision += 1
            tagStateVideoIDs = []
            return
        }
        tagStateRequestRevision += 1
        let requestRevision = tagStateRequestRevision
        loadTagStates(videoIDs) { [weak self] states in
            guard let self,
                  self.tagStateRequestRevision == requestRevision,
                  self.selectedVideos.map(\.id) == videoIDs else { return }
            let selectionChanged = self.tagStateVideoIDs != videoIDs
            self.tagStates = states
            self.tagStateVideoIDs = videoIDs
            if selectionChanged {
                self.tagOrderIDs = InspectorTagList.order(self.tags, states: states).map(\.id)
            }
            if self.keepsTagListAcrossSelection {
                self.updateTagCapsuleStates()
                if selectionChanged {
                    self.rebuildTagListMovingCapsules()
                }
            } else {
                self.renderSelection()
            }
        }
    }

    private var orderedTags: [TagRecord] {
        let ordered = Set(tagOrderIDs)
        let tagsByID = Dictionary(uniqueKeysWithValues: tags.map { ($0.id, $0) })
        // Tags created after the order was set show first, where the new tag is easy to find.
        return tags.filter { ordered.contains($0.id) == false } + tagOrderIDs.compactMap { tagsByID[$0] }
    }

    /// Rebuilds the tag list and slides every capsule from where it was to where it is now, so a
    /// new order or layout reads as tags moving rather than the list reloading.
    private func rebuildTagListMovingCapsules() {
        let focusedTagID = (view.window?.firstResponder as? TagCapsuleButton)?.tagRecord.id
        let previousFrames = tagCapsules.mapValues { $0.convert($0.bounds, to: nil) }
        renderSelection()
        view.layoutSubtreeIfNeeded()
        for (tagID, capsule) in tagCapsules {
            guard let previousFrame = previousFrames[tagID], let layer = capsule.layer else { continue }
            let currentFrame = capsule.convert(capsule.bounds, to: nil)
            let dx = previousFrame.minX - currentFrame.minX
            let windowDY = previousFrame.minY - currentFrame.minY
            let dy = capsule.superview?.isFlipped == true ? -windowDY : windowDY
            guard dx != 0 || dy != 0 else { continue }
            let slide = CABasicAnimation(keyPath: "transform")
            slide.fromValue = CATransform3DMakeTranslation(dx, dy, 0)
            slide.toValue = CATransform3DIdentity
            slide.duration = InspectorTagList.reorderDuration
            slide.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
            layer.add(slide, forKey: "reorder")
        }
        if let focusedTagID, let capsule = tagCapsules[focusedTagID] {
            view.window?.makeFirstResponder(capsule)
        }
    }

    private func updateTagCapsuleStates() {
        for (tagID, capsule) in tagCapsules {
            capsule.state = InspectorTagList.controlState(tagStates[tagID] ?? .off)
        }
    }

    private func renderSelection() {
        loadViewIfNeeded()
        tagListWasOnScreen = isShowingTagList
        defer {
            updateTagSearchFieldVisibility()
        }
        clearContent()
        contentStack.spacing = mode == .resolve ? 16 : 9
        if browsingContext == .scanResults {
            addScanCandidateDetails(scannedCandidates)
            updateScrollDocumentSize()
            return
        }
        let videos = selectedVideos

        if mode == .resolve {
            addResolveControls(for: videos)
            updateScrollDocumentSize()
            return
        }
        guard videos.isEmpty == false else {
            addSecondaryText(String(localized: .inspectorEmpty))
            updateScrollDocumentSize()
            return
        }
        guard mode == .details else {
            addTagControls()
            updateScrollDocumentSize()
            return
        }
        guard let video = selectedVideo else {
            addPrimaryText(String(localized: .selectionVideoCount(videos.count)))
            let totalBytes = videos.reduce(Int64(0)) { $0 + $1.fileSize }
            addField(
                title: String(localized: .detailTotalSize),
                value: ByteCountFormatter.string(fromByteCount: totalBytes, countStyle: .file)
            )
            updateScrollDocumentSize()
            return
        }

        addFilename(video.filename)
        let accessStatus: String
        switch video.accessPresentation {
        case .none:
            accessStatus = String(localized: .detailAccessAvailable)
        case .offline:
            if let sourceName = offlineSourceName(video), sourceName.isEmpty == false {
                accessStatus = String(localized: .detailAccessOfflineNamed(sourceName))
            } else {
                accessStatus = String(localized: .detailAccessOffline)
            }
        case .cloud, .accessNeedsVerification, .unavailable:
            accessStatus = video.accessPresentation.accessibilityLabel ?? String(localized: .detailAccessAvailable)
        }
        let media = video.mediaSourceInfo
        let lastKnownLocation = lastKnownLocationDisplay(for: video)
        let fileFields: [(String, String)] = [
                (
                    String(localized: .detailContainerFormat),
                    formattedContainer(media)
                ),
                (String(localized: .detailExtension), video.fileExtension.uppercased()),
                (
                    String(localized: .detailSize),
                    ByteCountFormatter.string(fromByteCount: video.fileSize, countStyle: .file)
                ),
                (String(localized: .detailDuration), formattedDuration(video.duration)),
                (String(localized: .detailCreated), formattedDate(video.creationDate)),
                (String(localized: .detailModified), formattedDate(video.modificationDate)),
                (String(localized: .detailAccessStatus), accessStatus),
                (video.availability == .unavailable
                    ? lastKnownLocation.title
                    : String(localized: .detailPath),
                 video.availability == .unavailable
                    ? lastKnownLocation.value
                    : filePath(video) ?? String(localized: .detailPathUnavailable)),
        ]
        addDetailSection(.file, fields: fileFields)
        addDetailSection(
            .video,
            fields: [
                (String(localized: .detailVideoCodec), valueOrUnavailable(media?.videoCodec)),
                (String(localized: .detailCodecTag), valueOrUnavailable(media?.videoCodecTag)),
                (String(localized: .detailCodecProfile), valueOrUnavailable(media?.videoProfile)),
                (String(localized: .detailResolution), formattedResolution(video)),
                (String(localized: .detailFrameRate), formattedFrameRate(media?.frameRate)),
                (String(localized: .detailBitRate), formattedBitRate(media?.videoBitRate)),
                (String(localized: .detailBitDepth), formattedBitDepth(media?.bitDepth)),
                (String(localized: .detailColorType), formattedColorInfo(media)),
                (String(localized: .detailRotation), formattedRotation(media?.rotationDegrees)),
            ]
        )
        addDetailSection(
            .audio,
            fields: [
                (String(localized: .detailAudioCodec), valueOrUnavailable(media?.audioCodec)),
                (String(localized: .detailCodecTag), valueOrUnavailable(media?.audioCodecTag)),
                (String(localized: .detailCodecProfile), valueOrUnavailable(media?.audioProfile)),
                (String(localized: .detailChannels), formattedChannels(media?.audioChannels)),
                (String(localized: .detailSampleRate), formattedSampleRate(media?.audioSampleRate)),
                (String(localized: .detailBitRate), formattedBitRate(media?.audioBitRate)),
            ]
        )
        updateScrollDocumentSize()
    }

    private var mode: Mode {
        if sectionControl.selectedSegment == 1 { return .details }
        return browsingContext == .unavailable ? .resolve : .tags
    }

    private func addScanCandidateDetails(_ candidates: [ScannedVideoCandidate]) {
        guard candidates.isEmpty == false else {
            addSecondaryText(String(
                localized: "scan.inspector.empty",
                defaultValue: "Select a video to view its file information."
            ))
            return
        }
        guard candidates.count == 1, let candidate = candidates.first else {
            addPrimaryText(String(
                localized: "scan.inspector.selection",
                defaultValue: "\(candidates.count) Videos Selected"
            ))
            addField(
                title: String(localized: .detailTotalSize),
                value: ByteCountFormatter.string(
                    fromByteCount: candidates.reduce(Int64(0)) { $0 + $1.video.fileSize },
                    countStyle: .file
                )
            )
            return
        }
        addPrimaryText(candidate.video.filename)
        addField(
            title: String(localized: "scan.inspector.status", defaultValue: "Status"),
            value: String(localized: "scan.inspector.pending", defaultValue: "Waiting to Import")
        )
        let relativeFolder = (candidate.video.relativePath as NSString)
            .deletingLastPathComponent
        let location = relativeFolder.isEmpty
            ? candidate.sourceName
            : "\(candidate.sourceName) / \(relativeFolder)"
        addField(
            title: String(localized: .detailPath),
            value: location
        )
        addField(
            title: String(localized: .detailExtension),
            value: candidate.video.fileExtension.uppercased()
        )
        addField(
            title: String(localized: .detailSize),
            value: ByteCountFormatter.string(
                fromByteCount: candidate.video.fileSize,
                countStyle: .file
            )
        )
        addField(
            title: String(localized: .detailCreated),
            value: formattedDate(candidate.video.creationDate)
        )
        addField(
            title: String(localized: .detailModified),
            value: formattedDate(candidate.video.modificationDate)
        )
    }

    private func addResolveControls(for videos: [VideoRecord]) {
        guard videos.isEmpty == false else {
            addResolveTitle(String(
                localized: "unavailable.resolve.empty.title",
                defaultValue: "Select a video to resolve"
            ))
            addSecondaryText(String(
                localized: "unavailable.resolve.empty.detail",
                defaultValue: "Select a video to see its status and available actions."
            ))
            return
        }

        guard let video = selectedVideo else {
            addResolveTitle(String(
                format: String(
                    localized: "unavailable.resolve.selection.title",
                    defaultValue: "%lld Unavailable Videos Selected"
                ),
                videos.count
            ))
            addSecondaryText(String(
                localized: "unavailable.resolve.selection.detail",
                defaultValue: "Relinking requires confirming each original file individually. The current selection can only be removed in a batch."
            ))
            addUnavailableSelectionSummaryCard(videos)
            addResolveActions(showsRelink: false, selectedCount: videos.count)
            return
        }

        switch video.availability {
        case .unavailable:
            let lastKnownLocation = lastKnownLocationDisplay(for: video)
            addResolveTitle(String(
                localized: "detail.accessUnavailable",
                defaultValue: "Unavailable"
            ))
            addResolveFactCard(
                title: lastKnownLocation.title,
                value: lastKnownLocation.value,
                promise: String(
                    localized: "unavailable.retainedDetail",
                    defaultValue: "Original tags and media information will be preserved."
                )
            )
            addResolveActions(showsRelink: true, selectedCount: 1)
        case .offline:
            addResolveTitle(String(
                localized: "unavailable.resolve.offline.title",
                defaultValue: "Currently Offline"
            ))
            let source = offlineSourceName(video).flatMap { $0.isEmpty ? nil : $0 }
            addResolveFactCard(
                title: String(localized: "unavailable.resolve.source", defaultValue: "Source"),
                value: source.map {
                    String(
                        format: String(
                            localized: "unavailable.resolve.source.offline.named",
                            defaultValue: "“%@” is not connected"
                        ),
                        $0
                    )
                } ?? String(
                    localized: "unavailable.resolve.source.offline",
                    defaultValue: "The source is not connected"
                ),
                promise: String(
                    localized: "unavailable.resolve.offline.detail",
                    defaultValue: "It will restore automatically after the device is connected. Original tags and media information will be preserved."
                )
            )
            addResolveActions(showsRelink: false, selectedCount: 1)
        case .available:
            addSecondaryText(String(localized: .inspectorEmpty))
        }
    }

    private func lastKnownLocationDisplay(for video: VideoRecord) -> (title: String, value: String) {
        if let path = filePath(video), path.isEmpty == false {
            return (
                String(localized: "detail.lastKnownLocation", defaultValue: "Last Known Location"),
                path
            )
        }
        return (
            String(localized: "detail.lastKnownFile", defaultValue: "Last Known File"),
            video.filename
        )
    }

    private func addResolveTitle(_ value: String) {
        let label = NSTextField(wrappingLabelWithString: value)
        label.font = .systemFont(ofSize: 16, weight: .semibold)
        contentStack.addArrangedSubview(label)
        label.widthAnchor.constraint(equalTo: contentStack.widthAnchor).isActive = true
    }

    private func addResolveFactCard(title: String, value: String, promise: String) {
        let titleLabel = NSTextField(labelWithString: title)
        titleLabel.font = .systemFont(ofSize: 11, weight: .medium)
        titleLabel.textColor = .secondaryLabelColor

        let valueLabel = NSTextField(wrappingLabelWithString: value)
        valueLabel.font = .systemFont(ofSize: 12, weight: .medium)
        valueLabel.isSelectable = true

        let fact = NSStackView(views: [titleLabel, valueLabel])
        fact.orientation = .vertical
        fact.alignment = .leading
        fact.spacing = 3

        let promiseLabel = NSTextField(wrappingLabelWithString: promise)
        promiseLabel.font = .systemFont(ofSize: 11)
        promiseLabel.textColor = .secondaryLabelColor

        addResolveCard(views: [fact, promiseLabel])
    }

    private func addUnavailableSelectionSummaryCard(_ videos: [VideoRecord]) {
        let counts: [(String, Int)] = [
            (String(localized: "detail.accessUnavailable", defaultValue: "Unavailable"),
             videos.filter { $0.availability == .unavailable }.count),
            (String(localized: .videoOfflineBadge),
             videos.filter { $0.availability == .offline }.count),
        ].filter { $0.1 > 0 }
        let rows = counts.map { title, count -> [NSView] in
            let titleLabel = NSTextField(labelWithString: title)
            titleLabel.textColor = .secondaryLabelColor
            let countLabel = NSTextField(labelWithString: count.formatted())
            countLabel.alignment = .right
            return [titleLabel, countLabel]
        }
        let grid = NSGridView(views: rows)
        grid.rowSpacing = 7
        grid.columnSpacing = 12
        grid.column(at: 0).xPlacement = .leading
        grid.column(at: 1).xPlacement = .trailing
        addResolveCard(views: [grid])
    }

    private func addResolveCard(views: [NSView]) {
        let card = InspectorResolveCardView()
        let cardStack = NSStackView(views: views)
        cardStack.translatesAutoresizingMaskIntoConstraints = false
        cardStack.orientation = .vertical
        cardStack.alignment = .leading
        cardStack.spacing = 10
        card.addSubview(cardStack)
        NSLayoutConstraint.activate([
            cardStack.leadingAnchor.constraint(equalTo: card.leadingAnchor, constant: 12),
            cardStack.trailingAnchor.constraint(equalTo: card.trailingAnchor, constant: -12),
            cardStack.topAnchor.constraint(equalTo: card.topAnchor, constant: 12),
            cardStack.bottomAnchor.constraint(equalTo: card.bottomAnchor, constant: -12),
        ])
        views.forEach {
            $0.widthAnchor.constraint(equalTo: cardStack.widthAnchor).isActive = true
        }
        contentStack.addArrangedSubview(card)
        card.widthAnchor.constraint(equalTo: contentStack.widthAnchor).isActive = true
    }

    private func addResolveActions(showsRelink: Bool, selectedCount: Int) {
        let group = NSStackView()
        group.orientation = .vertical
        group.alignment = .leading
        group.spacing = 8

        if showsRelink {
            let isRelinking = selectedVideo.map { $0.id == relinkingVideoID } ?? false
            let relinkButton = InspectorResolvePrimaryButton(
                title: isRelinking
                    ? String(
                        localized: "unavailable.relink.checking",
                        defaultValue: "Checking the selected file…"
                    )
                    : String(
                        localized: "unavailable.relink.action",
                        defaultValue: "Relink Original…"
                    ),
                target: self,
                action: #selector(relinkSelectedVideo)
            )
            relinkButton.isEnabled = isRelinking == false
            group.addArrangedSubview(relinkButton)
            relinkButton.widthAnchor.constraint(equalTo: group.widthAnchor).isActive = true
        }

        let removeTitle = selectedCount > 1
            ? String(
                format: String(
                    localized: "unavailable.remove.action.multiple",
                    defaultValue: "Remove %lld Videos from Tagivy…"
                ),
                selectedCount
            )
            : String(
                localized: "unavailable.remove.action",
                defaultValue: "Remove from Tagivy…"
            )
        let removeButton = NSButton(
            title: removeTitle,
            target: self,
            action: #selector(removeSelectedUnavailableVideos)
        )
        removeButton.isBordered = false
        removeButton.alignment = .center
        removeButton.font = .systemFont(ofSize: 12, weight: .medium)
        removeButton.contentTintColor = .systemOrange
        removeButton.isEnabled = selectedVideos.contains { $0.id == relinkingVideoID } == false
        group.addArrangedSubview(removeButton)
        removeButton.widthAnchor.constraint(equalTo: group.widthAnchor).isActive = true
        removeButton.heightAnchor.constraint(greaterThanOrEqualToConstant: 28).isActive = true

        contentStack.addArrangedSubview(group)
        group.widthAnchor.constraint(equalTo: contentStack.widthAnchor).isActive = true
    }

    @objc private func relinkSelectedVideo() {
        guard let selectedVideo,
              selectedVideo.id != relinkingVideoID,
              selectedVideo.availability == .unavailable else { return }
        onRelinkVideo(selectedVideo)
    }

    @objc private func removeSelectedUnavailableVideos() {
        let videos = selectedVideos.filter { $0.availability != .available }
        guard browsingContext == .unavailable,
              videos.isEmpty == false,
              videos.count == selectedVideos.count,
              let window = view.window else { return }
        let alert = NSAlert()
        alert.alertStyle = .warning
        if videos.count > 1 {
            alert.messageText = String(
                format: String(
                    localized: "unavailable.remove.title.multiple",
                    defaultValue: "Remove %lld records from Tagivy?"
                ),
                videos.count
            )
            alert.informativeText = String(
                localized: "unavailable.remove.detail.multiple",
                defaultValue: "The original tags and media information for these records will be deleted from Tagivy. This will not affect original files that may exist on your Mac."
            )
        } else {
            alert.messageText = String(
                localized: "unavailable.remove.title",
                defaultValue: "Remove this record from Tagivy?"
            )
            alert.informativeText = String(
                localized: "unavailable.remove.detail",
                defaultValue: "The original tags and media information will be deleted from Tagivy. This will not affect the original file that may exist on your Mac."
            )
        }
        alert.addButton(withTitle: String(localized: .actionRemove))
        alert.addButton(withTitle: String(localized: .actionCancel))
        alert.buttons.first?.hasDestructiveAction = true
        let videoIDs = videos.map(\.id)
        alert.beginSheetModal(for: window) { [weak self] response in
            guard let self, response == .alertFirstButtonReturn else { return }
            self.onRemoveVideos(videoIDs) { [weak self] succeeded in
                guard succeeded else { return }
                self?.onVideoRemoved?(videoIDs.count)
            }
        }
    }

    private func addPrimaryText(_ value: String) {
        let label = NSTextField(wrappingLabelWithString: value)
        label.font = .systemFont(ofSize: 14, weight: .medium)
        contentStack.addArrangedSubview(label)
    }

    private func addFilename(_ filename: String) {
        let label = NSTextField(wrappingLabelWithString: filename)
        label.font = .systemFont(ofSize: 14, weight: .medium)
        label.isSelectable = true

        let image = NSImage(
            systemSymbolName: "doc.on.doc",
            accessibilityDescription: String(localized: .accessibilityCopyFilename)
        ) ?? NSImage()
        let copyButton = NSButton(image: image, target: self, action: #selector(copyFilename))
        copyButton.title = ""
        copyButton.imagePosition = .imageOnly
        copyButton.isBordered = false
        copyButton.controlSize = .small
        copyButton.contentTintColor = .secondaryLabelColor
        copyButton.toolTip = String(localized: .accessibilityCopyFilename)
        copyButton.setAccessibilityLabel(String(localized: .accessibilityCopyFilename))
        copyButton.setContentHuggingPriority(.required, for: .horizontal)
        copyButton.setContentCompressionResistancePriority(.required, for: .horizontal)

        let filenameRow = NSStackView(views: [label, copyButton])
        filenameRow.orientation = .horizontal
        filenameRow.alignment = .centerY
        filenameRow.spacing = 6
        contentStack.addArrangedSubview(filenameRow)
        filenameRow.widthAnchor.constraint(equalTo: contentStack.widthAnchor).isActive = true
    }

    private func addSecondaryText(_ value: String) {
        let label = InspectorWrappingHelpLabel(value)
        contentStack.addArrangedSubview(label)
        label.widthAnchor.constraint(equalTo: contentStack.widthAnchor).isActive = true
        label.updateMeasuredWidth(contentWidth.constant)
    }

    private func addField(title: String, value: String) {
        let titleLabel = NSTextField(labelWithString: title)
        titleLabel.font = .systemFont(ofSize: 11, weight: .medium)
        titleLabel.textColor = .secondaryLabelColor
        let valueLabel = NSTextField(wrappingLabelWithString: value)
        valueLabel.isSelectable = true
        let fieldStack = NSStackView(views: [titleLabel, valueLabel])
        fieldStack.orientation = .vertical
        fieldStack.alignment = .leading
        fieldStack.spacing = 2
        contentStack.addArrangedSubview(fieldStack)
    }

    private func addDetailSection(_ section: DetailSection, fields: [(String, String)]) {
        let header = NSButton(
            title: section.title,
            target: self,
            action: #selector(toggleDetailSection(_:))
        )
        header.tag = section.rawValue
        header.isBordered = false
        header.bezelStyle = .inline
        header.font = .systemFont(ofSize: 12, weight: .semibold)
        header.alignment = .left
        header.imagePosition = .imageLeading
        header.image = NSImage(
            systemSymbolName: collapsedDetailSections.contains(section) ? "chevron.right" : "chevron.down",
            accessibilityDescription: nil
        )
        header.contentTintColor = .secondaryLabelColor
        header.setAccessibilityLabel(section.title)

        let rows = fields.map { title, value -> [NSView] in
            let titleLabel = NSTextField(labelWithString: title)
            titleLabel.font = .systemFont(ofSize: 11)
            titleLabel.textColor = .secondaryLabelColor
            titleLabel.setContentCompressionResistancePriority(.required, for: .horizontal)

            let valueLabel = NSTextField(wrappingLabelWithString: value)
            valueLabel.font = .systemFont(ofSize: 11)
            valueLabel.alignment = .right
            valueLabel.isSelectable = true
            valueLabel.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
            return [titleLabel, valueLabel]
        }
        let grid = NSGridView(views: rows)
        grid.rowSpacing = 7
        grid.columnSpacing = 12
        grid.column(at: 0).xPlacement = .leading
        grid.column(at: 1).xPlacement = .trailing
        grid.isHidden = collapsedDetailSections.contains(section)

        let group = NSStackView(views: [header, grid])
        group.orientation = .vertical
        group.alignment = .leading
        group.spacing = 7
        contentStack.addArrangedSubview(group)
        group.widthAnchor.constraint(equalTo: contentStack.widthAnchor).isActive = true
        header.widthAnchor.constraint(equalTo: group.widthAnchor).isActive = true
        grid.widthAnchor.constraint(equalTo: group.widthAnchor).isActive = true

        let separator = NSBox()
        separator.boxType = .separator
        contentStack.addArrangedSubview(separator)
        separator.widthAnchor.constraint(equalTo: contentStack.widthAnchor).isActive = true
    }

    @objc private func toggleDetailSection(_ sender: NSButton) {
        guard let section = DetailSection(rawValue: sender.tag) else { return }
        if collapsedDetailSections.contains(section) {
            collapsedDetailSections.remove(section)
        } else {
            collapsedDetailSections.insert(section)
        }
        renderSelection()
    }

    private func formattedDuration(_ duration: Double?) -> String {
        guard let duration, duration.isFinite else {
            return String(localized: .detailMediaUnavailable)
        }
        let totalSeconds = max(0, Int(duration.rounded()))
        let hours = totalSeconds / 3600
        let minutes = (totalSeconds % 3600) / 60
        let seconds = totalSeconds % 60
        return hours > 0
            ? String(format: "%d:%02d:%02d", hours, minutes, seconds)
            : String(format: "%d:%02d", minutes, seconds)
    }

    private func formattedDate(_ date: Date?) -> String {
        guard let date else { return String(localized: .detailUnknown) }
        return date.formatted(date: .abbreviated, time: .shortened)
    }

    private func valueOrUnavailable(_ value: String?) -> String {
        guard let value, value.isEmpty == false else {
            return String(localized: .detailMediaUnavailable)
        }
        return value
    }

    private func formattedContainer(_ media: MediaSourceInfo?) -> String {
        guard let format = media?.containerFormat, format.isEmpty == false else {
            return String(localized: .detailMediaUnavailable)
        }
        guard let brand = media?.containerBrand, brand.isEmpty == false else { return format }
        return "\(format) · \(brand)"
    }

    private func formattedResolution(_ video: VideoRecord) -> String {
        guard let width = video.width, let height = video.height else {
            return String(localized: .detailMediaUnavailable)
        }
        return "\(width) × \(height)"
    }

    private func formattedFrameRate(_ value: Double?) -> String {
        guard let value, value.isFinite, value > 0 else {
            return String(localized: .detailMediaUnavailable)
        }
        let number = value.formatted(.number.precision(.fractionLength(0...3)))
        return String(localized: .detailFramesPerSecond(number))
    }

    private func formattedBitRate(_ value: Double?) -> String {
        guard let value, value.isFinite, value > 0 else {
            return String(localized: .detailMediaUnavailable)
        }
        if value >= 1_000_000 {
            let number = (value / 1_000_000).formatted(.number.precision(.fractionLength(0...2)))
            return String(localized: .detailMegabitsPerSecond(number))
        }
        let number = (value / 1_000).formatted(.number.precision(.fractionLength(0...1)))
        return String(localized: .detailKilobitsPerSecond(number))
    }

    private func formattedBitDepth(_ value: Int?) -> String {
        guard let value, value > 0 else {
            return String(localized: .detailMediaUnavailable)
        }
        return String(localized: .detailBitDepthValue(value))
    }

    private func formattedColorInfo(_ media: MediaSourceInfo?) -> String {
        guard let media else { return String(localized: .detailMediaUnavailable) }
        let transfer = media.colorTransfer ?? ""
        let colorType: String
        if transfer.localizedCaseInsensitiveContains("2084")
            || transfer.localizedCaseInsensitiveContains("PQ") {
            colorType = "HDR10"
        } else if transfer.localizedCaseInsensitiveContains("2100")
            || transfer.localizedCaseInsensitiveContains("HLG") {
            colorType = "HLG"
        } else if transfer.isEmpty == false || media.colorPrimaries != nil {
            colorType = "SDR"
        } else {
            return String(localized: .detailMediaUnavailable)
        }

        guard let primaries = media.colorPrimaries else { return colorType }
        let colorSpace: String?
        if primaries.localizedCaseInsensitiveContains("2020") {
            colorSpace = "BT.2020"
        } else if primaries.localizedCaseInsensitiveContains("709") {
            colorSpace = "BT.709"
        } else if primaries.localizedCaseInsensitiveContains("P3") {
            colorSpace = "Display P3"
        } else {
            colorSpace = nil
        }
        return [colorType, colorSpace].compactMap { $0 }.joined(separator: " · ")
    }

    private func formattedRotation(_ value: Double?) -> String {
        guard let value, value.isFinite else {
            return String(localized: .detailMediaUnavailable)
        }
        return "\(value.formatted(.number.precision(.fractionLength(0...1))))°"
    }

    private func formattedChannels(_ value: Int?) -> String {
        guard let value, value > 0 else {
            return String(localized: .detailMediaUnavailable)
        }
        let layout: String? = switch value {
        case 1: String(localized: .detailMono)
        case 2: String(localized: .detailStereo)
        case 6: String(localized: .detailSurroundFiveOne)
        default: nil
        }
        let count = String(localized: .detailChannelCount(value))
        return [layout, count].compactMap { $0 }.joined(separator: " · ")
    }

    private func formattedSampleRate(_ value: Double?) -> String {
        guard let value, value.isFinite, value > 0 else {
            return String(localized: .detailMediaUnavailable)
        }
        let number = (value / 1_000).formatted(.number.precision(.fractionLength(0...2)))
        return String(localized: .detailKilohertz(number))
    }

    private func addTagControls() {
        guard selectedVideos.isEmpty == false else { return }
        // Check marks of another selection may only stay while the list they belong to is already on
        // screen and about to be updated; a list that appears fresh waits for its own states.
        guard tagStateVideoIDs == selectedVideos.map(\.id) || tagListWasOnScreen else {
            addSecondaryText(String(localized: .tagLoading))
            return
        }
        isShowingTagList = true
        let hasExactMatch = tags.contains {
            $0.name.compare(tagSearchText, options: [.caseInsensitive, .diacriticInsensitive]) == .orderedSame
        }
        if tagSearchText.isEmpty == false, hasExactMatch == false {
            addCreateTagButton(title: tagSearchText)
        }
        let visibleTags = orderedTags.filter {
            tagSearchText.isEmpty || $0.name.localizedCaseInsensitiveContains(tagSearchText)
        }
        switch tagLayout {
        case .list:
            addTagCapsules(visibleTags, oneItemPerRow: true)
        case .compact:
            for group in InspectorTagList.groups(visibleTags, allTags: tags) {
                if let parent = group.parent {
                    addTagGroupHeader(tagPath(for: parent))
                }
                addTagCapsules(group.tags, oneItemPerRow: false)
            }
        }
        if tagSearchText.isEmpty, tags.isEmpty {
            addSecondaryText(String(localized: .tagEmpty))
        } else if tagSearchText.isEmpty == false, visibleTags.isEmpty, hasExactMatch {
            addSecondaryText(String(localized: .tagNoMatches))
        }
    }

    private func addTagGroupHeader(_ title: String) {
        let label = NSTextField(labelWithString: title)
        label.font = .systemFont(ofSize: 11, weight: .semibold)
        label.textColor = .secondaryLabelColor
        label.lineBreakMode = .byTruncatingTail
        label.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        contentStack.addArrangedSubview(label)
        label.widthAnchor.constraint(lessThanOrEqualTo: contentStack.widthAnchor).isActive = true
        contentStack.setCustomSpacing(5, after: label)
    }

    private func addTagCapsules(_ tags: [TagRecord], oneItemPerRow: Bool) {
        guard tags.isEmpty == false else { return }
        let capsules = tags.map { tag in
            let capsule = TagCapsuleButton(tag: tag, target: self, action: #selector(toggleTag(_:)))
            capsule.toolTip = tagPath(for: tag)
            capsule.state = InspectorTagList.controlState(tagStates[tag.id] ?? .off)
            capsule.onMoveFocus = { [weak self] capsule, step in self?.moveTagFocus(from: capsule, by: step) }
            tagCapsules[tag.id] = capsule
            return capsule
        }
        tagCapsuleFocusOrder.append(contentsOf: capsules)
        let flow = TagCapsuleFlowView(items: capsules, oneItemPerRow: oneItemPerRow)
        contentStack.addArrangedSubview(flow)
        flow.widthAnchor.constraint(equalTo: contentStack.widthAnchor).isActive = true
    }

    private func moveTagFocus(from capsule: TagCapsuleButton, by step: Int) {
        guard let index = tagCapsuleFocusOrder.firstIndex(where: { $0 === capsule }) else { return }
        let target = index + step
        guard tagCapsuleFocusOrder.indices.contains(target) else { return }
        let next = tagCapsuleFocusOrder[target]
        view.window?.makeFirstResponder(next)
        next.scrollToVisible(next.bounds.insetBy(dx: 0, dy: -8))
    }

    @objc private func changeTagLayout(_ sender: NSSegmentedControl) {
        tagLayout = sender.selectedSegment == 0 ? .list : .compact
        tagLayout.persist()
        rebuildTagListMovingCapsules()
    }

    private func addCreateTagButton(title: String) {
        let image = NSImage(systemSymbolName: "plus", accessibilityDescription: nil)
        let button = NSButton(
            title: String(localized: .tagNewNamed(title)),
            target: self,
            action: #selector(createTagFromSearch(_:))
        )
        button.image = image
        button.imagePosition = .imageLeading
        button.isBordered = false
        button.alignment = .left
        button.contentTintColor = .controlAccentColor
        button.toolTip = String(localized: .tagActionCreate)
        button.setAccessibilityLabel(String(localized: .accessibilityNewTagNamed(title)))
        contentStack.addArrangedSubview(button)
        button.widthAnchor.constraint(equalTo: contentStack.widthAnchor).isActive = true
    }

    @objc private func changeSection(_ sender: NSSegmentedControl) {
        closeNewTagPopover()
        renderSelection()
        scheduleInitialTagStateLoadIfNeeded()
    }

    @objc private func toggleTag(_ sender: TagCapsuleButton) {
        let tagID = sender.tagRecord.id
        let videoIDs = selectedVideos.map(\.id)
        let previousState = tagStates[tagID] ?? .off
        // Check marks still belong to the previous selection until its states load.
        guard videoIDs.isEmpty == false, tagStateVideoIDs == videoIDs else {
            sender.state = InspectorTagList.controlState(previousState)
            return
        }
        let nextState = InspectorTagList.toggledState(previousState)
        tagStates[tagID] = nextState
        sender.state = InspectorTagList.controlState(nextState)
        // A load that started before this change would bring back the old check mark.
        tagStateRequestRevision += 1
        onApplyTagDraft([], [tagID: nextState == .on], videoIDs) { [weak self] succeeded in
            // Show what was actually saved; a captured earlier state can be stale after quick repeat clicks.
            guard succeeded == false, let self else { return }
            if self.mode == .tags, self.selectedVideos.isEmpty == false {
                self.refreshTagAssignments()
            } else {
                // Not on screen now: forget the optimistic states so Tags loads them again when shown.
                self.tagStateVideoIDs = []
            }
        }
    }

    @objc private func searchTags(_ sender: NSSearchField) {
        tagSearchText = sender.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        renderSelection()
    }

    @objc private func createTagFromSearch(_ sender: NSButton) {
        showNewTagPopover(relativeTo: sender.bounds, of: sender, suggestedName: tagSearchText)
    }

    /// Add Tags in the Video menu: shows the Tags section and puts the cursor in its search field,
    /// where typing finds a tag or offers to create it.
    var canFocusTagInput: Bool {
        browsingContext == .library && selectedVideos.isEmpty == false
    }

    func focusTagInput() {
        guard canFocusTagInput else { return }
        if sectionControl.selectedSegment != 0 {
            sectionControl.selectedSegment = 0
            closeNewTagPopover()
            renderSelection()
            scheduleInitialTagStateLoadIfNeeded()
        }
        guard tagToolbar.isHidden == false else { return }
        view.window?.makeFirstResponder(tagSearchField)
        tagSearchField.selectText(nil)
    }

    var canBeginCreatingTag: Bool {
        mode == .tags && selectedVideos.isEmpty == false
    }

    func beginCreatingTag() {
        guard canBeginCreatingTag else { return }
        sectionControl.selectedSegment = 0
        renderSelection()
        showNewTagPopover(
            relativeTo: tagSearchField.bounds,
            of: tagSearchField,
            suggestedName: tagSearchText
        )
    }

    private func showNewTagPopover(relativeTo rect: NSRect, of positioningView: NSView, suggestedName: String) {
        guard canBeginCreatingTag else { return }
        closeNewTagPopover()
        let controller = NewTagPopoverViewController(
            suggestedName: suggestedName,
            parentOptions: parentTagOptions
        )
        controller.onCancel = { [weak self] in self?.closeNewTagPopover() }
        controller.onCreate = { [weak self] name, parentID in
            guard let self else { return String(localized: .tagCreateFailed) }
            let duplicateExists = self.tags.contains {
                $0.parentID == parentID
                    && $0.name.compare(name, options: [.caseInsensitive, .diacriticInsensitive]) == .orderedSame
            }
            guard duplicateExists == false else {
                return String(localized: .tagCreateDuplicate)
            }
            let creation = TagCreationDraft(id: UUID().uuidString, name: name, parentID: parentID)
            self.tagSearchText = ""
            self.tagSearchField.stringValue = ""
            self.closeNewTagPopover()
            self.renderSelection()
            self.onApplyTagDraft([creation], [creation.id: true], self.selectedVideos.map(\.id)) { _ in }
            return nil
        }
        let popover = NSPopover()
        popover.behavior = .transient
        popover.animates = true
        popover.contentViewController = controller
        newTagPopover = popover
        popover.show(relativeTo: rect, of: positioningView, preferredEdge: .maxY)
    }

    private func closeNewTagPopover() {
        newTagPopover?.performClose(nil)
        newTagPopover = nil
    }

    private var parentTagOptions: [NewTagParentOption] {
        tags
            .map { NewTagParentOption(id: $0.id, title: tagPath(for: $0)) }
            .sorted { $0.title.localizedStandardCompare($1.title) == .orderedAscending }
    }

    private func tagPath(for tag: TagRecord) -> String {
        var names = [tag.name]
        var parentID = tag.parentID
        var visited = Set([tag.id])
        while let currentID = parentID,
              visited.insert(currentID).inserted,
              let parent = tags.first(where: { $0.id == currentID }) {
            names.insert(parent.name, at: 0)
            parentID = parent.parentID
        }
        return names.joined(separator: " › ")
    }

    @objc private func copyFilename() {
        guard let filename = selectedVideo?.filename else { return }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(filename, forType: .string)
    }

    private func scheduleInitialTagStateLoadIfNeeded() {
        guard mode == .tags,
              selectedVideos.isEmpty == false,
              tagStateVideoIDs != selectedVideos.map(\.id) else { return }
        DispatchQueue.main.async { [weak self] in
            self?.refreshTagAssignments()
        }
    }

    private func updateTagSearchFieldVisibility() {
        guard isViewLoaded else { return }
        tagToolbar.isHidden = browsingContext == .scanResults
            || mode != .tags
            || selectedVideos.isEmpty
    }

    private func clearContent() {
        tagCapsules = [:]
        tagCapsuleFocusOrder = []
        isShowingTagList = false
        contentStack.arrangedSubviews.forEach {
            contentStack.removeArrangedSubview($0)
            $0.removeFromSuperview()
        }
    }

    private func updateScrollDocumentSize() {
        guard isViewLoaded else { return }
        let clipWidth = contentScrollView.contentSize.width
        guard clipWidth > Self.horizontalInset else { return }

        // A legacy scrollbar may occupy part of the external trailing gutter.
        let documentWidth = max(0, contentScrollView.bounds.width - 2 * Self.horizontalInset)
        let width = min(documentWidth, clipWidth - Self.horizontalInset)
        guard width > 0 else { return }
        contentWidth.constant = width
        for view in contentStack.arrangedSubviews {
            (view as? InspectorWrappingHelpLabel)?.updateMeasuredWidth(width)
            (view as? TagCapsuleFlowView)?.updateMeasuredWidth(width)
        }
        let height = ceil(contentStack.fittingSize.height) + Self.documentTopInset + Self.documentBottomInset
        let size = NSSize(width: clipWidth, height: height)
        if scrollDocument.frame.size != size {
            scrollDocument.setFrameSize(size)
        }
        scrollDocument.layoutSubtreeIfNeeded()
        contentScrollView.reflectScrolledClipView(contentScrollView.contentView)
    }

}

// A frame-sized scroll document does not give its stack a horizontal
// fitting proposal. Measure its help text against the actual clip width.
final class InspectorWrappingHelpLabel: NSTextField {
    private var measuredHeight: NSLayoutConstraint?
    private var measuredWidth: CGFloat = 0

    init(_ text: String) {
        super.init(frame: .zero)
        stringValue = text
        isEditable = false
        isSelectable = false
        isBezeled = false
        isBordered = false
        drawsBackground = false
        font = .systemFont(ofSize: NSFont.systemFontSize)
        textColor = .secondaryLabelColor
        cell?.usesSingleLineMode = false
        maximumNumberOfLines = 0
        lineBreakMode = .byWordWrapping
        cell?.wraps = true
        cell?.isScrollable = false
        setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    func updateMeasuredWidth(_ width: CGFloat) {
        guard width > 0, abs(measuredWidth - width) > 0.5 else { return }
        measuredWidth = width
        preferredMaxLayoutWidth = width
        let textFont = font ?? .systemFont(ofSize: NSFont.systemFontSize)
        let textSize = (stringValue as NSString).boundingRect(
            with: NSSize(width: max(1, width - 6), height: .greatestFiniteMagnitude),
            options: [.usesLineFragmentOrigin, .usesFontLeading],
            attributes: [.font: textFont]
        ).size
        let minimumHeight = ceil(textSize.height) + 4
        if let measuredHeight {
            measuredHeight.constant = minimumHeight
        } else {
            let constraint = heightAnchor.constraint(greaterThanOrEqualToConstant: minimumHeight)
            constraint.isActive = true
            measuredHeight = constraint
        }
    }
}

private final class InspectorScrollDocumentView: NSView {
    override var isFlipped: Bool { true }
}

private final class InspectorResolveCardView: NSView {
    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        updateAppearance()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        updateAppearance()
    }

    private func updateAppearance() {
        let isDark = effectiveAppearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
        layer?.cornerRadius = 7
        layer?.cornerCurve = .continuous
        layer?.masksToBounds = true
        layer?.borderWidth = 1
        layer?.borderColor = (isDark
            ? NSColor.white.withAlphaComponent(0.13)
            : NSColor.black.withAlphaComponent(0.18)).cgColor
        layer?.backgroundColor = NSColor.secondaryLabelColor
            .withAlphaComponent(isDark ? 0.11 : 0.09).cgColor
    }
}

private final class InspectorResolvePrimaryButton: NSButton {
    private var trackingArea: NSTrackingArea?
    private var isHovered = false
    private var isPressed = false

    init(title: String, target: AnyObject?, action: Selector?) {
        super.init(frame: .zero)
        self.title = title
        self.target = target
        self.action = action
        isBordered = false
        bezelStyle = .regularSquare
        controlSize = .large
        font = .systemFont(ofSize: 13, weight: .semibold)
        alignment = .center
        contentTintColor = .white
        focusRingType = .default
        wantsLayer = true
        layer?.cornerRadius = 7
        layer?.cornerCurve = .continuous
        layer?.masksToBounds = true
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override var wantsUpdateLayer: Bool { true }

    override var intrinsicContentSize: NSSize {
        NSSize(width: NSView.noIntrinsicMetric, height: 34)
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let trackingArea {
            removeTrackingArea(trackingArea)
        }
        let area = NSTrackingArea(
            rect: .zero,
            options: [.activeInKeyWindow, .inVisibleRect, .mouseEnteredAndExited],
            owner: self,
            userInfo: nil
        )
        addTrackingArea(area)
        trackingArea = area
    }

    override func mouseEntered(with event: NSEvent) {
        isHovered = true
        needsDisplay = true
    }

    override func mouseExited(with event: NSEvent) {
        isHovered = false
        needsDisplay = true
    }

    override func mouseDown(with event: NSEvent) {
        isPressed = true
        needsDisplay = true
        displayIfNeeded()
        super.mouseDown(with: event)
        isPressed = false
        needsDisplay = true
    }

    override func updateLayer() {
        let alpha = isPressed ? 0.72 : (isHovered ? 0.88 : 1)
        layer?.backgroundColor = NSColor.controlAccentColor.withAlphaComponent(alpha).cgColor
    }
}

private struct NewTagParentOption {
    let id: String
    let title: String
}

@MainActor
private final class NewTagPopoverViewController: NSViewController {
    var onCancel: (() -> Void)?
    var onCreate: ((String, String?) -> String?)?

    private let suggestedName: String
    private let parentOptions: [NewTagParentOption]
    private let nameField = NSTextField()
    private let parentPopup = NSPopUpButton()
    private let errorLabel = NSTextField(wrappingLabelWithString: "")

    init(suggestedName: String, parentOptions: [NewTagParentOption]) {
        self.suggestedName = suggestedName
        self.parentOptions = parentOptions
        super.init(nibName: nil, bundle: nil)
        preferredContentSize = NSSize(width: 300, height: 190)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func loadView() {
        let container = NSView()
        let stack = NSStackView()
        stack.translatesAutoresizingMaskIntoConstraints = false
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 10

        let titleLabel = NSTextField(labelWithString: String(localized: .tagCreateTitle))
        titleLabel.font = .systemFont(ofSize: 13, weight: .semibold)
        stack.addArrangedSubview(titleLabel)

        nameField.stringValue = suggestedName
        nameField.placeholderString = String(localized: .tagCreateNamePlaceholder)
        nameField.target = self
        nameField.action = #selector(createTag)
        addFormRow(title: String(localized: .tagCreateName), control: nameField, to: stack)

        parentPopup.addItem(withTitle: String(localized: .tagCreateTopLevelNoParent))
        for option in parentOptions {
            let item = NSMenuItem(title: option.title, action: nil, keyEquivalent: "")
            item.representedObject = option.id
            parentPopup.menu?.addItem(item)
        }
        addFormRow(title: String(localized: .tagCreateParent), control: parentPopup, to: stack)

        let noteLabel = NSTextField(
            wrappingLabelWithString: String(localized: .tagCreateNote)
        )
        noteLabel.font = .systemFont(ofSize: 10)
        noteLabel.textColor = .secondaryLabelColor
        stack.addArrangedSubview(noteLabel)
        noteLabel.widthAnchor.constraint(equalTo: stack.widthAnchor).isActive = true

        errorLabel.font = .systemFont(ofSize: 10)
        errorLabel.textColor = .systemRed
        errorLabel.isHidden = true
        stack.addArrangedSubview(errorLabel)
        errorLabel.widthAnchor.constraint(equalTo: stack.widthAnchor).isActive = true

        let cancelButton = NSButton(
            title: String(localized: .actionCancel),
            target: self,
            action: #selector(cancel)
        )
        let createButton = NSButton(
            title: String(localized: .tagActionCreate),
            target: self,
            action: #selector(createTag)
        )
        createButton.keyEquivalent = "\r"
        let spacer = NSView()
        spacer.setContentHuggingPriority(.defaultLow, for: .horizontal)
        let buttons = NSStackView(views: [spacer, cancelButton, createButton])
        buttons.orientation = .horizontal
        buttons.alignment = .centerY
        buttons.spacing = 8
        stack.addArrangedSubview(buttons)
        buttons.widthAnchor.constraint(equalTo: stack.widthAnchor).isActive = true

        container.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: 14),
            stack.trailingAnchor.constraint(equalTo: container.trailingAnchor, constant: -14),
            stack.topAnchor.constraint(equalTo: container.topAnchor, constant: 14),
            stack.bottomAnchor.constraint(lessThanOrEqualTo: container.bottomAnchor, constant: -14),
        ])
        view = container
    }

    override func viewDidAppear() {
        super.viewDidAppear()
        view.window?.makeFirstResponder(nameField)
        nameField.selectText(nil)
    }

    private func addFormRow(title: String, control: NSView, to stack: NSStackView) {
        let label = NSTextField(labelWithString: title)
        label.textColor = .secondaryLabelColor
        label.alignment = .right
        label.widthAnchor.constraint(equalToConstant: 48).isActive = true
        let row = NSStackView(views: [label, control])
        row.orientation = .horizontal
        row.alignment = .centerY
        row.spacing = 8
        stack.addArrangedSubview(row)
        row.widthAnchor.constraint(equalTo: stack.widthAnchor).isActive = true
        control.widthAnchor.constraint(greaterThanOrEqualToConstant: 190).isActive = true
    }

    @objc private func cancel() {
        onCancel?()
    }

    @objc private func createTag() {
        let name = nameField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        guard name.isEmpty == false else {
            showError(String(localized: .tagValidationEnterName))
            return
        }
        let parentID = parentPopup.selectedItem?.representedObject as? String
        if let error = onCreate?(name, parentID) {
            showError(error)
        }
    }

    private func showError(_ message: String) {
        errorLabel.stringValue = message
        errorLabel.isHidden = false
        nameField.selectText(nil)
    }
}

enum InspectorTagList {
    struct Entry: Equatable {
        let id: String
        let name: String
    }

    static let reorderDuration: CFTimeInterval = 0.25

    /// Tags any of the selected videos have, then the rest, each in library order.
    static func order(_ tags: [TagRecord], states: [String: TagAssignmentState]) -> [TagRecord] {
        let assigned = tags.filter { (states[$0.id] ?? .off) != .off }
        let unassigned = tags.filter { (states[$0.id] ?? .off) == .off }
        return assigned + unassigned
    }

    struct Group {
        let parent: TagRecord?
        let tags: [TagRecord]
    }

    /// Splits ordered tags by parent for the compact layout: top-level tags first, then each parent's
    /// children under it, parents in library order. Order inside a group follows the given order.
    static func groups(_ orderedTags: [TagRecord], allTags: [TagRecord]) -> [Group] {
        let parentIDs = allTags.map(\.id)
        let byParent = Dictionary(grouping: orderedTags, by: \.parentID)
        let tagsByID = Dictionary(uniqueKeysWithValues: allTags.map { ($0.id, $0) })
        var groups: [Group] = []
        if let topLevel = byParent[nil] {
            groups.append(Group(parent: nil, tags: topLevel))
        }
        for parentID in parentIDs {
            guard let children = byParent[parentID] else { continue }
            groups.append(Group(parent: tagsByID[parentID], tags: children))
        }
        // Children whose parent is missing still show, at the top level.
        let orphans = orderedTags.filter { tag in tag.parentID.map { tagsByID[$0] == nil } ?? false }
        if orphans.isEmpty == false {
            if let first = groups.first, first.parent == nil {
                groups[0] = Group(parent: nil, tags: first.tags + orphans)
            } else {
                groups.insert(Group(parent: nil, tags: orphans), at: 0)
            }
        }
        return groups
    }

    static func entries(_ tags: [TagRecord]) -> [Entry] {
        tags.map { Entry(id: $0.id, name: $0.name) }
    }

    static func toggledState(_ state: TagAssignmentState) -> TagAssignmentState {
        state == .on ? .off : .on
    }

    static func controlState(_ state: TagAssignmentState) -> NSControl.StateValue {
        switch state {
        case .off: .off
        case .mixed: .mixed
        case .on: .on
        }
    }
}
