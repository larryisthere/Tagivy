import Foundation

enum AppConfiguration {
    static let internalName = "Tagivy"
    static let bundleIdentifier = "com.larryisthere.tagivy"
    static let minimumSystemVersion = "14.0"
    /// Info.plist key the release lane fills with N when it builds Beta N; empty in releases.
    static let betaNumberInfoKey = "TagivyBetaNumber"

    static var isBetaBuild: Bool { AppVersion(info: Bundle.main.infoDictionary ?? [:]).betaNumber != nil }

    static var displayName: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleDisplayName") as? String ?? internalName
    }

    static var version: AppVersion { AppVersion(info: Bundle.main.infoDictionary ?? [:]) }

    static var versionDescription: String { version.description }
}

/// The version as people read it: "1.0.18 Beta 5" in a beta, "1.0.18" in a release, plus the build.
struct AppVersion: Equatable {
    let marketingVersion: String?
    let betaNumber: Int?
    let build: String?

    init(marketingVersion: String?, betaNumber: Int?, build: String?) {
        self.marketingVersion = marketingVersion
        self.betaNumber = betaNumber
        self.build = build
    }

    init(info: [String: Any]) {
        let betaValue = info[AppConfiguration.betaNumberInfoKey] as? String ?? ""
        self.init(
            marketingVersion: info["CFBundleShortVersionString"] as? String,
            betaNumber: Int(betaValue).flatMap { $0 > 0 ? $0 : nil },
            build: info["CFBundleVersion"] as? String
        )
    }

    /// "1.0.18 Beta 5"; the same form the appcast and GitHub release use.
    var displayVersion: String? {
        guard let marketingVersion else { return nil }
        guard let betaNumber else { return marketingVersion }
        return "\(marketingVersion) Beta \(betaNumber)"
    }

    var description: String {
        switch (displayVersion, build) {
        case let (.some(version), .some(build)):
            String(localized: .aboutVersionBuild(version, build))
        case let (.some(version), .none):
            String(localized: .aboutVersion(version))
        case let (.none, .some(build)):
            String(localized: .aboutBuild(build))
        case (.none, .none):
            String(localized: .aboutUnavailable)
        }
    }
}
