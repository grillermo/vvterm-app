import Combine
import Foundation

/// Owns temporary terminal presentation choices and observed presentation facts.
/// This state is local to the current process and is not persisted.
@MainActor
final class TerminalPresentationStateStore: ObservableObject {
    @Published private(set) var splitZoomedTabIds: Set<UUID> = []

    @Published private(set) var terminalFindNavigatorVisibleByPane: [UUID: Bool] = [:]

    func toggleSplitZoom(for tabId: UUID) {
        if splitZoomedTabIds.contains(tabId) {
            splitZoomedTabIds.remove(tabId)
        } else {
            splitZoomedTabIds.insert(tabId)
        }
    }

    func removeTab(_ tabId: UUID) {
        splitZoomedTabIds.remove(tabId)
    }

    func setTerminalFindNavigatorVisible(_ isVisible: Bool, for paneId: UUID) {
        guard terminalFindNavigatorVisibleByPane[paneId] != isVisible else { return }
        terminalFindNavigatorVisibleByPane[paneId] = isVisible
    }

    func removePane(_ paneId: UUID) {
        terminalFindNavigatorVisibleByPane.removeValue(forKey: paneId)
    }

    #if DEBUG
    func reset() {
        splitZoomedTabIds.removeAll()
        terminalFindNavigatorVisibleByPane.removeAll()
    }
    #endif
}
