//
//  TerminalArrowRepeatGestureUITests+iOS.swift
//  VVTermUITests
//
//  iOS terminal arrow-repeat drag gesture regression coverage.
//

import XCTest

final class TerminalArrowRepeatGestureUITests: TerminalKeyboardUITestCase {
    /// A two-finger drag locks the horizontal axis and emits at least the immediate
    /// first key. The exact count is time-dependent, so assert the axis lock plus a
    /// non-zero count rather than an exact total.
    @MainActor
    func testTwoFingerDragLocksHorizontalAxisAndEmitsKeys() throws {
        // XCUICoordinate.press(forDuration:thenDragTo:withVelocity:thenHoldForDuration:)
        // only synthesizes a single-finger touch-drag-release sequence, so the two-finger
        // UIPanGestureRecognizer (arrowRepeatTouchRecognizer, minimumNumberOfTouches = 2)
        // never receives a second touch and never arms. This is a test-harness limitation,
        // not a defect in the gesture code: axis locking, direction, displacement, and
        // interval are already covered directly by the Task 6 unit tests in
        // TerminalArrowRepeatPolicyTests.swift. A possible future follow-up is a
        // harness-side simulation hook that drives the gesture handler with a synthetic
        // two-finger translation directly, bypassing XCUITest touch synthesis; that is not
        // implemented here.
        throw XCTSkip(
            "XCUITest cannot synthesize a genuine two-finger drag via " +
            "press(forDuration:thenDragTo:) — see comment above."
        )
    }

    /// Retained pending a future two-finger touch-synthesis hook (see the comment on
    /// `testTwoFingerDragLocksHorizontalAxisAndEmitsKeys`). Not currently called — kept so
    /// the assertions aren't lost, without triggering an unreachable-code warning at the
    /// `throw XCTSkip` call site above.
    @MainActor
    private func assertTwoFingerDragLocksHorizontalAxisAndEmitsKeys() throws {
        let app = launchKeyboardHarness()
        let terminal = waitForTerminal(in: app)
        let diagnostics = app.staticTexts["vvterm.keyboardTest.diagnostics"]

        wait(for: diagnostics, labelContaining: "arrowRepeatKeys=0", timeout: 5, diagnostics: diagnosticsText(in: app))

        let start = terminal.coordinate(withNormalizedOffset: CGVector(dx: 0.7, dy: 0.5))
        let end = terminal.coordinate(withNormalizedOffset: CGVector(dx: 0.2, dy: 0.5))
        start.press(forDuration: 0.05, thenDragTo: end, withVelocity: .default, thenHoldForDuration: 0.3)

        wait(for: diagnostics, labelContaining: "arrowRepeatAxis=horizontal", timeout: 5, diagnostics: diagnosticsText(in: app))
        XCTAssertFalse(
            diagnostics.label.contains("arrowRepeatKeys=0"),
            "Expected at least one arrow key. Diagnostics: \(diagnosticsText(in: app))"
        )
    }

    /// Regression: one finger held must still start native text selection, and must not
    /// arm the arrow repeat.
    @MainActor
    func testOneFingerHoldStillStartsSelection() throws {
        let app = launchKeyboardHarness()
        let terminal = waitForTerminal(in: app)
        let diagnostics = app.staticTexts["vvterm.keyboardTest.diagnostics"]

        terminal.press(forDuration: 0.6)

        wait(for: diagnostics, labelContaining: "nativeSelectionActive=true", timeout: 5, diagnostics: diagnosticsText(in: app))
        wait(for: diagnostics, labelContaining: "arrowRepeatKeys=0", timeout: 5, diagnostics: diagnosticsText(in: app))
        wait(for: diagnostics, labelContaining: "arrowRepeatAxis=none", timeout: 5, diagnostics: diagnosticsText(in: app))
    }

    /// Regression: an unmodified one-finger drag must stay with the scroll recognizer and
    /// emit no arrow keys.
    @MainActor
    func testOneFingerDragEmitsNoArrowKeys() throws {
        let app = launchKeyboardHarness()
        let terminal = waitForTerminal(in: app)
        let diagnostics = app.staticTexts["vvterm.keyboardTest.diagnostics"]

        terminal.swipeLeft()

        wait(for: diagnostics, labelContaining: "arrowRepeatKeys=0", timeout: 5, diagnostics: diagnosticsText(in: app))
        wait(for: diagnostics, labelContaining: "arrowRepeatAxis=none", timeout: 5, diagnostics: diagnosticsText(in: app))
        // Prove the drag actually reached the scroll recognizer rather than being
        // silently dropped by both recognizers (which would also read arrowRepeatKeys=0).
        XCTAssertFalse(
            diagnostics.label.contains("scrollEvents=0"),
            "Expected at least one scroll event. Diagnostics: \(diagnosticsText(in: app))"
        )
    }
}
