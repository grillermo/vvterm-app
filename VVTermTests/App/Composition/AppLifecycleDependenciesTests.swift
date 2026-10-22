import Testing
@testable import VVTerm

@MainActor
struct AppLifecycleDependenciesTests {
    @Test
    func routesEachLifecycleActionToItsConfiguredEffect() async {
        var events: [String] = []
        let subscribeToRemoteChanges: @MainActor () async -> Void = {
            events.append("subscribe")
        }
        let refreshNetwork: @MainActor () -> Void = {
            events.append("refresh")
        }
        let dependencies = AppLifecycleDependencies(
            subscribeToRemoteChanges: subscribeToRemoteChanges,
            refreshNetwork: refreshNetwork,
            endLiveActivitiesForApplicationTermination: {
                events.append("end-live-activities")
                return false
            }
        )

        await dependencies.subscribeToRemoteChanges()
        dependencies.refreshNetwork()
        let didEndLiveActivities = dependencies.endLiveActivitiesForApplicationTermination()
        #expect(!didEndLiveActivities)

        #expect(events == ["subscribe", "refresh", "end-live-activities"])
    }
}
