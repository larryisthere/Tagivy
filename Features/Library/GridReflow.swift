import Foundation

/// When a thumbnail size change moves items to other rows, they glide there instead of jumping.
/// Size changes that keep every item in its row apply at once, so dragging the slider never lags.
enum GridReflow {
    static let duration: TimeInterval = 0.22

    /// Matches how NSCollectionViewFlowLayout fills a row: as many items as fit with the spacing
    /// between them, and always at least one.
    static func columnCount(availableWidth: Double, itemWidth: Double, interitemSpacing: Double) -> Int {
        guard itemWidth > 0 else { return 1 }
        return max(1, Int(((availableWidth + interitemSpacing) / (itemWidth + interitemSpacing)).rounded(.down)))
    }

    /// How long the change to the new item width should take: zero applies it at once.
    /// A change during a glide follows it to the same finish, so the items turn toward
    /// the newest positions instead of starting a second glide or snapping.
    static func animationDuration(
        fromColumns: Int,
        toColumns: Int,
        remainingGlide: TimeInterval,
        reduceMotion: Bool
    ) -> TimeInterval {
        guard reduceMotion == false else { return 0 }
        if fromColumns != toColumns { return duration }
        return max(0, remainingGlide)
    }
}
