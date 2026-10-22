import SwiftUI

struct ServerViewTabNavigationButton: View {
    let icon: String
    let action: () -> Void
    var help: String = ""

    @State private var isHovering = false

    var body: some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(.system(size: 11))
                .frame(width: 24, height: 24)
                .background(
                    isHovering ? Color.gray.opacity(0.3) : Color.clear,
                    in: Circle()
                )
        }
        .buttonStyle(.plain)
        .help(help)
    }
}

struct ServerViewNewTabButton: View {
    let help: String
    let action: () -> Void

    @State private var isHovering = false

    var body: some View {
        Button(action: action) {
            Image(systemName: "plus")
                .font(.system(size: 11))
                .frame(width: 24, height: 24)
                .background(
                    isHovering ? Color.gray.opacity(0.3) : Color.clear,
                    in: Circle()
                )
        }
        .buttonStyle(.plain)
        .help(Text(help))
    }
}

enum ServerViewTopTabBarMetrics {
    static let tabHeight: CGFloat = 36
    static let tabVerticalPadding: CGFloat = 7
    static let barVerticalInset: CGFloat = 4
    static let tabSpacing: CGFloat = 4
    static let horizontalPadding: CGFloat = 4
    static let outerHorizontalPadding: CGFloat = 12
    static var barHeight: CGFloat { tabHeight + barVerticalInset * 2 }
}
