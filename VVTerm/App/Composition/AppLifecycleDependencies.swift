@MainActor
struct AppLifecycleDependencies {
    let subscribeToRemoteChanges: @MainActor () async -> Void
    let refreshNetwork: @MainActor () -> Void

    let endLiveActivitiesForApplicationTermination: @MainActor () -> Bool
}
