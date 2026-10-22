import XCTest

final class TerminalTabStripUITests: TerminalReconnectUITestCase {
    /// A new tab opens at the trailing end of an overflowing strip, and its
    /// runtime title arrives after it opens and widens it. Its close button
    /// must stay on screen without the user scrolling the strip.
    @MainActor
    func testNewTabCloseButtonStaysVisibleAfterRuntimeTitleGrows() throws {
        let (app, diagnostics) = launchApprovingLoopbackHost()
        defer { app.terminate() }

        let newTabButton = app.buttons["vvterm.terminal.newTab"]
        XCTAssertTrue(newTabButton.waitForExistence(timeout: 5), diagnosticText(in: app))

        let strip = app.scrollViews["vvterm.terminalTabs.strip"]
        var overflowingChecks = 0
        for _ in 0..<5 {
            let previousShellId = diagnosticValue("shellId", in: diagnostics) ?? "none"
            newTabButton.tap()
            _ = waitForChangedDiagnosticValue(
                "shellId",
                previousValue: previousShellId,
                in: diagnostics,
                timeout: 30,
                app: app
            )

            // Shell integration titles the tab `user@host:cwd` after it opens,
            // widening a tab that was already revealed.
            let titleDeadline = Date().addingTimeInterval(10)
            while diagnosticValue("title", in: diagnostics)?.contains("@") != true,
                  Date() < titleDeadline {
                RunLoop.current.run(until: Date().addingTimeInterval(0.1))
            }
            XCTAssertEqual(
                diagnosticValue("title", in: diagnostics)?.contains("@"),
                true,
                diagnosticText(in: app)
            )

            // Until the strip overflows, tabs share its width and cannot hide.
            if strip.exists {
                assertSelectedTabCloseButtonVisible(in: strip, app: app)
                overflowingChecks += 1
            }
        }
        XCTAssertGreaterThanOrEqual(overflowingChecks, 2, "Tab strip never overflowed")
    }

    /// The harness forgets the loopback host key on every launch, so the first
    /// connection stops at the host-key approval sheet until it is trusted.
    @MainActor
    private func launchApprovingLoopbackHost() -> (XCUIApplication, XCUIElement) {
        let app = XCUIApplication()
        app.terminate()
        app.launchArguments = [
            "--vvterm-ui-test-terminal-reconnect-harness",
            "-AppleLanguages", "(en)",
            "-AppleLocale", "en_US",
            "-hasSeenWelcome", "YES",
            "-iCloudSyncEnabled", "NO",
            "-terminalTmuxEnabledDefault", "NO",
            "-security.privacyModeEnabled", "NO",
            "-security.fullAppLockEnabled", "NO",
            "-security.lockOnBackground", "NO",
        ]
        app.launch()

        let diagnostics = app.staticTexts["vvterm.reconnectTest.diagnostics"]
        XCTAssertTrue(diagnostics.waitForExistence(timeout: 45), "Production SSH harness did not mount")

        let trustNewHostKey = app.buttons["Trust New Host Key"]
        if trustNewHostKey.waitForExistence(timeout: 20) {
            trustNewHostKey.tap()
            let trustAndReconnect = app.alerts.buttons["Trust and Reconnect"]
            XCTAssertTrue(trustAndReconnect.waitForExistence(timeout: 5), diagnosticText(in: app))
            trustAndReconnect.tap()
        }

        wait(for: diagnostics, containing: "state=connected", timeout: 45, app: app)
        wait(for: diagnostics, containing: "shell=true", timeout: 10, app: app)
        return (app, diagnostics)
    }

    @MainActor
    private func assertSelectedTabCloseButtonVisible(in strip: XCUIElement, app: XCUIApplication) {
        let closeButton = app.buttons
            .matching(identifier: "vvterm.terminalTabs.close")
            .matching(NSPredicate(format: "value == %@", "selected"))
            .firstMatch
        XCTAssertTrue(closeButton.waitForExistence(timeout: 5), diagnosticText(in: app))

        let deadline = Date().addingTimeInterval(3)
        while Date() < deadline {
            if strip.frame.contains(closeButton.frame) {
                return
            }
            RunLoop.current.run(until: Date().addingTimeInterval(0.1))
        }
        XCTFail(
            "Selected tab close button \(closeButton.frame) is outside the strip \(strip.frame)"
        )
    }
}
