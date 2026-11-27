import AppKit

/// The bottom-left corner of the library: a rounded row under a separator showing update progress.
/// When an update can be installed, the whole row is the button that installs and relaunches.
/// The row keeps its text short so it fits the narrowest sidebar; the version goes in the help tag
/// and the accessibility label, and anything that still doesn't fit shows in full on hover.
@MainActor
final class UpdateStatusView: NSView {
    var onInstall: () -> Void = {}

    private let separator = NSBox()
    private let capsule = UpdateStatusCapsule()
    private let spinner = NSProgressIndicator()
    private let icon = NSImageView()
    private let label = NSTextField(labelWithString: "")

    private(set) var status: AppUpdateStatus = .idle

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        translatesAutoresizingMaskIntoConstraints = false

        separator.boxType = .separator
        separator.translatesAutoresizingMaskIntoConstraints = false

        spinner.style = .spinning
        spinner.controlSize = .small
        spinner.minValue = 0
        spinner.maxValue = 1
        spinner.translatesAutoresizingMaskIntoConstraints = false

        icon.symbolConfiguration = .init(pointSize: 14, weight: .regular)
        icon.translatesAutoresizingMaskIntoConstraints = false

        label.font = .systemFont(ofSize: NSFont.systemFontSize)
        label.lineBreakMode = .byTruncatingTail
        label.translatesAutoresizingMaskIntoConstraints = false
        label.allowsExpansionToolTips = true
        label.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)

        capsule.translatesAutoresizingMaskIntoConstraints = false
        capsule.onPress = { [weak self] in self?.onInstall() }
        capsule.addSubview(spinner)
        capsule.addSubview(icon)
        capsule.addSubview(label)

        addSubview(separator)
        addSubview(capsule)
        NSLayoutConstraint.activate([
            separator.leadingAnchor.constraint(equalTo: leadingAnchor),
            separator.trailingAnchor.constraint(equalTo: trailingAnchor),
            separator.topAnchor.constraint(equalTo: topAnchor),

            capsule.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 10),
            capsule.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -10),
            capsule.topAnchor.constraint(equalTo: separator.bottomAnchor, constant: 10),
            capsule.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -10),
            capsule.heightAnchor.constraint(equalToConstant: 32),

            spinner.leadingAnchor.constraint(equalTo: capsule.leadingAnchor, constant: 10),
            spinner.centerYAnchor.constraint(equalTo: capsule.centerYAnchor),
            spinner.widthAnchor.constraint(equalToConstant: 16),
            spinner.heightAnchor.constraint(equalToConstant: 16),

            icon.centerXAnchor.constraint(equalTo: spinner.centerXAnchor),
            icon.centerYAnchor.constraint(equalTo: capsule.centerYAnchor),

            label.leadingAnchor.constraint(equalTo: spinner.trailingAnchor, constant: 8),
            label.trailingAnchor.constraint(lessThanOrEqualTo: capsule.trailingAnchor, constant: -10),
            label.centerYAnchor.constraint(equalTo: capsule.centerYAnchor),
        ])
        render(.idle)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    func render(_ status: AppUpdateStatus) {
        self.status = status
        isHidden = status == .idle

        switch status {
        case .idle:
            show(.none, text: "")
        case .checking:
            show(.spinner, text: String(localized: .updateChecking))
        case .upToDate:
            show(.symbol("checkmark.circle"), text: String(localized: .updateUpToDate))
        case .failed:
            show(.symbol("exclamationmark.circle"), text: String(localized: .updateFailed))
        case let .available(version):
            show(
                .symbol("arrow.down.circle"),
                text: String(localized: .updateInstall),
                detail: String(localized: .updateInstallVersion(version)),
                actionable: true
            )
        case let .downloading(version, fraction):
            show(
                fraction.map(Leading.progress) ?? .spinner,
                text: String(localized: .updateDownloading),
                detail: String(localized: .updateDownloadingVersion(version))
            )
        case .preparing:
            show(.spinner, text: String(localized: .updatePreparing))
        case let .readyToRelaunch(version):
            show(
                .symbol("arrow.clockwise.circle"),
                text: String(localized: .updateRelaunch),
                detail: String(localized: .updateRelaunchVersion(version)),
                actionable: true
            )
        case .installing:
            show(.spinner, text: String(localized: .updateInstalling))
        }
    }

    private enum Leading {
        case none
        case spinner
        case progress(Double)
        case symbol(String)
    }

    /// `detail` names the version; it becomes the help tag and what VoiceOver reads.
    private func show(_ leading: Leading, text: String, detail: String? = nil, actionable: Bool = false) {
        label.stringValue = text
        label.textColor = actionable ? .labelColor : .secondaryLabelColor

        icon.isHidden = true
        spinner.isHidden = true
        spinner.stopAnimation(nil)
        switch leading {
        case .none:
            break
        case .spinner:
            spinner.isIndeterminate = true
            spinner.isHidden = false
            spinner.startAnimation(nil)
        case let .progress(fraction):
            spinner.isIndeterminate = false
            spinner.doubleValue = fraction
            spinner.isHidden = false
        case let .symbol(name):
            icon.image = NSImage(systemSymbolName: name, accessibilityDescription: nil)
            icon.contentTintColor = actionable ? .controlAccentColor : .secondaryLabelColor
            icon.isHidden = false
        }

        capsule.isActionable = actionable
        capsule.toolTip = detail
        capsule.setAccessibilityLabel(detail ?? text)
    }
}

/// The rounded row itself; clickable only while it offers an install.
@MainActor
private final class UpdateStatusCapsule: NSView {
    var onPress: () -> Void = {}
    var isActionable = false {
        didSet {
            guard isActionable != oldValue else { return }
            isHovered = false
            setAccessibilityRole(isActionable ? .button : .staticText)
            window?.invalidateCursorRects(for: self)
            needsDisplay = true
        }
    }

    private var isHovered = false {
        didSet { if isHovered != oldValue { needsDisplay = true } }
    }
    private var isPressed = false {
        didSet { if isPressed != oldValue { needsDisplay = true } }
    }

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        setAccessibilityElement(true)
        setAccessibilityRole(.staticText)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override var isFlipped: Bool { true }

    override func draw(_ dirtyRect: NSRect) {
        let emphasis = isActionable && (isHovered || isPressed)
        let fill = NSColor.labelColor.withAlphaComponent(isPressed && isActionable ? 0.14 : emphasis ? 0.1 : 0.06)
        fill.setFill()
        NSBezierPath(roundedRect: bounds, xRadius: 8, yRadius: 8).fill()
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        trackingAreas.forEach(removeTrackingArea)
        addTrackingArea(NSTrackingArea(
            rect: .zero,
            options: [.mouseEnteredAndExited, .activeInKeyWindow, .inVisibleRect],
            owner: self
        ))
    }

    override func resetCursorRects() {
        if isActionable { addCursorRect(bounds, cursor: .pointingHand) }
    }

    override func mouseEntered(with event: NSEvent) { isHovered = isActionable }
    override func mouseExited(with event: NSEvent) { isHovered = false }

    override func mouseDown(with event: NSEvent) {
        guard isActionable else { return super.mouseDown(with: event) }
        isPressed = true
    }

    override func mouseUp(with event: NSEvent) {
        guard isActionable, isPressed else { return super.mouseUp(with: event) }
        isPressed = false
        if bounds.contains(convert(event.locationInWindow, from: nil)) { onPress() }
    }

    override func accessibilityPerformPress() -> Bool {
        guard isActionable else { return false }
        onPress()
        return true
    }
}
