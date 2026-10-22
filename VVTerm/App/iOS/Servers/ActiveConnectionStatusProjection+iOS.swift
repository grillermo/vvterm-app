import Combine
import Foundation

/// Live connection state per active server for the connection tab strip.
/// Only the strip observes it, so status changes do not redraw route chrome.
@MainActor
final class ActiveConnectionStatusProjection: ObservableObject {
    @Published private(set) var statesByServer: [UUID: ConnectionState] = [:]

    private let sessionState: TerminalSessionStateStore
    private var trackedServerIds: [UUID] = []
    private var cancellables: [UUID: AnyCancellable] = [:]

    init(sessionState: TerminalSessionStateStore) {
        self.sessionState = sessionState
    }

    func track(serverIds: [UUID]) {
        guard serverIds != trackedServerIds else { return }
        trackedServerIds = serverIds
        let tracked = Set(serverIds)

        for serverId in cancellables.keys where !tracked.contains(serverId) {
            cancellables.removeValue(forKey: serverId)
            statesByServer.removeValue(forKey: serverId)
        }
        for serverId in serverIds where cancellables[serverId] == nil {
            cancellables[serverId] = sessionState.changes(for: serverId)
                .map {
                    ActiveConnectionStatusPolicy.representativeState(
                        tabs: $0.tabs,
                        connectionStatesByPane: $0.connectionStatesByPane
                    )
                }
                .removeDuplicates()
                .sink { [weak self] state in
                    self?.statesByServer[serverId] = state
                }
        }
    }
}
