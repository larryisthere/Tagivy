import AppKit

/// The one way Tagivy tells people something that needs no decision: a notice at the bottom of the window
/// that counts down and fades out on its own. Hovering pauses it, and it offers at most one optional action.
/// Anything that needs an answer (confirm, choose, name) uses an `NSAlert` sheet instead.
@MainActor
final class TransientNotice {
    struct Action {
        let title: String
        let perform: () -> Void
    }

    static let visibleDuration: Duration = .seconds(5)

    /// A newer notice replaces the one on screen, so there is never more than one.
    private static let current = TransientNotice()

    private var view: TransientNoticeView?
    private var dismissTask: Task<Void, Never>?
    private var remaining: Duration = .zero
    private var countingSince: ContinuousClock.Instant?

    private init() {}

    static func show(in window: NSWindow, title: String, detail: String? = nil, action: Action? = nil) {
        current.show(in: window, title: title, detail: detail, action: action)
    }

    private func show(in window: NSWindow, title: String, detail: String?, action: Action?) {
        dismiss(animated: false)
        guard let contentView = window.contentView else { return }
        let notice = TransientNoticeView(title: title, detail: detail, actionTitle: action?.title) { [weak self] in
            action?.perform()
            self?.dismiss(animated: true)
        }
        notice.onHoverChanged = { [weak self, weak notice] isHovering in
            guard let self, let notice, self.view === notice else { return }
            if isHovering {
                pauseCountdown()
                notice.countdown.pause()
            } else {
                notice.countdown.resume()
                resumeCountdown()
            }
        }
        notice.translatesAutoresizingMaskIntoConstraints = false
        notice.alphaValue = 0
        contentView.addSubview(notice)
        NSLayoutConstraint.activate([
            notice.centerXAnchor.constraint(equalTo: contentView.centerXAnchor),
            notice.bottomAnchor.constraint(equalTo: contentView.bottomAnchor, constant: -24),
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
        remaining = Self.visibleDuration
        notice.countdown.start(duration: Self.visibleDuration)
        resumeCountdown()
    }

    /// Hovering stops the clock where it is; leaving runs only the time that was left.
    private func pauseCountdown() {
        dismissTask?.cancel()
        dismissTask = nil
        if let countingSince {
            remaining = max(remaining - countingSince.duration(to: .now), .zero)
        }
        countingSince = nil
    }

    private func resumeCountdown() {
        guard countingSince == nil else { return }
        dismissTask?.cancel()
        countingSince = .now
        let delay = remaining
        dismissTask = Task { [weak self] in
            try? await Task.sleep(for: delay)
            guard Task.isCancelled == false else { return }
            self?.dismiss(animated: true)
        }
    }

    private func dismiss(animated: Bool) {
        dismissTask?.cancel()
        dismissTask = nil
        countingSince = nil
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
    static let horizontalPadding: CGFloat = 16
    static let verticalPadding: CGFloat = 14

    var onHoverChanged: (Bool) -> Void = { _ in }
    let countdown = CountdownBar()
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
            detailLabel.preferredMaxLayoutWidth = Self.textWidth
            detailLabel.widthAnchor.constraint(equalToConstant: Self.textWidth).isActive = true
            texts.append(detailLabel)
        }
        let textStack = NSStackView(views: texts)
        textStack.orientation = .vertical
        textStack.alignment = .leading
        textStack.spacing = 2
        textStack.translatesAutoresizingMaskIntoConstraints = false
        addSubview(textStack)

        countdown.translatesAutoresizingMaskIntoConstraints = false
        addSubview(countdown)

        var constraints = [
            textStack.leadingAnchor.constraint(equalTo: leadingAnchor, constant: Self.horizontalPadding),
            textStack.topAnchor.constraint(equalTo: topAnchor, constant: Self.verticalPadding),
            textStack.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -Self.verticalPadding),
            countdown.leadingAnchor.constraint(equalTo: leadingAnchor),
            countdown.trailingAnchor.constraint(equalTo: trailingAnchor),
            countdown.bottomAnchor.constraint(equalTo: bottomAnchor),
            countdown.heightAnchor.constraint(equalToConstant: CountdownBar.height),
        ]
        if let actionTitle {
            let button = NSButton(title: actionTitle, target: self, action: #selector(performAction))
            button.bezelStyle = .push
            button.controlSize = .small
            button.translatesAutoresizingMaskIntoConstraints = false
            addSubview(button)
            constraints += [
                button.leadingAnchor.constraint(equalTo: textStack.trailingAnchor, constant: 20),
                button.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -Self.horizontalPadding),
                button.centerYAnchor.constraint(equalTo: centerYAnchor),
            ]
        } else {
            constraints.append(textStack.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -Self.horizontalPadding))
        }
        NSLayoutConstraint.activate(constraints)
        setAccessibilityElement(true)
        setAccessibilityRole(.group)
        setAccessibilityLabel(title)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        trackingAreas.forEach(removeTrackingArea)
        addTrackingArea(NSTrackingArea(rect: bounds, options: [.mouseEnteredAndExited, .activeAlways], owner: self))
    }

    override func mouseEntered(with event: NSEvent) { onHoverChanged(true) }
    override func mouseExited(with event: NSEvent) { onHoverChanged(false) }

    @objc private func performAction() { onAction() }
}

/// A line along the bottom edge that empties as the notice's time runs out.
/// With Reduce Motion it steps down once a second instead of sliding.
private final class CountdownBar: NSView {
    static let height: CGFloat = 3

    private let fill = CALayer()

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        fill.anchorPoint = CGPoint(x: 0, y: 0.5)
        layer?.addSublayer(fill)
        setAccessibilityElement(false)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func layout() {
        super.layout()
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        fill.bounds = CGRect(origin: .zero, size: bounds.size)
        fill.position = CGPoint(x: 0, y: bounds.midY)
        CATransaction.commit()
    }

    override func updateLayer() {
        fill.backgroundColor = NSColor.controlAccentColor.withAlphaComponent(0.7).cgColor
    }

    override var wantsUpdateLayer: Bool { true }

    func start(duration: Duration) {
        reset()
        let seconds = Double(duration.components.seconds) + Double(duration.components.attoseconds) / 1e18
        let animation: CAAnimation
        if NSWorkspace.shared.accessibilityDisplayShouldReduceMotion {
            let steps = max(Int(seconds.rounded()), 1)
            let stepped = CAKeyframeAnimation(keyPath: "transform.scale.x")
            stepped.values = (0...steps).map { 1 - Double($0) / Double(steps) }
            stepped.calculationMode = .discrete
            animation = stepped
        } else {
            let smooth = CABasicAnimation(keyPath: "transform.scale.x")
            smooth.fromValue = 1
            smooth.toValue = 0
            smooth.timingFunction = CAMediaTimingFunction(name: .linear)
            animation = smooth
        }
        animation.duration = seconds
        animation.fillMode = .forwards
        animation.isRemovedOnCompletion = false
        fill.add(animation, forKey: "countdown")
    }

    func reset() {
        fill.removeAnimation(forKey: "countdown")
        fill.speed = 1
        fill.timeOffset = 0
        fill.beginTime = 0
    }

    func pause() {
        guard fill.speed != 0 else { return }
        let now = fill.convertTime(CACurrentMediaTime(), from: nil)
        fill.speed = 0
        fill.timeOffset = now
    }

    func resume() {
        guard fill.speed == 0 else { return }
        let pausedAt = fill.timeOffset
        fill.speed = 1
        fill.timeOffset = 0
        fill.beginTime = 0
        fill.beginTime = fill.convertTime(CACurrentMediaTime(), from: nil) - pausedAt
    }
}
