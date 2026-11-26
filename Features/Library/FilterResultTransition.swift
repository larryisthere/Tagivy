import AppKit
import QuartzCore

/// When a filter change alters which videos the grid shows, thumbnails that stay glide to their new
/// places (top-left corner only, like `GridReflow`), ones that leave fade and shrink away, and ones
/// that arrive fade in just after. Changes too large to follow, or that replace most of what is on
/// screen, switch at once.
enum FilterResultTransition {
    /// Above this many on-screen thumbnails in any one role, the motion stops reading as a change.
    static let maxAnimatedItemsPerRole = 60
    /// When more than this share of the thumbnails on screen both leave and arrive, it is a new view.
    static let replacedShare = 2.0 / 3.0

    static let removalDuration: CFTimeInterval = 0.15
    static let removalScale: CGFloat = 0.9
    static let insertionDuration: CFTimeInterval = 0.16
    /// Lets the leaving thumbnails mostly clear before new ones show.
    static let insertionDelay: CFTimeInterval = 0.06
    static let longestImageWait: CFTimeInterval = 0.3
    static let reducedMotionCrossfadeDuration: CFTimeInterval = 0.15
    static let insertionAnimationKey = "filterResultInsertion"

    enum Style: Equatable {
        case instant
        case crossfade
        case animated
    }

    struct Plan: Equatable {
        /// On screen before and still in the result; glide from where they were.
        var staying: [String]
        /// On screen before and no longer in the result.
        var removed: [String]
        /// On screen now and not on screen before.
        var inserted: [String]
    }

    /// Decided before the grid reloads, from what is on screen and the new result.
    static func style(
        isFilterChange: Bool,
        reduceMotion: Bool,
        oldVisibleIDs: [String],
        newIDs: Set<String>
    ) -> Style {
        guard isFilterChange, oldVisibleIDs.isEmpty == false || newIDs.isEmpty == false else { return .instant }
        if reduceMotion { return .crossfade }
        let staying = oldVisibleIDs.filter(newIDs.contains).count
        let removed = oldVisibleIDs.count - staying
        return staying > maxAnimatedItemsPerRole || removed > maxAnimatedItemsPerRole ? .instant : .animated
    }

    /// Decided after the grid reloads, once the new on-screen thumbnails are known.
    /// Returns nil when the change should land without motion.
    static func plan(oldVisibleIDs: [String], newVisibleIDs: [String], newIDs: Set<String>) -> Plan? {
        let oldVisible = Set(oldVisibleIDs)
        let plan = Plan(
            staying: oldVisibleIDs.filter(newIDs.contains),
            removed: oldVisibleIDs.filter { newIDs.contains($0) == false },
            inserted: newVisibleIDs.filter { oldVisible.contains($0) == false }
        )
        let tooMany = [plan.staying.count, plan.removed.count, plan.inserted.count]
            .contains { $0 > maxAnimatedItemsPerRole }
        let mostlyReplaced = oldVisibleIDs.isEmpty == false && newVisibleIDs.isEmpty == false
            && Double(plan.removed.count) > replacedShare * Double(oldVisibleIDs.count)
            && Double(plan.inserted.count) > replacedShare * Double(newVisibleIDs.count)
        return tooMany || mostlyReplaced ? nil : plan
    }

    /// Before the grid reloads, where in the new display order the screen is expected to land: the
    /// scroll offset stays, so roughly the same positions as before (or the top, when it resets).
    static func expectedOnScreenRange(firstOldIndex: Int, onScreenCount: Int, newCount: Int) -> Range<Int> {
        let start = min(max(0, firstOldIndex), newCount)
        return start..<min(newCount, start + onScreenCount)
    }

    /// Thumbnails whose views will show other videos after the reload, so they need a snapshot:
    /// the ones leaving the result, and staying ones expected to land off screen or within `margin`
    /// positions (about a row) of its edges.
    static func idsExpectedToLeaveScreen(
        oldVisibleIDs: [String],
        newIndices: [String: Int],
        expectedOnScreen: Range<Int>,
        margin: Int
    ) -> [String] {
        // At the very top nothing can sit above the screen.
        let lower = expectedOnScreen.lowerBound == 0 ? 0 : expectedOnScreen.lowerBound + margin
        let safelyOnScreen = lower..<max(lower, expectedOnScreen.upperBound - margin)
        return oldVisibleIDs.filter { id in
            guard let index = newIndices[id] else { return true }
            return safelyOnScreen.contains(index) == false
        }
    }

    /// Fades and shrinks a snapshot of a thumbnail that left the result, then drops it.
    @MainActor
    static func fadeOut(_ snapshot: CALayer) {
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        CATransaction.setCompletionBlock { snapshot.removeFromSuperlayer() }
        let fade = CABasicAnimation(keyPath: "opacity")
        fade.fromValue = 1
        fade.toValue = 0
        let shrink = CABasicAnimation(keyPath: "transform.scale")
        shrink.fromValue = 1
        shrink.toValue = removalScale
        let group = CAAnimationGroup()
        group.animations = [fade, shrink]
        group.duration = removalDuration
        group.timingFunction = CAMediaTimingFunction(name: .easeIn)
        snapshot.opacity = 0
        snapshot.add(group, forKey: "filterResultRemoval")
        CATransaction.commit()
    }

    /// Fades in a thumbnail that joined the result, from fully hidden on the first frame.
    @MainActor
    static func fadeIn(_ layer: CALayer, after delay: CFTimeInterval = insertionDelay) {
        let fade = CABasicAnimation(keyPath: "opacity")
        fade.fromValue = 0
        fade.toValue = 1
        fade.beginTime = CACurrentMediaTime() + delay
        fade.duration = insertionDuration
        fade.fillMode = .backwards
        fade.timingFunction = CAMediaTimingFunction(name: .easeOut)
        layer.add(fade, forKey: insertionAnimationKey)
    }

    /// Keeps a new thumbnail hidden until its image is ready, so it appears in one fade with the
    /// image instead of fading in as a placeholder and then again as the image. If the image takes
    /// longer than `longestImageWait`, it fades in anyway.
    @MainActor
    static func fadeInAwaitingImage(_ layer: CALayer) {
        let hold = CAKeyframeAnimation(keyPath: "opacity")
        let total = longestImageWait + insertionDuration
        hold.values = [0, 0, 1]
        hold.keyTimes = [0, NSNumber(value: longestImageWait / total), 1]
        hold.duration = total
        hold.timingFunctions = [CAMediaTimingFunction(name: .linear), CAMediaTimingFunction(name: .easeOut)]
        layer.add(hold, forKey: insertionAnimationKey)
    }

    /// An image of the layer as drawn now, for a thumbnail whose view is about to be reused.
    @MainActor
    static func snapshot(of layer: CALayer, scale: CGFloat) -> CGImage? {
        let size = layer.bounds.size
        let width = Int((size.width * scale).rounded(.up))
        let height = Int((size.height * scale).rounded(.up))
        guard width > 0, height > 0,
              let context = CGContext(
                  data: nil,
                  width: width,
                  height: height,
                  bitsPerComponent: 8,
                  bytesPerRow: 0,
                  space: CGColorSpace(name: CGColorSpace.sRGB) ?? CGColorSpaceCreateDeviceRGB(),
                  bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
              )
        else { return nil }
        context.scaleBy(x: scale, y: scale)
        layer.render(in: context)
        return context.makeImage()
    }
}

/// Tells a result that answers a filter change apart from a refresh of the same filter (an import,
/// a tag edit) that happens to arrive first or later. Each filter change gets a new generation, the
/// library echoes the generation its result was fetched under, and only the first result shown for
/// the latest generation counts as the filter change.
struct FilterQueryGenerations {
    private(set) var latest = 0
    private var shown = 0

    mutating func next() -> Int {
        latest += 1
        return latest
    }

    mutating func resultIsFilterChange(generation: Int) -> Bool {
        defer { shown = max(shown, generation) }
        return generation == latest && generation > shown
    }
}

/// Holds snapshots of thumbnails on their way out, above the grid and clipped to it.
final class FilterResultOverlayView: NSView {
    override var isFlipped: Bool { true }

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        layer?.masksToBounds = true
        autoresizingMask = [.width, .height]
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func hitTest(_ point: NSPoint) -> NSView? { nil }

    func removeSnapshots() {
        layer?.sublayers?.forEach { $0.removeFromSuperlayer() }
    }
}
