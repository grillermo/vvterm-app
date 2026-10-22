import CoreGraphics
import Foundation
import Testing
import UIKit
@testable import VVTerm

/// Arming coverage for the two arrow-repeat drag recognizers.
///
/// UIKit exposes no accessor for a recognizer's `require(toFail:)` dependencies, and
/// synthesizing a genuine two-finger drag needs private touch-event API, so the
/// recognition race itself stays manual validation. What is deterministic here is the
/// arming decision the view makes before that race: whether the recognizer is installed
/// and whether `gestureRecognizerShouldBegin` lets a plain two-finger drag through.
@Suite(.serialized)
@MainActor
struct GhosttyTerminalArrowRepeatGestureTests {
    @Test
    func twoFingerDragArmsArrowRepeatAndYieldsToCompetingInteractions() throws {
        let app = GhosttyRuntime()
        defer { app.cleanup() }
        let appHandle = try #require(app.app)
        let terminal = GhosttyTerminalView(
            frame: CGRect(x: 0, y: 0, width: 800, height: 600),
            worktreePath: FileManager.default.currentDirectoryPath,
            ghosttyApp: appHandle,
            appWrapper: app,
            paneId: "arrow-repeat-arming",
            terminalAccessoryInputSnapshot: TerminalAccessoryInputSnapshot(profile: .defaultValue(lastWriterDeviceId: "arrow-repeat-arming-test")),
            useCustomIO: true
        )
        defer { terminal.cleanup() }

        let presenter = UIViewController()
        let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 800, height: 600))
        window.rootViewController = presenter
        window.makeKeyAndVisible()
        defer { window.isHidden = true }
        presenter.view.addSubview(terminal)
        terminal.acceptsTerminalInput = true

        #expect(terminal.arrowRepeatTouchRecognizer.view === terminal)
        #expect(terminal.arrowRepeatModifierRecognizer.view === terminal)
        #expect(terminal.arrowRepeatTouchRecognizer.minimumNumberOfTouches == 2)
        #expect(terminal.arrowRepeatModifierRecognizer.maximumNumberOfTouches == 1)

        // Regression: a two-finger drag with no hardware modifier must arm. This returned
        // true even while the gesture was dead in the field, so it is the floor, not the
        // proof — the recognition race against pinch is validated manually.
        #expect(terminal.gestureRecognizerShouldBegin(terminal.arrowRepeatTouchRecognizer))

        // A bare one-finger drag belongs to scrolling, not arrow-repeat: with no Command
        // held, the single-touch recognizer must refuse.
        #expect(!terminal.gestureRecognizerShouldBegin(terminal.arrowRepeatModifierRecognizer))

        // An in-flight pinch must NOT hold the two-finger recognizer back: arming is what
        // starts the arbitration that decides between the two. Only the one-finger
        // recognizer, which never contends with pinch, stays out of its way.
        terminal.isPinchingTerminalZoom = true
        #expect(terminal.gestureRecognizerShouldBegin(terminal.arrowRepeatTouchRecognizer))
        #expect(!terminal.gestureRecognizerShouldBegin(terminal.arrowRepeatModifierRecognizer))
        terminal.isPinchingTerminalZoom = false

        terminal.isPaused = true
        #expect(!terminal.gestureRecognizerShouldBegin(terminal.arrowRepeatTouchRecognizer))
        terminal.isPaused = false

        terminal.nativeSelectionLifecycle.prepare(restoreTerminalInput: true)
        terminal.nativeSelectionLifecycle.beginInteraction(restoreTerminalInput: true)
        #expect(terminal.hasActiveSelectionInteraction)
        #expect(!terminal.gestureRecognizerShouldBegin(terminal.arrowRepeatTouchRecognizer))
        terminal.nativeSelectionLifecycle.cancel()

        #expect(terminal.gestureRecognizerShouldBegin(terminal.arrowRepeatTouchRecognizer))
    }

    /// Pinch and the two-finger arrow drag must recognize together, because the policy —
    /// not the recognition race — decides between them. Every other pairing stays
    /// exclusive.
    @Test
    func arrowRepeatRecognizesAlongsidePinchOnly() throws {
        let app = GhosttyRuntime()
        defer { app.cleanup() }
        let appHandle = try #require(app.app)
        let terminal = GhosttyTerminalView(
            frame: CGRect(x: 0, y: 0, width: 800, height: 600),
            worktreePath: FileManager.default.currentDirectoryPath,
            ghosttyApp: appHandle,
            appWrapper: app,
            paneId: "arrow-repeat-exclusion",
            terminalAccessoryInputSnapshot: TerminalAccessoryInputSnapshot(profile: .defaultValue(lastWriterDeviceId: "arrow-repeat-exclusion-test")),
            useCustomIO: true
        )
        defer { terminal.cleanup() }

        #expect(
            terminal.gestureRecognizer(
                terminal.arrowRepeatTouchRecognizer,
                shouldRecognizeSimultaneouslyWith: terminal.pinchRecognizer
            )
        )
        #expect(
            terminal.gestureRecognizer(
                terminal.pinchRecognizer,
                shouldRecognizeSimultaneouslyWith: terminal.arrowRepeatTouchRecognizer
            )
        )
        #expect(
            !terminal.gestureRecognizer(
                terminal.arrowRepeatModifierRecognizer,
                shouldRecognizeSimultaneouslyWith: terminal.pinchRecognizer
            )
        )
        #expect(
            !terminal.gestureRecognizer(
                terminal.arrowRepeatModifierRecognizer,
                shouldRecognizeSimultaneouslyWith: terminal.scrollRecognizer
            )
        )
        #expect(
            !terminal.gestureRecognizer(
                terminal.arrowRepeatTouchRecognizer,
                shouldRecognizeSimultaneouslyWith: terminal.scrollRecognizer
            )
        )
    }

    /// The arbitration gates the zoom side too, so one pair of touches never both zooms
    /// and sends keys — and a resolved or torn-down gesture always hands pinch back.
    @Test
    func pinchZoomIsSuppressedOnlyWhileTheArrowDragOwnsTheTouches() throws {
        let app = GhosttyRuntime()
        defer { app.cleanup() }
        let appHandle = try #require(app.app)
        let terminal = GhosttyTerminalView(
            frame: CGRect(x: 0, y: 0, width: 800, height: 600),
            worktreePath: FileManager.default.currentDirectoryPath,
            ghosttyApp: appHandle,
            appWrapper: app,
            paneId: "arrow-repeat-zoom-arbitration",
            terminalAccessoryInputSnapshot: TerminalAccessoryInputSnapshot(profile: .defaultValue(lastWriterDeviceId: "arrow-repeat-zoom-test")),
            useCustomIO: true
        )
        defer { terminal.cleanup() }

        #expect(terminal.twoFingerDragOwner == .inactive)
        #expect(terminal.canHandlePinchZoom)

        terminal.twoFingerDragOwner = .undecided
        #expect(!terminal.canHandlePinchZoom)
        // Touch delivery must survive the wait, or pinch loses the whole gesture.
        #expect(terminal.canReceivePinchTouch)

        terminal.twoFingerDragOwner = .arrowRepeat
        #expect(!terminal.canHandlePinchZoom)
        #expect(terminal.canReceivePinchTouch)

        terminal.twoFingerDragOwner = .zoom
        #expect(terminal.canHandlePinchZoom)

        // Teardown must hand pinch back; a stale owner would suppress zoom for good.
        terminal.twoFingerDragOwner = .arrowRepeat
        terminal.stopArrowRepeat()
        #expect(terminal.twoFingerDragOwner == .inactive)
        #expect(terminal.canHandlePinchZoom)
    }
}
