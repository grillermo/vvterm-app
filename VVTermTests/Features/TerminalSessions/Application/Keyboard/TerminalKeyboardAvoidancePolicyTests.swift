import CoreGraphics
import Testing
@testable import VVTerm

struct TerminalKeyboardAvoidancePolicyTests {
    private let terminalFrame = CGRect(x: 0, y: 0, width: 390, height: 800)

    @Test
    func hiddenKeyboardDoesNotMoveTerminal() {
        let offset = TerminalKeyboardAvoidancePolicy.verticalOffset(
            terminalFrame: terminalFrame,
            cursorFrame: CGRect(x: 8, y: 760, width: 8, height: 18),
            keyboardFrame: nil
        )

        #expect(offset == 0)
    }

    @Test
    func cursorAboveKeyboardDoesNotMoveTerminal() {
        let offset = TerminalKeyboardAvoidancePolicy.verticalOffset(
            terminalFrame: terminalFrame,
            cursorFrame: CGRect(x: 8, y: 300, width: 8, height: 18),
            keyboardFrame: CGRect(x: 0, y: 500, width: 390, height: 300)
        )

        #expect(offset == 0)
    }

    @Test
    func coveredCursorMovesJustAboveKeyboard() {
        let cursor = CGRect(x: 8, y: 700, width: 8, height: 18)
        let keyboard = CGRect(x: 0, y: 500, width: 390, height: 300)
        let offset = TerminalKeyboardAvoidancePolicy.verticalOffset(
            terminalFrame: terminalFrame,
            cursorFrame: cursor,
            keyboardFrame: keyboard
        )

        #expect(offset == -230)
        #expect(cursor.maxY + offset + TerminalKeyboardAvoidancePolicy.defaultCursorClearance == keyboard.minY)
    }

    @Test
    func cursorClearanceCanMovePastCoveredTerminalHeight() {
        let offset = TerminalKeyboardAvoidancePolicy.verticalOffset(
            terminalFrame: terminalFrame,
            cursorFrame: CGRect(x: 8, y: 790, width: 8, height: 18),
            keyboardFrame: CGRect(x: 0, y: 500, width: 390, height: 300),
            cursorClearance: 40
        )

        #expect(offset == -348)
    }

    @Test
    func liftAlwaysLeavesAVisibleTerminalViewport() {
        let offset = TerminalKeyboardAvoidancePolicy.verticalOffset(
            terminalFrame: terminalFrame,
            cursorFrame: CGRect(x: 8, y: 1_390, width: 8, height: 18),
            keyboardFrame: CGRect(x: 0, y: 500, width: 390, height: 300),
            cursorClearance: 40
        )

        #expect(offset == -799)
        #expect(terminalFrame.height + offset >= TerminalKeyboardAvoidancePolicy.minimumVisibleHeight)
    }

    @Test
    func floatingKeyboardAwayFromCursorDoesNotMoveTerminal() {
        let offset = TerminalKeyboardAvoidancePolicy.verticalOffset(
            terminalFrame: terminalFrame,
            cursorFrame: CGRect(x: 16, y: 610, width: 8, height: 18),
            keyboardFrame: CGRect(x: 160, y: 480, width: 210, height: 220)
        )

        #expect(offset == 0)
    }

    @Test
    func floatingKeyboardCoveringCursorMovesTerminal() {
        let cursor = CGRect(x: 220, y: 610, width: 8, height: 18)
        let keyboard = CGRect(x: 160, y: 480, width: 210, height: 220)
        let offset = TerminalKeyboardAvoidancePolicy.verticalOffset(
            terminalFrame: terminalFrame,
            cursorFrame: cursor,
            keyboardFrame: keyboard
        )

        #expect(offset == -160)
    }

    @Test
    func dockedFloatingDockedTransitionsReplaceGeometryWithoutStalePreservation() {
        let docked = CGRect(x: 0, y: 500, width: 390, height: 300)
        let floating = CGRect(x: 160, y: 480, width: 210, height: 220)
        let geometries = [docked, floating, docked, nil].map {
            TerminalKeyboardAvoidancePolicy.resolvedGeometry(
                screenFrame: terminalFrame,
                terminalFrame: terminalFrame,
                keyboardFrame: $0
            )
        }

        #expect(
            geometries == [
                .docked(frame: docked),
                .floating(frame: floating),
                .docked(frame: docked),
                .hidden,
            ]
        )
    }

    @Test
    func defaultLayoutResizesOnlyForDockedKeyboard() {
        let docked = TerminalKeyboardAvoidancePolicy.layout(
            preservesTerminalSize: false,
            geometry: .docked(frame: CGRect(x: 0, y: 500, width: 390, height: 300)),
            terminalFrame: terminalFrame,
            cursorFrame: CGRect(x: 8, y: 700, width: 8, height: 18)
        )
        let floating = TerminalKeyboardAvoidancePolicy.layout(
            preservesTerminalSize: false,
            geometry: .floating(frame: CGRect(x: 160, y: 480, width: 210, height: 220)),
            terminalFrame: terminalFrame,
            cursorFrame: CGRect(x: 220, y: 610, width: 8, height: 18)
        )

        #expect(docked == .init(bottomInset: 300, verticalOffset: 0, preservesTerminalSurfaceSize: false))
        #expect(floating == .unobstructed)
    }

    @Test
    func floatingKeyboardInsetsOnlyTheBottomDockedAccessory() {
        let layout = TerminalKeyboardAvoidancePolicy.layout(
            preservesTerminalSize: false,
            geometry: .floating(frame: CGRect(x: 160, y: 480, width: 210, height: 220)),
            terminalFrame: terminalFrame,
            cursorFrame: CGRect(x: 8, y: 700, width: 8, height: 18),
            accessoryFrame: CGRect(x: 0, y: 752, width: 390, height: 48)
        )

        #expect(
            layout == .init(
                bottomInset: 48,
                verticalOffset: 0,
                preservesTerminalSurfaceSize: false
            )
        )
    }

    @Test
    func accessoryAttachedToFloatingKeyboardDoesNotCreateBottomInset() {
        let layout = TerminalKeyboardAvoidancePolicy.layout(
            preservesTerminalSize: false,
            geometry: .floating(frame: CGRect(x: 160, y: 480, width: 210, height: 220)),
            terminalFrame: terminalFrame,
            cursorFrame: CGRect(x: 8, y: 700, width: 8, height: 18),
            accessoryFrame: CGRect(x: 160, y: 432, width: 210, height: 48)
        )

        #expect(layout == .unobstructed)
    }

    @Test
    func preservedLayoutMovesWithoutLeavingDockedInsetBehind() {
        let docked = TerminalKeyboardAvoidancePolicy.layout(
            preservesTerminalSize: true,
            geometry: .docked(frame: CGRect(x: 0, y: 500, width: 390, height: 300)),
            terminalFrame: terminalFrame,
            cursorFrame: CGRect(x: 8, y: 700, width: 8, height: 18)
        )
        let floating = TerminalKeyboardAvoidancePolicy.layout(
            preservesTerminalSize: true,
            geometry: .floating(frame: CGRect(x: 160, y: 480, width: 210, height: 220)),
            terminalFrame: terminalFrame,
            cursorFrame: CGRect(x: 220, y: 610, width: 8, height: 18)
        )

        #expect(docked.bottomInset == 0)
        #expect(docked.verticalOffset == -230)
        #expect(docked.preservesTerminalSurfaceSize)
        #expect(floating.bottomInset == 0)
        #expect(floating.verticalOffset == -160)
        #expect(floating.preservesTerminalSurfaceSize)
    }

    @Test
    func offWindowKeyboardGeometryIsHidden() {
        let geometry = TerminalKeyboardAvoidancePolicy.resolvedGeometry(
            screenFrame: terminalFrame,
            terminalFrame: terminalFrame,
            keyboardFrame: CGRect(x: 500, y: 480, width: 210, height: 220)
        )

        #expect(geometry == .hidden)
    }

    @Test
    func floatingKeyboardRemainsFloatingInNarrowAppWindow() {
        let screenFrame = CGRect(x: 0, y: 0, width: 1_366, height: 1_024)
        let narrowTerminalFrame = CGRect(x: 991, y: 0, width: 375, height: 1_024)
        let floating = CGRect(x: 1_046, y: 704, width: 320, height: 320)

        let geometry = TerminalKeyboardAvoidancePolicy.resolvedGeometry(
            screenFrame: screenFrame,
            terminalFrame: narrowTerminalFrame,
            keyboardFrame: floating
        )

        #expect(geometry == .floating(frame: floating))
    }

    @Test
    func preservedLayoutLiftsCursorAboveBarOnDockedKeyboard() {
        let keyboard = CGRect(x: 0, y: 500, width: 390, height: 300)
        let bar = CGRect(x: 0, y: 452, width: 390, height: 48)
        let cursor = CGRect(x: 8, y: 440, width: 8, height: 18)

        let withoutBar = TerminalKeyboardAvoidancePolicy.layout(
            preservesTerminalSize: true,
            geometry: .docked(frame: keyboard),
            terminalFrame: terminalFrame,
            cursorFrame: cursor
        )
        let withBar = TerminalKeyboardAvoidancePolicy.layout(
            preservesTerminalSize: true,
            geometry: .docked(frame: keyboard),
            terminalFrame: terminalFrame,
            cursorFrame: cursor,
            accessoryFrame: bar
        )

        #expect(withoutBar.verticalOffset == 0)
        // cursor.maxY 458 + clearance 12 - bar.minY 452 = 18pt lift
        #expect(withBar == .init(bottomInset: 0, verticalOffset: -18, preservesTerminalSurfaceSize: true))
    }

    @Test
    func barAwayFromDockedKeyboardDoesNotExtendObstruction() {
        let layout = TerminalKeyboardAvoidancePolicy.layout(
            preservesTerminalSize: true,
            geometry: .docked(frame: CGRect(x: 0, y: 500, width: 390, height: 300)),
            terminalFrame: terminalFrame,
            cursorFrame: CGRect(x: 8, y: 440, width: 8, height: 18),
            accessoryFrame: CGRect(x: 0, y: 200, width: 390, height: 48)
        )

        #expect(layout.verticalOffset == 0)
    }

    /// The gutter is real accessory height, so a bottom-docked accessory
    /// must shrink the terminal by bar plus gutter, never overlay it.
    @Test
    func accessoryWithGutterInsetsTerminalByFullHeight() {
        let accessoryHeight = TerminalAccessoryAppearancePolicy.barHeight
            + TerminalAccessoryAppearancePolicy.defaultBottomGutterHeight
        let layout = TerminalKeyboardAvoidancePolicy.layout(
            preservesTerminalSize: false,
            geometry: .hidden,
            terminalFrame: terminalFrame,
            cursorFrame: CGRect(x: 8, y: 20, width: 8, height: 18),
            accessoryFrame: CGRect(
                x: terminalFrame.minX,
                y: terminalFrame.maxY - accessoryHeight,
                width: terminalFrame.width,
                height: accessoryHeight
            )
        )
        #expect(layout.bottomInset == 192)
        #expect(layout.verticalOffset == 0)
    }
}
