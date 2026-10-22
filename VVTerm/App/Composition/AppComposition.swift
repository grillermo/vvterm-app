import Foundation

/// The single production dependency graph for the application.
@MainActor
struct AppComposition {
    let networkMonitor: NetworkMonitor
    let analyticsTracker: AnalyticsTracker
    let ghosttyApp: GhosttyRuntime
    let appLockManager: AppLockManager
    let serverManager: ServerManager
    let engagementTracker: EngagementTracker
    let tabManager: TerminalTabManager
    let remoteFileBrowserStore: RemoteFileBrowserStore
    let terminalFontStore: TerminalFontStore
    let terminalThemeManager: TerminalThemeManager
    let terminalAccessoryPreferencesManager: TerminalAccessoryPreferencesManager
    let statsPreferencesStore: PreferencesStore
    let serverVolumeVisibilityStore: ServerVolumeVisibilityStore
    let viewTabConfigurationManager: ViewTabConfigurationManager
    let syncSettingsCoordinator: SyncSettingsCoordinator
    let sshKeySettingsCoordinator: SSHKeySettingsCoordinator
    let knownHostSettingsCoordinator: KnownHostSettingsCoordinator
    let onWelcomeCompleted: @MainActor () -> Void
    let statsRuntimeStore: ServerStatsRuntimeStore
    let makeLocalDiscoveryManager: LocalSSHDiscoveryManagerFactory
    let serverFormDependencies: ServerFormDependencies
    let statsSecurityApprovalActions: ServerStatsSecurityApprovalActions
    let terminalSecurityActions: TerminalSecurityActions
    let analyticsOptOutAction: AnalyticsOptOutAction
    let appLifecycleDependencies: AppLifecycleDependencies

    static func live() -> Self {
        Self.init()
    }

    private init() {
        let defaults = UserDefaults.standard
        TerminalDefaults.applyIfNeeded(defaults: defaults)
        let terminalOptionAsAltMode = TerminalOptionAsAltMode.none.rawValue
        let terminalContentPadding = TerminalDefaults.storedContentPadding(defaults: defaults)
        let notificationCenter = NotificationCenter.default
        let calendar = Calendar.current
        let now: @Sendable () -> Date = Date.init
        let makeID: @Sendable () -> UUID = UUID.init
        let defaultWorkspaceName: () -> String = {
            AppLanguage.localizedString(
                "My Servers",
                rawValue: defaults.string(forKey: AppLanguage.storageKey)
            )
        }
        let networkMonitor = NetworkMonitor.shared
        let analyticsTracker = AnalyticsTracker.shared
        let cloudKitManager = CloudKitManager.shared
        let keychainManager = KeychainManager.shared
        let knownHostsManager = KnownHostsManager.shared
        let liveActivityManager = LiveActivityManager.shared
        let remoteMosh = RemoteMoshManager.shared
        let sshClientFactory = SSHClientLiveComposition.makeFactory(
            defaults: defaults,
            knownHostsManager: knownHostsManager,
            remoteMoshManager: remoteMosh
        )
        let connectionOperations = SSHConnectionOperationService(
            clientFactory: sshClientFactory
        )
        let remoteTmux = RemoteTmuxManager()
        let remoteSessions = RemoteSessionClient(
            registry: RemoteSessionBackendRegistry(backends: [
                HerdrRemoteSessionBackend(),
                TmuxRemoteSessionBackend(tmux: remoteTmux),
                ZellijRemoteSessionBackend(),
                ZmxRemoteSessionBackend()
            ])
        )
        let eternalTerminalResumeStore = EternalTerminalResumeStore.shared
        let moshResumeStore = MoshResumeStore.shared
        let terminalSurfaceStore = GhosttyTerminalSurfaceStore()
        let deviceID = DeviceIdentity.id
        let platform = AppPlatformComposition.live(
            cloudKitManager: cloudKitManager,
            networkMonitor: networkMonitor,
            liveActivityManager: liveActivityManager
        )
        let applicationIsActive = platform.applicationIsActive
        let appLockManager = AppLockManager()
        let syncLifecycle = CloudKitSyncLifecycleDriver(
            defaults: defaults,
            notificationCenter: notificationCenter,
            now: now
        )
        let isSyncEnabled = { SyncSettings.isEnabled(in: defaults) }
        let terminalFontRepository = LocalTerminalFontRepository.applicationSupport(
            defaults: defaults
        )
        let cloudKitSync = CloudKitSyncLiveComposition.makeLive(
            transport: cloudKitManager,
            terminalFontRepository: terminalFontRepository,
            defaults: defaults,
            now: now,
            makeID: makeID
        )
        let cloudKitSyncCoordinator = cloudKitSync.coordinator
        let makeLocalDiscoveryManager: LocalSSHDiscoveryManagerFactory = {
            LocalSSHDiscoveryManager(
                dependencies: .live(
                    networkConnectionType: { networkMonitor.connectionType },
                    makeScanID: makeID
                )
            )
        }
        let serverDeletionTerminalCleanup = ServerDeletionTerminalCleanupRelay()
        let serverManager = ServerManager(
            dependencies: .live(
                defaults: defaults,
                serverCloud: cloudKitSync.serverCloud,
                credentialRepository: keychainManager,
                knownHosts: knownHostsManager,
                freePlanTracker: analyticsTracker,
                actionAuthorizer: appLockManager,
                syncRepository: cloudKitSyncCoordinator,
                didDeleteServerLocalData: { serverID in
                    serverDeletionTerminalCleanup.handleServerDeletion(serverID)
                },
                defaultWorkspaceName: defaultWorkspaceName,
                now: now,
                makeID: makeID
            )
        )
        let serverFormDependencies = ServerFormDependencies.live(
            credentials: keychainManager,
            hostKeys: knownHostsManager,
            connectionOperations: connectionOperations,
            remoteMosh: remoteMosh,
            remoteSessionBackends: remoteSessions.backendMetadata,
            defaultRemoteSessionEnabled: {
                defaults.object(forKey: TerminalRemoteSessionDefaults.enabledKey) == nil
                    ? true
                    : defaults.bool(forKey: TerminalRemoteSessionDefaults.enabledKey)
            },
            defaultRemoteSessionBackendIdentifier: {
                let stored = defaults.string(
                    forKey: TerminalRemoteSessionDefaults.backendIdentifierKey
                ).map(RemoteSessionBackendIdentifier.init(rawValue:))
                return remoteSessions.backendMetadata.contains { $0.identifier == stored }
                    ? stored ?? .tmux
                    : .tmux
            },
            defaultRemoteSessionStartupBehavior: {
                defaults.string(forKey: TerminalRemoteSessionDefaults.startupBehaviorKey)
                    .flatMap(RemoteSessionStartupBehavior.init(persistedRawValue:)) ?? .ask
            },
            now: now,
            makeID: makeID
        )
        let engagementTracker = EngagementTracker(
            dependencies: .live(
                defaults: defaults,
                analytics: analyticsTracker,
                now: now,
                calendar: calendar,
                applicationIsActive: applicationIsActive
            )
        )
        let terminalFontStore = TerminalFontStore(
            dependencies: .live(
                repository: terminalFontRepository,
                cloud: cloudKitSync.terminalFontCloud,
                mutationQueue: cloudKitSyncCoordinator,
                syncLifecycle: syncLifecycle,
                isSyncEnabled: isSyncEnabled,
                now: now
            )
        )
        let terminalThemeManager = TerminalThemeManager(
            dependencies: .live(
                defaults: defaults,
                notificationCenter: notificationCenter,
                cloud: cloudKitSync.terminalThemeCloud,
                mutationQueue: cloudKitSyncCoordinator,
                syncLifecycle: syncLifecycle,
                themeFiles: TerminalThemeFileStore.appStorage,
                builtInThemeCatalog: BundleTerminalThemeCatalog(),
                paletteResolver: ThemeColorParserPaletteResolver(),
                isSyncEnabled: isSyncEnabled,
                now: now
            )
        )
        let tabManager = TerminalTabManagerLiveComposition.makeManager(
            defaults: defaults,
            sshClientFactory: sshClientFactory,
            networkMonitor: networkMonitor,
            appLockManager: appLockManager,
            serverManager: serverManager,
            prepareInitialConnection: { _ in },
            engagementTracker: engagementTracker,
            analyticsTracker: analyticsTracker,
            liveActivityManager: liveActivityManager,
            remoteMosh: remoteMosh,
            remoteSessions: remoteSessions,
            eternalTerminalResumeStore: eternalTerminalResumeStore,
            moshResumeStore: moshResumeStore,
            terminalSurfaceStore: terminalSurfaceStore,
            deviceID: deviceID,
            themeStyle: {
                TerminalRemoteSessionLiveComposition.themeStyle(
                    for: terminalThemeManager.themeSelection.darkThemeName
                )
            },
            applicationIsActive: applicationIsActive
        )
        serverDeletionTerminalCleanup.bind(to: tabManager)
        let terminalAccessoryPreferencesManager = TerminalAccessoryPreferencesManager(
            dependencies: .live(
                defaults: defaults,
                cloud: cloudKitSync.terminalAccessoryCloud,
                mutationQueue: cloudKitSyncCoordinator,
                syncLifecycle: syncLifecycle,
                resolutionSource: cloudKitSync.terminalAccessoryResolutions,
                writerID: deviceID,
                isSyncEnabled: isSyncEnabled,
                now: now,
                makeID: makeID,
                trackCustomActionCreated: { kind in
                    analyticsTracker.trackCustomActionCreated(kind: kind.rawValue)
                }
            )
        )
        let statsPreferencesStore = PreferencesStore(
            dependencies: .live(
                defaults: defaults,
                cloud: cloudKitSync.statsPreferencesCloud,
                mutationQueue: cloudKitSyncCoordinator,
                syncLifecycle: syncLifecycle,
                resolutionSource: cloudKitSync.statsPreferencesResolutions,
                writerID: deviceID,
                isSyncEnabled: isSyncEnabled,
                now: now
            )
        )
        let serverVolumeVisibilityStore = ServerVolumeVisibilityStore.live
        let viewTabConfigurationManager = ViewTabConfigurationManager(defaults: defaults)
        let makeStatsCollector = Self.makeStatsCollectorFactory(
            keychainManager: keychainManager,
            knownHostsManager: knownHostsManager,
            connectionOperations: connectionOperations,
            sshClientFactory: sshClientFactory
        )
        let statsRuntimeStore = ServerStatsRuntimeStore(
            makeCollector: makeStatsCollector
        )
        let terminalSecurityActions = Self.makeTerminalSecurityActions(
            keychainManager: keychainManager,
            knownHostsManager: knownHostsManager
        )
        let analyticsOptOutAction = AnalyticsOptOutAction(
            emitAnalyticsDisabled: {
                analyticsTracker.trackAnalyticsDisabled()
            }
        )
        let onWelcomeCompleted: @MainActor () -> Void = {
            analyticsTracker.trackWelcomeCompleted()
        }
        let syncSettingsCoordinator = SyncSettingsLiveComposition.makeCoordinator(
            cloudKit: cloudKitManager,
            keychain: keychainManager,
            serverManager: serverManager,
            terminalTheme: terminalThemeManager,
            terminalFont: terminalFontStore,
            terminalAccessory: terminalAccessoryPreferencesManager,
            statsPreferences: statsPreferencesStore,
            pendingSync: cloudKitSyncCoordinator,
            defaults: defaults
        )
        let sshKeySettingsCoordinator = SSHKeySettingsLiveComposition.makeCoordinator(
            keychain: keychainManager
        )
        let knownHostSettingsCoordinator = KnownHostSettingsLiveComposition.makeCoordinator(
            knownHosts: knownHostsManager
        )
        let appLifecycleDependencies = platform.lifecycleDependencies
        let ghosttyRuntimeConfiguration = Ghostty.RuntimeConfiguration(
            fontSelection: TerminalFontSelectionPolicy.resolve(
                primaryFamily: terminalFontStore.preference.primaryFamily,
                cjkFamily: terminalFontStore.preference.cjkFamily,
                catalog: terminalFontStore.catalog,
                allowsProFeatures: true
            ),
            fontSize: defaults.object(forKey: TerminalDefaults.fontSizeKey) as? Double
                ?? TerminalDefaults.defaultFontSize,
            contentPadding: terminalContentPadding,
            cursorStyleRawValue: defaults.string(forKey: TerminalDefaults.cursorStyleKey)
                ?? TerminalDefaults.defaultCursorStyle.rawValue,
            cursorBlink: defaults.object(forKey: TerminalDefaults.cursorBlinkKey) as? Bool
                ?? TerminalDefaults.defaultCursorBlink,
            optionAsAltModeRawValue: terminalOptionAsAltMode,
            remoteClipboardReadPolicyRawValue: defaults.string(
                forKey: TerminalRemoteClipboardReadPolicy.userDefaultsKey
            ) ?? TerminalRemoteClipboardReadPolicy.defaultValue.rawValue,
            remoteClipboardWritePolicyRawValue: defaults.string(
                forKey: TerminalRemoteClipboardWritePolicy.userDefaultsKey
            ) ?? TerminalRemoteClipboardWritePolicy.defaultValue.rawValue
        )
        let ghosttyApp = GhosttyRuntime(
            configuration: ghosttyRuntimeConfiguration,
            autoStart: false
        )
        let statsSecurityApprovalActions = Self.makeStatsSecurityApprovalActions(
            knownHostsManager: knownHostsManager
        )
        let remoteFileBrowserStore = Self.makeRemoteFileBrowserStore(
            tabManager: tabManager,
            serverManager: serverManager,
            credentialRepository: keychainManager,
            connectionOperations: connectionOperations,
            clientFactory: sshClientFactory,
            securityApprovalActions: Self.makeRemoteFileSecurityApprovalActions(
                knownHostsManager: knownHostsManager
            ),
            defaults: defaults
        )

        self.networkMonitor = networkMonitor
        self.analyticsTracker = analyticsTracker
        self.ghosttyApp = ghosttyApp
        self.appLockManager = appLockManager
        self.serverManager = serverManager
        self.engagementTracker = engagementTracker
        self.tabManager = tabManager
        self.remoteFileBrowserStore = remoteFileBrowserStore
        self.terminalFontStore = terminalFontStore
        self.terminalThemeManager = terminalThemeManager
        self.terminalAccessoryPreferencesManager = terminalAccessoryPreferencesManager
        self.statsPreferencesStore = statsPreferencesStore
        self.serverVolumeVisibilityStore = serverVolumeVisibilityStore
        self.viewTabConfigurationManager = viewTabConfigurationManager
        self.syncSettingsCoordinator = syncSettingsCoordinator
        self.sshKeySettingsCoordinator = sshKeySettingsCoordinator
        self.knownHostSettingsCoordinator = knownHostSettingsCoordinator
        self.onWelcomeCompleted = onWelcomeCompleted
        self.statsRuntimeStore = statsRuntimeStore
        self.makeLocalDiscoveryManager = makeLocalDiscoveryManager
        self.serverFormDependencies = serverFormDependencies
        self.statsSecurityApprovalActions = statsSecurityApprovalActions
        self.terminalSecurityActions = terminalSecurityActions
        self.analyticsOptOutAction = analyticsOptOutAction
        self.appLifecycleDependencies = appLifecycleDependencies
    }
}
