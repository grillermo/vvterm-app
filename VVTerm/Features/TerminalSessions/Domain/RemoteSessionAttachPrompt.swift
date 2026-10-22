import Foundation

struct RemoteSessionSelectionInfo: Identifiable, Equatable {
    let attachment: RemoteSessionAttachment
    let attachedClientCount: Int?
    let containerCount: Int?

    var id: RemoteSessionIdentifier { attachment.identifier }
    var displayName: String { id.rawValue }
}

struct RemoteSessionAttachPrompt: Identifiable, Equatable {
    /// Unique shell-start request that owns this prompt.
    let id: UUID
    let paneId: UUID
    let backendIdentifier: RemoteSessionBackendIdentifier
    let backendName: String
    let existingSessions: [RemoteSessionSelectionInfo]
    /// Whether the backend can create a session under a user-chosen name.
    let supportsNamedSessions: Bool
}

enum RemoteSessionAttachSelection: Equatable {
    case createManaged
    case attachExisting(RemoteSessionAttachment)
    /// Attach to the named session, creating it when it does not exist.
    case createNamed(RemoteSessionIdentifier)
    case plainShell
}
