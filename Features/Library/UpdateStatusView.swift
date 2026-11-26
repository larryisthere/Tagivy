import AppKit

/// The bottom-left corner of the library: update progress, and the one button that installs and relaunches.
@MainActor
final class UpdateStatusView: NSView {
    var onInstall: () -> Void = {}

    private let spinner = NSProgressIndicator()
    private let progressBar = NSProgressIndicator()
    private let icon = NSImageView()
    private let label = NSTextField(labelWithString: "")
    private let button = NSButton(title: "", target: nil, action: nil)
    private let row = NSStackView()
    private let stack = NSStackView()

    private(set) var status: AppUpdateStatus = .idle

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        translatesAutoresizingMaskIntoConstraints = false

        spinner.style = .spinning
        spinner.controlSize = .small
        spinner.isIndeterminate = true

        progressBar.style = .bar
        progressBar.controlSize = .small
        progressBar.minValue = 0
        progressBar.maxValue = 1

        icon.symbolConfiguration = .init(pointSize: 12, weight: .regular)

        label.font = .systemFont(ofSize: NSFont.smallSystemFontSize)
        label.textColor = .secondaryLabelColor
        label.lineBreakMode = .byTruncatingTail
        label.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)

        button.bezelStyle = .push
        button.controlSize = .regular
        button.bezelColor = .controlAccentColor
        button.keyEquivalent = ""
        button.target = self
        button.action = #selector(install(_:))
        button.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)

        row.orientation = .horizontal
        row.spacing = 6
        row.alignment = .centerY
        row.setViews([spinner, icon, label], in: .leading)

        stack.orientation = .vertical
        stack.alignment = .width
        stack.spacing = 6
        stack.edgeInsets = NSEdgeInsets(top: 8, left: 12, bottom: 10, right: 12)
        stack.translatesAutoresizingMaskIntoConstraints = false
        stack.setViews([row, progressBar, button], in: .top)
        addSubview(stack)
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: trailingAnchor),
            stack.topAnchor.constraint(equalTo: topAnchor),
            stack.bottomAnchor.constraint(equalTo: bottomAnchor),
        ])
        render(.idle)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    func render(_ status: AppUpdateStatus) {
        self.status = status
        isHidden = status == .idle
        spinner.stopAnimation(nil)
        spinner.isHidden = true
        icon.isHidden = true
        row.isHidden = false
        progressBar.isHidden = true
        button.isHidden = true

        switch status {
        case .idle:
            break
        case .checking:
            showSpinner(String(localized: .updateChecking))
        case .upToDate:
            showIcon("checkmark.circle", tint: .secondaryLabelColor, String(localized: .updateUpToDate))
        case .failed:
            showIcon("exclamationmark.circle", tint: .secondaryLabelColor, String(localized: .updateFailed))
        case let .available(version):
            row.isHidden = true
            showButton(String(localized: .updateInstallVersion(version)))
        case let .downloading(version, fraction):
            label.stringValue = String(localized: .updateDownloadingVersion(version))
            progressBar.isHidden = false
            progressBar.isIndeterminate = fraction == nil
            if let fraction {
                progressBar.doubleValue = fraction
            } else {
                progressBar.startAnimation(nil)
            }
        case .preparing:
            showSpinner(String(localized: .updatePreparing))
        case let .readyToRelaunch(version):
            row.isHidden = true
            showButton(String(localized: .updateRelaunchVersion(version)))
        case .installing:
            showSpinner(String(localized: .updateInstalling))
        }
        setAccessibilityLabel(button.isHidden ? label.stringValue : button.title)
    }

    private func showSpinner(_ text: String) {
        spinner.isHidden = false
        spinner.startAnimation(nil)
        label.stringValue = text
    }

    private func showIcon(_ symbolName: String, tint: NSColor, _ text: String) {
        icon.image = NSImage(systemSymbolName: symbolName, accessibilityDescription: nil)
        icon.contentTintColor = tint
        icon.isHidden = false
        label.stringValue = text
    }

    private func showButton(_ title: String) {
        button.title = title
        button.toolTip = title
        button.isHidden = false
    }

    @objc private func install(_ sender: Any?) {
        onInstall()
    }
}
