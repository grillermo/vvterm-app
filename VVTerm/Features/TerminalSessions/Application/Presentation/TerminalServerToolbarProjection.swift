import Combine
import Foundation

@MainActor
final class TerminalPaneTitleStore: ObservableObject {
    @Published private(set) var runtimeTitles: [UUID: String] = [:]
    @Published private(set) var overrides: [UUID: String] = [:]
    /// Names of persistent sessions the user chose to attach. Generated
    /// managed names are not meaningful titles and are never stored here.
    @Published private(set) var sessionNames: [UUID: String] = [:]

    @discardableResult
    func setRuntimeTitle(_ title: String, for paneId: UUID) -> Bool {
        guard runtimeTitles[paneId] != title else { return false }
        runtimeTitles[paneId] = title
        return true
    }

    func setOverride(_ title: String?, for paneId: UUID) {
        if let title, !title.isEmpty {
            guard overrides[paneId] != title else { return }
            overrides[paneId] = title
        } else if overrides[paneId] != nil {
            overrides.removeValue(forKey: paneId)
        }
    }

    func setSessionNames(_ names: [UUID: String]) {
        guard sessionNames != names else { return }
        sessionNames = names
    }

    func removePane(_ paneId: UUID) {
        if runtimeTitles[paneId] != nil {
            runtimeTitles.removeValue(forKey: paneId)
        }
        if overrides[paneId] != nil {
            overrides.removeValue(forKey: paneId)
        }
    }

    func removeAllRuntimeTitles() {
        guard !runtimeTitles.isEmpty else { return }
        runtimeTitles.removeAll()
    }

    func reset() {
        if !runtimeTitles.isEmpty {
            runtimeTitles.removeAll()
        }
        if !overrides.isEmpty {
            overrides.removeAll()
        }
    }

    func displayTitle(forPane paneId: UUID, fallback: String? = nil) -> String? {
        Self.paneTitle(
            paneId,
            runtimeTitles: runtimeTitles,
            overrides: overrides,
            sessionNames: sessionNames
        ) ?? fallback
    }

    func displayTitle(for tab: TerminalTab) -> String {
        Self.displayTitle(
            for: tab,
            runtimeTitles: runtimeTitles,
            overrides: overrides,
            sessionNames: sessionNames
        )
    }

    /// A user rename wins, then the chosen session name, which is steadier
    /// than whatever title the remote shell last emitted.
    static func displayTitle(
        for tab: TerminalTab,
        runtimeTitles: [UUID: String],
        overrides: [UUID: String],
        sessionNames: [UUID: String]
    ) -> String {
        [tab.focusedPaneId, tab.rootPaneId].lazy.compactMap {
            paneTitle(
                $0,
                runtimeTitles: runtimeTitles,
                overrides: overrides,
                sessionNames: sessionNames
            )
        }.first ?? tab.title
    }

    private static func paneTitle(
        _ paneId: UUID,
        runtimeTitles: [UUID: String],
        overrides: [UUID: String],
        sessionNames: [UUID: String]
    ) -> String? {
        overrides[paneId] ?? sessionNames[paneId] ?? runtimeTitles[paneId]
    }
}

@MainActor
final class TerminalPanePresentationProjection: ObservableObject {
    @Published private(set) var state: TerminalPanePresentationState?
    private var cancellable: AnyCancellable?

    init(paneId: UUID, sessionState: TerminalSessionStateStore) {
        state = sessionState.presentationState(for: paneId)
        cancellable = sessionState.presentationChanges(for: paneId)
            .sink { [weak self] state in
                guard self?.state != state else { return }
                self?.state = state
            }
    }
}

struct TerminalServerContentState: Equatable {
    let tabs: [TerminalTab]
    let selectedTabId: UUID?
    let selectedView: ConnectionViewTabID?
    let splitZoomedTabIds: Set<UUID>
}

struct TerminalServerToolbarTabItem: Equatable, Identifiable {
    let id: UUID
    let title: String
    let connectionState: ConnectionState?
    let paneCount: Int
}

struct TerminalServerToolbarTabStripState: Equatable {
    let items: [TerminalServerToolbarTabItem]
    let selectedTabId: UUID?
}

struct TerminalServerFocusedPaneState: Equatable {
    let focusedPaneId: UUID?
    /// The focused pane's registered surface. A new connection's terminal
    /// registers after the route first renders; publishing its identity lets
    /// route chrome resolve the terminal it mounts on.
    let focusedSurfaceIdentity: ObjectIdentifier?
    let findNavigatorIsVisible: Bool
}

@MainActor
final class TerminalServerContentProjection: ObservableObject {
    @Published private(set) var state: TerminalServerContentState

    init(state: TerminalServerContentState) {
        self.state = state
    }

    fileprivate func update(_ state: TerminalServerContentState) {
        guard self.state != state else { return }
        self.state = state
    }
}

@MainActor
final class TerminalServerToolbarTabStripProjection: ObservableObject {
    @Published private(set) var state: TerminalServerToolbarTabStripState

    init(state: TerminalServerToolbarTabStripState) {
        self.state = state
    }

    fileprivate func update(_ state: TerminalServerToolbarTabStripState) {
        guard self.state != state else { return }
        self.state = state
    }
}

@MainActor
final class TerminalServerFocusedPaneProjection: ObservableObject {
    @Published private(set) var state: TerminalServerFocusedPaneState

    init(state: TerminalServerFocusedPaneState) {
        self.state = state
    }

    fileprivate func update(_ state: TerminalServerFocusedPaneState) {
        guard self.state != state else { return }
        self.state = state
    }
}

/// One per-server projection with separate observable surfaces.
/// Title and connection-status changes redraw only the tab strip. They do not
/// invalidate route chrome or an open menu.
@MainActor
final class TerminalServerToolbarProjection: ObservableObject {
    let content: TerminalServerContentProjection
    let tabStrip: TerminalServerToolbarTabStripProjection
    let focusedPane: TerminalServerFocusedPaneProjection

    private var sessionSnapshot: TerminalServerSessionSnapshot
    private var selectedView: ConnectionViewTabID?
    private var runtimeTitles: [UUID: String]
    private var titleOverrides: [UUID: String]
    private var sessionNames: [UUID: String]
    private var splitZoomedTabIds: Set<UUID>
    private var findVisibility: [UUID: Bool]
    private let terminalSurfaceStore: any TerminalSurfaceStoring
    private var cancellables: Set<AnyCancellable> = []

    init(serverId: UUID, tabManager: TerminalTabManager) {
        sessionSnapshot = tabManager.sessionState.snapshot(for: serverId)
        selectedView = tabManager.connectionViewSelections.selection(for: serverId)
        runtimeTitles = tabManager.titleStore.runtimeTitles
        titleOverrides = tabManager.titleStore.overrides
        sessionNames = tabManager.titleStore.sessionNames
        splitZoomedTabIds = tabManager.presentationState.splitZoomedTabIds
        findVisibility = tabManager.presentationState.terminalFindNavigatorVisibleByPane
        terminalSurfaceStore = tabManager.terminalSurfaceStore

        let initialStates = Self.makeStates(
            sessionSnapshot: sessionSnapshot,
            selectedView: selectedView,
            runtimeTitles: runtimeTitles,
            titleOverrides: titleOverrides,
            sessionNames: sessionNames,
            splitZoomedTabIds: splitZoomedTabIds
        )
        content = TerminalServerContentProjection(state: initialStates.content)
        tabStrip = TerminalServerToolbarTabStripProjection(state: initialStates.tabStrip)
        focusedPane = TerminalServerFocusedPaneProjection(
            state: Self.makeFocusedPaneState(
                sessionSnapshot: sessionSnapshot,
                findVisibility: findVisibility,
                terminalSurfaceStore: tabManager.terminalSurfaceStore
            )
        )

        tabManager.sessionState.changes(for: serverId)
            .sink { [weak self] snapshot in
                self?.sessionSnapshot = snapshot
                self?.reconcile()
            }
            .store(in: &cancellables)

        tabManager.connectionViewSelections.$selectionsByServer
            .map { $0[serverId] }
            .removeDuplicates()
            .sink { [weak self] selection in
                self?.selectedView = selection
                self?.reconcile()
            }
            .store(in: &cancellables)

        tabManager.titleStore.$runtimeTitles
            .sink { [weak self] titles in
                self?.runtimeTitles = titles
                self?.reconcileTabStrip()
            }
            .store(in: &cancellables)

        tabManager.titleStore.$overrides
            .sink { [weak self] titles in
                self?.titleOverrides = titles
                self?.reconcileTabStrip()
            }
            .store(in: &cancellables)

        tabManager.titleStore.$sessionNames
            .sink { [weak self] names in
                self?.sessionNames = names
                self?.reconcileTabStrip()
            }
            .store(in: &cancellables)

        tabManager.presentationState.$splitZoomedTabIds
            .sink { [weak self] tabIds in
                self?.splitZoomedTabIds = tabIds
                self?.reconcile()
            }
            .store(in: &cancellables)

        tabManager.presentationState.$terminalFindNavigatorVisibleByPane
            .sink { [weak self] visibility in
                self?.findVisibility = visibility
                self?.reconcileFocusedPane()
            }
            .store(in: &cancellables)

        tabManager.terminalSurfaceStore.changes
            .sink { [weak self] _ in
                self?.reconcileFocusedPane()
            }
            .store(in: &cancellables)
    }

    private func reconcile() {
        let states = Self.makeStates(
            sessionSnapshot: sessionSnapshot,
            selectedView: selectedView,
            runtimeTitles: runtimeTitles,
            titleOverrides: titleOverrides,
            sessionNames: sessionNames,
            splitZoomedTabIds: splitZoomedTabIds
        )
        let focusedPaneState = Self.makeFocusedPaneState(
            sessionSnapshot: sessionSnapshot,
            findVisibility: findVisibility,
            terminalSurfaceStore: terminalSurfaceStore
        )
        let routeStateChanged = content.state != states.content
            || focusedPane.state != focusedPaneState
        if routeStateChanged {
            objectWillChange.send()
        }
        content.update(states.content)
        tabStrip.update(states.tabStrip)
        focusedPane.update(focusedPaneState)
    }

    private func reconcileTabStrip() {
        tabStrip.update(
            Self.makeTabStripState(
                sessionSnapshot: sessionSnapshot,
                runtimeTitles: runtimeTitles,
                titleOverrides: titleOverrides,
                sessionNames: sessionNames
            )
        )
    }

    private func reconcileFocusedPane() {
        let state = Self.makeFocusedPaneState(
            sessionSnapshot: sessionSnapshot,
            findVisibility: findVisibility,
            terminalSurfaceStore: terminalSurfaceStore
        )
        guard focusedPane.state != state else { return }
        objectWillChange.send()
        focusedPane.update(state)
    }

    private static func makeStates(
        sessionSnapshot: TerminalServerSessionSnapshot,
        selectedView: ConnectionViewTabID?,
        runtimeTitles: [UUID: String],
        titleOverrides: [UUID: String],
        sessionNames: [UUID: String],
        splitZoomedTabIds: Set<UUID>
    ) -> (
        content: TerminalServerContentState,
        tabStrip: TerminalServerToolbarTabStripState
    ) {
        let tabs = sessionSnapshot.tabs
        let selectedTab = resolvedSelectedTab(in: sessionSnapshot)
        let content = TerminalServerContentState(
            tabs: tabs,
            selectedTabId: selectedTab?.id,
            selectedView: selectedView,
            splitZoomedTabIds: splitZoomedTabIds.intersection(tabs.map(\.id))
        )
        return (
            content,
            makeTabStripState(
                sessionSnapshot: sessionSnapshot,
                runtimeTitles: runtimeTitles,
                titleOverrides: titleOverrides,
                sessionNames: sessionNames
            )
        )
    }

    private static func makeTabStripState(
        sessionSnapshot: TerminalServerSessionSnapshot,
        runtimeTitles: [UUID: String],
        titleOverrides: [UUID: String],
        sessionNames: [UUID: String]
    ) -> TerminalServerToolbarTabStripState {
        TerminalServerToolbarTabStripState(
            items: sessionSnapshot.tabs.map { tab in
                TerminalServerToolbarTabItem(
                    id: tab.id,
                    title: TerminalPaneTitleStore.displayTitle(
                        for: tab,
                        runtimeTitles: runtimeTitles,
                        overrides: titleOverrides,
                        sessionNames: sessionNames
                    ),
                    connectionState: sessionSnapshot.connectionStatesByPane[tab.focusedPaneId],
                    paneCount: tab.paneCount
                )
            },
            selectedTabId: resolvedSelectedTab(in: sessionSnapshot)?.id
        )
    }

    private static func resolvedSelectedTab(
        in sessionSnapshot: TerminalServerSessionSnapshot
    ) -> TerminalTab? {
        if let selectedTabId = sessionSnapshot.selectedTabId,
           let selected = sessionSnapshot.tabs.first(where: { $0.id == selectedTabId }) {
            return selected
        }
        return sessionSnapshot.tabs.first
    }

    private static func makeFocusedPaneState(
        sessionSnapshot: TerminalServerSessionSnapshot,
        findVisibility: [UUID: Bool],
        terminalSurfaceStore: any TerminalSurfaceStoring
    ) -> TerminalServerFocusedPaneState {
        let paneId = resolvedSelectedTab(in: sessionSnapshot)?.focusedPaneId
        return TerminalServerFocusedPaneState(
            focusedPaneId: paneId,
            focusedSurfaceIdentity: paneId
                .flatMap { terminalSurfaceStore.surface(for: $0) }
                .map { ObjectIdentifier($0) },
            findNavigatorIsVisible: paneId.flatMap { findVisibility[$0] } ?? false
        )
    }
}
