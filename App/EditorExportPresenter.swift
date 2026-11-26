import AppKit

/// Saves an export plan as a file that Premiere Pro, DaVinci Resolve or Final Cut Pro can import.
@MainActor
final class EditorExportPresenter: NSObject {
    private static let formatDefaultsKey = "export.editor.format"

    private var savePanel: NSSavePanel?
    private var plan: NLEExportPlan?
    private var format: NLEExportFormat = .fcp7XML

    static func defaultName(for scope: NLEExportScope) -> String {
        switch scope {
        case let .tag(tag):
            tag.name
        case let .smartCollection(collection):
            collection.name
        case let .videos(videos):
            String(localized: .exportEditorSelectionName(videos.count))
        }
    }

    func present(_ plan: NLEExportPlan, on window: NSWindow) {
        guard savePanel == nil else { return }
        guard plan.clips.isEmpty == false else {
            showAlert(
                on: window,
                title: String(localized: .exportEditorNothingTitle),
                message: String(localized: .exportEditorNothingDetail),
                buttons: [String(localized: .exportEditorOk)]
            ) { _ in }
            return
        }
        format = UserDefaults.standard.string(forKey: Self.formatDefaultsKey)
            .flatMap(NLEExportFormat.init(rawValue:)) ?? .fcp7XML
        self.plan = plan

        let panel = NSSavePanel()
        panel.canCreateDirectories = true
        panel.isExtensionHidden = false
        panel.allowedContentTypes = [format.contentType]
        panel.nameFieldStringValue = "\(plan.root.name).\(format.fileExtension)"
        panel.accessoryView = makeAccessoryView(skippedCount: plan.skippedCount)
        savePanel = panel
        panel.beginSheetModal(for: window) { [weak self] response in
            guard let self else { return }
            let url = panel.url
            self.savePanel = nil
            guard response == .OK, let url, var plan = self.plan else {
                self.plan = nil
                return
            }
            self.plan = nil
            if plan.mirrorsTags == false {
                plan.root.name = url.deletingPathExtension().lastPathComponent
            }
            self.write(plan, format: self.format, to: url, window: window)
        }
    }

    private func makeAccessoryView(skippedCount: Int) -> NSView {
        let label = NSTextField(labelWithString: String(localized: .exportEditorFormatLabel))
        label.alignment = .right
        let popup = NSPopUpButton(frame: .zero, pullsDown: false)
        for candidate in NLEExportFormat.allCases {
            popup.addItem(withTitle: Self.title(for: candidate))
            popup.lastItem?.representedObject = candidate.rawValue
        }
        popup.selectItem(at: NLEExportFormat.allCases.firstIndex(of: format) ?? 0)
        popup.target = self
        popup.action = #selector(formatChanged(_:))

        let row = NSStackView(views: [label, popup])
        row.orientation = .horizontal
        row.spacing = 8
        var views: [NSView] = [row]
        if skippedCount > 0 {
            let note = NSTextField(labelWithString: String(localized: .exportEditorSkipped(skippedCount)))
            note.font = .systemFont(ofSize: NSFont.smallSystemFontSize)
            note.textColor = .secondaryLabelColor
            views.append(note)
        }
        let stack = NSStackView(views: views)
        stack.orientation = .vertical
        stack.alignment = .centerX
        stack.spacing = 6
        stack.edgeInsets = NSEdgeInsets(top: 12, left: 20, bottom: 12, right: 20)
        stack.frame.size = stack.fittingSize
        return stack
    }

    @objc private func formatChanged(_ sender: NSPopUpButton) {
        guard let raw = sender.selectedItem?.representedObject as? String,
              let newFormat = NLEExportFormat(rawValue: raw),
              let panel = savePanel else { return }
        format = newFormat
        UserDefaults.standard.set(newFormat.rawValue, forKey: Self.formatDefaultsKey)
        panel.allowedContentTypes = [newFormat.contentType]
        let baseName = (panel.nameFieldStringValue as NSString).deletingPathExtension
        panel.nameFieldStringValue = "\(baseName).\(newFormat.fileExtension)"
    }

    private func write(_ plan: NLEExportPlan, format: NLEExportFormat, to url: URL, window: NSWindow) {
        UserDefaults.standard.set(format.rawValue, forKey: Self.formatDefaultsKey)
        Task {
            let succeeded = await Task.detached(priority: .userInitiated) { () -> Bool in
                let data = format.data(for: plan)
                do {
                    try data.write(to: url)
                    return true
                } catch {
                    try? FileManager.default.removeItem(at: url)
                    AppLogger.library.error(
                        "Editor export write failed with category: \(String(describing: type(of: error)), privacy: .public)"
                    )
                    return false
                }
            }.value
            if succeeded {
                showDone(plan: plan, format: format, url: url, window: window)
            } else {
                showAlert(
                    on: window,
                    title: String(localized: .exportEditorFailedTitle),
                    message: String(localized: .exportEditorFailedDetail),
                    buttons: [String(localized: .exportEditorOk)]
                ) { _ in }
            }
        }
    }

    private func showDone(plan: NLEExportPlan, format: NLEExportFormat, url: URL, window: NSWindow) {
        let count = plan.clips.count
        let hint = switch format {
        case .fcp7XML:
            String(localized: .exportEditorDonePremiere)
        case .fcpXML:
            String(localized: .exportEditorDoneFinalCut)
        }
        showAlert(
            on: window,
            title: String(localized: .exportEditorDoneTitle(count)),
            message: hint,
            buttons: [
                String(localized: .exportEditorDoneClose),
                String(localized: .exportEditorDoneReveal),
            ]
        ) { response in
            if response == .alertSecondButtonReturn {
                NSWorkspace.shared.activateFileViewerSelecting([url])
            }
        }
    }

    private func showAlert(
        on window: NSWindow,
        title: String,
        message: String,
        buttons: [String],
        completion: @escaping (NSApplication.ModalResponse) -> Void
    ) {
        let alert = NSAlert()
        alert.messageText = title
        alert.informativeText = message
        buttons.forEach { alert.addButton(withTitle: $0) }
        alert.beginSheetModal(for: window, completionHandler: completion)
    }

    static func title(for format: NLEExportFormat) -> String {
        switch format {
        case .fcp7XML:
            String(localized: .exportEditorFormatPremiere)
        case .fcpXML:
            String(localized: .exportEditorFormatFinalCut)
        }
    }
}
