import AppKit

/// "Export Tag ›" with one item per editing app. The format is chosen here, before the save panel
/// opens, because controls added to the sandboxed save panel do not stay in sync with it.
@MainActor
enum EditorExportMenu {
    static func item(
        title: String,
        scope: NLEExportScope?,
        isEnabled: Bool,
        target: AnyObject,
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
        let item = NSMenuItem(title: title, action: nil, keyEquivalent: "")
        item.submenu = submenu
        return item
    }

    static func formatTitle(_ format: NLEExportFormat) -> String {
        switch format {
        case .fcp7XML: String(localized: .exportEditorFormatPremiere)
        case .fcpXML: String(localized: .exportEditorFormatFinalCut)
        case .capCut: String(localized: .exportEditorFormatCapCut)
        }
    }
}
