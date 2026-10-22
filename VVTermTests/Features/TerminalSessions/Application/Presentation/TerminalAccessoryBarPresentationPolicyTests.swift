import Testing
@testable import VVTerm

struct TerminalAccessoryBarPresentationPolicyTests {
    @Test
    func enabledBarShowsForFocusedTerminal() {
        #expect(isVisible())
    }

    @Test
    func toggleOffHidesBar() {
        #expect(!isVisible(isEnabled: false))
    }

    @Test
    func barNeedsSelectedTerminalAndFocusedPane() {
        #expect(!isVisible(isTerminalSelected: false))
        #expect(!isVisible(hasFocusedTerminal: false))
    }

    @Test
    func findNavigatorTakesTheBarSlot() {
        #expect(!isVisible(findNavigatorIsVisible: true))
    }

    @Test
    func defaultsKeepBarOn() {
        #expect(TerminalDefaults.accessoryBarVisibleKey == "terminalAccessoryBarVisible")
        #expect(TerminalDefaults.defaultAccessoryBarVisible)
    }

    private func isVisible(
        isEnabled: Bool = true,
        isTerminalSelected: Bool = true,
        hasFocusedTerminal: Bool = true,
        findNavigatorIsVisible: Bool = false
    ) -> Bool {
        TerminalAccessoryBarPresentationPolicy.isVisible(
            for: .init(
                isEnabled: isEnabled,
                isTerminalSelected: isTerminalSelected,
                hasFocusedTerminal: hasFocusedTerminal,
                findNavigatorIsVisible: findNavigatorIsVisible
            )
        )
    }
}
