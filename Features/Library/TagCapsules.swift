import AppKit

/// How the inspector lays out tags. Both layouts use the same capsules and move them the same way.
enum InspectorTagLayout: String, CaseIterable {
    /// One capsule per row, in the selection's order.
    case list
    /// Capsules wrap across rows, grouped under their parent tag.
    case compact

    static let defaultsKey = "inspectorTagLayout"

    static func persisted(defaults: UserDefaults = .standard) -> InspectorTagLayout {
        defaults.string(forKey: defaultsKey).flatMap(InspectorTagLayout.init(rawValue:)) ?? .compact
    }

    func persist(defaults: UserDefaults = .standard) {
        defaults.set(rawValue, forKey: Self.defaultsKey)
    }
}

/// Places capsules left to right and wraps them, or one per row. Frames use top-left origin.
enum TagFlowLayout {
    static let spacing = CGSize(width: 6, height: 6)

    static func frames(for sizes: [CGSize], width: CGFloat, oneItemPerRow: Bool) -> [CGRect] {
        var frames: [CGRect] = []
        var x: CGFloat = 0
        var y: CGFloat = 0
        var rowHeight: CGFloat = 0
        for size in sizes {
            let itemWidth = min(size.width, max(0, width))
            let startsRow = frames.isEmpty == false && (oneItemPerRow || x + itemWidth > width)
            if startsRow {
                y += rowHeight + spacing.height
                x = 0
                rowHeight = 0
            }
            frames.append(CGRect(x: x, y: y, width: itemWidth, height: size.height))
            x += itemWidth + spacing.width
            rowHeight = max(rowHeight, size.height)
        }
        return frames
    }

    static func height(for sizes: [CGSize], width: CGFloat, oneItemPerRow: Bool) -> CGFloat {
        frames(for: sizes, width: width, oneItemPerRow: oneItemPerRow).map(\.maxY).max() ?? 0
    }
}

@MainActor
final class TagCapsuleFlowView: NSView {
    private var measuredWidth: CGFloat = 0
    private(set) var items: [NSView] = []
    let oneItemPerRow: Bool

    init(items: [NSView], oneItemPerRow: Bool) {
        self.oneItemPerRow = oneItemPerRow
        super.init(frame: .zero)
        translatesAutoresizingMaskIntoConstraints = false
        self.items = items
        for item in items {
            item.translatesAutoresizingMaskIntoConstraints = true
            addSubview(item)
        }
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override var isFlipped: Bool { true }

    // A frame-sized scroll document gives no width proposal, so the owner reports the width to wrap at.
    func updateMeasuredWidth(_ width: CGFloat) {
        guard measuredWidth != width else { return }
        measuredWidth = width
        invalidateIntrinsicContentSize()
        needsLayout = true
    }

    override var intrinsicContentSize: NSSize {
        NSSize(
            width: NSView.noIntrinsicMetric,
            height: TagFlowLayout.height(for: itemSizes, width: measuredWidth, oneItemPerRow: oneItemPerRow)
        )
    }

    override func layout() {
        super.layout()
        let width = measuredWidth > 0 ? measuredWidth : bounds.width
        let frames = TagFlowLayout.frames(for: itemSizes, width: width, oneItemPerRow: oneItemPerRow)
        for (item, frame) in zip(items, frames) where item.frame != frame {
            item.frame = frame
        }
    }

    private var itemSizes: [CGSize] {
        items.map { $0.intrinsicContentSize }
    }
}

/// A tag shown as a capsule: filled when every selected video has it, tinted when some do,
/// outlined when none do. Clicking toggles it.
@MainActor
final class TagCapsuleButton: NSButton {
    static let height: CGFloat = 22
    private static let horizontalPadding: CGFloat = 10
    private static let font = NSFont.systemFont(ofSize: 12)

    let tagRecord: TagRecord
    /// Moves keyboard focus to the previous (-1) or next (+1) capsule.
    var onMoveFocus: ((TagCapsuleButton, Int) -> Void)?

    init(tag: TagRecord, target: AnyObject?, action: Selector?) {
        tagRecord = tag
        super.init(frame: .zero)
        self.target = target
        self.action = action
        title = tag.name
        isBordered = false
        setButtonType(.pushOnPushOff)
        allowsMixedState = true
        toolTip = tag.name
        setAccessibilityRole(.checkBox)
        setAccessibilityLabel(tag.name)
        wantsLayer = true
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override var state: NSControl.StateValue {
        didSet { needsDisplay = true }
    }

    override var intrinsicContentSize: NSSize {
        let titleWidth = (tagRecord.name as NSString).size(withAttributes: [.font: Self.font]).width
        return NSSize(width: ceil(titleWidth) + 2 * Self.horizontalPadding, height: Self.height)
    }

    override var acceptsFirstResponder: Bool { true }

    override func draw(_ dirtyRect: NSRect) {
        let rect = bounds.insetBy(dx: 0.5, dy: 0.5)
        let path = NSBezierPath(roundedRect: rect, xRadius: rect.height / 2, yRadius: rect.height / 2)
        let accent = NSColor.controlAccentColor
        let fill: NSColor
        let stroke: NSColor
        let text: NSColor
        switch state {
        case .on:
            fill = accent
            stroke = accent
            text = .alternateSelectedControlTextColor
        case .mixed:
            fill = accent.withAlphaComponent(0.18)
            stroke = accent.withAlphaComponent(0.7)
            text = .labelColor
        default:
            fill = .clear
            stroke = .separatorColor
            text = .labelColor
        }
        fill.setFill()
        path.fill()
        stroke.setStroke()
        path.lineWidth = 1
        path.stroke()
        if isHighlighted {
            NSColor.labelColor.withAlphaComponent(0.08).setFill()
            path.fill()
        }

        let paragraph = NSMutableParagraphStyle()
        paragraph.lineBreakMode = .byTruncatingTail
        paragraph.alignment = .center
        let attributes: [NSAttributedString.Key: Any] = [
            .font: Self.font,
            .foregroundColor: text,
            .paragraphStyle: paragraph,
        ]
        let lineHeight = ceil(Self.font.ascender - Self.font.descender)
        let titleRect = NSRect(
            x: Self.horizontalPadding,
            y: floor((bounds.height - lineHeight) / 2),
            width: max(0, bounds.width - 2 * Self.horizontalPadding),
            height: lineHeight
        )
        (tagRecord.name as NSString).draw(
            with: titleRect,
            options: [.usesLineFragmentOrigin, .truncatesLastVisibleLine],
            attributes: attributes
        )
    }

    override func drawFocusRingMask() {
        NSBezierPath(roundedRect: bounds, xRadius: bounds.height / 2, yRadius: bounds.height / 2).fill()
    }

    override var focusRingMaskBounds: NSRect { bounds }

    override func keyDown(with event: NSEvent) {
        switch event.specialKey {
        case .leftArrow?, .upArrow?:
            onMoveFocus?(self, -1)
        case .rightArrow?, .downArrow?:
            onMoveFocus?(self, 1)
        default:
            super.keyDown(with: event)
        }
    }
}
