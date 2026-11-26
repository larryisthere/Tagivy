import AppKit

/// Saves an export plan as a file that Premiere Pro, DaVinci Resolve or Final Cut Pro can import.
@MainActor
final class EditorExportPresenter {
    private var isPresenting = false
    private let notice = TransientNotice()

    static func defaultName(for scope: NLEExportScope) -> String {
        switch scope {
        case let .tags(tags):
            tags.count == 1 ? tags[0].name : String(localized: .exportEditorSelectedTagsName(tags.count))
        case let .smartCollection(collection):
            collection.name
        case let .videos(videos):
            String(localized: .exportEditorSelectionName(videos.count))
        }
    }

    /// The save panel gets no accessory controls: in a sandboxed app it runs in another process,
    /// and added controls stop responding there.
    func present(_ plan: NLEExportPlan, format: NLEExportFormat, on window: NSWindow) {
        guard isPresenting == false else { return }
        guard plan.clips.isEmpty == false else {
            notice.show(
                in: window,
                title: String(localized: .exportEditorNothingTitle),
                detail: String(localized: .exportEditorNothingDetail)
            )
            return
        }
        isPresenting = true
        let panel = NSSavePanel()
        panel.canCreateDirectories = true
        panel.isExtensionHidden = false
        panel.allowedContentTypes = [format.contentType]
        panel.nameFieldStringValue = "\(plan.root.name).\(format.fileExtension)"
        panel.beginSheetModal(for: window) { [weak self] response in
            guard let self else { return }
            self.isPresenting = false
            guard response == .OK, let url = panel.url else { return }
            var plan = plan
            if plan.mirrorsTags == false {
                plan.root.name = url.deletingPathExtension().lastPathComponent
            }
            self.write(plan, format: format, to: url, window: window)
        }
    }

    private func write(_ plan: NLEExportPlan, format: NLEExportFormat, to url: URL, window: NSWindow) {
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
        var detail = switch format {
        case .fcp7XML: String(localized: .exportEditorDonePremiere)
        case .fcpXML: String(localized: .exportEditorDoneFinalCut)
        }
        if plan.skippedCount > 0 {
            detail += " " + String(localized: .exportEditorSkipped(plan.skippedCount))
        }
        notice.show(
            in: window,
            title: String(localized: .exportEditorDoneTitle(plan.clips.count)),
            detail: detail,
            actionTitle: String(localized: .exportEditorDoneReveal)
        ) {
            NSWorkspace.shared.activateFileViewerSelecting([url])
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
}
