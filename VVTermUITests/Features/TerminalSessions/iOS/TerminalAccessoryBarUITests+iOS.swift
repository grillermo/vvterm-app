import XCTest

final class TerminalAccessoryBarUITests: TerminalKeyboardUITestCase {
    @MainActor
    func testAccessoryBarStaysOnScreenWithHardwareKeyboard() throws {
        let app = launchKeyboardHarness(simulatesKeyboardFrames: true)
        let terminal = waitForTerminal(in: app)
        let diagnostics = app.staticTexts["vvterm.keyboardTest.diagnostics"]

        app.buttons["vvterm.keyboardTest.hardware.attach"].tap()
        wait(for: diagnostics, labelContaining: "hardware=true", timeout: 5, diagnostics: diagnosticsText(in: app))
        wait(for: diagnostics, labelContaining: "softwareKeyboardSuppressed=true", timeout: 5, diagnostics: diagnosticsText(in: app))
        assertAccessoryBar(attached: true, in: app)

        terminal.typeText("k")
        wait(for: diagnostics, labelContaining: "inputHex=6b", timeout: 5, diagnostics: diagnosticsText(in: app))
        assertAccessoryBar(attached: true, in: app)
    }

    @MainActor
    func testAccessoryBarStaysAfterDismissingSoftwareKeyboard() throws {
        let app = launchKeyboardHarness()
        let terminal = waitForTerminal(in: app)
        let diagnostics = app.staticTexts["vvterm.keyboardTest.diagnostics"]

        terminal.tap()
        assertKeyboardVisible(in: app)
        assertAccessoryBar(attached: true, in: app)

        let hide = app.buttons["vvterm.keyboard.accessory.hide"]
        XCTAssertTrue(hide.waitForExistence(timeout: 5), diagnosticsText(in: app))
        hide.tap()
        assertKeyboardHidden(in: app)
        wait(for: diagnostics, labelContaining: "browse=true", timeout: 5, diagnostics: diagnosticsText(in: app))
        assertAccessoryBar(attached: true, in: app)
    }

    @MainActor
    func testToggleOffHidesBarWhileSoftwareKeyboardStaysUp() throws {
        let app = launchKeyboardHarness()
        let terminal = waitForTerminal(in: app)

        terminal.tap()
        assertKeyboardVisible(in: app)
        assertAccessoryBar(attached: true, in: app)

        app.buttons["vvterm.keyboardTest.accessoryBar.toggle"].tap()
        assertAccessoryBar(attached: false, in: app)
        XCTAssertTrue(app.keyboards.firstMatch.exists, diagnosticsText(in: app))

        app.buttons["vvterm.keyboardTest.accessoryBar.toggle"].tap()
        assertAccessoryBar(attached: true, in: app)
    }

    @MainActor
    func testMoreMenuToggleHidesBar() throws {
        let app = launchKeyboardHarness()
        _ = waitForTerminal(in: app)
        assertAccessoryBar(attached: true, in: app)

        let menu = app.buttons["vvterm.keyboardTest.menu"]
        XCTAssertTrue(menu.waitForExistence(timeout: 5), diagnosticsText(in: app))
        menu.tap()
        let toggle = app.descendants(matching: .any)["vvterm.keyboardTest.menu.accessoryBar"]
        XCTAssertTrue(toggle.waitForExistence(timeout: 5), diagnosticsText(in: app))
        toggle.tap()

        assertAccessoryBar(attached: false, in: app)
    }

    @MainActor
    func testFindNavigatorHidesBar() throws {
        let app = launchKeyboardHarness()
        _ = waitForTerminal(in: app)
        let diagnostics = app.staticTexts["vvterm.keyboardTest.diagnostics"]
        assertAccessoryBar(attached: true, in: app)

        app.buttons["vvterm.keyboardTest.menu"].tap()
        let find = app.descendants(matching: .any)["vvterm.keyboardTest.menu.find"]
        XCTAssertTrue(find.waitForExistence(timeout: 5), diagnosticsText(in: app))
        find.tap()

        wait(for: diagnostics, labelContaining: "find=true", timeout: 5, diagnostics: diagnosticsText(in: app))
        assertAccessoryBar(attached: false, in: app)
    }

    @MainActor
    func testToggleSurvivesRelaunch() throws {
        var app = launchKeyboardHarness()
        _ = waitForTerminal(in: app)
        app.buttons["vvterm.keyboardTest.accessoryBar.toggle"].tap()
        assertAccessoryBar(attached: false, in: app)
        app.terminate()

        app = launchKeyboardHarness(resetsAccessoryBarVisibility: false)
        _ = waitForTerminal(in: app)
        assertAccessoryBar(attached: false, in: app)
    }
}
