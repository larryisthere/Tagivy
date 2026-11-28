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

/// Zoom works in whole columns, as in Photos: every step changes the number of thumbnails per row,
/// and the thumbnails take the width that fills the row exactly, so the grid never ends in a gap.
enum GridColumns {
    /// The most columns that fit with every thumbnail at least `minimumItemWidth` wide.
    static func maximumCount(availableWidth: Double, minimumItemWidth: Double, interitemSpacing: Double) -> Int {
        GridReflow.columnCount(availableWidth: availableWidth, itemWidth: minimumItemWidth, interitemSpacing: interitemSpacing)
    }

    /// The column count a thumbnail width gives, the way the flow layout fills a row.
    static func count(forItemWidth itemWidth: Double, availableWidth: Double, interitemSpacing: Double) -> Int {
        GridReflow.columnCount(availableWidth: availableWidth, itemWidth: itemWidth, interitemSpacing: interitemSpacing)
    }

    /// The thumbnail width at which `columns` thumbnails and the spacing between them fill the row.
    /// Rounded down to whole points so the flow layout never wraps the last one.
    static func itemWidth(columns: Int, availableWidth: Double, interitemSpacing: Double) -> Double {
        let columns = max(1, columns)
        let width = (availableWidth - Double(columns - 1) * interitemSpacing) / Double(columns)
        return max(1, width.rounded(.down))
    }

    static func clamped(_ columns: Int, maximum: Int) -> Int {
        min(max(1, maximum), max(1, columns))
    }

    /// Zoom In: one column fewer, so the thumbnails get larger.
    static func zoomedIn(from columns: Int, maximum: Int) -> Int {
        clamped(columns - 1, maximum: maximum)
    }

    /// Zoom Out: one column more, so the thumbnails get smaller.
    static func zoomedOut(from columns: Int, maximum: Int) -> Int {
        clamped(columns + 1, maximum: maximum)
    }

    /// The toolbar slider runs from the most columns (left, smallest thumbnails) to one column
    /// (right, largest). Its value is a position 1…maximum; this maps it to a column count, snapping
    /// to the nearest whole column.
    static func columns(forSliderValue value: Double, maximum: Int) -> Int {
        clamped(maximum + 1 - Int(value.rounded()), maximum: maximum)
    }

    static func sliderValue(forColumns columns: Int, maximum: Int) -> Double {
        Double(maximum + 1 - clamped(columns, maximum: maximum))
    }
}
