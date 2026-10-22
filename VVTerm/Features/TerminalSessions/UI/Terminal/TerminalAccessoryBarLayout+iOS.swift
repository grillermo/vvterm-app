import SwiftUI

/// Places the accessory bar at the bottom of the terminal chrome. The stack
/// respects the keyboard safe area, so the bar rides on a software keyboard
/// and rests at the bottom edge otherwise; content reserves the bar height
/// itself so "Keep terminal size" can still ignore the keyboard.
struct TerminalAccessoryBarLayout<Content: View>: View {
    let terminal: GhosttyTerminalView?
    let isVisible: Bool
    let content: (CGFloat) -> Content

    /// The gutter below the controls is a per-device preference. Observing it
    /// here resizes both the reserved content inset and the mounted bar, and
    /// lets the mounted UIKit view drop its cached intrinsic height.
    @AppStorage(TerminalDefaults.accessoryGutterHeightKey)
    private var gutterHeight = TerminalDefaults.defaultAccessoryGutterHeight

    init(
        terminal: GhosttyTerminalView?,
        isVisible: Bool,
        @ViewBuilder content: @escaping (CGFloat) -> Content
    ) {
        self.terminal = terminal
        self.isVisible = isVisible
        self.content = content
    }

    private var mountedTerminal: GhosttyTerminalView? {
        isVisible ? terminal : nil
    }

    private var accessoryHeight: CGFloat {
        TerminalInputAccessoryView.preferredHeight(gutterHeight: CGFloat(gutterHeight))
    }

    var body: some View {
        ZStack(alignment: .bottom) {
            content(mountedTerminal == nil ? 0 : accessoryHeight)

            if let mountedTerminal {
                TerminalAccessoryBarHost(terminal: mountedTerminal)
                    .frame(height: accessoryHeight)
                    .frame(maxWidth: .infinity)
            }
        }
        .onChange(of: gutterHeight) { _ in
            terminal?.invalidateTerminalInputAccessoryHeight()
        }
    }
}
