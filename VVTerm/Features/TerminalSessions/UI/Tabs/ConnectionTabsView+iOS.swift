import SwiftUI

private struct TerminalKeyboardSafeAreaHost<Content: View>: View {
    @AppStorage(TerminalDefaults.preserveTerminalSizeForKeyboardKey)
    private var preservesTerminalSizeForKeyboard = false

    let isTerminalSelected: Bool
    let content: Content

    init(
        isTerminalSelected: Bool,
        @ViewBuilder content: () -> Content
    ) {
        self.isTerminalSelected = isTerminalSelected
        self.content = content()
    }

    var body: some View {
        content.modifier(
            TerminalKeyboardSafeAreaModifier(
                isEnabled: preservesTerminalSizeForKeyboard && isTerminalSelected
            )
        )
    }
}

private struct TerminalAccessoryBarRouteLayout<Content: View>: View {
    @AppStorage(TerminalDefaults.accessoryBarVisibleKey)
    private var isEnabled = TerminalDefaults.defaultAccessoryBarVisible
    @ObservedObject private var focusedPane: TerminalServerFocusedPaneProjection

    let isTerminalSelected: Bool
    /// Resolved on every `body`; `focusedPane` publishes when the focused
    /// pane's surface registers, so a new connection's terminal is found.
    let terminalProvider: (UUID) -> GhosttyTerminalView?
    let content: (CGFloat) -> Content

    init(
        focusedPane: TerminalServerFocusedPaneProjection,
        isTerminalSelected: Bool,
        terminalProvider: @escaping (UUID) -> GhosttyTerminalView?,
        @ViewBuilder content: @escaping (CGFloat) -> Content
    ) {
        _focusedPane = ObservedObject(wrappedValue: focusedPane)
        self.isTerminalSelected = isTerminalSelected
        self.terminalProvider = terminalProvider
        self.content = content
    }

    private var focusedTerminal: GhosttyTerminalView? {
        focusedPane.state.focusedPaneId.flatMap(terminalProvider)
    }

    var body: some View {
        let terminal = focusedTerminal
        TerminalAccessoryBarLayout(
            terminal: terminal,
            isVisible: TerminalAccessoryBarPresentationPolicy.isVisible(
                for: .init(
                    isEnabled: isEnabled,
                    isTerminalSelected: isTerminalSelected,
                    hasFocusedTerminal: terminal != nil,
                    findNavigatorIsVisible: focusedPane.state.findNavigatorIsVisible
                )
            ),
            content: content
        )
    }
}

extension ConnectionTerminalContainer {
    var platformBody: some View {
        sharedBody
            .alert(
                disconnectAlertTitle,
                isPresented: $showingDisconnectConfirmation,
            ) {
                Button("Cancel", role: .cancel) {}
                Button(disconnectActionTitle, role: .destructive) {
                    disconnectFromServer()
                }
            } message: {
                Text(disconnectAlertMessage)
            }
            .terminalCloseConfirmationAlert(
                isPresented: $showingPaneCloseConfirmation,
                message: String(localized: "The SSH connection will be terminated."),
                onClose: closeFocusedPaneConfirmed
            )
    }

    func platformChrome(backgroundColor: Color) -> some View {
        TerminalAccessoryBarRouteLayout(
            focusedPane: terminalToolbarProjection.focusedPane,
            isTerminalSelected: selectedView == .terminal,
            terminalProvider: { tabManager.terminalSurfaceStore.ghosttySurface(for: $0) }
        ) { accessoryBarInset in
            TerminalKeyboardSafeAreaHost(isTerminalSelected: selectedView == .terminal) {
                VStack(spacing: 0) {
                    headerTabsBar

                    platformContentStack(backgroundColor: backgroundColor)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .background(backgroundColor)
                }
                .padding(.bottom, accessoryBarInset)
                .background(backgroundColor.ignoresSafeArea(.all))
            }
        }
    }

    @ViewBuilder
    private func platformContentStack(backgroundColor: Color) -> some View {
        Group {
            switch selectedView {
            case .stats:
                statsLayer(backgroundColor: backgroundColor)
            case .files:
                filesLayer
            case .terminal:
                terminalLayer
            }
        }
        // View switches must swap content without implicit animations: animating
        // the insertion of the Metal-backed terminal view during the segmented
        // picker's transition hangs the main thread in a trait-update loop.
        .transaction { transaction in
            transaction.animation = nil
        }
    }

    @ViewBuilder
    private func statsLayer(backgroundColor: Color) -> some View {
        // Mount stats only while selected. The dashboard nests ViewThatFits,
        // Grid, and lazy stacks; keeping it in the hierarchy at opacity 0 makes
        // every layout pass of the other views re-measure it, which explodes
        // combinatorially and hangs the main thread when the terminal mounts.
        if selectedView == .stats {
            ServerStatsView(
                server: server,
                backgroundColor: backgroundColor,
                sharedClientProvider: { tabManager.transportCoordinator.sharedStatsClient(for: server.id) },
                dependencies: statsDependencies
            )
            .zIndex(1)
        }
    }

    @ViewBuilder
    var terminalLayer: some View {
        if selectedView == .terminal, let tab = selectedTab {
            TerminalTabView(
                tab: tab,
                server: server,
                tabManager: tabManager,
                securityActions: terminalSecurityActions,
                isSelected: true,
                isSplitZoomed: terminalContent.state.splitZoomedTabIds.contains(tab.id),
                appearance: terminalAppearanceSnapshot
            )
            // Per-tab identity: without it SwiftUI reuses the previous tab's
            // representable (and its Ghostty view + SSH coordinator) when the
            // selected tab changes.
            .id(tab.id)
        }

        if selectedView == .terminal && serverTabs.isEmpty {
            TerminalEmptyStateView(server: server) {
                openNewTab()
            }
        }
    }

    @ViewBuilder
    private var headerTabsBar: some View {
        if selectedView == .terminal && serverTabs.count > 1 {
            SharedTerminalTabsBar(
                tabs: serverTabs,
                selectedTabId: selectedTabIdBinding,
                projection: terminalToolbarProjection.tabStrip,
                onClose: { tabManager.closeTab($0) }
            )
        }

        if selectedView == .files && serverFileTabs.count > 1 {
            RemoteFileTabsBar(
                tabs: serverFileTabs,
                selectedTabId: selectedFileTabIdBinding,
                titleForTab: displayedFileTabTitle(for:),
                onSelect: { fileTabManager.selectTab($0) },
                onClose: { tab in
                    if let removedTab = fileTabManager.closeTab(tab) {
                        fileBrowser.removeState(for: removedTab.id)
                    }
                }
            )
        }
    }

    private func disconnectFromServer() {
        statsDependencies.runtimeStore.releaseCollector(for: server.id)
        tabManager.disconnectServer(server.id)
        fileBrowser.disconnect(serverId: server.id)
        fileTabManager.disconnect(serverId: server.id)
    }

    func platformPrepareForPaneClose() {
        tabManager.keyboardCoordinator.deactivateInputImmediately(reason: .routeModal)
    }

    private var disconnectAlertTitle: String {
        String(localized: "Close Tab?")
    }

    private var disconnectActionTitle: String {
        String(localized: "Close")
    }

    private var disconnectAlertMessage: String {
        let terminalCount = serverTabs.count
        let fileCount = serverFileTabs.count

        if terminalCount == 0, fileCount == 0 {
            return String(localized: "This will return to the server list.")
        }

        if terminalCount > 0, fileCount > 0 {
            return String(localized: "All terminal and file tabs for this server will be closed.")
        }

        if fileCount > 0 {
            return String(localized: "All file tabs for this server will be closed.")
        }

        return String(localized: "All terminal tabs for this server will be closed.")
    }
}

private struct SharedTerminalTabsBar: View {
    let tabs: [TerminalTab]
    @Binding var selectedTabId: UUID?
    @ObservedObject var projection: TerminalServerToolbarTabStripProjection
    let onClose: (TerminalTab) -> Void

    var body: some View {
        CapsuleTabStrip(
            items: tabs.map { tab in
                let item = projection.state.items.first { $0.id == tab.id }
                return CapsuleTabStripItem(
                    id: tab.id,
                    title: item?.title ?? tab.title,
                    statusColor: ConnectionStatusDotColor.color(for: item?.connectionState)
                )
            },
            selectedId: selectedTabId,
            stripAccessibilityIdentifier: "vvterm.terminalTabs.strip",
            closeAccessibilityIdentifier: "vvterm.terminalTabs.close",
            onSelect: { selectedTabId = $0 },
            onClose: { id in
                guard let tab = tabs.first(where: { $0.id == id }) else { return }
                onClose(tab)
            }
        )
        .padding(.horizontal, 24)
        .padding(.vertical, 6)
    }
}
