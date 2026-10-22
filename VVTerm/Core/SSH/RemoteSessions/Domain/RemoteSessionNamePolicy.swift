import Foundation

/// Validates a session name the user types for a new named remote session.
///
/// The accepted set is deliberately narrower than what tmux tolerates: tmux
/// rewrites `.` and `:` (they are target separators), treats leading `$`, `@`,
/// `%` and `=` as target prefixes, and quoting is the only thing standing
/// between whitespace and a broken command. Restricting to ASCII letters,
/// digits, `-` and `_` keeps the name identical on the remote side and in the
/// tab title.
nonisolated enum RemoteSessionNamePolicy {
    enum ValidationError: Error, Equatable, Sendable {
        case empty
        case tooLong
        case invalidCharacters
        case reservedPrefix
        case alreadyExists
    }

    static let maximumLength = 64
    /// Generated VVTerm-managed names use this prefix; a user name with it
    /// could be mistaken for one of them.
    static let reservedPrefix = "vvterm-"

    static func identifier(
        for name: String,
        backendIdentifier: RemoteSessionBackendIdentifier,
        existingNames: Set<String> = []
    ) throws -> RemoteSessionIdentifier {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { throw ValidationError.empty }
        guard trimmed.utf8.count <= maximumLength else { throw ValidationError.tooLong }
        guard trimmed.utf8.allSatisfy(isAllowed) else {
            throw ValidationError.invalidCharacters
        }
        guard !trimmed.lowercased().hasPrefix(reservedPrefix) else {
            throw ValidationError.reservedPrefix
        }
        guard !existingNames.contains(trimmed) else { throw ValidationError.alreadyExists }
        return try RemoteSessionIdentifier(
            backendIdentifier: backendIdentifier,
            validating: trimmed
        )
    }

    private static func isAllowed(_ byte: UInt8) -> Bool {
        switch byte {
        case UInt8(ascii: "a")...UInt8(ascii: "z"),
             UInt8(ascii: "A")...UInt8(ascii: "Z"),
             UInt8(ascii: "0")...UInt8(ascii: "9"),
             UInt8(ascii: "-"),
             UInt8(ascii: "_"):
            return true
        default:
            return false
        }
    }
}
