import Combine
import Foundation
import Testing
@testable import VVTerm

private actor ReconnectCancellationGate {
    private var continuation: CheckedContinuation<Void, Never>?
    private(set) var started = false
    private(set) var cancellationObserved = false

    func waitIgnoringCancellation() async {
        started = true
        await withCheckedContinuation { continuation in
            self.continuation = continuation
        }
        cancellationObserved = Task.isCancelled
    }

    func release() {
        continuation?.resume()
        continuation = nil
    }
}

private actor ReconnectRetryGateSequence {
    private let gates: [ReconnectCancellationGate]
    private var nextGateIndex = 0

    init(_ gates: [ReconnectCancellationGate]) {
        self.gates = gates
    }

    func waitIgnoringCancellation() async {
        guard gates.indices.contains(nextGateIndex) else { return }
        let gate = gates[nextGateIndex]
        nextGateIndex += 1
        await gate.waitIgnoringCancellation()
    }
}

@MainActor
private final class ReconnectOwnerFixture {
    var facts: [UUID: TerminalReconnectPaneFacts] = [:]
    var cleanupCount = 0
    var startCount = 0
    var failureCount = 0
    var events: [TerminalReconnectCoordinator.EventStage] = []
    var applicationIsActive = true
    var networkReadyPaneIDs: [UUID] = []
    var firstCleanupGate: ReconnectCancellationGate?

    func access() -> TerminalReconnectAccess {
        TerminalReconnectAccess(
            paneFacts: { [weak self] in self?.facts[$0] },
            paneIDs: { [weak self] in self.map { Array($0.facts.keys) } ?? [] },
            paneIDsForServer: { _ in [] },
            networkPathBecameReady: { [weak self] in self?.networkReadyPaneIDs.append($0) },
            prepareTransport: { [weak self] _ in
                guard let self else { return }
                cleanupCount += 1
                if cleanupCount == 1, let firstCleanupGate {
                    await firstCleanupGate.waitIgnoringCancellation()
                }
            },
            startConnection: { [weak self] _ in
                guard let self else { return false }
                startCount += 1
                return true
            },
            failConnection: { [weak self] _ in self?.failureCount += 1 }
        )
    }
}

@MainActor
struct TerminalReconnectCoordinatorTests {
    private func makeCoordinator(
        fixture: ReconnectOwnerFixture,
        network: TerminalNetworkReadiness = .ready,
        applicationIsActive: Bool = true,
        appIsLocked: Bool = false,
        retryDelay: Duration = .seconds(5),
        sleep: @escaping TerminalReconnectCoordinator.Sleep = {
            try await Task.sleep(for: $0)
        }
    ) -> TerminalReconnectCoordinator {
        fixture.applicationIsActive = applicationIsActive
        return TerminalReconnectCoordinator(
            access: fixture.access(),
            initialNetworkReadiness: network,
            applicationIsActive: { [weak fixture] in
                fixture?.applicationIsActive == true
            },
            initialAppIsLocked: appIsLocked,
            retryDelay: retryDelay,
            sleep: sleep,
            onEvent: { [weak fixture] in fixture?.events.append($0.stage) },
            onChange: {}
        )
    }

    private func eventually(
        _ condition: @escaping @MainActor () -> Bool
    ) async -> Bool {
        for _ in 0..<200 {
            if condition() { return true }
            await Task.yield()
        }
        return condition()
    }

    private func eventuallyAsync(
        _ condition: @escaping () async -> Bool
    ) async -> Bool {
        for _ in 0..<200 {
            if await condition() { return true }
            await Task.yield()
        }
        return await condition()
    }

    @Test
    func twoOwnersDoNotShareAttemptsOrConnectionGenerations() async {
        let paneId = UUID()
        let firstFixture = ReconnectOwnerFixture()
        let secondFixture = ReconnectOwnerFixture()
        firstFixture.facts[paneId] = .init(connectionState: .disconnected, hasEstablishedConnection: true)
        secondFixture.facts[paneId] = .init(connectionState: .disconnected, hasEstablishedConnection: true)
        let first = makeCoordinator(fixture: firstFixture)
        let second = makeCoordinator(fixture: secondFixture)

        #expect(first.request(for: paneId, requiresReadyNetwork: true))
        #expect(await eventually { firstFixture.startCount == 1 })
        #expect(second.attempt(for: paneId) == nil)
        #expect(second.connectionGeneration(for: paneId) == paneId)
        #expect(first.connectionGeneration(for: paneId) != paneId)

        #expect(second.request(for: paneId, requiresReadyNetwork: true))
        #expect(await eventually { secondFixture.startCount == 1 })
        #expect(first.connectionGeneration(for: paneId) != second.connectionGeneration(for: paneId))
    }

    @Test
    func staleGenerationCannotPublishAfterReplacementCleanup() async {
        let paneId = UUID()
        let blocker = ReconnectCancellationGate()
        let fixture = ReconnectOwnerFixture()
        fixture.firstCleanupGate = blocker
        fixture.facts[paneId] = .init(connectionState: .disconnected, hasEstablishedConnection: true)
        let coordinator = makeCoordinator(fixture: fixture)
        let staleGeneration = UUID()
        let replacementGeneration = UUID()

        #expect(coordinator.request(
            for: paneId,
            requiresReadyNetwork: true,
            generation: staleGeneration,
            replacingCurrent: true
        ))
        #expect(await eventuallyAsync { await blocker.started })
        #expect(coordinator.request(
            for: paneId,
            requiresReadyNetwork: true,
            generation: replacementGeneration,
            replacingCurrent: true
        ))
        #expect(await eventually { fixture.startCount == 1 })
        #expect(coordinator.attempt(for: paneId)?.generation == replacementGeneration)

        await blocker.release()
        await Task.yield()
        #expect(fixture.startCount == 1)
        #expect(coordinator.attempt(for: paneId)?.generation == replacementGeneration)
    }

    @Test
    func networkApplicationAndLockSignalsResumeInOrderWithoutDuplicateStart() async {
        let paneId = UUID()
        let fixture = ReconnectOwnerFixture()
        fixture.facts[paneId] = .init(connectionState: .disconnected, hasEstablishedConnection: true)
        let coordinator = makeCoordinator(
            fixture: fixture,
            applicationIsActive: false,
            appIsLocked: true
        )

        #expect(coordinator.request(for: paneId, requiresReadyNetwork: true))
        #expect(await eventually {
            coordinator.attempt(for: paneId)?.phase == .waitingForApplication
        })
        coordinator.receiveApplicationActivity(true)
        #expect(coordinator.attempt(for: paneId)?.phase == .waitingForUnlock)

        coordinator.receiveNetworkReadiness(.unavailable)
        coordinator.receiveAppLock(false)
        #expect(await eventually {
            coordinator.attempt(for: paneId)?.phase == .waitingForNetwork
        })
        #expect(fixture.startCount == 0)

        coordinator.receiveNetworkReadiness(.ready)
        coordinator.receiveNetworkReadiness(.ready)
        coordinator.receiveApplicationActivity(true)
        coordinator.receiveAppLock(false)
        #expect(await eventually { fixture.startCount == 1 })
        #expect(coordinator.attempt(for: paneId)?.phase == .connecting)
    }

    @Test
    func reconcileUsesInjectedApplicationActivityAndRoutesNetworkReadyOnce() async {
        let paneId = UUID()
        let fixture = ReconnectOwnerFixture()
        fixture.facts[paneId] = .init(
            connectionState: .disconnected,
            hasEstablishedConnection: true
        )
        let coordinator = makeCoordinator(
            fixture: fixture,
            network: .unavailable,
            applicationIsActive: false
        )

        coordinator.reconcileAutomaticReconnect(
            for: paneId,
            sceneIsActive: true,
            automaticReconnectAllowed: true
        )
        #expect(!coordinator.applicationIsActive)
        #expect(fixture.startCount == 0)

        coordinator.receiveNetworkReadiness(.ready)
        coordinator.receiveNetworkReadiness(.ready)
        #expect(fixture.networkReadyPaneIDs == [paneId])
        #expect(fixture.startCount == 0)

        fixture.applicationIsActive = true
        #expect(coordinator.applicationActivityIsActive)
        coordinator.reconcileAutomaticReconnect(
            for: paneId,
            sceneIsActive: true,
            automaticReconnectAllowed: true
        )
        #expect(coordinator.applicationIsActive)
        #expect(await eventually { fixture.startCount == 1 })
    }

    @Test
    func duplicateGenerationDoesNotCreateSecondReconnect() async {
        let paneId = UUID()
        let generation = UUID()
        let fixture = ReconnectOwnerFixture()
        fixture.facts[paneId] = .init(connectionState: .disconnected, hasEstablishedConnection: true)
        let coordinator = makeCoordinator(fixture: fixture)

        #expect(coordinator.request(
            for: paneId,
            requiresReadyNetwork: true,
            generation: generation,
            replacingCurrent: true
        ))
        #expect(!coordinator.request(
            for: paneId,
            requiresReadyNetwork: true,
            generation: generation,
            replacingCurrent: true
        ))
        #expect(await eventually { fixture.startCount == 1 })
        #expect(fixture.cleanupCount == 1)
    }

    @Test
    func blockedCleanupDoesNotRetainOwnerAndObservesCancellation() async {
        let paneId = UUID()
        let blocker = ReconnectCancellationGate()
        let fixture = ReconnectOwnerFixture()
        fixture.firstCleanupGate = blocker
        fixture.facts[paneId] = .init(connectionState: .disconnected, hasEstablishedConnection: true)
        var coordinator: TerminalReconnectCoordinator? = makeCoordinator(fixture: fixture)
        weak var weakCoordinator = coordinator

        #expect(coordinator?.request(for: paneId, requiresReadyNetwork: true) == true)
        #expect(await eventuallyAsync { await blocker.started })
        coordinator = nil
        #expect(weakCoordinator == nil)

        await blocker.release()
        #expect(await eventuallyAsync { await blocker.cancellationObserved })
        #expect(fixture.startCount == 0)
    }

    @Test
    func blockedRetrySleepDoesNotRetainOwnerAndObservesCancellation() async {
        let paneId = UUID()
        let retryGate = ReconnectCancellationGate()
        let fixture = ReconnectOwnerFixture()
        fixture.facts[paneId] = .init(connectionState: .connected, hasEstablishedConnection: true)
        var coordinator: TerminalReconnectCoordinator? = makeCoordinator(
            fixture: fixture,
            retryDelay: .seconds(5),
            sleep: { _ in await retryGate.waitIgnoringCancellation() }
        )
        weak var weakCoordinator = coordinator
        coordinator?.reconcileAutomaticReconnect(
            for: paneId,
            sceneIsActive: true,
            automaticReconnectAllowed: true
        )
        fixture.facts[paneId] = .init(
            connectionState: .failed(terminalExternalFailure("temporary")),
            hasEstablishedConnection: true
        )
        coordinator?.connectionStateDidChange(for: paneId)

        #expect(await eventuallyAsync { await retryGate.started })
        coordinator = nil
        #expect(weakCoordinator == nil)
        await retryGate.release()
        #expect(await eventuallyAsync { await retryGate.cancellationObserved })
        #expect(fixture.startCount == 0)
    }

    @Test
    func staleCancellationIgnoringRetryCannotRemoveOrStartReplacement() async {
        let paneId = UUID()
        let firstRetryGate = ReconnectCancellationGate()
        let replacementRetryGate = ReconnectCancellationGate()
        let retrySequence = ReconnectRetryGateSequence([
            firstRetryGate,
            replacementRetryGate,
        ])
        let fixture = ReconnectOwnerFixture()
        fixture.facts[paneId] = .init(
            connectionState: .connected,
            hasEstablishedConnection: true
        )
        let coordinator = makeCoordinator(
            fixture: fixture,
            retryDelay: .seconds(5),
            sleep: { _ in await retrySequence.waitIgnoringCancellation() }
        )
        coordinator.reconcileAutomaticReconnect(
            for: paneId,
            sceneIsActive: true,
            automaticReconnectAllowed: true
        )

        fixture.facts[paneId] = .init(
            connectionState: .failed(terminalExternalFailure("first")),
            hasEstablishedConnection: true
        )
        coordinator.connectionStateDidChange(for: paneId)
        #expect(await eventuallyAsync { await firstRetryGate.started })

        fixture.facts[paneId] = .init(
            connectionState: .connecting,
            hasEstablishedConnection: true
        )
        coordinator.connectionStateDidChange(for: paneId)
        fixture.facts[paneId] = .init(
            connectionState: .failed(terminalExternalFailure("replacement")),
            hasEstablishedConnection: true
        )
        coordinator.connectionStateDidChange(for: paneId)
        #expect(await eventuallyAsync { await replacementRetryGate.started })

        await firstRetryGate.release()
        #expect(await eventuallyAsync { await firstRetryGate.cancellationObserved })
        for _ in 0..<20 {
            await Task.yield()
        }
        #expect(coordinator.attempt(for: paneId) == nil)
        #expect(fixture.startCount == 0)

        await replacementRetryGate.release()
        #expect(await eventually { fixture.startCount == 1 })
        #expect(coordinator.attempt(for: paneId)?.phase == .connecting)
    }
}
