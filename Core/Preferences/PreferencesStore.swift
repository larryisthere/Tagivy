import AppKit
import Combine

enum IdleLockInterval: Int, CaseIterable, Identifiable, Sendable {
    case immediately = 0
    case oneMinute = 60
    case fiveMinutes = 300
    case fifteenMinutes = 900
    case never = -1

    var id: Int { rawValue }
    var title: String {
        switch self {
        case .immediately: String(localized: .preferencesImmediately)
        case .oneMinute: String(localized: .preferencesOneMinute)
        case .fiveMinutes: String(localized: .preferencesFiveMinutes)
        case .fifteenMinutes: String(localized: .preferencesFifteenMinutes)
        case .never: String(localized: .preferencesNever)
        }
    }
}

enum FolderImportPreference: String, CaseIterable, Identifiable, Sendable {
    case ask = "ask"
    case direct = "direct"
    case folderTags = "folderTags"

    var id: String { rawValue }
    var title: String {
        switch self {
        case .ask: String(localized: .settingsFolderImportAsk)
        case .direct: String(localized: .folderImportDirectTitle)
        case .folderTags: String(localized: .folderImportTagsTitle)
        }
    }
}

/// Settings → General → Appearance. Automatic follows the system setting.
enum AppAppearancePreference: String, CaseIterable, Identifiable, Sendable {
    case automatic
    case light
    case dark

    var id: String { rawValue }
    var title: String {
        switch self {
        case .automatic: String(localized: "settings.appearance.automatic", defaultValue: "Automatic")
        case .light: String(localized: "settings.appearance.light", defaultValue: "Light")
        case .dark: String(localized: "settings.appearance.dark", defaultValue: "Dark")
        }
    }

    /// The value for `NSApp.appearance`; nil follows the system.
    var nsAppearance: NSAppearance? {
        switch self {
        case .automatic: nil
        case .light: NSAppearance(named: .aqua)
        case .dark: NSAppearance(named: .darkAqua)
        }
    }
}

@MainActor
final class PreferencesStore: ObservableObject {
    enum Key {
        static let authenticationEnabled = "authenticationEnabled"
        static let idleLockInterval = "idleLockInterval"
        static let folderImportPreference = "folderImportPreference"
        static let includeSelectedFolderAsRootTag = "includeSelectedFolderAsRootTag"
        static let receivesBetaUpdates = "receivesBetaUpdates"
        static let appearance = "appearance"
        static let floatsMainWindowOnTop = "floatsMainWindowOnTop"
    }

    private let defaults: UserDefaults

    @Published private(set) var authenticationEnabled: Bool
    @Published var idleLockInterval: IdleLockInterval {
        didSet { defaults.set(idleLockInterval.rawValue, forKey: Key.idleLockInterval) }
    }
    @Published var folderImportPreference: FolderImportPreference {
        didSet { defaults.set(folderImportPreference.rawValue, forKey: Key.folderImportPreference) }
    }
    @Published var includeSelectedFolderAsRootTag: Bool {
        didSet {
            defaults.set(
                includeSelectedFolderAsRootTag,
                forKey: Key.includeSelectedFolderAsRootTag
            )
        }
    }

    @Published var receivesBetaUpdates: Bool {
        didSet { defaults.set(receivesBetaUpdates, forKey: Key.receivesBetaUpdates) }
    }

    @Published var appearance: AppAppearancePreference {
        didSet { defaults.set(appearance.rawValue, forKey: Key.appearance) }
    }

    @Published var floatsMainWindowOnTop: Bool {
        didSet { defaults.set(floatsMainWindowOnTop, forKey: Key.floatsMainWindowOnTop) }
    }

    /// Running a beta build turns on receiving betas once and remembers it, so testers keep getting betas
    /// (and releases) until they turn it off, even after an update moves them to a release build.
    init(defaults: UserDefaults = .standard, isBetaBuild: Bool = AppConfiguration.isBetaBuild) {
        self.defaults = defaults
        authenticationEnabled = defaults.object(forKey: Key.authenticationEnabled) as? Bool ?? false
        idleLockInterval = IdleLockInterval(
            rawValue: defaults.object(forKey: Key.idleLockInterval) as? Int ?? IdleLockInterval.never.rawValue
        ) ?? .never
        folderImportPreference = FolderImportPreference(
            rawValue: defaults.string(forKey: Key.folderImportPreference) ?? ""
        ) ?? .ask
        includeSelectedFolderAsRootTag = defaults.object(
            forKey: Key.includeSelectedFolderAsRootTag
        ) as? Bool ?? false
        if defaults.object(forKey: Key.receivesBetaUpdates) == nil, isBetaBuild {
            defaults.set(true, forKey: Key.receivesBetaUpdates)
        }
        receivesBetaUpdates = defaults.object(forKey: Key.receivesBetaUpdates) as? Bool ?? false
        appearance = AppAppearancePreference(rawValue: defaults.string(forKey: Key.appearance) ?? "") ?? .automatic
        floatsMainWindowOnTop = defaults.bool(forKey: Key.floatsMainWindowOnTop)
    }

    func setAuthenticationEnabled(_ enabled: Bool) {
        authenticationEnabled = enabled
        defaults.set(enabled, forKey: Key.authenticationEnabled)
    }
}
