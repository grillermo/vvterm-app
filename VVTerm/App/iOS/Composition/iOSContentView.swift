//
//  iOSContentView.swift
//  VVTerm
//

import StoreKit
import SwiftUI

struct iOSContentView: View {
    /// Keeps one tab-open operation alive if its navigation route is popped and retried.
    private struct PendingConnection {
        let operationID: UUID
        let task: Task<TerminalTab, Error>
    }

    let fileTabs: RemoteFileTabManager
    let fileBrowser: RemoteFileBrowserStore
    let statsDependencies: ServerStatsScreenDependencies
    let terminalSecurityActions: TerminalSecurityActions
    let serverFormDependencies: ServerFormDependencies
    let analyticsOptOutAction: AnalyticsOptOutAction
    private let makeLocalDiscoveryManager: LocalSSHDiscoveryManagerFactory
    @ObservedObject private var serverManager: ServerManager
    @ObservedObject private var engagementTracker: EngagementTracker
    private let tabManager: TerminalTabManager
    @EnvironmentObject private var viewTabConfig: ViewTabConfigurationManager
    @Environment(\.requestReview) private var requestReview

    @State private var selectedWorkspace: Workspace?
    @State private var selectedEnvironment: ServerEnvironment?
    @State private var terminalRoute: ServerTerminalNavigationRoute?
    @State private var pendingConnections: [UUID: PendingConnection] = [:]

    init(
        serverManager: ServerManager,
        engagementTracker: EngagementTracker,
        tabManager: TerminalTabManager,
        fileTabs: RemoteFileTabManager,
        fileBrowser: RemoteFileBrowserStore,
        statsDependencies: ServerStatsScreenDependencies,
        terminalSecurityActions: TerminalSecurityActions,
        serverFormDependencies: ServerFormDependencies,
        makeLocalDiscoveryManager: @escaping LocalSSHDiscoveryManagerFactory,
        analyticsOptOutAction: AnalyticsOptOutAction
    ) {
        _serverManager = ObservedObject(wrappedValue: serverManager)
        _engagementTracker = ObservedObject(wrappedValue: engagementTracker)
        self.tabManager = tabManager
        self.fileTabs = fileTabs
        self.fileBrowser = fileBrowser
        self.statsDependencies = statsDependencies
        self.terminalSecurityActions = terminalSecurityActions
        self.serverFormDependencies = serverFormDependencies
        self.makeLocalDiscoveryManager = makeLocalDiscoveryManager
        self.analyticsOptOutAction = analyticsOptOutAction
    }

    private var preferredConnectView: ConnectionViewTabID {
        viewTabConfig.effectiveDefaultTab()
    }

    private var terminalPresentation: Binding<Bool> {
        Binding(
            get: { terminalRoute != nil },
            set: { isPresented in
                if !isPresented {
                    terminalRoute = nil
                }
            }
        )
    }

    private var navigationContent: some View {
        NavigationStack {
            ServerListScreen(
                serverManager: serverManager,
                tabManager: tabManager,
                fileTabs: fileTabs,
                fileBrowser: fileBrowser,
                statsDependencies: statsDependencies,
                analyticsOptOutAction: analyticsOptOutAction,
                serverFormDependencies: serverFormDependencies,
                makeLocalDiscoveryManager: makeLocalDiscoveryManager,
                selectedWorkspace: $selectedWorkspace,
                selectedEnvironment: $selectedEnvironment,
                onServerSelected: { server in
                    beginConnection(to: server)
                },
                onActiveConnectionSelected: { server in
                    terminalRoute = .active(serverId: server.id)
                }
            )
            .safeAreaInset(edge: .top, spacing: 0) {
                ServerLocalStorageNotice(serverManager: serverManager)
            }
            .navigationDestination(isPresented: terminalPresentation) {
                if let terminalRoute {
                    ServerTerminalRoute(
                        tabManager: tabManager,
                        serverManager: serverManager,
                        fileTabs: fileTabs,
                        fileBrowser: fileBrowser,
                        statsDependencies: statsDependencies,
                        terminalSecurityActions: terminalSecurityActions,
                        serverFormDependencies: serverFormDependencies,
                        analyticsOptOutAction: analyticsOptOutAction,
                        route: terminalRoute,
                        makeLocalDiscoveryManager: makeLocalDiscoveryManager,
                        onBack: { self.terminalRoute = nil },
                        onSelectActiveConnection: { server in
                            self.terminalRoute = .active(serverId: server.id)
                        }
                    )
                    // Each route owns per-server projections, so switching
                    // connections replaces the route instead of retargeting it.
                    .id(terminalRoute.serverId)
                }
            }
        }
        .navigationBarAppearance(backgroundColor: .clear, isTranslucent: true, shadowColor: .clear)
        .adaptiveSoftScrollEdges()
        .onAppear {
            reconcileWorkspaceSelection(serverManager.workspaces)
        }
        .onChange(of: serverManager.workspaces) { workspaces in
            reconcileWorkspaceSelection(workspaces)
        }
        .onChange(of: selectedWorkspace?.id) { _ in
            selectedEnvironment = WorkspaceSelectionPolicy.environment(
                current: selectedEnvironment,
                workspace: selectedWorkspace
            )
        }
        .onChange(of: terminalRoute?.serverId) { serverId in
            if serverId == nil {
                engagementTracker.noteTerminalSessionEnded(
                    otherTerminalsActive: false
                )
            }
        }
        .onChange(of: engagementTracker.reviewRequestToken) { _ in
            requestReview()
        }
    }

    var body: some View {
        navigationContent
    }

    private func reconcileWorkspaceSelection(_ workspaces: [Workspace]) {
        selectedWorkspace = WorkspaceSelectionPolicy.workspace(
            current: selectedWorkspace,
            available: workspaces
        )
        selectedEnvironment = WorkspaceSelectionPolicy.environment(
            current: selectedEnvironment,
            workspace: selectedWorkspace
        )
    }

    private func beginConnection(to server: Server) {
        guard terminalRoute == nil else { return }

        let attemptID = UUID()
        terminalRoute = .connecting(server: server, attemptID: attemptID)
        tabManager.sessionState.selectView(preferredConnectView, for: server.id)
        let pendingConnection = pendingConnection(for: server)

        Task {
            defer {
                finishPendingConnection(pendingConnection, for: server.id)
            }

            do {
                let tab = try await pendingConnection.task.value
                guard resolveConnection(for: attemptID, as: .succeeded) else {
                    return
                }
                tabManager.sessionState.selectView(preferredConnectView, for: server.id)
                tabManager.sessionState.selectTab(tab.id, for: server.id)
            } catch {
                resolveConnection(for: attemptID, as: .failed)
            }
        }
    }

    @discardableResult
    private func resolveConnection(
        for attemptID: UUID,
        as resolution: ServerTerminalNavigationRoute.ConnectionResolution
    ) -> Bool {
        guard let terminalRoute,
              terminalRoute.connectionAttemptID == attemptID else {
            return false
        }
        self.terminalRoute = terminalRoute.resolvingConnection(
            for: attemptID,
            as: resolution
        )
        return true
    }

    private func pendingConnection(for server: Server) -> PendingConnection {
        if let pendingConnection = pendingConnections[server.id] {
            return pendingConnection
        }

        let pendingConnection = PendingConnection(
            operationID: UUID(),
            task: Task {
                try await tabManager.openTab(for: server)
            }
        )
        pendingConnections[server.id] = pendingConnection
        return pendingConnection
    }

    private func finishPendingConnection(
        _ pendingConnection: PendingConnection,
        for serverID: UUID
    ) {
        guard let currentConnection = pendingConnections[serverID],
              currentConnection.operationID == pendingConnection.operationID else {
            return
        }
        pendingConnections.removeValue(forKey: serverID)
    }
}
