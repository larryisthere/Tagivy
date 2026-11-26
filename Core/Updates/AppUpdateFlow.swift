import Foundation

/// What the sidebar shows about updates. `idle` shows nothing.
enum AppUpdateStatus: Equatable, Sendable {
    case idle
    case checking
    case upToDate
    case available(version: String)
    case downloading(version: String, fraction: Double?)
    case preparing(version: String)
    case readyToRelaunch(version: String)
    case installing
    case failed

    /// Statuses that only acknowledge a check the user asked for and then go away by themselves.
    var dismissesAutomatically: Bool {
        switch self {
        case .upToDate, .failed: true
        default: false
        }
    }
}

/// Where an update Sparkle presents already is.
enum AppUpdateStage: Equatable, Sendable {
    case notDownloaded
    case downloaded
    case installing
}

/// Update UI state, kept independent of Sparkle so its rules can be tested.
struct AppUpdateFlow: Equatable, Sendable {
    private(set) var status: AppUpdateStatus = .idle
    private(set) var isUserInitiatedCheck = false
    private(set) var userChoseInstall = false
    private var version: String?
    private var expectedBytes: UInt64 = 0
    private var receivedBytes: UInt64 = 0

    /// The user asked to check (menu, settings or the sidebar).
    mutating func userCheckStarted() {
        isUserInitiatedCheck = true
        userChoseInstall = false
        status = .checking
    }

    /// Sparkle presents an update. Background and user checks behave the same:
    /// anything already downloaded is one click from relaunching.
    mutating func updateFound(version: String, stage: AppUpdateStage) {
        self.version = version
        isUserInitiatedCheck = false
        switch stage {
        case .notDownloaded:
            status = .available(version: version)
        case .downloaded, .installing:
            status = .readyToRelaunch(version: version)
        }
    }

    /// A background download finished; Sparkle will install on quit unless the user relaunches now.
    mutating func readyToInstallOnQuit(version: String) {
        self.version = version
        status = .readyToRelaunch(version: version)
    }

    /// Background checks never show "up to date" or errors; only a check the user asked for does.
    mutating func noUpdateFound() {
        status = isUserInitiatedCheck ? .upToDate : .idle
        isUserInitiatedCheck = false
    }

    mutating func failed() {
        if case .readyToRelaunch = status { return }
        status = isUserInitiatedCheck || userChoseInstall ? .failed : .idle
        isUserInitiatedCheck = false
        userChoseInstall = false
    }

    /// The user clicked the sidebar button. Returns whether the click should start installing.
    mutating func userChoseToInstall() -> Bool {
        switch status {
        case .available, .readyToRelaunch:
            userChoseInstall = true
            return true
        default:
            return false
        }
    }

    mutating func downloadStarted() {
        expectedBytes = 0
        receivedBytes = 0
        status = .downloading(version: version ?? "", fraction: nil)
    }

    mutating func downloadExpectedLength(_ length: UInt64) {
        expectedBytes = length
        receivedBytes = 0
        status = .downloading(version: version ?? "", fraction: downloadFraction)
    }

    mutating func downloadReceived(_ length: UInt64) {
        receivedBytes += length
        status = .downloading(version: version ?? "", fraction: downloadFraction)
    }

    mutating func extractionStarted() {
        status = .preparing(version: version ?? "")
    }

    /// Sparkle asks whether to install and relaunch once the update is ready.
    /// Clicking the sidebar button already answered that, so it installs without asking again.
    mutating func readyToInstall() -> Bool {
        if userChoseInstall { return true }
        status = .readyToRelaunch(version: version ?? "")
        return false
    }

    mutating func installing() {
        status = .installing
    }

    /// Sparkle closed the update session. A relaunch stays offered only while Sparkle can still perform it.
    mutating func dismissed(canStillRelaunch: Bool) {
        isUserInitiatedCheck = false
        userChoseInstall = false
        switch status {
        case .readyToRelaunch where canStillRelaunch, .upToDate, .failed:
            break
        default:
            status = .idle
        }
    }

    mutating func acknowledged() {
        if status.dismissesAutomatically { status = .idle }
    }

    private var downloadFraction: Double? {
        guard expectedBytes > 0 else { return nil }
        return min(1, Double(receivedBytes) / Double(expectedBytes))
    }
}
