//
//  TerminalDoubleTapGestureUITests+iOS.swift
//  VVTermUITests
//
//  iOS terminal double-tap action gesture regression coverage.
//

import XCTest

final class TerminalDoubleTapGestureUITests: TerminalKeyboardUITestCase {
    /// The shipped default: a double-tap sends Tab and leaves no selection behind.
    @MainActor
    func testDoubleTapSendsTabByDefault() throws {
        let app = launchKeyboardHarness(seedsTerminalSelectionFixture: true)
        let terminal = waitForTerminal(in: app)
        let diagnostics = app.staticTexts["vvterm.keyboardTest.diagnostics"]

        wait(
            for: diagnostics,
            labelContaining: "doubleTapCount=0",
            timeout: 5,
            diagnostics: diagnosticsText(in: app)
        )

        terminal.doubleTap()

        wait(
            for: diagnostics,
            labelContaining: "doubleTapAction=tab",
            timeout: 5,
            diagnostics: diagnosticsText(in: app)
        )
        waitForDiagnosticMetrics(in: app) { metrics in
            metrics["doubleTapCount"] == 1
        }
        wait(
            for: diagnostics,
            labelContaining: "nativeSelectionLength=0",
            timeout: 5,
            diagnostics: diagnosticsText(in: app)
        )
    }

    /// The stored preference drives the gesture, not just the compiled-in default.
    @MainActor
    func testStoredBindingOverridesTheDefault() throws {
        let app = launchKeyboardHarness(
            seedsTerminalSelectionFixture: true,
            doubleTapAction: "escape"
        )
        let terminal = waitForTerminal(in: app)
        let diagnostics = app.staticTexts["vvterm.keyboardTest.diagnostics"]

        terminal.doubleTap()

        wait(
            for: diagnostics,
            labelContaining: "doubleTapAction=escape",
            timeout: 5,
            diagnostics: diagnosticsText(in: app)
        )
        waitForDiagnosticMetrics(in: app) { metrics in
            metrics["doubleTapCount"] == 1
        }
    }

    /// Turning the binding off restores the word selection the gesture used to do.
    @MainActor
    func testOffBindingRestoresWordSelection() throws {
        let app = launchKeyboardHarness(
            seedsTerminalSelectionFixture: true,
            doubleTapAction: "off"
        )
        let terminal = waitForTerminal(in: app)

        terminal.doubleTap()

        waitForDiagnosticMetrics(in: app) { metrics in
            (metrics["nativeSelectionLength"] ?? 0) > 0
        }
        XCTAssertTrue(
            diagnosticsText(in: app).contains("doubleTapCount=0"),
            diagnosticsText(in: app)
        )
    }

    /// Regression: the triple-tap paragraph selection must still beat the
    /// double-tap action through its failure requirement, so a paragraph
    /// selection never also sends a key.
    @MainActor
    func testTripleTapSelectsWithoutSendingTheAction() throws {
        let app = launchKeyboardHarness(seedsTerminalSelectionFixture: true)
        let terminal = waitForTerminal(in: app)

        terminal.tap(withNumberOfTaps: 3, numberOfTouches: 1)

        waitForDiagnosticMetrics(in: app) { metrics in
            (metrics["nativeSelectionLength"] ?? 0) > 0
        }
        XCTAssertTrue(
            diagnosticsText(in: app).contains("doubleTapCount=0"),
            diagnosticsText(in: app)
        )
    }
}
