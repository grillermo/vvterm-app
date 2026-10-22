import Foundation

/// Picks the connection state that represents a whole server: its healthiest
/// pane, so one connected pane marks the server connected even while another
/// pane reconnects.
enum ActiveConnectionStatusPolicy {
    static func representativeState(
        tabs: [TerminalTab],
        connectionStatesByPane: [UUID: ConnectionState]
    ) -> ConnectionState? {
        tabs
            .flatMap(orderedPaneIds(for:))
            .compactMap { connectionStatesByPane[$0] }
            .min { rank($0) < rank($1) }
    }

    /// Focused pane first, so it wins ties between equally healthy panes.
    static func orderedPaneIds(for tab: TerminalTab) -> [UUID] {
        var paneIds = [tab.focusedPaneId, tab.rootPaneId]
        paneIds.append(contentsOf: tab.allPaneIds)
        return paneIds.reduce(into: []) { uniquePaneIds, paneId in
            if !uniquePaneIds.contains(paneId) {
                uniquePaneIds.append(paneId)
            }
        }
    }

    static func rank(_ state: ConnectionState) -> Int {
        switch state {
        case .connected:
            return 0
        case .connecting, .reconnecting:
            return 1
        case .failed:
            return 2
        case .disconnected:
            return 3
        case .idle:
            return 4
        }
    }
}
