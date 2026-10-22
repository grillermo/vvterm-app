import XCTest

final class CustomFontLibraryUITests: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    @MainActor
    func testFontSettingsOrderAndUngatedCustomFonts() throws {
        let app = launchApp()
        defer { app.terminate() }

        openTerminalAppearance(in: app)

        let fontSize = app.sliders["vvterm.settings.appearance.fontSize"]
        let cjkFont = app.descendants(matching: .any)[
            "vvterm.settings.appearance.cjkFont"
        ]
        let customFonts = app.buttons["vvterm.settings.appearance.customFonts"]

        XCTAssertTrue(fontSize.waitForExistence(timeout: 5))
        XCTAssertTrue(cjkFont.waitForExistence(timeout: 5))
        XCTAssertTrue(customFonts.waitForExistence(timeout: 5))
        XCTAssertLessThan(fontSize.frame.minY, cjkFont.frame.minY)
        XCTAssertLessThan(cjkFont.frame.minY, customFonts.frame.minY)
        XCTAssertFalse(customFonts.label.localizedCaseInsensitiveContains("pro"))

        customFonts.tap()

        let importFont = app.buttons["vvterm.settings.customFonts.import"]
        XCTAssertTrue(importFont.waitForExistence(timeout: 5))
        XCTAssertTrue(importFont.isEnabled)
        XCTAssertFalse(app.buttons["Upgrade to Pro"].exists)
        XCTAssertFalse(app.alerts["Custom Fonts"].exists)
    }

    @MainActor
    func testLibraryOpensFromTerminalAppearanceAndReturns() throws {
        let app = launchApp()
        defer { app.terminate() }

        openTerminalAppearance(in: app)

        let customFonts = app.buttons["vvterm.settings.appearance.customFonts"]
        XCTAssertTrue(scrollToHittable(customFonts, in: app))
        customFonts.tap()

        XCTAssertTrue(
            app.descendants(matching: .any)["vvterm.settings.customFonts.page"]
                .waitForExistence(timeout: 5)
        )
        let back = app.navigationBars["Custom Fonts"].buttons.firstMatch
        XCTAssertTrue(back.exists)
        back.tap()

        XCTAssertTrue(
            app.descendants(matching: .any)["vvterm.settings.page.terminalAppearance"]
                .waitForExistence(timeout: 5)
        )
    }

    @MainActor
    func testCJKFontOptionsCarryNoProMarkersAndAreSelectable() throws {
        let app = launchApp()
        defer { app.terminate() }

        openTerminalAppearance(in: app)

        let cjkFont = app.buttons["vvterm.settings.appearance.cjkFont"]
        XCTAssertTrue(cjkFont.waitForExistence(timeout: 5))
        XCTAssertTrue(cjkFont.isHittable)
        let initialSelection = cjkFont.label
        cjkFont.tap()

        let bundledOption = app.buttons["Hack Nerd Font"]
        XCTAssertTrue(bundledOption.waitForExistence(timeout: 5))
        XCTAssertFalse(
            app.buttons
                .matching(NSPredicate(format: "label CONTAINS[c] %@", "(Pro)"))
                .firstMatch
                .exists
        )
        bundledOption.tap()

        XCTAssertNotEqual(cjkFont.label, initialSelection)
        XCTAssertTrue(cjkFont.label.contains("Hack Nerd Font"))
    }

    @MainActor
    private func launchApp() -> XCUIApplication {
        let app = XCUIApplication()
        app.terminate()
        app.launchArguments = [
            "-AppleLanguages", "(en)",
            "-AppleLocale", "en_US",
            "-hasSeenWelcome", "YES",
            "-iCloudSyncEnabled", "NO",
            "-security.privacyModeEnabled", "NO",
            "-security.fullAppLockEnabled", "NO",
            "-security.lockOnBackground", "NO",
        ]
        app.launch()
        return app
    }

    @MainActor
    private func openTerminalAppearance(in app: XCUIApplication) {
        let settings = app.buttons["vvterm.serverList.settings"]
        XCTAssertTrue(settings.waitForExistence(timeout: 10))
        settings.tap()

        let terminalAppearance = app.buttons["vvterm.settings.route.terminalAppearance"]
        XCTAssertTrue(terminalAppearance.waitForExistence(timeout: 8))
        terminalAppearance.tap()
    }

    @MainActor
    private func scrollToHittable(
        _ element: XCUIElement,
        in app: XCUIApplication
    ) -> Bool {
        if element.waitForExistence(timeout: 2), element.isHittable {
            return true
        }
        for _ in 0..<6 {
            app.swipeUp()
            if element.exists, element.isHittable {
                return true
            }
        }
        return false
    }
}
