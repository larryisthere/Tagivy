import AppKit
import Combine
import Sparkle

/// Checks the GitHub appcast, downloads in the background and replaces the app through Sparkle,
/// showing progress in the sidebar instead of Sparkle's standard windows.
@MainActor
final class AppUpdateController: NSObject, ObservableObject {
    static let betaChannel = "beta"
    private static let acknowledgementDuration: Duration = .seconds(4)

    @Published private(set) var status: AppUpdateStatus = .idle

    var onShowLibraryWindow: () -> Void = {}
    var onStatusChange: (AppUpdateStatus) -> Void = { _ in }

    private let preferences: PreferencesStore
    private var updater: SPUUpdater?
    private var flow = AppUpdateFlow() {
        didSet { publish() }
    }
    private var updateFoundReply: ((SPUUserUpdateChoice) -> Void)?
    private var offeredChannel: String?
    private var readyToInstallReply: ((SPUUserUpdateChoice) -> Void)?
    private var installOnQuitNow: (() -> Void)?
    private var acknowledgement: (() -> Void)?
    private var acknowledgementTask: Task<Void, Never>?

    init(preferences: PreferencesStore) {
        self.preferences = preferences
        super.init()
    }

    /// Development builds never replace themselves; only signed release builds update.
    static var isEnabledInThisBuild: Bool {
        #if DEBUG
        false
        #else
        true
        #endif
    }

    func start() {
        guard Self.isEnabledInThisBuild, updater == nil else { return }
        let updater = SPUUpdater(
            hostBundle: .main,
            applicationBundle: .main,
            userDriver: self,
            delegate: self
        )
        do {
            try updater.start()
        } catch {
            AppLogger.lifecycle.error("Updater failed to start with category: \(String(describing: type(of: error)), privacy: .public)")
            return
        }
        self.updater = updater
        if updater.automaticallyChecksForUpdates {
            updater.checkForUpdatesInBackground()
        }
    }

    var canCheckForUpdates: Bool {
        guard let updater else { return false }
        switch status {
        case .idle, .upToDate, .failed, .available:
            return updater.canCheckForUpdates
        default:
            return false
        }
    }

    func checkForUpdates() {
        guard let updater, canCheckForUpdates else { return }
        clearAcknowledgement()
        updater.checkForUpdates()
    }

    /// The sidebar button: download if needed, then install and relaunch without another prompt.
    func installUpdate() {
        guard flow.userChoseToInstall() else { return }
        if let installOnQuitNow {
            self.installOnQuitNow = nil
            flow.installing()
            installOnQuitNow()
        } else if let reply = updateFoundReply {
            updateFoundReply = nil
            reply(.install)
        } else if let reply = readyToInstallReply {
            readyToInstallReply = nil
            flow.installing()
            reply(.install)
        }
    }

    var automaticallyChecksForUpdates: Bool {
        get { updater?.automaticallyChecksForUpdates ?? false }
        set {
            objectWillChange.send()
            updater?.automaticallyChecksForUpdates = newValue
        }
    }

    var automaticallyDownloadsUpdates: Bool {
        get { updater?.automaticallyDownloadsUpdates ?? false }
        set {
            objectWillChange.send()
            updater?.automaticallyDownloadsUpdates = newValue
        }
    }

    var receivesBetaUpdates: Bool {
        get { preferences.receivesBetaUpdates }
        set {
            objectWillChange.send()
            preferences.receivesBetaUpdates = newValue
            if !newValue { withdrawOfferedBeta() }
            guard let updater, updater.automaticallyChecksForUpdates, newValue else { return }
            updater.checkForUpdatesInBackground()
        }
    }

    var isAvailable: Bool { updater != nil }

    /// A beta offered but not yet installing is dropped when the user stops receiving betas.
    /// One Sparkle already scheduled to install on quit cannot be withdrawn; the setting's help says so.
    private func withdrawOfferedBeta() {
        guard offeredChannel == Self.betaChannel, installOnQuitNow == nil,
              let reply = updateFoundReply ?? readyToInstallReply else { return }
        resetReplies()
        reply(.dismiss)
        flow.dismissed(canStillRelaunch: false)
    }

    private func publish() {
        guard status != flow.status else { return }
        status = flow.status
        onStatusChange(status)
        guard status.dismissesAutomatically else { return }
        acknowledgementTask?.cancel()
        acknowledgementTask = Task { [weak self] in
            try? await Task.sleep(for: Self.acknowledgementDuration)
            guard !Task.isCancelled else { return }
            self?.clearAcknowledgement()
        }
    }

    private func clearAcknowledgement() {
        acknowledgementTask?.cancel()
        acknowledgementTask = nil
        let acknowledgement = self.acknowledgement
        self.acknowledgement = nil
        flow.acknowledged()
        acknowledgement?()
    }

    private func resetReplies() {
        updateFoundReply = nil
        readyToInstallReply = nil
    }
}

extension AppUpdateController: SPUUpdaterDelegate {
    func allowedChannels(for updater: SPUUpdater) -> Set<String> {
        preferences.receivesBetaUpdates ? [Self.betaChannel] : []
    }

    func updater(
        _ updater: SPUUpdater,
        willInstallUpdateOnQuit item: SUAppcastItem,
        immediateInstallationBlock immediateInstallHandler: @escaping () -> Void
    ) -> Bool {
        installOnQuitNow = immediateInstallHandler
        offeredChannel = item.channel
        flow.readyToInstallOnQuit(version: item.displayVersionString)
        return true
    }
}

extension AppUpdateController: SPUUserDriver {
    func show(_ request: SPUUpdatePermissionRequest, reply: @escaping (SUUpdatePermissionResponse) -> Void) {
        reply(SUUpdatePermissionResponse(automaticUpdateChecks: true, sendSystemProfile: false))
    }

    func showUserInitiatedUpdateCheck(cancellation: @escaping () -> Void) {
        flow.userCheckStarted()
    }

    func showUpdateFound(with appcastItem: SUAppcastItem, state: SPUUserUpdateState, reply: @escaping (SPUUserUpdateChoice) -> Void) {
        let stage: AppUpdateStage = switch state.stage {
        case .notDownloaded: .notDownloaded
        case .downloaded: .downloaded
        case .installing: .installing
        @unknown default: .notDownloaded
        }
        updateFoundReply = reply
        offeredChannel = appcastItem.channel
        flow.updateFound(version: appcastItem.displayVersionString, stage: stage)
    }

    func showUpdateReleaseNotes(with downloadData: SPUDownloadData) {}

    func showUpdateReleaseNotesFailedToDownloadWithError(_ error: any Error) {}

    func showUpdateNotFoundWithError(_ error: any Error, acknowledgement: @escaping () -> Void) {
        resetReplies()
        self.acknowledgement = acknowledgement
        flow.noUpdateFound()
        if flow.status == .idle { clearAcknowledgement() }
    }

    func showUpdaterError(_ error: any Error, acknowledgement: @escaping () -> Void) {
        AppLogger.lifecycle.error("Update failed with code: \((error as NSError).code, privacy: .public)")
        resetReplies()
        self.acknowledgement = acknowledgement
        flow.failed()
        if !flow.status.dismissesAutomatically { clearAcknowledgement() }
    }

    func showDownloadInitiated(cancellation: @escaping () -> Void) {
        flow.downloadStarted()
    }

    func showDownloadDidReceiveExpectedContentLength(_ expectedContentLength: UInt64) {
        flow.downloadExpectedLength(expectedContentLength)
    }

    func showDownloadDidReceiveData(ofLength length: UInt64) {
        flow.downloadReceived(length)
    }

    func showDownloadDidStartExtractingUpdate() {
        flow.extractionStarted()
    }

    func showExtractionReceivedProgress(_ progress: Double) {}

    func showReady(toInstallAndRelaunch reply: @escaping (SPUUserUpdateChoice) -> Void) {
        if flow.readyToInstall() {
            flow.installing()
            reply(.install)
        } else {
            readyToInstallReply = reply
        }
    }

    func showInstallingUpdate(withApplicationTerminated applicationTerminated: Bool, retryTerminatingApplication: @escaping () -> Void) {
        flow.installing()
    }

    func showUpdateInstalledAndRelaunched(_ relaunched: Bool, acknowledgement: @escaping () -> Void) {
        acknowledgement()
    }

    func showUpdateInFocus() {
        onShowLibraryWindow()
    }

    func dismissUpdateInstallation() {
        resetReplies()
        flow.dismissed(canStillRelaunch: installOnQuitNow != nil)
    }
}
