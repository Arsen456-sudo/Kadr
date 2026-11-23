import UIKit

/// One permanent parent for the floating/pinned picker; all other touches pass through.
final class ProfileIslandOverlay: UIView {
    override func point(inside point: CGPoint, with event: UIEvent?) -> Bool {
        subviews.contains { child in
            !child.isHidden && child.alpha > 0.01 && child.point(inside: child.convert(point, from: self), with: event)
        }
    }
}
