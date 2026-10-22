//
//  TerminalDoubleTapGesturePolicy.swift
//  VVTerm
//
//  Double-tap terminal gesture binding rules.
//

import Foundation

/// Resolves what a double-tap on the terminal surface sends.
///
/// Only actions that send a key are bindable: a latching modifier has no bar to
/// show its state on, and keyboard dismissal is not a key send.
nonisolated enum TerminalDoubleTapGesturePolicy {
    static let storageKey = "terminalDoubleTapAction"

    /// Stored value that leaves double-tap selecting a word, as it did before
    /// the gesture became bindable.
    static let offRawValue = "off"

    static let defaultActionID: TerminalAccessorySystemActionID = .tab

    static let bindableActions: [TerminalAccessorySystemActionID] =
        TerminalAccessorySystemActionID.allCases.filter {
            !$0.isModifier && $0 != .dismissKeyboard && $0 != .unknown
        }

    /// The bound action, or `nil` when the gesture is off. An unreadable or
    /// unbindable stored value resolves to the default rather than to off, so a
    /// value written by a newer build never silently disables the gesture.
    static func resolvedAction(rawValue: String?) -> TerminalAccessorySystemActionID? {
        guard let rawValue else { return defaultActionID }
        guard rawValue != offRawValue else { return nil }
        guard let actionID = TerminalAccessorySystemActionID(rawValue: rawValue),
              bindableActions.contains(actionID) else {
            return defaultActionID
        }
        return actionID
    }

    static func resolvedAction(
        defaults: UserDefaults = .standard
    ) -> TerminalAccessorySystemActionID? {
        resolvedAction(rawValue: defaults.string(forKey: storageKey))
    }
}
