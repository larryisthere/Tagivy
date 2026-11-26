import AppKit
import QuartzCore

/// When a thumbnail size change moves items to other rows, they glide there instead of jumping.
/// Each item takes its new size at once and only its top-left corner travels, in a straight line,
/// so nothing grows from its center or fades. Size changes that keep every item in its row apply
/// at once, so dragging the slider never lags.
enum GridReflow {
    static let duration: CFTimeInterval = 0.22
    static let glideAnimationKey = "gridReflowGlide"

    /// Matches how NSCollectionViewFlowLayout fills a row: as many items as fit with the spacing
    /// between them, and always at least one.
    static func columnCount(availableWidth: Double, itemWidth: Double, interitemSpacing: Double) -> Int {
        guard itemWidth > 0 else { return 1 }
        return max(1, Int(((availableWidth + interitemSpacing) / (itemWidth + interitemSpacing)).rounded(.down)))
    }

    static func shouldGlide(fromColumns: Int, toColumns: Int, reduceMotion: Bool) -> Bool {
        reduceMotion == false && fromColumns != toColumns
    }

    /// Where the layer is drawn relative to its frame right now; non-zero only mid-glide.
    @MainActor
    static func currentOffset(of layer: CALayer) -> CGSize {
        guard layer.animation(forKey: glideAnimationKey) != nil,
              let translation = layer.presentation()?.value(forKeyPath: "transform.translation") as? NSValue
        else { return .zero }
        return translation.sizeValue
    }

    /// Draws the layer `offset` away from its frame, then glides it home. Replacing a running glide
    /// starts from where that glide had got to, so a second column change turns the item mid-way.
    @MainActor
    static func glide(_ layer: CALayer, from offset: CGSize) {
        guard abs(offset.width) >= 0.5 || abs(offset.height) >= 0.5 else {
            layer.removeAnimation(forKey: glideAnimationKey)
            return
        }
        let animation = CABasicAnimation(keyPath: "transform.translation")
        animation.fromValue = NSValue(size: offset)
        animation.toValue = NSValue(size: .zero)
        animation.duration = duration
        animation.timingFunction = CAMediaTimingFunction(name: .easeOut)
        layer.add(animation, forKey: glideAnimationKey)
    }
}
