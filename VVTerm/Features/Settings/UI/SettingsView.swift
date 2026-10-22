import SwiftUI

struct SettingsView: View {
    let statsPreferencesStore: PreferencesStore
    let analyticsOptOutAction: AnalyticsOptOutAction
    let remoteSessionBackends: [RemoteSessionBackendMetadata]

    @AppStorage(TerminalDefaults.fontSizeKey) var terminalFontSize = TerminalDefaults.defaultFontSize
    @AppStorage(SettingsRoutePersistence.selectedRouteKey)
    var selectedRouteRaw = SettingsRoute.defaultRoute.rawValue
    @State var searchText = ""

    @Environment(\.dismiss) var dismiss

    var body: some View {
        platformBody
    }

    var selectedRoute: SettingsRoute {
        SettingsRoutePersistence.route(for: selectedRouteRaw)
    }

    func visibleRoutes(in group: SettingsGroup) -> [SettingsRoute] {
        SettingsRouteCatalog.visibleRoutes(
            from: SettingsRouteCatalog.routes(in: group),
            matching: searchText
        )
    }

    func visibleRoutes(from routes: [SettingsRoute]) -> [SettingsRoute] {
        SettingsRouteCatalog.visibleRoutes(from: routes, matching: searchText)
    }

    var visibleDetailRoute: SettingsRoute? {
        SettingsRouteCatalog.visibleDetailRoute(
            selectedRoute: selectedRoute,
            matching: searchText
        )
    }

    @ViewBuilder
    func destination(for route: SettingsRoute) -> some View {
        switch route {
        case .appearanceAndLanguage:
            AppearanceLanguageSettingsView()
        case .navigationAndStats:
            NavigationStatsSettingsView(statsPreferencesStore: statsPreferencesStore)
        case .privacyAndAppLock:
            PrivacyAppLockSettingsView(analyticsOptOutAction: analyticsOptOutAction)
        case .terminalAppearance:
            TerminalAppearanceSettingsView(fontSize: $terminalFontSize)
        case .keyboardAndInput:
            TerminalKeyboardInputSettingsView()
        case .sessionsAndConnections:
            TerminalSessionsConnectionsSettingsView(backends: remoteSessionBackends)
        case .clipboardAndPaste:
            TerminalClipboardPasteSettingsView()
        case .sshKeys:
            KeychainSettingsView()
        case .trustedHosts:
            TrustedHostsSettingsView()
        case .iCloudSync:
            SyncSettingsView()
        case .aboutAndSupport:
            AboutSettingsView()
        }
    }

    @ViewBuilder
    func routeLabel(for route: SettingsRoute) -> some View {
        Label(route.title, systemImage: route.icon)
            .accessibilityElement(children: .combine)
            .accessibilityIdentifier("vvterm.settings.route.\(route.rawValue)")
    }
}
