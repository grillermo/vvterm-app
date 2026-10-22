import Foundation
@testable import VVTerm

/// A minimal terminal surface for store and projection tests that never
/// needs a Ghostty runtime.
@MainActor
final class TerminalSurfaceStub: TerminalSurface {
    private final class InputSession: TerminalKeyboardInputSession {
        func keyboardCoordinatorDiagnosticSnapshot() -> TerminalKeyboardCoordinatorDiagnosticSnapshot {
            TerminalKeyboardCoordinatorDiagnosticSnapshot(
                windowAttached: false,
                windowIsKey: false,
                sceneActivationState: "unattached",
                isFirstResponder: false,
                isSoftwareInputActive: false
            )
        }
        func acquireTerminalInput() -> Bool { false }
        func forceSoftwareKeyboardInput() -> Bool { false }
        func focusTerminalInputWithoutShowingSoftwareKeyboard() -> Bool { false }
        func releaseTerminalInput() {}
        func releaseTerminalInputForReacquisition(completion: @escaping () -> Void) {
            completion()
        }
        func refreshTerminalInputAccessoryAppearance() {}
    }

    private let inputSession = InputSession()

    var terminalGeometry: TerminalSurfaceGeometry?
    var isHostingSceneActive: Bool?
    private(set) var receivedOutput: [Data] = []

    func receiveTerminalOutput(_ data: Data) async -> Bool {
        receivedOutput.append(data)
        return true
    }
    func applyPresentationOverrides(_ overrides: TerminalPresentationOverrides) {}
    func cleanup() {}
    func installRichPasteInterceptor(_ interceptor: @escaping () -> Bool) {}
    func pasteTextFromClipboard() {}
    func sendText(_ text: String) {}

    var keyboardInputSession: any TerminalKeyboardInputSession { inputSession }
    var isAttachedToWindow = false
    var acceptsTerminalInput = true
    var shouldRestoreKeyboardFocusOnReconnect = false
    var isFindNavigatorVisible = false

    func setLifecycleCallbacks(_ callbacks: TerminalSurfaceLifecycleCallbacks?) {}
}
