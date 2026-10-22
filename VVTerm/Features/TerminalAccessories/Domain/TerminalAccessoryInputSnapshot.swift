import Foundation

nonisolated enum TerminalAccessoryResolvedItem: Equatable, Sendable {
    case system(TerminalAccessorySystemActionID)
    case custom(TerminalAccessoryCustomAction)
}

nonisolated struct TerminalAccessoryInputSnapshot: Equatable, Sendable {
    let resolvedItems: [TerminalAccessoryResolvedItem]

    init(profile: TerminalAccessoryProfile) {
        var customActionsByID: [UUID: TerminalAccessoryCustomAction] = [:]
        for action in profile.customActions where !action.isDeleted {
            customActionsByID[action.id] = action
        }
        resolvedItems = profile.layout.activeItems.compactMap { item in
            switch item {
            case .system(let actionID):
                return .system(actionID)
            case .custom(let actionID):
                guard let action = customActionsByID[actionID] else { return nil }
                return .custom(action)
            }
        }
    }
}
