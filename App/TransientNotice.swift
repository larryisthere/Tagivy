import AppKit

/// A notice at the bottom of a window that fades out on its own; hovering keeps it open.
@MainActor
final class TransientNotice {
    static let visibleDuration: Duration = .seconds(5)

    private var view: TransientNoticeView?
    private var dismissTask: Task<Void, Never>?

    func show(in window: NSWindow, title: String, detail: String?, actionTitle: String? = nil, action: (() -> Void)? = nil) {
        dismiss(animated: false)
        guard let contentView = window.contentView else { return }
        let notice = TransientNoticeView(title: title, detail: detail, actionTitle: actionTitle) { [weak self] in
            action?()
            self?.dismiss(animated: true)
        }
        notice.onHoverChanged = { [weak self] isHovering in
            if isHovering {
                self?.dismissTask?.cancel()
            } else {
                self?.scheduleDismiss()
            }
        }
        notice.translatesAutoresizingMaskIntoConstraints = false
        notice.alphaValue = 0
        contentView.addSubview(notice)
        NSLayoutConstraint.activate([
            notice.centerXAnchor.constraint(equalTo: contentView.centerXAnchor),
            notice.bottomAnchor.constraint(equalTo: contentView.bottomAnchor, constant: -24),
            notice.widthAnchor.constraint(lessThanOrEqualToConstant: 460),
            notice.leadingAnchor.constraint(greaterThanOrEqualTo: contentView.leadingAnchor, constant: 24),
        ])
        view = notice
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.2
            notice.animator().alphaValue = 1
        }
        NSAccessibility.post(
            element: notice,
            notification: .announcementRequested,
            userInfo: [.announcement: [title, detail].compactMap { $0 }.joined(separator: " ")]
        )
        scheduleDismiss()
    }

    private func scheduleDismiss() {
        dismissTask?.cancel()
        dismissTask = Task { [weak self] in
            try? await Task.sleep(for: Self.visibleDuration)
            guard Task.isCancelled == false else { return }
            self?.dismiss(animated: true)
        }
    }

    private func dismiss(animated: Bool) {
        dismissTask?.cancel()
        dismissTask = nil
        guard let notice = view else { return }
        view = nil
        guard animated else {
            notice.removeFromSuperview()
            return
        }
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.25
            notice.animator().alphaValue = 0
        }
        Task {
            try? await Task.sleep(for: .milliseconds(250))
            notice.removeFromSuperview()
        }
    }
}

private final class TransientNoticeView: NSVisualEffectView {
    static let textWidth: CGFloat = 300

    var onHoverChanged: (Bool) -> Void = { _ in }
    private let onAction: () -> Void

    init(title: String, detail: String?, actionTitle: String?, onAction: @escaping () -> Void) {
        self.onAction = onAction
        super.init(frame: .zero)
        material = .popover
        blendingMode = .withinWindow
        state = .active
        wantsLayer = true
        layer?.cornerRadius = 12
        layer?.masksToBounds = true

        let titleLabel = NSTextField(labelWithString: title)
        titleLabel.font = .systemFont(ofSize: NSFont.systemFontSize, weight: .semibold)
        var texts: [NSView] = [titleLabel]
        if let detail {
            let detailLabel = NSTextField(wrappingLabelWithString: detail)
            detailLabel.textColor = .secondaryLabelColor
            detailLabel.font = .systemFont(ofSize: NSFont.smallSystemFontSize)
            // Without a wrapping width the label reports a one-line height and its second line spills out.
            detailLabel.preferredMaxLayoutWidth = Self.textWidth
            texts.append(detailLabel)
        }
        let textStack = NSStackView(views: texts)
        textStack.orientation = .vertical
        textStack.alignment = .leading
        textStack.spacing = 2

        var views: [NSView] = [textStack]
        if let actionTitle {
            let button = NSButton(title: actionTitle, target: self, action: #selector(performAction))
            button.bezelStyle = .push
            button.controlSize = .small
            button.setContentHuggingPriority(.required, for: .horizontal)
            views.append(button)
        }
        let row = NSStackView(views: views)
        row.orientation = .horizontal
        row.alignment = .centerY
        row.spacing = 16
        row.edgeInsets = NSEdgeInsets(top: 12, left: 16, bottom: 12, right: 12)
        row.translatesAutoresizingMaskIntoConstraints = false
        addSubview(row)
        NSLayoutConstraint.activate([
            row.leadingAnchor.constraint(equalTo: leadingAnchor),
            row.trailingAnchor.constraint(equalTo: trailingAnchor),
            row.topAnchor.constraint(equalTo: topAnchor),
            row.bottomAnchor.constraint(equalTo: bottomAnchor),
        ])
        setAccessibilityElement(true)
        setAccessibilityRole(.group)
        setAccessibilityLabel(title)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        trackingAreas.forEach(removeTrackingArea)
        addTrackingArea(NSTrackingArea(rect: bounds, options: [.mouseEnteredAndExited, .activeInKeyWindow], owner: self))
    }

    override func mouseEntered(with event: NSEvent) { onHoverChanged(true) }
    override func mouseExited(with event: NSEvent) { onHoverChanged(false) }

    @objc private func performAction() { onAction() }
}
