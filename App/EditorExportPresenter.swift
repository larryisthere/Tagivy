import AppKit

/// Saves an export plan as a file that Premiere Pro, DaVinci Resolve or Final Cut Pro can import.
@MainActor
final class EditorExportPresenter {
    private var isPresenting = false

    static func defaultName(for scope: VideoScope) -> String {
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
            TransientNotice.show(
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
            if plan.rootIsTag == false {
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
                    // Atomic, so a failed write leaves any file the user chose to replace untouched.
                    try data.write(to: url, options: .atomic)
                    return true
                } catch {
                    AppLogger.library.error(
                        "Editor export write failed with category: \(String(describing: type(of: error)), privacy: .public)"
                    )
                    return false
                }
            }.value
            if succeeded {
                showDone(plan: plan, format: format, url: url, window: window)
            } else {
                TransientNotice.show(
                    in: window,
                    title: String(localized: .exportEditorFailedTitle),
                    detail: String(localized: .exportEditorFailedDetail)
                )
            }
        }
    }

    private func showDone(plan: NLEExportPlan, format: NLEExportFormat, url: URL, window: NSWindow) {
        var detail = switch format {
        case .fcp7XML: String(localized: .exportEditorDonePremiere)
        case .fcpXML: String(localized: .exportEditorDoneFinalCut)
        case .capCut: String(localized: .exportEditorDoneCapCut)
        }
        if plan.skippedCount > 0 {
            detail += " " + String(localized: .exportEditorSkipped(plan.skippedCount))
        }
        TransientNotice.show(
            in: window,
            title: String(localized: .exportEditorDoneTitle(plan.clips.count)),
            detail: detail,
            action: TransientNotice.Action(title: String(localized: .exportEditorDoneReveal)) {
                NSWorkspace.shared.activateFileViewerSelecting([url])
            }
        )
    }
}
