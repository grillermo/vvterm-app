import Foundation
import SwiftUI
import Testing
import UIKit
@testable import VVTerm

@MainActor
private final class StatusSnapshotMemory: TerminalTabSnapshotStoring {
    func loadSnapshotData() -> Data? { nil }
    func saveSnapshotData(_ data: Data) {}
    func removeSnapshotData() {}
}

@Suite(.serialized)
@MainActor
struct ActiveConnectionStatusTests {
    @Test
    func healthiestPaneRepresentsTheServer() {
        let serverId = UUID()
        let first = TerminalTab(serverId: serverId, title: "one")
        let second = TerminalTab(serverId: serverId, title: "two")

        let state = ActiveConnectionStatusPolicy.representativeState(
            tabs: [first, second],
            connectionStatesByPane: [
                first.rootPaneId: .reconnecting(attempt: 2),
                second.rootPaneId: .connected,
            ]
        )

        #expect(state == .connected)
    }

    @Test
    func serverWithoutTerminalPanesHasNoState() {
        #expect(
            ActiveConnectionStatusPolicy.representativeState(
                tabs: [],
                connectionStatesByPane: [:]
            ) == nil
        )
    }

    @Test
    func projectionPublishesEachTrackedServersLiveState() {
        let store = makeStore()
        let tab = TerminalTab(serverId: UUID(), title: "one")
        var pane = TerminalPaneState(paneId: tab.rootPaneId, tabId: tab.id, serverId: tab.serverId)
        pane.connectionState = .connecting
        store.install(tab, paneState: pane, select: true)
        let projection = ActiveConnectionStatusProjection(sessionState: store)

        projection.track(serverIds: [tab.serverId])
        #expect(projection.statesByServer[tab.serverId] == .connecting)

        store.updatePane(tab.rootPaneId) { $0.connectionState = .connected }
        #expect(projection.statesByServer[tab.serverId] == .connected)

        projection.track(serverIds: [])
        #expect(projection.statesByServer.isEmpty)
    }

    /// The principal toolbar item is sized from its ideal width; without an
    /// explicit one the strip collapsed to a sliver between the bar buttons.
    @Test
    func stripFillsTheNavigationBarBetweenItsButtons() async throws {
        let options = ["immunemac", "macmini", "Pc"].map {
            ActiveConnectionSwitcherOption(id: UUID(), title: $0)
        }
        let view = NavigationStack {
            Color.clear
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .navigationBarLeading) {
                        Button {} label: { Image(systemName: "chevron.left") }
                    }
                    ToolbarItem(placement: .principal) {
                        ActiveConnectionTabStrip(
                            options: options,
                            selectedServerId: options[1].id,
                            sessionState: makeStore(),
                            onSelect: { _ in },
                            onClose: { _ in }
                        )
                    }
                    ToolbarItemGroup(placement: .navigationBarTrailing) {
                        Button {} label: { Image(systemName: "plus") }
                        Button {} label: { Image(systemName: "ellipsis.circle") }
                    }
                }
        }
        let scene = try #require(
            UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first
        )
        let window = UIWindow(windowScene: scene)
        window.frame = CGRect(x: 0, y: 0, width: 390, height: 300)
        window.rootViewController = UIHostingController(rootView: view)
        window.makeKeyAndVisible()
        defer { window.isHidden = true }

        var stripWidth: CGFloat = 0
        for _ in 0..<20 where stripWidth < 150 {
            try await Task.sleep(for: .milliseconds(100))
            window.layoutIfNeeded()
            stripWidth = Self.scrollViews(in: window).map(\.bounds.width).max() ?? 0
        }

        #expect(stripWidth >= 150)
    }

    private func makeStore() -> TerminalSessionStateStore {
        TerminalSessionStateStore(
            snapshotStore: StatusSnapshotMemory(),
            connectionViewSelections: ConnectionViewSelectionStore(),
            remoteSessionResolver: RemoteSessionAttachResolver(
                configuration: .testing,
                remoteSessions: UnavailableTerminalRemoteSessionService()
            )
        )
    }

    private static func scrollViews(in view: UIView) -> [UIScrollView] {
        let own = (view as? UIScrollView).map { [$0] } ?? []
        return own + view.subviews.flatMap(scrollViews(in:))
    }
}
