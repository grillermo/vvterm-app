import Foundation
import Testing
@testable import VVTerm

struct RemoteSessionNamePolicyTests {
    @Test(arguments: ["work", "my-work_1", "A", String(repeating: "x", count: 64)])
    func acceptsLettersDigitsHyphensAndUnderscores(_ name: String) throws {
        let identifier = try RemoteSessionNamePolicy.identifier(
            for: name,
            backendIdentifier: .tmux
        )

        #expect(identifier.rawValue == name)
        #expect(identifier.backendIdentifier == .tmux)
    }

    @Test
    func trimsSurroundingWhitespace() throws {
        let identifier = try RemoteSessionNamePolicy.identifier(
            for: "  work \n",
            backendIdentifier: .tmux
        )

        #expect(identifier.rawValue == "work")
    }

    @Test(arguments: [
        ("", RemoteSessionNamePolicy.ValidationError.empty),
        ("   ", .empty),
        (String(repeating: "x", count: 65), .tooLong),
        ("a.b", .invalidCharacters),
        ("a:b", .invalidCharacters),
        ("two words", .invalidCharacters),
        ("$1", .invalidCharacters),
        ("=work", .invalidCharacters),
        ("x'; rm -rf ~", .invalidCharacters),
        ("café", .invalidCharacters),
        ("vvterm-mine", .reservedPrefix),
        ("VVTerm-mine", .reservedPrefix)
    ])
    func rejectsNamesTmuxOrVVTermCannotUseVerbatim(
        _ name: String,
        expected: RemoteSessionNamePolicy.ValidationError
    ) {
        #expect(throws: expected) {
            try RemoteSessionNamePolicy.identifier(for: name, backendIdentifier: .tmux)
        }
    }

    @Test
    func rejectsANameThatIsAlreadyListed() {
        #expect(throws: RemoteSessionNamePolicy.ValidationError.alreadyExists) {
            try RemoteSessionNamePolicy.identifier(
                for: "currentps",
                backendIdentifier: .tmux,
                existingNames: ["currentps", "claude-vvterm-main"]
            )
        }
    }
}
