import AppKit
import SwiftUI

/// Settings panes, in toolbar order.
enum SettingsPane: String, CaseIterable {
    case importOptions
    case privacy
    case updates

    var title: String {
        switch self {
        case .importOptions: String(localized: .settingsImport)
        case .privacy: String(localized: .settingsPrivacy)
        case .updates: String(localized: .settingsUpdates)
        }
    }

    var systemImage: String {
        switch self {
        case .importOptions: "tray.and.arrow.down"
        case .privacy: "hand.raised"
        case .updates: "arrow.triangle.2.circlepath"
        }
    }

    /// The pane the window opens on: the one last viewed, or the first.
    static func initial(saved: String?, in panes: [SettingsPane]) -> SettingsPane {
        saved.flatMap(SettingsPane.init(rawValue:)).flatMap { panes.contains($0) ? $0 : nil } ?? panes[0]
    }
}

/// A standard Mac settings window: one toolbar button per pane, the window titled after the pane,
/// sized to the pane, not resizable, and reopening on the pane last viewed.
@MainActor
final class SettingsTabViewController: NSTabViewController {
    static let selectedPaneDefaultsKey = "SettingsSelectedPane"
    private let defaults: UserDefaults

    init(panes: [(SettingsPane, NSViewController)], defaults: UserDefaults = .standard) {
        self.defaults = defaults
        super.init(nibName: nil, bundle: nil)
        tabStyle = .toolbar
        canPropagateSelectedChildViewControllerTitle = true
        for (pane, controller) in panes {
            controller.title = pane.title
            let item = NSTabViewItem(viewController: controller)
            item.identifier = pane.rawValue
            item.label = pane.title
            item.image = NSImage(systemSymbolName: pane.systemImage, accessibilityDescription: pane.title)
            addTabViewItem(item)
        }
        let initial = SettingsPane.initial(
            saved: defaults.string(forKey: Self.selectedPaneDefaultsKey),
            in: panes.map(\.0)
        )
        selectedTabViewItemIndex = panes.firstIndex { $0.0 == initial } ?? 0
    }

    var selectedPane: SettingsPane? {
        guard tabViewItems.indices.contains(selectedTabViewItemIndex) else { return nil }
        return (tabViewItems[selectedTabViewItemIndex].identifier as? String).flatMap(SettingsPane.init(rawValue:))
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func tabView(_ tabView: NSTabView, didSelect tabViewItem: NSTabViewItem?) {
        super.tabView(tabView, didSelect: tabViewItem)
        if let pane = tabViewItem?.identifier as? String {
            defaults.set(pane, forKey: Self.selectedPaneDefaultsKey)
        }
    }
}

/// Every pane has the same width, so only the height changes when switching panes.
private struct SettingsPaneForm<Content: View>: View {
    @ViewBuilder let content: Content

    var body: some View {
        Form { content }
            .formStyle(.grouped)
            .scrollDisabled(true)
            .frame(width: 500)
            .fixedSize(horizontal: false, vertical: true)
    }
}

struct ImportSettingsView: View {
    @ObservedObject var preferences: PreferencesStore

    var body: some View {
        SettingsPaneForm {
            Section {
                Picker(selection: $preferences.folderImportPreference) {
                    ForEach(FolderImportPreference.allCases) { preference in
                        Text(preference.title).tag(preference)
                    }
                } label: {
                    Text(String(localized: .settingsFolderImportMethod))
                    Text(String(localized: .settingsFolderImportMethodHelp))
                }

                Toggle(isOn: $preferences.includeSelectedFolderAsRootTag) {
                    Text(String(localized: .folderImportIncludeRoot))
                    Text(String(localized: .settingsIncludeSelectedFolderHelp))
                }
                .disabled(preferences.folderImportPreference == .direct)
            }
        }
    }
}

struct PrivacySettingsView: View {
    @ObservedObject var preferences: PreferencesStore
    let setAuthenticationEnabled: (Bool) -> Void

    var body: some View {
        SettingsPaneForm {
            Section {
                Toggle(isOn: Binding(
                    get: { preferences.authenticationEnabled },
                    set: { enabled in setAuthenticationEnabled(enabled) }
                )) {
                    Text(String(localized: .settingsEnableLock))
                    Text(String(localized: .settingsLockNote))
                }

                Picker(String(localized: .settingsIdleLock), selection: $preferences.idleLockInterval) {
                    ForEach(IdleLockInterval.allCases) { interval in
                        Text(interval.title).tag(interval)
                    }
                }
                .disabled(preferences.authenticationEnabled == false)
            }
        }
    }
}

struct UpdatesSettingsView: View {
    @ObservedObject var updates: AppUpdateController

    var body: some View {
        SettingsPaneForm {
            Section {
                Toggle(String(localized: .settingsUpdatesCheckAutomatically), isOn: $updates.automaticallyChecksForUpdates)
                Toggle(isOn: $updates.automaticallyDownloadsUpdates) {
                    Text(String(localized: .settingsUpdatesDownloadAutomatically))
                    Text(
                        updates.automaticallyDownloadsUpdates && updates.automaticallyChecksForUpdates
                            ? String(localized: .settingsUpdatesDownloadAutomaticallyHelp)
                            : String(localized: .settingsUpdatesPromptHelp)
                    )
                }
                .disabled(!updates.automaticallyChecksForUpdates)
                Toggle(isOn: $updates.receivesBetaUpdates) {
                    Text(String(localized: .settingsUpdatesBeta))
                    Text(String(localized: .settingsUpdatesBetaHelp))
                }
            }
            .disabled(!updates.isAvailable)

            Section {
                LabeledContent {
                    Button(String(localized: .menuCheckForUpdates)) {
                        updates.checkForUpdates()
                    }
                    .disabled(!updates.canCheckForUpdates)
                } label: {
                    Text(AppConfiguration.displayName)
                    Text(AppConfiguration.versionDescription)
                }
            }
        }
    }
}
