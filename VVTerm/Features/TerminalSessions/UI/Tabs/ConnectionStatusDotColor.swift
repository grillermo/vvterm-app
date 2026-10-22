import SwiftUI

/// Status dot color shared by the terminal and active connection tab strips.
enum ConnectionStatusDotColor {
    static func color(for state: ConnectionState?) -> Color {
        switch state ?? .idle {
        case .connected:
            return .green
        case .connecting, .reconnecting:
            return .orange
        case .failed:
            return .red
        case .disconnected, .idle:
            return .secondary
        }
    }
}
