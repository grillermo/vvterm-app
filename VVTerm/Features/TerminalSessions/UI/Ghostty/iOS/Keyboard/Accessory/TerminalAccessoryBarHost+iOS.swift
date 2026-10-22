import SwiftUI
import UIKit

/// Mounts a terminal's accessory bar inside the app layout. The bar is no
/// longer a UIKit input accessory, so it stays on screen independently of
/// the software keyboard, a hardware keyboard, or an input session.
struct TerminalAccessoryBarHost: UIViewRepresentable {
    let terminal: GhosttyTerminalView

    func makeUIView(context: Context) -> ContainerView {
        ContainerView()
    }

    func updateUIView(_ uiView: ContainerView, context: Context) {
        uiView.mount(terminal.accessoryBarView())
    }

    static func dismantleUIView(_ uiView: ContainerView, coordinator: ()) {
        uiView.mount(nil)
    }
}

extension TerminalAccessoryBarHost {
    /// One bar per terminal: switching the focused pane swaps the mounted bar
    /// so each pane keeps its own modifier state.
    final class ContainerView: UIView {
        private weak var mountedBar: UIView?

        func mount(_ bar: UIView?) {
            guard mountedBar !== bar || bar?.superview !== self else { return }
            if let mountedBar, mountedBar.superview === self {
                mountedBar.removeFromSuperview()
            }
            mountedBar = bar
            guard let bar else { return }
            bar.translatesAutoresizingMaskIntoConstraints = false
            addSubview(bar)
            NSLayoutConstraint.activate([
                bar.topAnchor.constraint(equalTo: topAnchor),
                bar.bottomAnchor.constraint(equalTo: bottomAnchor),
                bar.leadingAnchor.constraint(equalTo: leadingAnchor),
                bar.trailingAnchor.constraint(equalTo: trailingAnchor)
            ])
        }
    }
}
