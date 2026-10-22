import Foundation
import Combine
import Testing
@testable import VVTerm

extension TerminalTabManagerLifecycleTests {
    @Suite(.serialized)
    @MainActor
    struct Presentation: TerminalTabManagerTestSupport {
        @Test
        func toolbarProjectionSeparatesRouteTabTitleAndFocusedPaneInvalidation() async {
            await withCleanManager { manager in
                let observedTab = TerminalTab(serverId: UUID(), title: "Observed")
                let otherTab = TerminalTab(serverId: UUID(), title: "Other")
                installTab(observedTab, in: manager, connectionState: .connected)
                installTab(otherTab, in: manager, connectionState: .connected)
                let projection = TerminalServerToolbarProjection(
                    serverId: observedTab.serverId,
                    tabManager: manager
                )
                var contentUpdates = 0
                var tabStripUpdates = 0
                var focusedPaneUpdates = 0
                var routeUpdates = 0
                var cancellations = [
                    projection.objectWillChange.sink { routeUpdates += 1 },
                    projection.content.objectWillChange.sink { contentUpdates += 1 },
                    projection.tabStrip.objectWillChange.sink { tabStripUpdates += 1 }
                ]
                cancellations.append(
                    projection.focusedPane.objectWillChange.sink { focusedPaneUpdates += 1 }
                )
                defer {
                    cancellations.forEach { $0.cancel() }
                }

                manager.updatePaneWorkingDirectory(
                    observedTab.rootPaneId,
                    rawDirectory: "/tmp/output-metadata"
                )
                #expect(contentUpdates == 0)
                #expect(tabStripUpdates == 0)
                #expect(focusedPaneUpdates == 0)
                #expect(routeUpdates == 0)

                manager.updatePaneTitle(observedTab.rootPaneId, rawTitle: "Output title")
                #expect(contentUpdates == 0)
                #expect(tabStripUpdates == 1)
                #expect(projection.tabStrip.state.items.first?.title == "Output title")
                #expect(focusedPaneUpdates == 0)
                #expect(routeUpdates == 0)

                manager.updatePaneTitle(observedTab.rootPaneId, rawTitle: "Output title")
                manager.updatePaneTitle(otherTab.rootPaneId, rawTitle: "Other output title")
                #expect(contentUpdates == 0)
                #expect(tabStripUpdates == 1)
                #expect(focusedPaneUpdates == 0)
                #expect(routeUpdates == 0)

                manager.presentationState.setTerminalFindNavigatorVisible(true, for: otherTab.rootPaneId)
                #expect(focusedPaneUpdates == 0)
                #expect(routeUpdates == 0)

                manager.presentationState.setTerminalFindNavigatorVisible(true, for: observedTab.rootPaneId)
                #expect(focusedPaneUpdates == 1)
                #expect(routeUpdates == 1)
                #expect(projection.focusedPane.state.findNavigatorIsVisible)

                manager.presentationState.setTerminalFindNavigatorVisible(false, for: observedTab.rootPaneId)
                #expect(focusedPaneUpdates == 2)
                #expect(routeUpdates == 2)
                #expect(!projection.focusedPane.state.findNavigatorIsVisible)
            }
        }

        /// A new connection mounts its terminal after the route first renders.
        /// The accessory bar resolves that terminal from the focused-pane
        /// projection, so registering it must publish or the bar stays hidden.
        @Test
        func focusedPaneProjectionPublishesWhenItsSurfaceRegisters() async {
            await withCleanManager { manager in
                let tab = TerminalTab(serverId: UUID(), title: "New connection")
                let otherPaneId = UUID()
                installTab(tab, in: manager, connectionState: .connecting)
                let projection = TerminalServerToolbarProjection(
                    serverId: tab.serverId,
                    tabManager: manager
                )
                var focusedPaneUpdates = 0
                let cancellation = projection.focusedPane.objectWillChange.sink {
                    focusedPaneUpdates += 1
                }
                defer { cancellation.cancel() }
                #expect(projection.focusedPane.state.focusedSurfaceIdentity == nil)

                manager.terminalSurfaceStore.register(TerminalSurfaceStub(), for: otherPaneId)
                #expect(focusedPaneUpdates == 0)

                let surface = TerminalSurfaceStub()
                manager.terminalSurfaceStore.register(surface, for: tab.rootPaneId)
                #expect(focusedPaneUpdates == 1)
                #expect(projection.focusedPane.state.focusedSurfaceIdentity == ObjectIdentifier(surface))

                let replacement = TerminalSurfaceStub()
                manager.terminalSurfaceStore.register(replacement, for: tab.rootPaneId)
                #expect(focusedPaneUpdates == 2)
                #expect(projection.focusedPane.state.focusedSurfaceIdentity == ObjectIdentifier(replacement))

                manager.terminalSurfaceStore.remove(for: tab.rootPaneId) { _ in }
                #expect(focusedPaneUpdates == 3)
                #expect(projection.focusedPane.state.focusedSurfaceIdentity == nil)
            }
        }

        /// A tab attached to a session the user chose shows that session's name
        /// instead of the server name. Generated managed names stay hidden.
        @Test
        func tabTitleUsesChosenPersistentSessionName() async {
            await withCleanManager { manager in
                let tab = TerminalTab(serverId: UUID(), title: "macmini")
                installTab(tab, in: manager, connectionState: .connected)
                let projection = TerminalServerToolbarProjection(
                    serverId: tab.serverId,
                    tabManager: manager
                )
                @MainActor func stripTitle() -> String? { projection.tabStrip.state.items.first?.title }

                manager.remoteSessionCoordinator.setAttachment(
                    for: tab.rootPaneId,
                    identifier: remoteSessionIdentifier("vvterm-maci-d0123456789-s0123456"),
                    ownership: .managed
                )
                #expect(stripTitle() == "macmini")

                manager.remoteSessionCoordinator.setAttachment(
                    for: tab.rootPaneId,
                    identifier: remoteSessionIdentifier("vvterm-claude"),
                    ownership: .external
                )
                #expect(stripTitle() == "vvterm-claude")
                #expect(manager.titleStore.displayTitle(for: tab) == "vvterm-claude")

                manager.updatePaneTitle(tab.rootPaneId, rawTitle: "zsh")
                #expect(stripTitle() == "vvterm-claude")

                manager.setPaneTitleOverride("Renamed", for: tab.rootPaneId)
                #expect(stripTitle() == "Renamed")

                manager.setPaneTitleOverride(nil, for: tab.rootPaneId)
                manager.remoteSessionCoordinator.clearAttachmentState(for: tab.rootPaneId)
                #expect(stripTitle() == "zsh")
            }
        }

        /// A session started under a typed name is user-owned, so the tab shows
        /// that name and closing the tab must not kill it.
        @Test
        func namedSessionSelectionTitlesTabAndIsUserOwned() async throws {
            try await withCleanManager { manager in
                let tab = TerminalTab(serverId: UUID(), title: "macmini")
                installTab(tab, in: manager, connectionState: .connected)
                let projection = TerminalServerToolbarProjection(
                    serverId: tab.serverId,
                    tabManager: manager
                )

                try manager.remoteSessionCoordinator.resolver.updateAttachmentState(
                    for: tab.rootPaneId,
                    serverID: tab.serverId,
                    backendIdentifier: .tmux,
                    selection: .createNamed(remoteSessionIdentifier("my-work"))
                )

                let attachment = manager.remoteSessionCoordinator.attachment(for: tab.rootPaneId)
                #expect(attachment?.attachment.ownership == .external)
                #expect(attachment?.attachment.identifier.rawValue == "my-work")
                #expect(projection.tabStrip.state.items.first?.title == "my-work")
            }
        }

        @Test
        func connectionAttemptUpdatesOnlyTheTabStripProjection() async {
            await withCleanManager { manager in
                let tab = TerminalTab(serverId: UUID(), title: "Connecting")
                installTab(tab, in: manager, connectionState: .connecting)
                let projection = TerminalServerToolbarProjection(
                    serverId: tab.serverId,
                    tabManager: manager
                )
                var routeUpdates = 0
                var contentUpdates = 0
                var tabStripUpdates = 0
                let cancellations = [
                    projection.objectWillChange.sink { routeUpdates += 1 },
                    projection.content.objectWillChange.sink { contentUpdates += 1 },
                    projection.tabStrip.objectWillChange.sink { tabStripUpdates += 1 }
                ]
                defer { cancellations.forEach { $0.cancel() } }

                manager.updatePaneState(tab.rootPaneId, connectionState: .reconnecting(attempt: 2))

                #expect(routeUpdates == 0)
                #expect(contentUpdates == 0)
                #expect(tabStripUpdates == 1)
            }
        }
    }
}
