import Foundation
import Testing
@testable import VVTerm

private final class EmptyBundleToken {}

struct RemoteTerminalTypeResolverTests {
    private let posixEnvironment = RemoteEnvironment(
        platform: .linux,
        shellProfile: .posix(shellName: "zsh"),
        activeShellName: "zsh",
        powerShellExecutable: nil
    )

    private let cmdEnvironment = RemoteEnvironment(
        platform: .windows,
        shellProfile: .cmd,
        activeShellName: "cmd.exe",
        powerShellExecutable: nil
    )

    private let terminfoSource = """
    xterm-ghostty|ghostty|Ghostty,
    \tclear=\\E[H\\E[2J,
    \tE3=\\E[3J,
    """

    private enum TestError: Error {
        case commandFailed
        case invalidWrappedCommand
    }

    actor FakeExecutor {
        struct Invocation: Sendable {
            let command: String
            let timeout: Duration?
        }

        private var outputs: [Result<String, Error>]
        private var invocations: [Invocation] = []

        init(outputs: [Result<String, Error>]) {
            self.outputs = outputs
        }

        func run(command: String, timeout: Duration?) throws -> String {
            invocations.append(Invocation(command: command, timeout: timeout))
            guard !outputs.isEmpty else {
                Issue.record("Unexpected extra command: \(command)")
                return ""
            }
            switch outputs.removeFirst() {
            case .success(let output):
                return output
            case .failure(let error):
                throw error
            }
        }

        func recordedInvocations() -> [Invocation] {
            invocations
        }
    }

    @Test
    func resolveFallsBackForNonPOSIXRemotesWithoutExecutingCommands() async {
        let executor = FakeExecutor(outputs: [])

        let terminalType = await resolve(environment: cmdEnvironment, executor: executor)

        #expect(terminalType == .xterm256Color)
        #expect(await executor.recordedInvocations().isEmpty)
    }

    @Test
    func resolveUsesGhosttyForACompleteEntryInOneBoundedCommand() async {
        let executor = FakeExecutor(outputs: [
            .success("__VVTERM_XTERM_GHOSTTY_INSTALLED__")
        ])

        let terminalType = await resolve(environment: posixEnvironment, executor: executor)

        let invocations = await executor.recordedInvocations()
        #expect(terminalType == .xtermGhostty)
        #expect(invocations.count == 1)
        #expect(invocations[0].timeout == .seconds(12))
        #expect(invocations[0].command.contains("infocmp -1 -x xterm-ghostty"))
        #expect(invocations[0].command.contains("tic -x"))
    }

    @Test
    func commandsRequireE3AndNeverTrustCompiledFileExistence() {
        let install = RemoteTerminalTypeResolver.installCommand(terminfoSource: terminfoSource)
        let probe = RemoteTerminalTypeResolver.probeCommand()

        for command in [install, probe] {
            #expect(command.contains("vvterm_xterm_ghostty_is_current"))
            #expect(command.contains("infocmp -1 -x xterm-ghostty"))
            #expect(command.contains("E3=\\E[3J,"))
            #expect(!command.contains("/x/xterm-ghostty"))
            #expect(!command.contains("/78/xterm-ghostty"))
        }
        #expect(install.contains("if ! command -v tic"))
        #expect(install.contains("if ! command -v infocmp"))
    }

    @Test
    func resolveInstallsTrustedSourceWhenEntryIsStale() async {
        let executor = FakeExecutor(outputs: [
            .success("__VVTERM_XTERM_GHOSTTY_INSTALLED__")
        ])

        let terminalType = await resolve(environment: posixEnvironment, executor: executor)

        let command = await executor.recordedInvocations().first?.command
        #expect(terminalType == .xtermGhostty)
        #expect(command?.contains("tic -x -o \"$HOME/.terminfo\" -") == true)
        #expect(command?.contains("xterm-ghostty|ghostty|Ghostty") == true)
    }

    @Test(arguments: [
        "__VVTERM_XTERM_GHOSTTY_NO_TIC__",
        "__VVTERM_XTERM_GHOSTTY_INSTALL_FAILED__",
        "unexpected output"
    ])
    func resolveFallsBackForEveryUnusableInstallResult(_ output: String) async {
        let executor = FakeExecutor(outputs: [.success(output)])

        let terminalType = await resolve(environment: posixEnvironment, executor: executor)

        #expect(terminalType == .xterm256Color)
    }

    @Test
    func resolveFallsBackWhenInstallCommandThrows() async {
        let executor = FakeExecutor(outputs: [.failure(TestError.commandFailed)])

        let terminalType = await resolve(environment: posixEnvironment, executor: executor)

        #expect(terminalType == .xterm256Color)
    }

    @Test
    func missingBundledSourceUsesCapabilityProbeWithFiveSecondTimeout() async {
        let executor = FakeExecutor(outputs: [
            .success("__VVTERM_XTERM_GHOSTTY_OK__")
        ])

        let terminalType = await RemoteTerminalTypeResolver.resolve(
            environment: posixEnvironment,
            execute: { command, timeout in
                try await executor.run(command: command, timeout: timeout)
            },
            bundle: Bundle(for: EmptyBundleToken.self),
            terminfoSource: nil
        )

        let invocations = await executor.recordedInvocations()
        #expect(terminalType == .xtermGhostty)
        #expect(invocations.count == 1)
        #expect(invocations[0].timeout == .seconds(5))
    }

    @Test
    func bundledTerminfoSourceIncludesScrollbackEraseCapability() throws {
        let source = try #require(RemoteTerminalBootstrap.ghosttyTerminfoSource())

        #expect(source.contains("E3=\\E[3J,"))
    }

    private func resolve(
        environment: RemoteEnvironment,
        executor: FakeExecutor
    ) async -> RemoteTerminalType {
        await RemoteTerminalTypeResolver.resolve(
            environment: environment,
            execute: { command, timeout in
                try await executor.run(command: command, timeout: timeout)
            },
            terminfoSource: terminfoSource
        )
    }
}
