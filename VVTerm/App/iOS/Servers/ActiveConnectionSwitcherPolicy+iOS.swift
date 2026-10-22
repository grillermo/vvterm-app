import Foundation

nonisolated struct ActiveConnectionSwitcherOption: Equatable, Identifiable, Sendable {
    let id: UUID
    let title: String
}

/// Decides which active connections the terminal route offers as switch
/// targets. The switcher appears only when there is another connection to
/// switch to and the current server is itself one of the active connections.
nonisolated enum ActiveConnectionSwitcherPolicy {
    static func options(
        currentServerId: UUID,
        activeServerIds: Set<UUID>,
        servers: [Server]
    ) -> [ActiveConnectionSwitcherOption] {
        let options = servers
            .filter { activeServerIds.contains($0.id) }
            .map { ActiveConnectionSwitcherOption(id: $0.id, title: $0.name) }
            .sorted {
                $0.title.localizedCaseInsensitiveCompare($1.title) == .orderedAscending
            }

        guard options.count > 1,
              options.contains(where: { $0.id == currentServerId }) else {
            return []
        }
        return options
    }
}
