import XCTest

final class TerminalHardwareKeyboardUITests: TerminalKeyboardUITestCase {
    @MainActor
    func testTouchingTerminalRequestsPaneFocus() throws {
        let app = launchKeyboardHarness(simulatesKeyboardFrames: true)
        let terminal = waitForTerminal(in: app)
        let diagnostics = app.staticTexts["vvterm.keyboardTest.diagnostics"]

        wait(for: diagnostics, labelContaining: "paneFocusActions=0", timeout: 5, diagnostics: diagnosticsText(in: app))
        // The harness focuses the terminal at launch, so the keyboard and the
        // 192pt accessory may already have shrunk it to ~374pt, putting its
        // center under the harness button overlay (to ~230pt). 300pt from the
        // top stays on terminal content whether or not the keyboard is up.
        terminal.coordinate(withNormalizedOffset: .zero)
            .withOffset(CGVector(dx: terminal.frame.width / 2, dy: 300))
            .tap()
        wait(for: diagnostics, labelContaining: "paneFocusActions=1", timeout: 5, diagnostics: diagnosticsText(in: app))
    }

    @MainActor
    func testExplicitKeyboardCommandMaintainsForcedPolicyWhileHardwareRemainsAttached() throws {
        let app = launchKeyboardHarness(simulatesKeyboardFrames: true)
        let terminal = waitForTerminal(in: app)
        let diagnostics = app.staticTexts["vvterm.keyboardTest.diagnostics"]

        wait(for: diagnostics, labelContaining: "softwareInputActive=true", timeout: 5, diagnostics: diagnosticsText(in: app))
        app.buttons["vvterm.keyboardTest.hardware.attach"].tap()
        wait(for: diagnostics, labelContaining: "hardware=true", timeout: 5, diagnostics: diagnosticsText(in: app))
        wait(for: diagnostics, labelContaining: "softwareInputActive=true", timeout: 5, diagnostics: diagnosticsText(in: app))
        wait(for: diagnostics, labelContaining: "keyboardForced=false", timeout: 5, diagnostics: diagnosticsText(in: app))
        wait(for: diagnostics, labelContaining: "softwareKeyboardSuppressed=true", timeout: 5, diagnostics: diagnosticsText(in: app))
        assertKeyboardHidden(in: app)

        let firstRestoreBaseline = try keyboardTransitionBaseline(in: app)
        app.buttons["vvterm.keyboardTest.showKeyboard"].tap()
        waitForDiagnosticMetrics(in: app) { metrics in
            metrics["inputRebuilds"] == firstRestoreBaseline.rebuilds + 1
        }
        app.buttons["vvterm.keyboardTest.geometry.docked"].tap()
        wait(for: diagnostics, labelContaining: "hardware=true", timeout: 5, diagnostics: diagnosticsText(in: app))
        wait(for: diagnostics, labelContaining: "keyboardForced=true", timeout: 5, diagnostics: diagnosticsText(in: app))
        wait(for: diagnostics, labelContaining: "softwareKeyboardSuppressed=false", timeout: 5, diagnostics: diagnosticsText(in: app))
        wait(for: diagnostics, labelContaining: "keyboardVisible=true", timeout: 5, diagnostics: diagnosticsText(in: app))
        wait(for: diagnostics, labelContaining: "accessoryAttached=true", timeout: 5, diagnostics: diagnosticsText(in: app))

        terminal.typeText("h")
        wait(for: diagnostics, labelContaining: "inputHex=68", timeout: 5, diagnostics: diagnosticsText(in: app))

        app.buttons["vvterm.keyboardTest.hardwareFocus"].tap()
        wait(for: diagnostics, labelContaining: "hardware=true", timeout: 5, diagnostics: diagnosticsText(in: app))
        wait(for: diagnostics, labelContaining: "keyboardForced=true", timeout: 5, diagnostics: diagnosticsText(in: app))
        wait(for: diagnostics, labelContaining: "softwareKeyboardSuppressed=false", timeout: 5, diagnostics: diagnosticsText(in: app))
        wait(for: diagnostics, labelContaining: "accessoryAttached=true", timeout: 5, diagnostics: diagnosticsText(in: app))

        app.buttons["vvterm.keyboardTest.hardware.attach"].tap()
        wait(for: diagnostics, labelContaining: "hardware=true", timeout: 5, diagnostics: diagnosticsText(in: app))
        wait(for: diagnostics, labelContaining: "keyboardForced=true", timeout: 5, diagnostics: diagnosticsText(in: app))
        wait(for: diagnostics, labelContaining: "softwareKeyboardSuppressed=false", timeout: 5, diagnostics: diagnosticsText(in: app))
        wait(for: diagnostics, labelContaining: "accessoryAttached=true", timeout: 5, diagnostics: diagnosticsText(in: app))
        assertSingleKeyboardRepair(since: firstRestoreBaseline, in: app)

        app.buttons["vvterm.keyboardTest.geometry.hidden"].tap()
        wait(for: diagnostics, labelContaining: "keyboardForced=true", timeout: 5, diagnostics: diagnosticsText(in: app))
        wait(for: diagnostics, labelContaining: "browse=false", timeout: 5, diagnostics: diagnosticsText(in: app))
        wait(for: diagnostics, labelContaining: "keyboardVisible=false", timeout: 5, diagnostics: diagnosticsText(in: app))
        // A keyboard-hidden event while the user's explicit request is still
        // in force against an attached hardware keyboard is the external
        // keyboard case, not a failed presentation: the bar stays.
        wait(for: diagnostics, labelContaining: "accessoryAttached=true", timeout: 5, diagnostics: diagnosticsText(in: app))

        let forcedRetryBaseline = try keyboardTransitionBaseline(in: app)
        app.buttons["vvterm.keyboardTest.showKeyboard"].tap()
        waitForDiagnosticMetrics(in: app) { metrics in
            metrics["inputRebuilds"] == forcedRetryBaseline.rebuilds + 1
        }
        app.buttons["vvterm.keyboardTest.geometry.docked"].tap()
        wait(for: diagnostics, labelContaining: "keyboardForced=true", timeout: 5, diagnostics: diagnosticsText(in: app))
        wait(for: diagnostics, labelContaining: "softwareKeyboardSuppressed=false", timeout: 5, diagnostics: diagnosticsText(in: app))
        wait(for: diagnostics, labelContaining: "keyboardVisible=true", timeout: 5, diagnostics: diagnosticsText(in: app))
        wait(for: diagnostics, labelContaining: "accessoryAttached=true", timeout: 5, diagnostics: diagnosticsText(in: app))
        assertSingleKeyboardRepair(since: forcedRetryBaseline, in: app)

        app.buttons["vvterm.keyboardTest.hideViaToolbar"].tap()
        wait(for: diagnostics, labelContaining: "hardware=true", timeout: 5, diagnostics: diagnosticsText(in: app))
        wait(for: diagnostics, labelContaining: "softwareInputActive=true", timeout: 5, diagnostics: diagnosticsText(in: app))
        wait(for: diagnostics, labelContaining: "browse=true", timeout: 5, diagnostics: diagnosticsText(in: app))
        wait(for: diagnostics, labelContaining: "keyboardForced=false", timeout: 5, diagnostics: diagnosticsText(in: app))
        wait(for: diagnostics, labelContaining: "softwareKeyboardSuppressed=true", timeout: 5, diagnostics: diagnosticsText(in: app))
        wait(for: diagnostics, labelContaining: "keyboardVisible=false", timeout: 5, diagnostics: diagnosticsText(in: app))
        assertKeyboardHidden(in: app)

        let secondRestoreBaseline = try keyboardTransitionBaseline(in: app)
        app.buttons["vvterm.keyboardTest.showKeyboard"].tap()
        app.buttons["vvterm.keyboardTest.geometry.docked"].tap()
        wait(for: diagnostics, labelContaining: "hardware=true", timeout: 5, diagnostics: diagnosticsText(in: app))
        wait(for: diagnostics, labelContaining: "keyboardForced=true", timeout: 5, diagnostics: diagnosticsText(in: app))
        wait(for: diagnostics, labelContaining: "softwareKeyboardSuppressed=false", timeout: 5, diagnostics: diagnosticsText(in: app))
        wait(for: diagnostics, labelContaining: "keyboardVisible=true", timeout: 5, diagnostics: diagnosticsText(in: app))
        wait(for: diagnostics, labelContaining: "accessoryAttached=true", timeout: 5, diagnostics: diagnosticsText(in: app))
        assertSingleKeyboardRestore(since: secondRestoreBaseline, in: app)
    }

    @MainActor
    func testDefaultKeyboardAvoidanceResizesTerminalGrid() throws {
        let app = launchKeyboardHarness()
        let terminal = waitForTerminal(in: app)
        terminal.tap()
        assertKeyboardVisible(in: app)

        app.buttons["vvterm.keyboardTest.hideViaToolbar"].tap()
        assertKeyboardHidden(in: app)
        let expandedRows = try requiredDiagnosticMetric("gridRows", in: app)

        let transitionBaseline = try keyboardTransitionBaseline(in: app)
        app.buttons["vvterm.keyboardTest.showKeyboard"].tap()
        assertKeyboardVisible(in: app)
        waitForDiagnosticMetrics(in: app) { metrics in
            guard let rows = metrics["gridRows"],
                  let terminalBottom = metrics["terminalBottom"],
                  let keyboardTop = metrics["keyboardTop"] else { return false }
            return rows < expandedRows && terminalBottom <= keyboardTop + 1
        }
        assertSingleKeyboardRestore(since: transitionBaseline, in: app)
    }

    @MainActor
    func testRepeatedFocusTapsKeepDefaultKeyboardAndLayoutStable() throws {
        let app = launchKeyboardHarness(preservesTerminalSize: false)
        let terminal = waitForTerminal(in: app)
        terminal.tap()
        assertKeyboardVisible(in: app)

        for _ in 0..<8 {
            terminal.tap()
        }
        assertKeyboardVisible(in: app)

        let stableRows = try requiredDiagnosticMetric("gridRows", in: app)
        let diagnostics = app.staticTexts["vvterm.keyboardTest.diagnostics"]
        let deadline = Date().addingTimeInterval(2)
        while Date() < deadline {
            XCTAssertTrue(app.keyboards.firstMatch.exists, diagnosticsText(in: app))
            XCTAssertTrue(diagnostics.label.contains("keyboardVisible=true"), diagnosticsText(in: app))
            XCTAssertTrue(diagnostics.label.contains("accessoryAttached=true"), diagnosticsText(in: app))
            XCTAssertEqual(
                try requiredDiagnosticMetric("gridRows", in: app),
                stableRows,
                diagnosticsText(in: app)
            )
            RunLoop.current.run(until: Date().addingTimeInterval(0.1))
        }

        terminal.typeText("x")
        wait(
            for: diagnostics,
            labelContaining: "inputHex=78",
            timeout: 5,
            diagnostics: diagnosticsText(in: app)
        )
    }

}
