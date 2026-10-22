import Foundation
import Testing
@testable import VVTerm

struct TerminalDoubleTapGesturePolicyTests {
    private static let suiteName = "TerminalDoubleTapGesturePolicyTests"

    @Test
    func unsetBindingSendsTab() {
        #expect(TerminalDoubleTapGesturePolicy.resolvedAction(rawValue: nil) == .tab)
    }

    @Test
    func offSentinelLeavesTheGestureUnbound() {
        #expect(
            TerminalDoubleTapGesturePolicy.resolvedAction(
                rawValue: TerminalDoubleTapGesturePolicy.offRawValue
            ) == nil
        )
    }

    @Test
    func storedActionResolvesToItself() {
        #expect(TerminalDoubleTapGesturePolicy.resolvedAction(rawValue: "escape") == .escape)
        #expect(TerminalDoubleTapGesturePolicy.resolvedAction(rawValue: "ctrlC") == .ctrlC)
        #expect(TerminalDoubleTapGesturePolicy.resolvedAction(rawValue: "shiftTab") == .shiftTab)
    }

    @Test
    func unreadableStoredValueFallsBackToTheDefault() {
        // A value written by a newer build must not silently disable the gesture.
        for rawValue in ["", "garbage", "unknown"] {
            #expect(TerminalDoubleTapGesturePolicy.resolvedAction(rawValue: rawValue) == .tab)
        }
    }

    @Test
    func unbindableActionsFallBackToTheDefault() {
        // A latching modifier has no bar to show its state on, and keyboard
        // dismissal is not a key send, so neither may reach the gesture handler.
        for actionID in [
            TerminalAccessorySystemActionID.controlModifier,
            .alternateModifier,
            .commandModifier,
            .shiftModifier,
            .dismissKeyboard
        ] {
            #expect(
                TerminalDoubleTapGesturePolicy.resolvedAction(rawValue: actionID.rawValue) == .tab
            )
        }
    }

    @Test
    func everyBindableActionSendsAKey() {
        // The handler routes through `performAccessorySystemAction`, which is a
        // no-op for an action with no terminal key.
        for actionID in TerminalDoubleTapGesturePolicy.bindableActions {
            #expect(actionID.terminalKey != nil)
        }
    }

    @Test
    func bindableActionsCoverTheKeySendingActions() {
        #expect(TerminalDoubleTapGesturePolicy.bindableActions.contains(.tab))
        #expect(TerminalDoubleTapGesturePolicy.bindableActions.contains(.escape))
        #expect(TerminalDoubleTapGesturePolicy.bindableActions.contains(.ctrlC))
        #expect(
            TerminalDoubleTapGesturePolicy.bindableActions
                .contains(TerminalDoubleTapGesturePolicy.defaultActionID)
        )
    }

    @Test
    func storedDefaultsReadResolvesThroughTheSameRules() throws {
        let defaults = try #require(UserDefaults(suiteName: Self.suiteName))
        defaults.removePersistentDomain(forName: Self.suiteName)
        defer { defaults.removePersistentDomain(forName: Self.suiteName) }

        #expect(TerminalDoubleTapGesturePolicy.resolvedAction(defaults: defaults) == .tab)

        defaults.set("escape", forKey: TerminalDoubleTapGesturePolicy.storageKey)
        #expect(TerminalDoubleTapGesturePolicy.resolvedAction(defaults: defaults) == .escape)

        defaults.set(
            TerminalDoubleTapGesturePolicy.offRawValue,
            forKey: TerminalDoubleTapGesturePolicy.storageKey
        )
        #expect(TerminalDoubleTapGesturePolicy.resolvedAction(defaults: defaults) == nil)
    }
}
