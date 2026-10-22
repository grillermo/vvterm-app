import Foundation
import Testing
@testable import VVTerm

struct ActiveConnectionSwitcherPolicyTests {
    @Test
    func listsActiveServersSortedByName() {
        let beta = makeServer(name: "beta")
        let alpha = makeServer(name: "Alpha")
        let idle = makeServer(name: "Idle")

        let options = ActiveConnectionSwitcherPolicy.options(
            currentServerId: beta.id,
            activeServerIds: [alpha.id, beta.id],
            servers: [beta, idle, alpha]
        )

        #expect(options == [
            ActiveConnectionSwitcherOption(id: alpha.id, title: "Alpha"),
            ActiveConnectionSwitcherOption(id: beta.id, title: "beta"),
        ])
    }

    @Test
    func hidesSwitcherWithSingleActiveConnection() {
        let server = makeServer(name: "Only")

        let options = ActiveConnectionSwitcherPolicy.options(
            currentServerId: server.id,
            activeServerIds: [server.id],
            servers: [server]
        )

        #expect(options.isEmpty)
    }

    @Test
    func hidesSwitcherWhileCurrentServerIsNotActiveYet() {
        let connecting = makeServer(name: "Connecting")
        let first = makeServer(name: "First")
        let second = makeServer(name: "Second")

        let options = ActiveConnectionSwitcherPolicy.options(
            currentServerId: connecting.id,
            activeServerIds: [first.id, second.id],
            servers: [connecting, first, second]
        )

        #expect(options.isEmpty)
    }

    @Test
    func ignoresActiveIdsWithoutConfiguredServer() {
        let current = makeServer(name: "Current")

        let options = ActiveConnectionSwitcherPolicy.options(
            currentServerId: current.id,
            activeServerIds: [current.id, UUID()],
            servers: [current]
        )

        #expect(options.isEmpty)
    }

    private func makeServer(name: String) -> Server {
        Server(
            workspaceId: UUID(),
            name: name,
            host: "example.com",
            username: "vvterm"
        )
    }
}
