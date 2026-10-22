//
//  GhosttyTerminalArrowRepeatGesture+iOS.swift
//  VVTerm
//
//  iOS terminal arrow-repeat drag gesture.
//

import UIKit

extension GhosttyTerminalView {
    // MARK: - Gesture

    @objc func handleArrowRepeatGesture(_ recognizer: UIPanGestureRecognizer) {
        switch recognizer.state {
        case .began:
            // Momentum scrolling and arrow repeat both drive the surface; never both.
            stopMomentumScrolling()
            stopArrowRepeat()
            // Invalidate once up front rather than on every emitted key below, which
            // would otherwise tear down the IME/UITextView session up to 30x/second.
            invalidateLocalTextInputSession()
            arrowRepeatFeedback.prepare()
            beginTwoFingerArbitrationIfNeeded(for: recognizer)
        case .changed:
            guard arrowRepeatOwnsDrag(recognizer) else { return }
            updateArrowRepeat(translation: recognizer.translation(in: self))
        case .ended, .cancelled, .failed:
            stopArrowRepeat()
            endTwoFingerArbitration(for: recognizer)
        default:
            break
        }
    }

    // MARK: - Pinch Arbitration

    /// The two-finger drag shares its touches with `pinchRecognizer`, so both suppress
    /// their effect until the policy has told them apart.
    private func beginTwoFingerArbitrationIfNeeded(for recognizer: UIPanGestureRecognizer) {
        guard recognizer == arrowRepeatTouchRecognizer else { return }
        twoFingerDragOwner = .undecided
        twoFingerInitialSpread = touchSpread(in: recognizer)
    }

    private func endTwoFingerArbitration(for recognizer: UIPanGestureRecognizer) {
        guard recognizer == arrowRepeatTouchRecognizer else { return }
        twoFingerDragOwner = .inactive
        twoFingerInitialSpread = nil
    }

    /// Resolves the arbitration on first classifiable movement and answers whether the
    /// arrow drag may act. The Command + one-finger recognizer never contends with pinch,
    /// so it always owns its own drag.
    private func arrowRepeatOwnsDrag(_ recognizer: UIPanGestureRecognizer) -> Bool {
        guard recognizer == arrowRepeatTouchRecognizer else { return true }

        switch twoFingerDragOwner {
        case .arrowRepeat:
            return true
        case .inactive, .zoom:
            return false
        case .undecided:
            guard let initialSpread = twoFingerInitialSpread,
                  let currentSpread = touchSpread(in: recognizer) else {
                return false
            }
            twoFingerDragOwner = TerminalArrowRepeatPolicy.twoFingerOwner(
                centroidTranslation: recognizer.translation(in: self),
                initialSpread: initialSpread,
                currentSpread: currentSpread
            )
            return twoFingerDragOwner == .arrowRepeat
        }
    }

    /// Distance between the two touches, or nil when the recognizer is not tracking
    /// exactly two — a lifted finger leaves nothing to measure a spread against.
    private func touchSpread(in recognizer: UIPanGestureRecognizer) -> Double? {
        guard recognizer.numberOfTouches == 2 else { return nil }
        let first = recognizer.location(ofTouch: 0, in: self)
        let second = recognizer.location(ofTouch: 1, in: self)
        return Double(hypot(second.x - first.x, second.y - first.y))
    }

    /// Locks the axis on the first move past the dead zone, then only updates magnitude
    /// and sign. The axis never changes for the rest of the gesture.
    private func updateArrowRepeat(translation: CGPoint) {
        let axis: TerminalArrowRepeatAxis
        if let lockedAxis = arrowRepeatAxis {
            axis = lockedAxis
        } else {
            guard let newAxis = TerminalArrowRepeatPolicy.axis(forTranslation: translation) else {
                return
            }
            axis = newAxis
            arrowRepeatAxis = newAxis
            arrowRepeatUITestLastAxis = String(describing: newAxis)
            arrowRepeatFeedback.impactOccurred()
            // Fire once immediately so a small flick moves exactly one character.
            emitArrowRepeatKey(
                direction: TerminalArrowRepeatPolicy.direction(forTranslation: translation, axis: axis)
            )
            startArrowRepeatDisplayLink()
        }

        arrowRepeatDirection = TerminalArrowRepeatPolicy.direction(
            forTranslation: translation,
            axis: axis
        )
        arrowRepeatDisplacement = TerminalArrowRepeatPolicy.displacement(
            forTranslation: translation,
            axis: axis
        )
    }

    // MARK: - Repeat Driver

    private func startArrowRepeatDisplayLink() {
        guard arrowRepeatDisplayLink == nil else { return }
        let displayLink = CADisplayLink(target: self, selector: #selector(arrowRepeatTick(_:)))
        displayLink.add(to: .main, forMode: .common)
        arrowRepeatDisplayLink = displayLink
    }

    @objc private func arrowRepeatTick(_ displayLink: CADisplayLink) {
        guard let direction = arrowRepeatDirection,
              canRouteTerminalInput,
              !isPaused,
              !isShuttingDown else {
            stopArrowRepeat()
            return
        }

        arrowRepeatAccumulatedTime += displayLink.targetTimestamp - displayLink.timestamp
        let interval = TerminalArrowRepeatPolicy.interval(
            forDisplacement: arrowRepeatDisplacement
        )
        while arrowRepeatAccumulatedTime >= interval {
            arrowRepeatAccumulatedTime -= interval
            emitArrowRepeatKey(direction: direction)
        }
    }

    /// Emits with empty mods even while Command is physically held, and calls
    /// `sendToolbarGhosttyKey` directly rather than `sendToolbarKey`, because the latter
    /// routes `.super` into `performTerminalSplitShortcut`. Going through libghostty also
    /// means DECCKM application-cursor-key mode is encoded correctly without a branch here.
    private func emitArrowRepeatKey(direction: TerminalArrowRepeatDirection) {
        let key: Ghostty.Input.Key = switch direction {
        case .up: .arrowUp
        case .down: .arrowDown
        case .left: .arrowLeft
        case .right: .arrowRight
        }
        sendToolbarGhosttyKey(key, mods: [], invalidateLocalSession: false)
        arrowRepeatUITestKeyCount += 1
    }

    // MARK: - Teardown

    private func resetArrowRepeatState() {
        arrowRepeatAxis = nil
        arrowRepeatDirection = nil
        arrowRepeatDisplacement = 0
        arrowRepeatAccumulatedTime = 0
        // Every teardown path clears the arbitration too: a stale owner left behind by a
        // cancelled or torn-down gesture would keep suppressing pinch indefinitely.
        twoFingerDragOwner = .inactive
        twoFingerInitialSpread = nil
    }

    /// The view starts the display link, so the view owns cancelling it. Safe to call
    /// repeatedly and when no gesture is in flight.
    func stopArrowRepeat() {
        arrowRepeatDisplayLink?.invalidate()
        arrowRepeatDisplayLink = nil
        resetArrowRepeatState()
    }
}
