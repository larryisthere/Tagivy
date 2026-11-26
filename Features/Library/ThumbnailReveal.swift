import AppKit
import QuartzCore

/// How a thumbnail replaces what was on screen before it: a placeholder, or an older image.
/// An image that is ready by the time the view is drawn appears at once. One that keeps the
/// viewer waiting fades in, so the late arrival reads as loading finishing, not as a flicker.
enum ThumbnailReveal: Equatable {
    case immediate
    case fade

    static let fadeDuration: CFTimeInterval = 0.2
    /// Roughly three frames: an image within this wait was never seen missing.
    static let longestUnnoticedWait: TimeInterval = 0.05

    static func after(waiting seconds: TimeInterval) -> ThumbnailReveal {
        seconds < longestUnnoticedWait ? .immediate : .fade
    }

    /// Call before changing what the layer shows; the change then fades in when it should.
    @MainActor
    func prepare(_ layer: CALayer?) {
        guard let layer else { return }
        layer.removeAnimation(forKey: kCATransition)
        guard self == .fade else { return }
        let transition = CATransition()
        transition.type = .fade
        transition.duration = Self.fadeDuration
        transition.timingFunction = CAMediaTimingFunction(name: .easeOut)
        // Core Animation files every transition under kCATransition, whatever key it is given.
        layer.add(transition, forKey: kCATransition)
    }
}

/// Measures how long a view has been waiting for its thumbnail.
struct ThumbnailWait {
    private let start = ProcessInfo.processInfo.systemUptime

    var reveal: ThumbnailReveal {
        .after(waiting: ProcessInfo.processInfo.systemUptime - start)
    }
}
