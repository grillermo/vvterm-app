#if DEBUG
import SwiftUI

@MainActor
struct ServerDuplicateUITestHarness: View {
    private actor AutomaticConnectionTester: ServerConnectionTesting {
        func test(
            server: Server,
            credentials: ServerCredentials
        ) async -> ServerConnectionTestResult {
            .successWithDetectedSystem(
                RemoteSystemIdentity(
                    kind: .macOS,
                    appleHardwareModelIdentifier: AppleHardwareModelIdentifier(
                        rawValue: "MacBookPro18,3"
                    )
                )
            )
        }
    }

    private static let fallbackWorkspaceID = UUID(
        uuidString: "9B678329-F5FC-4A81-971C-CFCAC3261656"
    )!

    let serverManager: ServerManager
    let dependencies: ServerFormDependencies
    let makeLocalDiscoveryManager: LocalSSHDiscoveryManagerFactory

    @State private var formIntent: ServerFormIntent?

    private var workspace: Workspace? {
        serverManager.workspaces.first
    }

    private var sourceServer: Server {
        Server(
            id: UUID(uuidString: "4BEE9E2E-E2CF-438C-A44C-B2391D0606E5")!,
            workspaceId: workspace?.id ?? Self.fallbackWorkspaceID,
            name: "DEV-397 UI Test Source",
            host: "duplicate-test.example.com",
            port: 2222,
            username: "wiedy",
            connectionMode: .tailscale,
            iconSelection: .custom(.database),
            detectedSystemIdentity: RemoteSystemIdentity(
                kind: .ubuntu,
                displayName: "Ubuntu 24.04 LTS"
            ),
            notes: "Duplicate form fixture"
        )
    }

    var body: some View {
        NavigationStack {
            List {
                ServerListRow(
                    serverManager: serverManager,
                    server: sourceServer,
                    onTap: {},
                    onEdit: { formIntent = .edit(sourceServer) },
                    onMove: {},
                    onDuplicate: { formIntent = .duplicate(sourceServer) }
                )
                .accessibilityIdentifier("vvterm.serverDuplicateTest.row")
            }
            .navigationTitle("Server Duplicate Test")
        }
        .sheet(item: $formIntent) { intent in
            formSheet(for: intent)
        }
        .accessibilityIdentifier("vvterm.serverDuplicateTest.root")
    }

    @ViewBuilder
    private func formSheet(for intent: ServerFormIntent) -> some View {
        NavigationStack {
            serverForm(for: intent)
        }
    }

    private func serverForm(for intent: ServerFormIntent) -> some View {
        ServerFormSheet(
            serverManager: serverManager,
            workspace: workspace,
            intent: intent,
            dependencies: automaticDetectionDependencies,
            makeLocalDiscoveryManager: makeLocalDiscoveryManager,
            onSave: { _ in formIntent = nil }
        )
    }

    private var automaticDetectionDependencies: ServerFormDependencies {
        ServerFormDependencies(
            credentials: dependencies.credentials,
            connectionTester: AutomaticConnectionTester(),
            hostKeys: dependencies.hostKeys,
            remoteSessionBackends: dependencies.remoteSessionBackends,
            defaultRemoteSessionEnabled: dependencies.defaultRemoteSessionEnabled,
            defaultRemoteSessionBackendIdentifier:
                dependencies.defaultRemoteSessionBackendIdentifier,
            defaultRemoteSessionStartupBehavior:
                dependencies.defaultRemoteSessionStartupBehavior,
            now: dependencies.now,
            makeID: dependencies.makeID
        )
    }
}
#endif
