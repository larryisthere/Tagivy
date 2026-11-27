import AppKit

/// "Export to Editing App ›" with one item per editing app, the same wherever the videos come from. The format is chosen here, before the save panel
/// opens, because controls added to the sandboxed save panel do not stay in sync with it.
@MainActor
enum EditorExportMenu {
    static func item(
        scope: VideoScope?,
        isEnabled: Bool,
        target: AnyObject?,
        action: Selector
    ) -> NSMenuItem {
        let submenu = NSMenu()
        submenu.autoenablesItems = false
        for format in NLEExportFormat.allCases {
            let item = NSMenuItem(title: formatTitle(format), action: action, keyEquivalent: "")
            item.target = target
            item.isEnabled = isEnabled
            item.representedObject = NLEExportMenuChoice(scope: scope, format: format)
            submenu.addItem(item)
        }
        let item = NSMenuItem(title: String(localized: .exportEditorMenu), action: nil, keyEquivalent: "")
        item.submenu = submenu
        return item
    }

    static func formatTitle(_ format: NLEExportFormat) -> String {
        switch format {
        case .fcp7XML: String(localized: .exportEditorFormatPremiere)
        case .resolve: String(localized: .exportEditorFormatResolve)
        case .fcpXML: String(localized: .exportEditorFormatFinalCut)
        case .capCut: String(localized: .exportEditorFormatCapCut)
        }
    }
}
