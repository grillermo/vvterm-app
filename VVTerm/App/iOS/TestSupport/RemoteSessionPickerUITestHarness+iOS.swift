#if DEBUG
import SwiftUI

/// Presents the real remote-session picker with fixed sessions and reports the
/// confirmed selection, so UI tests can drive the picker without a server.
struct RemoteSessionPickerUITestHarness: View {
    @State private var prompt: RemoteSessionAttachPrompt? = Self.makePrompt()
    @State private var result = "pending"

    var body: some View {
        Text(result)
            .accessibilityIdentifier("vvterm.remoteSessionPickerTest.result")
            .sheet(item: $prompt) { prompt in
                RemoteSessionAttachPromptSheet(prompt: prompt) { selection in
                    result = Self.describe(selection)
                    self.prompt = nil
                }
            }
    }

    private static func makePrompt() -> RemoteSessionAttachPrompt {
        let existing = ["claude-vvterm-main", "currentps"].compactMap { name in
            (try? RemoteSessionIdentifier(backendIdentifier: .tmux, validating: name)).map {
                RemoteSessionSelectionInfo(
                    attachment: RemoteSessionAttachment(identifier: $0, ownership: .external),
                    attachedClientCount: 0,
                    containerCount: 1
                )
            }
        }
        return RemoteSessionAttachPrompt(
            id: UUID(),
            paneId: UUID(),
            backendIdentifier: .tmux,
            backendName: "tmux",
            existingSessions: existing,
            supportsNamedSessions: true
        )
    }

    private static func describe(_ selection: RemoteSessionAttachSelection) -> String {
        switch selection {
        case .createManaged: "createManaged"
        case .attachExisting(let attachment): "attachExisting:\(attachment.identifier.rawValue)"
        case .createNamed(let identifier): "createNamed:\(identifier.rawValue)"
        case .plainShell: "plainShell"
        }
    }
}
#endif
