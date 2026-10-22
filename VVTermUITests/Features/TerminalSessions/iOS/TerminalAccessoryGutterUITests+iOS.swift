//
//  TerminalAccessoryGutterUITests+iOS.swift
//  VVTermUITests
//
//  Screen-space accessory gutter geometry screenshot tests.
//

import XCTest

/// Accessory bar gutter geometry against UIKit's real keyboard hosting.
/// Never uses simulated keyboard frames or the DEBUG hardware override: the
/// reverted attempt passed a test built on those and was wrong on device.
final class TerminalAccessoryGutterUITests: TerminalKeyboardUITestCase {
    static let barHeight = 48.0
    static let gutterHeight = 144.0

    private var lastScreenshot: UIImage?

    /// Case (a). Needs the simulator's I/O → Keyboard → Connect Hardware
    /// Keyboard on, so it is opt-in: TEST_RUNNER_VVTERM_SIM_HARDWARE_KEYBOARD=1.
    @MainActor
    func testCaseAHardwareKeyboardDockedBar() throws {
        try XCTSkipUnless(
            ProcessInfo.processInfo.environment["VVTERM_SIM_HARDWARE_KEYBOARD"] == "1",
            "Set TEST_RUNNER_VVTERM_SIM_HARDWARE_KEYBOARD=1 with Connect Hardware Keyboard on."
        )
        let app = launchKeyboardHarness()
        let terminal = waitForTerminal(in: app)
        let diagnostics = app.staticTexts["vvterm.keyboardTest.diagnostics"]
        terminal.tap()
        wait(for: diagnostics, labelContaining: "hardware=true", timeout: 10,
             diagnostics: "Simulator hardware keyboard not detected; toggle I/O → Keyboard → Connect Hardware Keyboard. \(diagnosticsText(in: app))")
        app.buttons["vvterm.keyboardTest.showKeyboard"].tap()
        wait(for: diagnostics, labelContaining: "keyboardForced=true", timeout: 10, diagnostics: diagnosticsText(in: app))
        wait(for: diagnostics, labelContaining: "accessoryAttached=true", timeout: 10, diagnostics: diagnosticsText(in: app))
        settleLayout()

        let geometry = try recordEvidence(named: "case-a-hardware-keyboard", in: app)
        assertGeometry(geometry, bottomBoundaryY: Double(geometry.screen.maxY), in: app)

        // The spec ends the gutter at the screen bottom when no software
        // keyboard is present. `violations` only checks accessory.maxY
        // against the boundary, so it would still pass if UIKit hosted the
        // accessory above system chrome (e.g. the home-indicator safe area)
        // with a gap below it. Require the accessory frame itself, and the
        // theme color it paints, to actually reach the screen edge.
        XCTAssertEqual(
            Double(geometry.accessory.maxY), Double(geometry.screen.maxY), accuracy: 1,
            "Case (a) gutter must reach the screen bottom. \(diagnosticsText(in: app))"
        )
        let image = try XCTUnwrap(lastScreenshot, "No screenshot captured")
        let visibleBottom = TerminalAccessoryGutterGeometry.visibleBottomBoundaryY(
            in: image,
            x: geometry.accessory.midX,
            from: geometry.controls.maxY + 1,
            to: geometry.screen.maxY,
            backgroundHex: geometry.backgroundHex
        )
        XCTAssertEqual(
            Double(visibleBottom), Double(geometry.screen.maxY), accuracy: 1,
            "Theme-colored gutter must run to the screen bottom with no system chrome below it. \(diagnosticsText(in: app))"
        )
    }

    /// Case (b). Needs Connect Hardware Keyboard off (the simulator default for CI).
    @MainActor
    func testCaseBSoftwareKeyboardBar() throws {
        let app = launchKeyboardHarness()
        let terminal = waitForTerminal(in: app)
        let diagnostics = app.staticTexts["vvterm.keyboardTest.diagnostics"]
        terminal.tap()
        assertKeyboardVisible(in: app)
        wait(for: diagnostics, labelContaining: "accessoryHeight=192.0", timeout: 5, diagnostics: diagnosticsText(in: app))
        wait(for: diagnostics, labelContaining: "accessoryFittingHeight=192.0", timeout: 5, diagnostics: diagnosticsText(in: app))
        settleLayout()

        let geometry = try recordEvidence(named: "case-b-software-keyboard", in: app)
        XCTAssertTrue(app.keyboards.firstMatch.exists, "Software keyboard must be visible. \(diagnosticsText(in: app))")
        // XCUI reports the keyboard frame's minY ~17pt below its visible top,
        // so the boundary is read from the screenshot where the theme-colored
        // gutter ends.
        let image = try XCTUnwrap(lastScreenshot, "No screenshot captured")
        let visibleBottom = TerminalAccessoryGutterGeometry.visibleBottomBoundaryY(
            in: image,
            x: geometry.accessory.midX,
            from: geometry.controls.maxY + 1,
            to: geometry.screen.maxY,
            backgroundHex: geometry.backgroundHex
        )
        XCTAssertEqual(
            Double(visibleBottom), Double(geometry.accessory.maxY), accuracy: 2,
            "Visible gutter must end at the accessory bottom. \(diagnosticsText(in: app))"
        )
        XCTAssertLessThan(
            visibleBottom, geometry.screen.maxY,
            "A software keyboard must be visible below the gutter. \(diagnosticsText(in: app))"
        )
        assertGeometry(geometry, bottomBoundaryY: Double(visibleBottom), in: app)
        assertTerminalViewportValid(in: app)
    }

    /// Case (c). The gutter is a preference now, so a configured height must
    /// drive every accessory sizing path and the painted theme color with it.
    /// The bar is not an input accessory, so this needs no keyboard.
    @MainActor
    func testConfiguredGutterHeightResizesBar() throws {
        let configuredGutter = 64.0
        let app = launchKeyboardHarness(accessoryGutterHeight: configuredGutter)
        _ = waitForTerminal(in: app)
        let diagnostics = app.staticTexts["vvterm.keyboardTest.diagnostics"]
        let expectedHeight = Self.barHeight + configuredGutter

        wait(for: diagnostics, labelContaining: "accessoryAttached=true", timeout: 10,
             diagnostics: diagnosticsText(in: app))
        wait(for: diagnostics, labelContaining: "accessoryHeight=\(expectedHeight)", timeout: 5,
             diagnostics: diagnosticsText(in: app))
        wait(for: diagnostics, labelContaining: "accessoryFittingHeight=\(expectedHeight)", timeout: 5,
             diagnostics: diagnosticsText(in: app))
        settleLayout()

        let geometry = try recordEvidence(named: "case-c-configured-gutter", in: app)
        let violations = geometry.violations(
            barHeight: Self.barHeight,
            gutterHeight: configuredGutter,
            bottomBoundaryY: Double(geometry.accessory.maxY)
        )
        XCTAssertTrue(violations.isEmpty, "\(violations.joined(separator: "\n"))\n\(diagnosticsText(in: app))")

        let image = try XCTUnwrap(lastScreenshot, "No screenshot captured")
        let gutterMid = CGPoint(x: geometry.accessory.midX, y: geometry.controls.maxY + configuredGutter / 2)
        let gutterPixel = TerminalAccessoryGutterGeometry.pixelHex(in: image, at: gutterMid)
        XCTAssertTrue(
            gutterPixel.map { TerminalAccessoryGutterGeometry.hex($0, matches: geometry.backgroundHex) } == true,
            "Gutter pixel \(gutterPixel ?? "nil") at \(gutterMid) != theme background \(geometry.backgroundHex)"
        )
        assertTerminalViewportValid(in: app)
    }

    private func settleLayout() {
        // Let UIKit finish keyboard animation and accessory self-sizing.
        let settled = expectation(description: "layout settled")
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { settled.fulfill() }
        wait(for: [settled], timeout: 3)
    }

    @MainActor
    private func recordEvidence(named name: String, in app: XCUIApplication) throws -> TerminalAccessoryGutterGeometry {
        let screenshot = XCUIScreen.main.screenshot()
        let image = XCTAttachment(screenshot: screenshot)
        image.name = name
        image.lifetime = .keepAlways
        add(image)

        let text = diagnosticsText(in: app)
        let diagnosticsAttachment = XCTAttachment(string: text)
        diagnosticsAttachment.name = "\(name)-diagnostics"
        diagnosticsAttachment.lifetime = .keepAlways
        add(diagnosticsAttachment)

        let geometry = try XCTUnwrap(
            TerminalAccessoryGutterGeometry(diagnostics: text),
            "Missing screen-space accessory diagnostics. \(text)"
        )
        lastScreenshot = screenshot.image
        return geometry
    }

    private func assertGeometry(
        _ geometry: TerminalAccessoryGutterGeometry,
        bottomBoundaryY: Double,
        in app: XCUIApplication
    ) {
        let violations = geometry.violations(
            barHeight: Self.barHeight,
            gutterHeight: Self.gutterHeight,
            bottomBoundaryY: bottomBoundaryY
        )
        XCTAssertTrue(violations.isEmpty, "\(violations.joined(separator: "\n"))\n\(diagnosticsText(in: app))")

        guard let image = lastScreenshot else { return XCTFail("No screenshot captured") }
        let gutterMid = CGPoint(x: geometry.accessory.midX, y: geometry.controls.maxY + Self.gutterHeight / 2)
        let gutterPixel = TerminalAccessoryGutterGeometry.pixelHex(in: image, at: gutterMid)
        XCTAssertTrue(
            gutterPixel.map { TerminalAccessoryGutterGeometry.hex($0, matches: geometry.backgroundHex) } == true,
            "Gutter pixel \(gutterPixel ?? "nil") at \(gutterMid) != theme background \(geometry.backgroundHex)"
        )
    }
}
