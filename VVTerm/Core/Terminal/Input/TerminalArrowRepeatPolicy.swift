import CoreGraphics
import Foundation

/// The axis a drag is locked to for its whole lifetime. Locking on first move keeps a
/// vertical wobble during a horizontal drag from firing Up-arrow, which in a shell
/// recalls history and replaces the line being edited.
nonisolated enum TerminalArrowRepeatAxis: Equatable, Sendable {
    case horizontal
    case vertical
}

nonisolated enum TerminalArrowRepeatDirection: Equatable, Sendable {
    case up
    case down
    case left
    case right
}

nonisolated enum TerminalArrowRepeatDragOwner: Equatable, Sendable {
    case none
    case scroll
    case arrowRepeat
}

/// Which effect a two-finger drag has been resolved to. Two fingers can mean either an
/// arrow drag or a font-size pinch, and the two recognizers share the same touches, so
/// neither may lock the other out of recognizing; this is decided from the movement
/// instead, and the loser stays locked out for the rest of the gesture.
nonisolated enum TerminalTwoFingerDragOwner: Equatable, Sendable {
    /// No two-finger arrow drag is in flight, so pinch owns the touches outright.
    case inactive
    /// In flight, but not yet moved far enough to tell the two apart. Both effects stay
    /// suppressed until it has, so an ambiguous start cannot both zoom and send keys.
    case undecided
    case arrowRepeat
    case zoom
}

nonisolated enum TerminalArrowRepeatPolicy {
    /// Travel required before the gesture emits anything, in points.
    static let deadZone: Double = 12

    /// Returns the axis to lock to, or nil while the drag is still inside the dead zone.
    /// An exact diagonal tie resolves to horizontal.
    static func axis(forTranslation translation: CGPoint) -> TerminalArrowRepeatAxis? {
        let horizontal = abs(Double(translation.x))
        let vertical = abs(Double(translation.y))
        guard max(horizontal, vertical) >= deadZone else { return nil }
        return vertical > horizontal ? .vertical : .horizontal
    }

    static let tierOneUpperBound: Double = 40
    static let tierTwoUpperBound: Double = 80

    /// 6 keys/s, 14 keys/s, 30 keys/s. Discrete tiers rather than a smooth curve: they
    /// give a learnable "gear" feel and make the tests exact rather than tolerance-based.
    static let tierOneInterval: TimeInterval = 1.0 / 6.0
    static let tierTwoInterval: TimeInterval = 1.0 / 14.0
    static let tierThreeInterval: TimeInterval = 1.0 / 30.0

    /// Absolute travel along the locked axis. Deliberately not euclidean distance, so
    /// perpendicular drift cannot accelerate the repeat.
    static func displacement(
        forTranslation translation: CGPoint,
        axis: TerminalArrowRepeatAxis
    ) -> Double {
        switch axis {
        case .horizontal:
            abs(Double(translation.x))
        case .vertical:
            abs(Double(translation.y))
        }
    }

    /// Only meaningful once an axis is locked; the dead zone is gated by `axis(forTranslation:)`.
    static func interval(forDisplacement displacement: Double) -> TimeInterval {
        if displacement < tierOneUpperBound {
            return tierOneInterval
        }
        if displacement < tierTwoUpperBound {
            return tierTwoInterval
        }
        return tierThreeInterval
    }

    static func direction(
        forTranslation translation: CGPoint,
        axis: TerminalArrowRepeatAxis
    ) -> TerminalArrowRepeatDirection {
        switch axis {
        case .horizontal:
            Double(translation.x) < 0 ? .left : .right
        case .vertical:
            // UIKit y grows downward.
            Double(translation.y) < 0 ? .up : .down
        }
    }

    /// Separates a two-finger arrow drag from a font-size pinch.
    ///
    /// Parallel travel moves the centroid while the spread between the fingers holds.
    /// A pinch does the opposite, and does it by a wide margin even one-handed: with one
    /// finger anchored and the other moving by `d`, the centroid shifts `d / 2` while the
    /// spread changes by the full `d`. Plain dominance therefore separates the two
    /// without a tuned margin, and the same `deadZone` that gates arrow emission gates
    /// the decision, so nothing acts on a movement too small to classify.
    ///
    /// An exact tie resolves to zoom: pinch is the older, more familiar gesture, so it
    /// keeps the benefit of the doubt.
    static func twoFingerOwner(
        centroidTranslation: CGPoint,
        initialSpread: Double,
        currentSpread: Double
    ) -> TerminalTwoFingerDragOwner {
        let travel = max(
            abs(Double(centroidTranslation.x)),
            abs(Double(centroidTranslation.y))
        )
        let spreadChange = abs(currentSpread - initialSpread)
        guard max(travel, spreadChange) >= deadZone else { return .undecided }
        return travel > spreadChange ? .arrowRepeat : .zoom
    }

    /// Single source of truth for the scroll/arrow-repeat exclusion. Both
    /// `gestureRecognizerShouldBegin` branches read this so they cannot disagree.
    static func owner(commandHeld: Bool, touchCount: Int) -> TerminalArrowRepeatDragOwner {
        guard touchCount > 0 else { return .none }
        if touchCount > 1 { return .arrowRepeat }
        return commandHeld ? .arrowRepeat : .scroll
    }
}
