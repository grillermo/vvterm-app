import Foundation
import Testing
@testable import VVTerm

private actor ZellijProbeExecutor {
    private let result: Result<String, Error>
    private var commands: [String] = []

    init(_ result: Result<String, Error>) {
        self.result = result
    }

    func run(_ command: String) throws -> String {
        commands.append(command)
        return try result.get()
    }

    func recordedCommands() -> [String] {
        commands
    }
}

private final class ZellijFixtureBundleToken {}

struct ZellijRemoteSessionBackendTests {
    @Test(arguments: ["0.44.3", "0.45.0"])
    func probePinsSupportedCLIVersions(_ version: String) throws {
        let result = try #require(ZellijRemoteSessionParser.parseProbe("""
        noise
        __VVTERM_ZELLIJ_OK__
        __VVTERM_ZELLIJ_PATH__/usr/local/bin/zellij
        zellij \(version)
        """))

        #expect(result.executable.path == "/usr/local/bin/zellij")
        #expect(result.rawVersion == "zellij \(version)")
        #expect(result.semanticVersion == RemoteSessionSemanticVersion(version))
        #expect(ZellijRemoteSessionBackend.supportedVersions.contains(result.semanticVersion))
    }

    @Test
    func availabilityDistinguishesMissingUnsupportedAndInvalidResponses() async {
        let missing = await availability(
            output: .success(ZellijRemoteSessionCommandBuilder.missingMarker)
        )
        let oldPatch = await availability(output: .success(probeOutput(version: "0.44.2")))
        let unpinnedPatch = await availability(
            output: .success(probeOutput(version: "0.45.1"))
        )
        let futureMinor = await availability(
            output: .success(probeOutput(version: "0.46.0"))
        )
        let invalid = await availability(output: .success("unexpected"))

        #expect(missing == .confirmedMissing)
        #expect({ if case .incompatible = oldPatch { true } else { false } }())
        #expect({ if case .incompatible = unpinnedPatch { true } else { false } }())
        #expect({ if case .incompatible = futureMinor { true } else { false } }())
        #expect(invalid == .indeterminate(.invalidResponse))
    }

    @Test
    func unsupportedPlatformDoesNotProbe() async {
        let backend = ZellijRemoteSessionBackend()
        let executor = ZellijProbeExecutor(.success("unexpected"))
        let windows = RemoteEnvironment(
            platform: .windows,
            shellProfile: .powershell(executableName: "pwsh"),
            activeShellName: "pwsh",
            powerShellExecutable: "pwsh"
        )

        let result = await backend.availability(in: windows) { command in
            try await executor.run(command)
        }

        #expect(result == .unsupportedEnvironment)
        #expect(await executor.recordedCommands().isEmpty)
    }

    @Test
    func parserPreservesExplicitOwnershipAndCleanupSafety() throws {
        let sessions = try ZellijRemoteSessionParser.parseSessionList("""
        name=vvterm-user-created\townership=external\tclients=0
        name=managed-attached\townership=managed\tclients=2
        name=managed-unknown\townership=managed\tclients=?
        name=managed-detached\townership=managed\tclients=0
        """)

        #expect(sessions.map(\.attachment.ownership) == [
            .external, .managed, .managed, .managed
        ])
        #expect(sessions.map(\.cleanupDisposition) == [
            .safeToDelete, .inUse, .unknown, .safeToDelete
        ])
        #expect(
            sessions.first?.id.rawValue == "vvterm-user-created"
                && sessions.first?.attachment.ownership == .external
        )
        #expect(
            RemoteSessionCleanupPolicy.identifiersToDelete(
                from: sessions,
                keeping: []
            ).map(\.rawValue) == ["managed-detached"]
        )
    }

    @Test
    func parserRejectsMalformedDuplicateAndUnboundedLists() {
        for output in [
            "missing metadata",
            "name=bad/name\townership=external\tclients=0",
            "name=bad\townership=guessed\tclients=0",
            "name=bad\townership=managed\tclients=-1",
            "name=bad\townership=managed\tclients=4097"
        ] {
            #expect(throws: SSHError.self) {
                try ZellijRemoteSessionParser.parseSessionList(output)
            }
        }
        #expect(throws: SSHError.self) {
            try ZellijRemoteSessionParser.parseSessionList("""
            name=same\townership=external\tclients=0
            name=same\townership=managed\tclients=0
            """)
        }
        #expect(throws: SSHError.self) {
            try ZellijRemoteSessionParser.parseSessionList(
                String(repeating: "x", count: ZellijRemoteSessionParser.maximumOutputBytes + 1)
            )
        }
        let excessiveList = (0...ZellijRemoteSessionParser.maximumSessionCount)
            .map { "name=s\($0)\townership=external\tclients=0" }
            .joined(separator: "\n")
        #expect(throws: SSHError.self) {
            try ZellijRemoteSessionParser.parseSessionList(excessiveList)
        }
    }

    @Test
    func workingDirectoryMustBeAbsoluteBoundedAndLive() {
        let valid = """
        [{"is_plugin":false,"is_focused":false,"exited":false,"pane_cwd":"/srv/old"},{"is_plugin":false,"is_focused":true,"exited":false,"pane_cwd":"/srv/project"}]
        """
        let exited = """
        [{"is_plugin":false,"is_focused":true,"exited":true,"pane_cwd":"/srv/stale"}]
        """
        let relative = """
        [{"is_plugin":false,"is_focused":true,"exited":false,"pane_cwd":"relative"}]
        """
        let tooLongPath = "/" + String(
            repeating: "x",
            count: RemoteSessionExecutable.maximumLength
        )
        let tooLong = """
        [{"is_plugin":false,"is_focused":true,"exited":false,"pane_cwd":"\(tooLongPath)"}]
        """

        #expect(ZellijRemoteSessionParser.parseWorkingDirectory(valid) == "/srv/project")
        #expect(ZellijRemoteSessionParser.parseWorkingDirectory(exited) == nil)
        #expect(ZellijRemoteSessionParser.parseWorkingDirectory(relative) == nil)
        #expect(ZellijRemoteSessionParser.parseWorkingDirectory(tooLong) == nil)
        #expect(ZellijRemoteSessionParser.parseWorkingDirectory("not-json") == nil)
    }

    @Test
    func workingDirectoryLookupRequestsAllPaneFields() throws {
        let command = try ZellijRemoteSessionCommandBuilder.listPanesCommand(
            attachment: RemoteSessionAttachment(
                identifier: identifier("work"),
                ownership: .external
            ),
            runtime: runtime()
        )

        #expect(command.contains("'action' 'list-panes' '--all' '--json'"))
    }

    @Test
    func managedNamesAreDeterministicAndFitUTF8Bounds() throws {
        let backend = ZellijRemoteSessionBackend()
        let entityID = UUID(uuidString: "11111111-2222-3333-4444-555555555555")!
        let first = try backend.managedIdentifier(
            deviceID: "AAAAAAAA-BBBB-CCCC-DDDD-EEEEEEEEEEEE",
            entityID: entityID,
            serverName: "Prod API 🚀"
        )
        let repeated = try backend.managedIdentifier(
            deviceID: "AAAAAAAA-BBBB-CCCC-DDDD-EEEEEEEEEEEE",
            entityID: entityID,
            serverName: "Prod API 🚀"
        )

        #expect(first == repeated)
        #expect(first.rawValue.utf8.count <= RemoteSessionIdentifier.maximumRawValueLength)
        #expect(ZellijRemoteSessionParser.isValidSessionName(first.rawValue))
    }

    @Test
    func listScopesUseSeparateNamespacesAndLiveActions() throws {
        let external = try ZellijRemoteSessionCommandBuilder.listCommand(
            scope: .userVisible,
            runtime: runtime()
        )
        let managed = try ZellijRemoteSessionCommandBuilder.listCommand(
            scope: .managedCleanup,
            runtime: runtime()
        )

        for command in [external, managed] {
            #expect(command.contains("'list-sessions' '--short' '--no-formatting'"))
            #expect(command.contains("'action' 'list-panes' '--json'"))
            #expect(command.contains("'action' 'list-clients'"))
            #expect(!command.contains("EXITED"))
            #expect(!command.localizedCaseInsensitiveContains("resurrect"))
        }
        #expect(!external.contains("ZELLIJ_SOCKET_DIR="))
        #expect(external.contains("ownership=%s\tclients=%s"))
        #expect(managed.contains("ZELLIJ_SOCKET_DIR="))
        #expect(managed.contains("/tmp/vvterm-zellij-"))
        #expect(managed.contains("vvtermZellijOwnershipMarker"))
    }

    @Test
    func blankManagedCreationUsesNativeShellAndDisablesSerialization() throws {
        let command = try launchCommand(
            intent: .ensureManaged(
                identifier: identifier("work session"),
                initialCommand: " \n "
            )
        )

        #expect(command.contains("'attach' '--create-background' 'work session'"))
        #expect(command.contains("'options' '--session-serialization' 'false'"))
        #expect(!command.contains("--layout-string"))
        #expect(!command.contains("'/bin/sh' '-lc'"))
        #expect(!command.contains("ZELLIJ_CONFIG_DIR"))
        #expect(!command.contains("ZELLIJ_CONFIG_FILE"))
    }

    @Test
    func customManagedCreationUsesOneNativeKDLLayout() throws {
        let command = try launchCommand(
            intent: .ensureManaged(
                identifier: identifier("work session"),
                initialCommand: "cd ~/project && printf 'ready' && exec $SHELL -l"
            )
        )

        #expect(command.contains("'--layout-string'"))
        #expect(command.contains("pane command="))
        #expect(command.contains("args"))
        #expect(command.contains("'attach' '--create-background' 'work session'"))
        #expect(command.contains("'options' '--session-serialization' 'false'"))
        #expect(!command.contains("'run'"))
        #expect(!command.contains("run --in-place"))
        #expect(!command.contains("focus-pane-with-id"))
        #expect(!command.contains("send-keys"))
        #expect(!command.contains("send-text"))
        #expect(!command.contains("delete-session"))
        #expect(!command.contains("incomplete"))
        #expect(!command.contains("dispatched"))
    }

    @Test
    func customManagedCreationRunsCommandInsideLoginShell() throws {
        let rawCommand = #"printf '%s' "$HOME""#
        let command = try launchCommand(
            intent: .ensureManaged(
                identifier: identifier("login shell"),
                initialCommand: rawCommand
            )
        )

        #expect(command.contains("VVTERM_STARTUP="))
        #expect(command.contains("-lic"))

        // The layout string embeds `ZellijKDLStringEncoder.encode(loginShellStartupCommand(cmd))`
        // verbatim, then the renderer wraps the whole `--layout-string` argument in
        // `RemoteTerminalBootstrap.shellQuoted` (see RemoteSessionCommandPlan.swift ~109-110).
        // The resulting invocation string is itself embedded in the larger managed-session
        // setup script, which `ZellijRemoteSessionBackend` wraps a second time via
        // `RemoteTerminalBootstrap.wrapPOSIXShellCommand` for the final "/bin/sh -lc" command.
        // Both escaping passes are per-character substitutions (homomorphic over
        // concatenation), so applying them in the same order directly to the encoded
        // command reproduces the exact substring the double wrap embeds, without
        // touching either helper's private escaping logic.
        let loginShellCommand = RemoteTerminalBootstrap.loginShellStartupCommand(rawCommand)
        let encodedCommand = try ZellijKDLStringEncoder.encode(loginShellCommand)
        let singleQuoted = try unwrappedShellQuotedArgument(encodedCommand)
        let doubleWrapped = try escapedShellArgument(singleQuoted)
        #expect(command.contains(doubleWrapped))
    }

    /// Extracts the escaped text `RemoteTerminalBootstrap.shellQuoted` would embed for
    /// `raw`, without depending on its private escaping logic.
    private func unwrappedShellQuotedArgument(_ raw: String) throws -> String {
        let quoted = RemoteTerminalBootstrap.shellQuoted(raw)
        guard quoted.hasPrefix("'"), quoted.hasSuffix("'") else {
            struct UnexpectedShellQuotedShape: Error {}
            throw UnexpectedShellQuotedShape()
        }
        return String(quoted.dropFirst().dropLast())
    }

    /// Extracts the escaped-argument text `RemoteTerminalBootstrap.wrapPOSIXShellCommand`
    /// would embed for `raw`, without depending on its private escaping logic.
    private func escapedShellArgument(_ raw: String) throws -> String {
        let wrapped = RemoteTerminalBootstrap.wrapPOSIXShellCommand(raw)
        let prefix = "/bin/sh -lc \""
        let suffix = "\""
        guard wrapped.hasPrefix(prefix), wrapped.hasSuffix(suffix) else {
            struct UnexpectedWrapShape: Error {}
            throw UnexpectedWrapShape()
        }
        return String(wrapped.dropFirst(prefix.count).dropLast(suffix.count))
    }

    @Test
    func attachNeverCarriesAnInitialCommandOrCreationOption() throws {
        let attachment = RemoteSessionAttachment(
            identifier: try identifier("vvterm-user-created"),
            ownership: .external
        )
        let command = try launchCommand(intent: .attach(attachment))

        #expect(command.contains("'attach' 'vvterm-user-created'"))
        #expect(command.contains("'action' 'list-panes' '--json'"))
        #expect(!command.contains("--create"))
        #expect(!command.contains("--layout-string"))
        #expect(!command.contains("ZELLIJ_SOCKET_DIR="))
        #expect(!command.contains("/srv/default"))
    }

    @Test
    func presenceUsesLiveProbeAndExplicitManagedOwnership() throws {
        let external = try ZellijRemoteSessionCommandBuilder.presenceProbe(
            attachment: RemoteSessionAttachment(
                identifier: identifier("vvterm-user-created"),
                ownership: .external
            ),
            runtime: runtime()
        )
        let managed = try ZellijRemoteSessionCommandBuilder.presenceProbe(
            attachment: RemoteSessionAttachment(
                identifier: identifier("managed"),
                ownership: .managed
            ),
            runtime: runtime()
        )

        #expect(external.command.contains("'action' 'list-panes' '--json'"))
        #expect(!external.command.contains("list-sessions"))
        #expect(!external.command.contains("ZELLIJ_SOCKET_DIR="))
        #expect(managed.command.contains("vvtermZellijOwnershipMarker"))
        #expect(managed.command.contains("ZELLIJ_SOCKET_DIR="))
        #expect(external.sessionExists(in: external.existsMarker) == true)
        #expect(external.sessionExists(in: external.missingMarker) == false)
        #expect(external.sessionExists(in: "unrelated") == nil)
    }

    @Test
    func KDLStringEncoderPreservesBytesWithoutShellQuoting() throws {
        let input = "\"\\\n\r\té$`(){};\u{0001}"
        let expected = "\""
            + "\\\""
            + "\\\\"
            + "\\n"
            + "\\r"
            + "\\t"
            + "é$`(){};"
            + "\\u{1}"
            + "\""

        #expect(try ZellijKDLStringEncoder.encode(input) == expected)
        #expect(try ZellijKDLStringEncoder.encode("$(echo no) `echo no`")
            == "\"$(echo no) `echo no`\"")
        #expect(throws: ZellijKDLStringEncoder.EncodingError.outputTooLong) {
            try ZellijKDLStringEncoder.encode(
                String(repeating: "\\", count: ZellijKDLStringEncoder.maximumEncodedByteCount)
            )
        }
    }

    @Test
    func runtimeRejectsUnpinnedVersionsAndDeclaresStartupSupport() throws {
        #expect(ZellijRemoteSessionBackend().metadata.managedStartupCommandSupport == .supported)
        #expect(throws: SSHError.self) {
            try ZellijRemoteSessionBackend().launchPlan(
                for: launchRequest(
                    intent: .ensureManaged(
                        identifier: self.identifier("managed"),
                        initialCommand: nil
                    )
                ),
                runtime: self.runtime(version: "0.45.1")
            )
        }
    }

    private func availability(
        output: Result<String, Error>
    ) async -> RemoteSessionAvailability {
        let executor = ZellijProbeExecutor(output)
        return await ZellijRemoteSessionBackend().availability(in: .fallbackPOSIX) { command in
            try await executor.run(command)
        }
    }

    private func probeOutput(version: String) -> String {
        """
        \(ZellijRemoteSessionCommandBuilder.availableMarker)
        \(ZellijRemoteSessionCommandBuilder.pathMarker)/opt/tools/zellij
        zellij \(version)
        """
    }

    private func launchCommand(
        intent: RemoteSessionLaunchIntent,
        executablePath: String = "/opt/tools/zellij",
        workingDirectory: String = "/srv/default"
    ) throws -> String {
        try ZellijRemoteSessionBackend().launchPlan(
            for: launchRequest(
                intent: intent,
                workingDirectory: workingDirectory
            ),
            runtime: runtime(executablePath: executablePath)
        ).command
    }

    private func launchRequest(
        intent: RemoteSessionLaunchIntent,
        workingDirectory: String = "/srv/default"
    ) -> RemoteSessionLaunchRequest {
        RemoteSessionLaunchRequest(
            intent: intent,
            workingDirectory: workingDirectory,
            lifecycleEnvelope: deterministicRemoteSessionLifecycleEnvelope,
            transport: .ssh,
            themeStyle: deterministicRemoteSessionThemeStyle
        )
    }

    private func identifier(_ rawValue: String) throws -> RemoteSessionIdentifier {
        try RemoteSessionIdentifier(backendIdentifier: .zellij, validating: rawValue)
    }

    private func runtime(
        version: String = "0.45.0",
        executablePath: String = "/opt/tools/zellij"
    ) throws -> RemoteSessionRuntime {
        let parsedVersion = try #require(RemoteSessionSemanticVersion(version))
        return RemoteSessionRuntime(probe: RemoteSessionProbe(
            backendIdentifier: .zellij,
            executable: try RemoteSessionExecutable(validating: executablePath),
            implementationVariant: "zellij-\(parsedVersion.major).\(parsedVersion.minor)",
            rawVersion: "zellij \(version)",
            semanticVersion: parsedVersion,
            shellFamily: .posix,
            shellExecutable: "/bin/zsh"
        ))
    }
}
