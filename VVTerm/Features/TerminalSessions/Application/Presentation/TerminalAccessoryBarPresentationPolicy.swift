import Foundation

/// The accessory bar is a standalone control. Whether it is on screen depends
/// only on the user's toggle and on what the terminal route shows; software or
/// hardware keyboard presence is deliberately not an input.
nonisolated enum TerminalAccessoryBarPresentationPolicy {
    nonisolated struct Facts: Equatable, Sendable {
        let isEnabled: Bool
        let isTerminalSelected: Bool
        let hasFocusedTerminal: Bool
        let findNavigatorIsVisible: Bool
    }

    static func isVisible(for facts: Facts) -> Bool {
        facts.isEnabled
            && facts.isTerminalSelected
            && facts.hasFocusedTerminal
            && !facts.findNavigatorIsVisible
    }
}
