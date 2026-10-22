//
//  ServerTerminalRoute+iOS.swift
//  VVTerm
//

import SwiftUI

import UIKit

// MARK: - Server Terminal Route

struct ServerTerminalRoute: View {
    private enum PresentedRouteSheet: Hashable, Identifiable {
        case settings
        case serverForm(ServerFormIntent)

        var id: Self { self }
    }

    let tabManager: TerminalTabManager
    @ObservedObject var serverManager: ServerManager
    @ObservedObject var fileTabs: RemoteFileTabManager
    let fileBrowser: RemoteFileBrowserStore
    let statsDependencies: ServerStatsScreenDependencies
    let terminalSecurityActions: TerminalSecurityActions
    let serverFormDependencies: ServerFormDependencies
    let analyticsOptOutAction: AnalyticsOptOutAction
    let route: ServerTerminalNavigationRoute
    let onBack: () -> Void
    let onSelectActiveConnection: (Server) -> Void
    let makeLocalDiscoveryManager: LocalSSHDiscoveryManagerFactory

    @ObservedObject private var keyboardCoordinator: TerminalKeyboardCoordinator
    @StateObject private var toolbarProjection: TerminalServerToolbarProjection
    @EnvironmentObject private var viewTabConfig: ViewTabConfigurationManager
    @EnvironmentObject private var appLockManager: AppLockManager
    @EnvironmentObject private var screenAwakeCoordinator: TerminalScreenAwakeCoordinator

    @State private var isRouteVisible = false
    @State private var screenAwakeRequestID = UUID()
    @State private var presentedRouteSheet: PresentedRouteSheet?
    @State private var isTerminalChildModalPresented = false
    @State private var terminalServerIds: Set<UUID> = []
    @State private var pendingDisconnectServer: Server?
    /// Set once this route gives keyboard ownership to another connection's
    /// route. The replacement route can appear before this one disappears, so
    /// teardown must not clear the input state that route now owns.
    @State private var hasHandedOffToConnection = false
    @AppStorage(PrivacyModeSettings.enabledKey) private var privacyModeEnabled = false
    @AppStorage(TerminalDefaults.keepScreenAwakeKey) private var keepScreenAwakeEnabled = TerminalDefaults.defaultKeepScreenAwake
    @AppStorage(TerminalDefaults.accessoryBarVisibleKey)
    private var accessoryBarVisible = TerminalDefaults.defaultAccessoryBarVisible
    @Environment(\.scenePhase) private var scenePhase

    init(
        tabManager: TerminalTabManager,
        serverManager: ServerManager,
        fileTabs: RemoteFileTabManager,
        fileBrowser: RemoteFileBrowserStore,
        statsDependencies: ServerStatsScreenDependencies,
        terminalSecurityActions: TerminalSecurityActions,
        serverFormDependencies: ServerFormDependencies,
        analyticsOptOutAction: AnalyticsOptOutAction,
        route: ServerTerminalNavigationRoute,
        makeLocalDiscoveryManager: @escaping LocalSSHDiscoveryManagerFactory,
        onBack: @escaping () -> Void,
        onSelectActiveConnection: @escaping (Server) -> Void
    ) {
        self.tabManager = tabManager
        self.serverManager = serverManager
        self.fileTabs = fileTabs
        self.fileBrowser = fileBrowser
        self.statsDependencies = statsDependencies
        self.terminalSecurityActions = terminalSecurityActions
        self.serverFormDependencies = serverFormDependencies
        self.analyticsOptOutAction = analyticsOptOutAction
        self.route = route
        self.makeLocalDiscoveryManager = makeLocalDiscoveryManager
        self.onBack = onBack
        self.onSelectActiveConnection = onSelectActiveConnection
        self._keyboardCoordinator = ObservedObject(wrappedValue: tabManager.keyboardCoordinator)
        let toolbarProjection = TerminalServerToolbarProjection(
            serverId: route.serverId,
            tabManager: tabManager
        )
        self._toolbarProjection = StateObject(wrappedValue: toolbarProjection)
    }

    private var terminalContent: TerminalServerContentProjection {
        toolbarProjection.content
    }

    private var focusedPane: TerminalServerFocusedPaneProjection {
        toolbarProjection.focusedPane
    }

    private var selectedServer: Server? {
        if let server = serverManager.servers.first(where: { $0.id == route.serverId }) {
            return server
        }
        return route.connectingServer
    }

    private var selectedView: ConnectionViewTabID {
        guard selectedServer != nil else {
            return viewTabConfig.effectiveDefaultTab()
        }
        return viewTabConfig.effectiveView(for: terminalContent.state.selectedView)
    }

    private var selectedTab: TerminalTab? {
        guard let selectedTabId = terminalContent.state.selectedTabId else { return nil }
        return terminalContent.state.tabs.first { $0.id == selectedTabId }
    }

    private var selectedFileTab: RemoteFileTab? {
        guard let server = selectedServer else { return nil }
        return fileTabs.selectedTab(for: server.id)
    }

    private var focusedTerminal: GhosttyTerminalView? {
        guard let paneId = selectedTab?.focusedPaneId else { return nil }
        return tabManager.terminalSurfaceStore.ghosttySurface(for: paneId)
    }

    private var focusedPaneId: UUID? {
        selectedTab?.focusedPaneId
    }

    private var hasNavigationContext: Bool {
        route.isConnecting
            || !terminalContent.state.tabs.isEmpty
            || !fileTabs.tabs(for: route.serverId).isEmpty
    }

    private var activeConnectionOptions: [ActiveConnectionSwitcherOption] {
        ActiveConnectionSwitcherPolicy.options(
            currentServerId: route.serverId,
            activeServerIds: terminalServerIds.union(
                fileTabs.tabsByServer.compactMap { $0.value.isEmpty ? nil : $0.key }
            ),
            servers: serverManager.servers
        )
    }

    private var isFocusedTerminalFindNavigatorVisible: Bool {
        focusedPane.state.findNavigatorIsVisible
    }

    var body: some View {
        content
            .navigationBarBackButtonHidden(true)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { navigationToolbar }
            .alert(
                pendingDisconnectServer?.name ?? "",
                isPresented: Binding(
                    get: { pendingDisconnectServer != nil },
                    set: { isPresented in
                        guard !isPresented else { return }
                        pendingDisconnectServer = nil
                        updateTerminalRouteActivation()
                    }
                ),
                presenting: pendingDisconnectServer
            ) { server in
                Button("Cancel", role: .cancel) {}
                Button(String(localized: "Disconnect"), role: .destructive) {
                    disconnect(server)
                }
            } message: { _ in
                Text(String(localized: "All terminal and file tabs for this server will be closed."))
            }
            .sheet(item: $presentedRouteSheet, onDismiss: updateTerminalRouteActivation) { sheet in
                switch sheet {
                case .settings:
                    SettingsView(
                        statsPreferencesStore: statsDependencies.preferencesStore,
                        analyticsOptOutAction: analyticsOptOutAction,
                        remoteSessionBackends: tabManager.remoteSessionCoordinator.backendMetadata
                    )
                        .modifier(AppearanceModifier())
                        .adaptiveSoftScrollEdges()
                case .serverForm(let intent):
                    NavigationStack {
                        ServerFormSheet(
                            serverManager: serverManager,
                            workspace: intent.sourceServer.flatMap { sourceServer in
                                serverManager.workspaces.first { $0.id == sourceServer.workspaceId }
                            },
                            intent: intent,
                            dependencies: serverFormDependencies,
                            makeLocalDiscoveryManager: makeLocalDiscoveryManager,
                            onSave: { _ in presentedRouteSheet = nil }
                        )
                    }
                    .adaptiveSoftScrollEdges()
                }
            }
            .onAppear {
                isRouteVisible = true
                dismissIfContextEnded()
                updateTerminalRouteActivation()
            }
            .onDisappear {
                isRouteVisible = false
                tabManager.reconnectCoordinator.invalidatePreparations(forServer: route.serverId)
                if !hasHandedOffToConnection {
                    keyboardCoordinator.setViewActive(false)
                    keyboardCoordinator.setActivePane(nil)
                }
                screenAwakeCoordinator.update(isRequested: false, for: screenAwakeRequestID)
            }
            .onChange(of: selectedView) { _ in
                updateTerminalRouteActivation()
            }
            .onChange(of: selectedTab?.id) { _ in
                updateTerminalRouteActivation()
            }
            .onChange(of: focusedPaneId) { _ in
                updateTerminalRouteActivation()
            }
            .onReceive(tabManager.terminalSurfaceStore.changes) { _ in
                updateTerminalRouteActivation()
            }
            .onChange(of: terminalContent.state.tabs) { _ in
                dismissIfContextEnded()
                updateTerminalRouteActivation()
            }
            .onReceive(tabManager.sessionState.navigationChanges) { navigationState in
                terminalServerIds = Set(navigationState.tabCountsByServer.keys)
            }
            .onChange(of: fileTabs.tabsByServer) { _ in
                dismissIfContextEnded()
                updateTerminalRouteActivation()
            }
            .onChange(of: scenePhase) { _ in
                updateTerminalRouteActivation()
            }
            .onChange(of: isContentObscured) { _ in
                updateTerminalRouteActivation()
            }
            .onChange(of: keepScreenAwakeEnabled) { _ in
                updateTerminalRouteActivation()
            }
            .onPreferenceChange(TerminalRouteModalPresentationPreferenceKey.self) {
                updateTerminalChildModalPresentation($0)
            }
            .onReceive(NotificationCenter.default.publisher(for: UIScene.didActivateNotification)) { notification in
                handleSceneDidActivate(notification)
            }
            .onReceive(NotificationCenter.default.publisher(for: UIScene.willDeactivateNotification)) { notification in
                handleSceneWillDeactivate(notification)
            }
            .onReceive(NotificationCenter.default.publisher(for: UIWindow.didBecomeKeyNotification)) { notification in
                handleTerminalWindowKeyChange(notification)
            }
            .onReceive(NotificationCenter.default.publisher(for: UIWindow.didResignKeyNotification)) { notification in
                handleTerminalWindowKeyChange(notification)
            }
            .onChange(of: isFocusedTerminalFindNavigatorVisible) { _ in
                updateTerminalRouteActivation()
            }
    }

    @ViewBuilder
    private var content: some View {
        if let server = selectedServer {
            ConnectionTerminalContainer(
                tabManager: tabManager,
                terminalToolbarProjection: toolbarProjection,
                fileTabManager: fileTabs,
                fileBrowser: fileBrowser,
                statsDependencies: statsDependencies,
                terminalSecurityActions: terminalSecurityActions,
                server: server,
                isSidebarVisible: false,
                onToggleSidebar: {}
            )
            .navigationTitle(server.name)
        } else if route.isConnecting {
            connectingStateView(
                serverName: route.connectingServer?.name ?? String(localized: "Server")
            )
        } else {
            TerminalEmptyStateView(server: nil) {
                leaveRoute()
            }
        }
    }

    @ToolbarContentBuilder
    private var navigationToolbar: some ToolbarContent {
        ToolbarItem(placement: .navigationBarLeading) {
            Button {
                leaveRoute()
            } label: {
                Image(systemName: "chevron.left")
            }
            .accessibilityIdentifier("vvterm.terminal.back")
        }

        if selectedServer != nil, !activeConnectionOptions.isEmpty {
            activeConnectionStripItem
        } else if let server = selectedServer {
            ToolbarItem(placement: .principal) {
                HStack(spacing: 7) {
                    ServerIconView(server: server, size: 19)
                    Text(server.name)
                        .font(.headline)
                        .lineLimit(1)
                }
            }
        }

        ToolbarItemGroup(placement: .navigationBarTrailing) {
            if let server = selectedServer, selectedView == .terminal {
                Button {
                    openNewTab(for: server)
                } label: {
                    Image(systemName: "plus")
                }
                .accessibilityIdentifier("vvterm.terminal.newTab")
            }

            if let server = selectedServer, selectedView == .files {
                Button {
                    openNewFileTab(for: server)
                } label: {
                    Image(systemName: "plus")
                }
            }

            Menu {
                if let server = selectedServer {
                    if viewTabConfig.currentVisibleTabs.count > 1 {
                        Picker(selection: selectedViewBinding(for: server.id)) {
                            ForEach(viewTabConfig.currentVisibleTabs) { tab in
                                Label(LocalizedStringKey(tab.localizedKey), systemImage: tab.icon)
                                    .tag(tab)
                            }
                        } label: {
                            Label("View", systemImage: selectedView.icon)
                        }
                        .pickerStyle(.menu)
                        .accessibilityIdentifier("vvterm.terminal.viewPicker")

                        Divider()
                    }

                    if selectedView == .terminal {
                        Button {
                            focusedTerminal?.showFindNavigator()
                        } label: {
                            Label("Find", systemImage: "magnifyingglass")
                        }

                        Button {
                            showKeyboardForFocusedTerminal()
                        } label: {
                            Label("Keyboard", systemImage: "keyboard")
                        }

                        Toggle(isOn: $accessoryBarVisible) {
                            Label("Accessory Bar", systemImage: "keyboard.badge.ellipsis")
                        }
                        .accessibilityIdentifier("vvterm.terminal.accessoryBarToggle")

                        Divider()
                    }

                    Button {
                        presentRouteSheet(.serverForm(.edit(server)))
                    } label: {
                        Label("Edit Server", systemImage: "pencil")
                    }

                    Button {
                        presentRouteSheet(.serverForm(.duplicate(server)))
                    } label: {
                        Label("Duplicate", systemImage: "plus.square.on.square")
                    }
                    .accessibilityIdentifier("vvterm.terminal.duplicateServer")

                    Button {
                        presentRouteSheet(.settings)
                    } label: {
                        Label("Settings", systemImage: "gear")
                    }
                    .accessibilityIdentifier("vvterm.terminal.settings")

                    Divider()

                    Button(role: .destructive) {
                        disconnect(server)
                    } label: {
                        Label("Disconnect", systemImage: "xmark.circle")
                    }
                } else {
                    Button {
                        presentRouteSheet(.settings)
                    } label: {
                        Label("Settings", systemImage: "gear")
                    }
                    .accessibilityIdentifier("vvterm.terminal.settings")
                }
            } label: {
                Image(systemName: "ellipsis.circle")
            }
            .accessibilityIdentifier("vvterm.terminal.moreMenu")
        }
    }

    /// The strip draws its own capsule, so on iOS 26 it opts out of the
    /// toolbar's shared glass pill.
    @ToolbarContentBuilder
    private var activeConnectionStripItem: some ToolbarContent {
        if #available(iOS 26.0, *) {
            ToolbarItem(placement: .principal) {
                activeConnectionStrip
            }
            .sharedBackgroundVisibility(.hidden)
        } else {
            ToolbarItem(placement: .principal) {
                activeConnectionStrip
            }
        }
    }

    private var activeConnectionStrip: some View {
        ActiveConnectionTabStrip(
            options: activeConnectionOptions,
            selectedServerId: route.serverId,
            sessionState: tabManager.sessionState,
            onSelect: switchToActiveConnection,
            onClose: requestDisconnect
        )
    }

    private func selectedViewBinding(for serverId: UUID) -> Binding<ConnectionViewTabID> {
        Binding(
            get: {
                viewTabConfig.effectiveView(
                    for: tabManager.connectionViewSelections.selection(for: serverId)
                )
            },
            set: { newValue in
                tabManager.sessionState.selectView(viewTabConfig.effectiveView(for: newValue), for: serverId)
            }
        )
    }

    /// Prefer the terminal's own UIKit scene because SwiftUI's scenePhase can
    /// lag under iPhone Mirroring and another foreground scene must not make
    /// this route appear active.
    private var terminalSceneActivation: TerminalKeyboardRouteActivationPolicy.SceneActivation {
        if let activationState = focusedTerminal?.window?.windowScene?.activationState {
            switch activationState {
            case .foregroundActive:
                return .foregroundActive
            case .foregroundInactive:
                return .foregroundInactive
            case .background, .unattached:
                return .background
            @unknown default:
                return .background
            }
        }

        switch scenePhase {
        case .active:
            return .foregroundActive
        case .inactive:
            return .foregroundInactive
        case .background:
            return .background
        @unknown default:
            return .background
        }
    }

    private var isContentObscured: Bool {
        let terminalSceneIsActive: Bool
        switch terminalSceneActivation {
        case .foregroundActive:
            terminalSceneIsActive = true
        case .foregroundInactive, .background:
            terminalSceneIsActive = false
        }
        return AppContentProtectionPolicy.shouldObscureContent(
            sceneIsActive: terminalSceneIsActive,
            fullAppLockEnabled: appLockManager.fullAppLockEnabled,
            privacyModeEnabled: privacyModeEnabled,
            isAppLocked: appLockManager.isAppLocked
        )
    }

    private var keyboardPresentationOwnership: TerminalKeyboardRouteActivationPolicy.PresentationOwnership {
        presentedRouteSheet == nil && pendingDisconnectServer == nil && !isTerminalChildModalPresented
            ? .terminal
            : .routeModal
    }

    private func updateTerminalChildModalPresentation(_ isPresented: Bool) {
        guard isTerminalChildModalPresented != isPresented else { return }
        isTerminalChildModalPresented = isPresented
        if isPresented {
            keyboardCoordinator.deactivateInputImmediately(reason: .routeModal)
        } else {
            updateTerminalRouteActivation()
        }
    }

    private var screenAwakeSceneIsInBackground: Bool {
        switch terminalSceneActivation {
        case .foregroundActive, .foregroundInactive:
            false
        case .background:
            true
        }
    }

    private func handleSceneWillDeactivate(_ notification: Notification) {
        if let notifyingScene = notification.object as? UIScene,
           let terminalScene = focusedTerminal?.window?.windowScene,
           notifyingScene !== terminalScene {
            return
        }

        // Freeze the current grid before UIKit removes the software keyboard
        // and expands the terminal layout during the app-switch transition.
        focusedTerminal?.pauseRendering(
            preservingForegroundKeyboardGrid: keyboardCoordinator.softwareKeyboardEndFrame != nil
        )

        if AppContentProtectionPolicy.shouldPrepareForSceneDeactivation(
            fullAppLockEnabled: appLockManager.fullAppLockEnabled,
            privacyModeEnabled: privacyModeEnabled,
            isAppLocked: appLockManager.isAppLocked
        ) {
            keyboardCoordinator.deactivateInputImmediately()
        } else {
            if let focusedPaneId {
                keyboardCoordinator.activeTerminalSceneWillDeactivate(for: focusedPaneId)
            }
            updateTerminalRouteActivation()
        }
    }

    private func handleSceneDidActivate(_ notification: Notification) {
        guard let notifyingScene = notification.object as? UIScene,
              let terminal = focusedTerminal,
              notifyingScene === terminal.window?.windowScene else {
            return
        }

        updateTerminalRouteActivation()
        guard let focusedPaneId else { return }
        keyboardCoordinator.activeTerminalSceneDidActivate(for: focusedPaneId)
    }

    private func handleTerminalWindowKeyChange(_ notification: Notification) {
        guard let notifyingWindow = notification.object as? UIWindow,
              notifyingWindow === focusedTerminal?.window else {
            return
        }
        updateTerminalRouteActivation()
        if notifyingWindow.isKeyWindow, let focusedPaneId {
            keyboardCoordinator.activeTerminalWindowDidBecomeKey(for: focusedPaneId)
        }
    }

    private func updateTerminalRouteActivation() {
        let presentationOwnership = keyboardPresentationOwnership
        let effect = TerminalKeyboardRouteActivationPolicy.effect(
            routeVisible: isRouteVisible,
            terminalSelected: selectedView == .terminal,
            sceneActivation: terminalSceneActivation,
            windowOwnership: focusedTerminal?.window.map {
                $0.isKeyWindow ? .key : .notKey
            } ?? .unknown,
            presentationOwnership: presentationOwnership,
            contentObscured: isContentObscured
        )

        screenAwakeCoordinator.update(
            isRequested: TerminalScreenAwakeCoordinator.shouldRequest(
                preferenceEnabled: keepScreenAwakeEnabled,
                routeVisible: isRouteVisible,
                terminalSelected: selectedView == .terminal,
                sceneIsInBackground: screenAwakeSceneIsInBackground
            ),
            for: screenAwakeRequestID
        )

        if effect == .suspend {
            if let focusedPaneId {
                keyboardCoordinator.activeTerminalSceneWillDeactivate(for: focusedPaneId)
            }
            return
        }

        if effect == .deactivate {
            if isContentObscured {
                keyboardCoordinator.deactivateInputImmediately()
                return
            }
            if presentationOwnership == .routeModal {
                keyboardCoordinator.deactivateInputImmediately(reason: .routeModal)
                return
            }
        }

        let activePaneId = effect == .activate ? focusedPaneId : nil

        keyboardCoordinator.setActivePane(activePaneId)
        keyboardCoordinator.setViewActive(effect == .activate)
        if let activePaneId {
            keyboardCoordinator.setFindNavigatorActive(
                isFocusedTerminalFindNavigatorVisible,
                for: activePaneId
            )
            if keyboardCoordinator.contentProtectionRecoveryIsPending(for: activePaneId),
               let terminal = focusedTerminal {
                terminal.resumeRendering()
                keyboardCoordinator.activeTerminalContentDidBecomeVisible(for: activePaneId)
            }
        }
    }

    private func dismissIfContextEnded() {
        guard !hasNavigationContext else { return }
        leaveRoute()
    }

    private func leaveRoute() {
        tabManager.reconnectCoordinator.invalidatePreparations(forServer: route.serverId)
        keyboardCoordinator.relinquishRouteOwnershipForNavigation()
        onBack()
    }

    private func switchToActiveConnection(_ serverId: UUID) {
        guard serverId != route.serverId else { return }
        Task {
            guard let server = serverManager.servers.first(where: { $0.id == serverId }),
                  await appLockManager.ensureServerUnlocked(server),
                  isRouteVisible,
                  let connection = ActiveServerSummary.makeAll(
                      tabManager: tabManager,
                      fileTabs: fileTabs,
                      server: { id in serverManager.servers.first { $0.id == id } },
                      viewTabConfig: viewTabConfig
                  ).first(where: { $0.id == serverId }) else {
                return
            }

            if let tab = connection.terminalTab {
                tabManager.sessionState.selectTab(tab.id, for: serverId)
            }
            tabManager.sessionState.selectView(connection.targetView, for: serverId)
            hasHandedOffToConnection = true
            tabManager.reconnectCoordinator.invalidatePreparations(forServer: route.serverId)
            keyboardCoordinator.relinquishRouteOwnershipForNavigation()
            onSelectActiveConnection(server)
        }
    }

    private func presentRouteSheet(_ sheet: PresentedRouteSheet) {
        keyboardCoordinator.deactivateInputImmediately(reason: .routeModal)
        presentedRouteSheet = sheet
    }

    private func showKeyboardForFocusedTerminal() {
        guard selectedView == .terminal else { return }
        keyboardCoordinator.userRequestedShow()
        focusedTerminal?.dismissFindNavigator()
    }

    private func openNewTab(for server: Server) {
        Task {
            do {
                let tab = try await tabManager.openTab(for: server)
                tabManager.sessionState.selectView(viewTabConfig.effectiveView(for: .terminal), for: server.id)
                tabManager.sessionState.selectTab(tab.id, for: server.id)
            } catch {
                // No-op: user cancelled biometric auth or open failed.
            }
        }
    }

    private func openNewFileTab(for server: Server) {
        let sourceTab = selectedFileTab
        let seedPath = sourceTab.flatMap { fileBrowser.lastVisitedPath(for: $0) }
            ?? selectedTab.flatMap {
                tabManager.sessionState.paneState(for: $0.focusedPaneId)?.workingDirectory
            }
        let newTab = sourceTab.flatMap {
            fileTabs.duplicateTab(
                $0,
                seedPath: seedPath,
                hasProAccess: ProAccess.isUnlocked
            )
        } ?? fileTabs.openTab(
            for: server,
            seedPath: seedPath,
            hasProAccess: ProAccess.isUnlocked
        )

        guard let newTab else { return }
        fileBrowser.prepareNewTab(newTab, duplicating: sourceTab)
        tabManager.sessionState.selectView(viewTabConfig.effectiveView(for: .files), for: server.id)
    }

    private func requestDisconnect(_ serverId: UUID) {
        guard let server = serverManager.servers.first(where: { $0.id == serverId }) else { return }
        keyboardCoordinator.deactivateInputImmediately(reason: .routeModal)
        pendingDisconnectServer = server
    }

    private func disconnect(_ server: Server) {
        fileBrowser.disconnect(serverId: server.id)
        fileTabs.disconnect(serverId: server.id)
        tabManager.disconnectServer(server.id)
        dismissIfContextEnded()
    }

    @ViewBuilder
    private func connectingStateView(serverName: String) -> some View {
        BlockingStatusView(showsScrim: false) {
            VStack(spacing: 12) {
                ProgressView()
                    .progressViewStyle(.circular)
                    .scaleEffect(1.1)
                Text(String(format: String(localized: "Connecting to %@..."), serverName))
                    .font(.headline)
                Text(String(localized: "Preparing server details..."))
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
