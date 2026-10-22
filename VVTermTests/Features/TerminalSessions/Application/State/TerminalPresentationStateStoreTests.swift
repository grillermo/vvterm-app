import Foundation
import Testing
@testable import VVTerm

@MainActor
struct TerminalPresentationStateStoreTests {
    @Test
    func splitZoomIsEphemeralAndClearsWithItsTab() {
        let store = TerminalPresentationStateStore()
        let tabId = UUID()

        store.toggleSplitZoom(for: tabId)
        #expect(store.splitZoomedTabIds == [tabId])

        store.toggleSplitZoom(for: tabId)
        #expect(store.splitZoomedTabIds.isEmpty)

        store.toggleSplitZoom(for: tabId)
        store.removeTab(tabId)
        #expect(store.splitZoomedTabIds.isEmpty)
    }

    @Test
    func resetClearsTemporaryPresentationState() {
        let store = TerminalPresentationStateStore()
        store.toggleSplitZoom(for: UUID())
        let paneId = UUID()
        store.setTerminalFindNavigatorVisible(true, for: paneId)

        store.reset()

        #expect(store.splitZoomedTabIds.isEmpty)
        #expect(store.terminalFindNavigatorVisibleByPane.isEmpty)
    }

    @Test
    func paneCleanupRemovesFindPresentationState() {
        let store = TerminalPresentationStateStore()
        let paneId = UUID()

        store.setTerminalFindNavigatorVisible(true, for: paneId)
        #expect(store.terminalFindNavigatorVisibleByPane[paneId] == true)

        store.removePane(paneId)
        #expect(store.terminalFindNavigatorVisibleByPane[paneId] == nil)
    }

}
