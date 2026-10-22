import Foundation
import Testing
@testable import VVTerm

struct RemoteTmuxOwnershipTests {
    @Test @MainActor
    func managedSessionNameUsesTheDerivedServerName() throws {
        let serverId = UUID()
        let resolver = RemoteSessionAttachResolver(
            configuration: configuration(serverID: serverId, serverName: "Prod API"),
            remoteSessions: UnavailableTerminalRemoteSessionService()
        )

        let identifier = try resolver.managedIdentifier(
            for: UUID(uuidString: "11111111-2222-3333-4444-555555555555")!,
            serverID: serverId,
            backendIdentifier: .tmux
        )

        #expect(identifier.rawValue.hasPrefix("vvterm-prod-d"))
    }

    @Test @MainActor
    func selectedVVTermManagedSessionKeepsManagedClearBehavior() throws {
        let resolver = makeResolver()
        let paneId = UUID()
        let serverId = UUID()
        let identifier = try resolver.managedIdentifier(
            for: paneId,
            serverID: serverId,
            backendIdentifier: .tmux
        )

        try resolver.updateAttachmentState(
            for: paneId,
            serverID: serverId,
            backendIdentifier: .tmux,
            selection: .attachExisting(RemoteSessionAttachment(
                identifier: identifier,
                ownership: .managed
            ))
        )
        let ownership = try #require(resolver.attachment(for: paneId)?.attachment.ownership)
        let command = RemoteTmuxCommandBuilder.attachExistingCommand(
            themeStyle: deterministicRemoteSessionThemeStyle,
            sessionName: identifier.rawValue,
            ownership: ownership
        )

        #expect(ownership == .managed)
        #expect(command.contains("set-option -wq -t \"$vvtermWindow\" scroll-on-clear 'off'"))
        #expect(command.contains("set-hook -t '=\(identifier.rawValue):' 'after-new-window[1000]'"))
    }

    @Test @MainActor
    func createManagedPreservesRestoredIdentifierAndConfirmation() throws {
        let resolver = makeResolver()
        let paneId = UUID()
        let serverId = UUID()
        let restoredIdentifier = try RemoteSessionIdentifier(
            backendIdentifier: .tmux,
            validating: "legacy-session"
        )
        resolver.setAttachment(
            TerminalRemoteSessionAttachmentState(
                attachment: RemoteSessionAttachment(
                    identifier: restoredIdentifier,
                    ownership: .managed
                ),
                managedSessionConfirmed: true
            ),
            for: paneId
        )

        try resolver.updateAttachmentState(
            for: paneId,
            serverID: serverId,
            backendIdentifier: .tmux,
            selection: .createManaged
        )

        let state = try #require(resolver.attachment(for: paneId))
        #expect(state.attachment.identifier == restoredIdentifier)
        #expect(state.managedSessionConfirmed)
    }

    @Test @MainActor
    func managedOwnershipSurvivesListingSelectionRestoreAndCleanup() throws {
        let paneId = UUID()
        let serverId = UUID()
        let identifier = try RemoteSessionIdentifier(
            backendIdentifier: .tmux,
            validating: "managed-without-name-convention"
        )
        let descriptor = RemoteSessionDescriptor(
            attachment: RemoteSessionAttachment(
                identifier: identifier,
                ownership: .managed
            ),
            attachedClientCount: 0,
            containerCount: 1,
            cleanupDisposition: .safeToDelete
        )
        let resolver = makeResolver()
        let listedAttachment = try #require(
            resolver.selectionInfo(from: [descriptor]).first?.attachment
        )

        try resolver.updateAttachmentState(
            for: paneId,
            serverID: serverId,
            backendIdentifier: .tmux,
            selection: .attachExisting(listedAttachment)
        )
        let restoredResolver = makeResolver()
        restoredResolver.restoreAttachments(resolver.attachments)

        #expect(restoredResolver.attachment(for: paneId)?.attachment.ownership == .managed)
        #expect(RemoteSessionCleanupPolicy.identifiersToDelete(
            from: [descriptor],
            keeping: []
        ) == [identifier])
    }

    @Test @MainActor
    func selectedVVTermStyleUserSessionRemainsExternal() throws {
        let resolver = makeResolver()
        let paneId = UUID()
        let serverId = UUID()
        let identifier = try RemoteSessionIdentifier(
            backendIdentifier: .tmux,
            validating: "vvterm-user-created"
        )

        try resolver.updateAttachmentState(
            for: paneId,
            serverID: serverId,
            backendIdentifier: .tmux,
            selection: .attachExisting(RemoteSessionAttachment(
                identifier: identifier,
                ownership: .external
            ))
        )
        let ownership = try #require(resolver.attachment(for: paneId)?.attachment.ownership)
        let command = RemoteTmuxCommandBuilder.attachExistingCommand(
            themeStyle: deterministicRemoteSessionThemeStyle,
            sessionName: identifier.rawValue,
            ownership: ownership
        )

        #expect(ownership == .external)
        #expect(!command.contains("source-file"))
        #expect(!command.contains("~/.vvterm/tmux.conf"))
    }

    @Test @MainActor
    func rememberedExternalSessionReattachesByNameWithoutListing() async throws {
        // The session listing hides tmux errors as an empty list. A tab that
        // remembers a session must not fall back to the server default when
        // the listing misses it; the attach command verifies presence itself.
        let serverId = UUID()
        let resolver = RemoteSessionAttachResolver(
            configuration: configuration(
                serverID: serverId,
                serverName: "Pc",
                startupBehavior: .plainShell
            ),
            remoteSessions: UnavailableTerminalRemoteSessionService()
        )
        let paneId = UUID()
        let attachment = RemoteSessionAttachment(
            identifier: try RemoteSessionIdentifier(
                backendIdentifier: .tmux,
                validating: "shared-session"
            ),
            ownership: .external
        )
        resolver.setAttachment(
            TerminalRemoteSessionAttachmentState(
                attachment: attachment,
                managedSessionConfirmed: false
            ),
            for: paneId
        )

        let selection = try await resolver.resolveSelection(
            for: paneId,
            serverID: serverId,
            client: SSHClient.testing(),
            runtime: runtime(),
            requestID: UUID(),
            validateOwner: {}
        )

        #expect(selection == .attachExisting(attachment))
        #expect(resolver.attachment(for: paneId)?.attachment == attachment)
    }

    @MainActor
    private func makeResolver() -> RemoteSessionAttachResolver {
        RemoteSessionAttachResolver(
            configuration: .testing,
            remoteSessions: UnavailableTerminalRemoteSessionService()
        )
    }

    @MainActor
    private func configuration(
        serverID: UUID,
        serverName: String,
        startupBehavior: RemoteSessionStartupBehavior = .createManaged
    ) -> TerminalRemoteSessionConfiguration {
        TerminalRemoteSessionConfiguration(
            deviceID: "test-device",
            enabledByDefault: { true },
            backendIdentifierByDefault: { .tmux },
            startupBehaviorByDefault: { .createManaged },
            serverSettings: { requestedID in
                guard requestedID == serverID else { return nil }
                return TerminalRemoteSessionConfiguration.ServerSettings(
                    name: serverName,
                    enabledOverride: true,
                    backendIdentifier: .tmux,
                    startupBehaviorOverride: startupBehavior,
                    startupAction: nil
                )
            },
            themeStyle: { deterministicRemoteSessionThemeStyle }
        )
    }

    private func runtime() -> RemoteSessionRuntime {
        RemoteSessionRuntime(probe: RemoteSessionProbe(
            backendIdentifier: .tmux,
            executable: try! RemoteSessionExecutable(validating: "/usr/bin/tmux"),
            implementationVariant: "tmux",
            rawVersion: "tmux 3.5a",
            semanticVersion: RemoteSessionSemanticVersion("3.5.0"),
            shellFamily: .posix,
            shellExecutable: "/bin/zsh"
        ))
    }
}
