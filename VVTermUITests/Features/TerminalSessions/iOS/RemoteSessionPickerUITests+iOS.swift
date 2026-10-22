import XCTest

final class RemoteSessionPickerUITests: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    @MainActor
    func testNamedSessionValidatesNameAndConfirmsCreateNamed() throws {
        let app = launchPickerHarness()
        let namedButton = app.buttons["tmuxNamedSessionButton"]
        XCTAssertTrue(namedButton.waitForExistence(timeout: 10))
        namedButton.tap()

        let field = app.textFields["tmuxNamedSessionNameField"]
        let start = app.buttons["tmuxNamedSessionStartButton"]
        let error = app.staticTexts["tmuxNamedSessionError"]
        XCTAssertTrue(field.waitForExistence(timeout: 5))
        XCTAssertTrue(app.navigationBars["Start named session"].exists)
        XCTAssertFalse(start.isEnabled)

        field.tap()
        field.typeText("bad.name")
        XCTAssertTrue(error.waitForExistence(timeout: 5))
        XCTAssertEqual(error.label, "Use only letters, numbers, hyphens, and underscores.")
        XCTAssertFalse(start.isEnabled)

        clear(field)
        field.typeText("currentps")
        XCTAssertTrue(error.waitForExistence(timeout: 5))
        XCTAssertEqual(error.label, "A session with this name already exists.")
        XCTAssertFalse(start.isEnabled)

        clear(field)
        field.typeText("my-work_1")
        XCTAssertFalse(error.waitForExistence(timeout: 1))
        XCTAssertTrue(start.isEnabled)
        start.tap()

        let result = app.staticTexts["vvterm.remoteSessionPickerTest.result"]
        XCTAssertTrue(result.waitForExistence(timeout: 5))
        XCTAssertEqual(result.label, "createNamed:my-work_1")
    }

    @MainActor
    func testCancellingNamedSessionReturnsToPicker() throws {
        let app = launchPickerHarness()
        let namedButton = app.buttons["tmuxNamedSessionButton"]
        XCTAssertTrue(namedButton.waitForExistence(timeout: 10))
        namedButton.tap()

        XCTAssertTrue(app.textFields["tmuxNamedSessionNameField"].waitForExistence(timeout: 5))
        app.navigationBars["Start named session"].buttons["Cancel"].tap()

        XCTAssertTrue(app.navigationBars["Choose tmux session"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.textFields["tmuxNamedSessionNameField"].exists)
        XCTAssertTrue(namedButton.exists)
    }

    private func clear(_ field: XCUIElement) {
        guard let value = field.value as? String, !value.isEmpty else { return }
        field.typeText(String(repeating: XCUIKeyboardKey.delete.rawValue, count: value.count))
    }

    private func launchPickerHarness() -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = [
            "--vvterm-ui-test-remote-session-picker-harness",
            "-AppleLanguages", "(en)",
            "-AppleLocale", "en_US"
        ]
        app.launch()
        return app
    }
}
