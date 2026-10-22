import CoreGraphics
import Testing
@testable import VVTerm

struct TerminalArrowRepeatPolicyTests {
    @Test
    func returnsNoAxisInsideDeadZone() {
        #expect(TerminalArrowRepeatPolicy.axis(forTranslation: .zero) == nil)
        #expect(TerminalArrowRepeatPolicy.axis(forTranslation: CGPoint(x: 11.9, y: 0)) == nil)
        #expect(TerminalArrowRepeatPolicy.axis(forTranslation: CGPoint(x: 0, y: -11.9)) == nil)
    }

    @Test
    func locksHorizontalAxisAtDeadZoneBoundary() {
        #expect(TerminalArrowRepeatPolicy.axis(forTranslation: CGPoint(x: 12, y: 0)) == .horizontal)
        #expect(TerminalArrowRepeatPolicy.axis(forTranslation: CGPoint(x: -12, y: 0)) == .horizontal)
    }

    @Test
    func locksVerticalAxisWhenVerticalDominates() {
        #expect(TerminalArrowRepeatPolicy.axis(forTranslation: CGPoint(x: 5, y: 40)) == .vertical)
        #expect(TerminalArrowRepeatPolicy.axis(forTranslation: CGPoint(x: -5, y: -40)) == .vertical)
    }

    @Test
    func resolvesExactDiagonalTieToHorizontal() {
        // Horizontal is the non-destructive direction: a stray Up-arrow recalls
        // shell history and replaces the line being edited.
        #expect(TerminalArrowRepeatPolicy.axis(forTranslation: CGPoint(x: 30, y: 30)) == .horizontal)
        #expect(TerminalArrowRepeatPolicy.axis(forTranslation: CGPoint(x: -30, y: 30)) == .horizontal)
    }

    @Test
    func measuresDisplacementAlongLockedAxisOnly() {
        let translation = CGPoint(x: 30, y: 90)
        // Perpendicular drift must never accelerate the repeat.
        #expect(
            TerminalArrowRepeatPolicy.displacement(forTranslation: translation, axis: .horizontal) == 30
        )
        #expect(
            TerminalArrowRepeatPolicy.displacement(forTranslation: translation, axis: .vertical) == 90
        )
    }

    @Test
    func measuresDisplacementAsAbsoluteValue() {
        let translation = CGPoint(x: -45, y: -70)
        #expect(
            TerminalArrowRepeatPolicy.displacement(forTranslation: translation, axis: .horizontal) == 45
        )
        #expect(
            TerminalArrowRepeatPolicy.displacement(forTranslation: translation, axis: .vertical) == 70
        )
    }

    @Test
    func mapsDisplacementToTierIntervals() {
        #expect(TerminalArrowRepeatPolicy.interval(forDisplacement: 12) == 1.0 / 6.0)
        #expect(TerminalArrowRepeatPolicy.interval(forDisplacement: 39.9) == 1.0 / 6.0)
        #expect(TerminalArrowRepeatPolicy.interval(forDisplacement: 40) == 1.0 / 14.0)
        #expect(TerminalArrowRepeatPolicy.interval(forDisplacement: 79.9) == 1.0 / 14.0)
        #expect(TerminalArrowRepeatPolicy.interval(forDisplacement: 80) == 1.0 / 30.0)
        #expect(TerminalArrowRepeatPolicy.interval(forDisplacement: 5_000) == 1.0 / 30.0)
    }

    @Test
    func clampsNegativeAndZeroDisplacementToSlowestTier() {
        #expect(TerminalArrowRepeatPolicy.interval(forDisplacement: 0) == 1.0 / 6.0)
        #expect(TerminalArrowRepeatPolicy.interval(forDisplacement: -100) == 1.0 / 6.0)
    }

    @Test
    func resolvesHorizontalDirectionFromSign() {
        #expect(
            TerminalArrowRepeatPolicy.direction(
                forTranslation: CGPoint(x: -50, y: 0), axis: .horizontal
            ) == .left
        )
        #expect(
            TerminalArrowRepeatPolicy.direction(
                forTranslation: CGPoint(x: 50, y: 0), axis: .horizontal
            ) == .right
        )
    }

    @Test
    func resolvesVerticalDirectionUsingUIKitOrientation() {
        // UIKit y grows downward, so a positive y translation is a downward drag.
        #expect(
            TerminalArrowRepeatPolicy.direction(
                forTranslation: CGPoint(x: 0, y: -50), axis: .vertical
            ) == .up
        )
        #expect(
            TerminalArrowRepeatPolicy.direction(
                forTranslation: CGPoint(x: 0, y: 50), axis: .vertical
            ) == .down
        )
    }

    @Test
    func givesUnmodifiedSingleFingerDragToScroll() {
        #expect(
            TerminalArrowRepeatPolicy.owner(commandHeld: false, touchCount: 1) == .scroll
        )
    }

    @Test
    func givesCommandSingleFingerDragToArrowRepeat() {
        #expect(
            TerminalArrowRepeatPolicy.owner(commandHeld: true, touchCount: 1) == .arrowRepeat
        )
    }

    @Test
    func givesTwoFingerDragToArrowRepeatRegardlessOfCommand() {
        #expect(
            TerminalArrowRepeatPolicy.owner(commandHeld: false, touchCount: 2) == .arrowRepeat
        )
        #expect(
            TerminalArrowRepeatPolicy.owner(commandHeld: true, touchCount: 2) == .arrowRepeat
        )
        #expect(
            TerminalArrowRepeatPolicy.owner(commandHeld: false, touchCount: 3) == .arrowRepeat
        )
    }

    @Test
    func givesNoOwnerWhenNoTouchesAreDown() {
        #expect(TerminalArrowRepeatPolicy.owner(commandHeld: true, touchCount: 0) == .none)
        #expect(TerminalArrowRepeatPolicy.owner(commandHeld: false, touchCount: 0) == .none)
    }

    // MARK: - Two-Finger Arbitration

    @Test
    func leavesTwoFingerDragUndecidedInsideDeadZone() {
        #expect(
            TerminalArrowRepeatPolicy.twoFingerOwner(
                centroidTranslation: CGPoint(x: 11.9, y: 0),
                initialSpread: 200,
                currentSpread: 205
            ) == .undecided
        )
        #expect(
            TerminalArrowRepeatPolicy.twoFingerOwner(
                centroidTranslation: .zero,
                initialSpread: 200,
                currentSpread: 200
            ) == .undecided
        )
    }

    @Test
    func givesParallelTwoFingerTravelToArrowRepeat() {
        // Both fingers travel together, so the spread holds while the centroid moves.
        #expect(
            TerminalArrowRepeatPolicy.twoFingerOwner(
                centroidTranslation: CGPoint(x: -60, y: 2),
                initialSpread: 180,
                currentSpread: 183
            ) == .arrowRepeat
        )
    }

    @Test
    func givesSpreadingFingersToZoom() {
        #expect(
            TerminalArrowRepeatPolicy.twoFingerOwner(
                centroidTranslation: CGPoint(x: 3, y: 1),
                initialSpread: 120,
                currentSpread: 190
            ) == .zoom
        )
        #expect(
            TerminalArrowRepeatPolicy.twoFingerOwner(
                centroidTranslation: CGPoint(x: 0, y: -4),
                initialSpread: 190,
                currentSpread: 120
            ) == .zoom
        )
    }

    @Test
    func givesOneHandedPinchToZoomDespiteMovingCentroid() {
        // One finger anchored, the other travelling 40pt: the centroid shifts half that
        // while the spread changes by the full amount, so dominance still picks zoom.
        // This is the case that used to be protected by a recognizer failure requirement,
        // which cost the arrow drag its whole gesture.
        #expect(
            TerminalArrowRepeatPolicy.twoFingerOwner(
                centroidTranslation: CGPoint(x: 20, y: 0),
                initialSpread: 100,
                currentSpread: 140
            ) == .zoom
        )
    }

    @Test
    func resolvesExactTwoFingerTieToZoom() {
        // Pinch is the older, more familiar gesture, so it keeps the benefit of the doubt.
        #expect(
            TerminalArrowRepeatPolicy.twoFingerOwner(
                centroidTranslation: CGPoint(x: 30, y: 0),
                initialSpread: 100,
                currentSpread: 130
            ) == .zoom
        )
    }
}
