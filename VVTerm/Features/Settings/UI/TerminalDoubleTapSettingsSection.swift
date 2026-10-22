import SwiftUI

/// Picks what a double-tap on the terminal surface sends. "Off" restores the
/// word selection the gesture performed before it became bindable.
struct TerminalDoubleTapSettingsSection: View {
    @AppStorage(TerminalDoubleTapGesturePolicy.storageKey)
    private var doubleTapActionRaw = TerminalDoubleTapGesturePolicy.defaultActionID.rawValue

    var body: some View {
        Section {
            Picker("Double-tap sends", selection: selectedActionRawValue) {
                Text("Off").tag(String?.none)
                ForEach(TerminalDoubleTapGesturePolicy.bindableActions) { actionID in
                    Text(actionID.listTitle).tag(String?.some(actionID.rawValue))
                }
            }
            .accessibilityIdentifier("vvterm.settings.doubleTap.action")
        } header: {
            Text("Terminal Gestures")
        } footer: {
            Text(
                "Double-tapping the terminal sends this key. Turn it off to select a word instead. Long-press always selects a word, and triple-tap always selects a paragraph."
            )
            .font(.caption)
            .foregroundStyle(.secondary)
        }
    }

    /// Reads through the policy so a value stored by a newer build shows the
    /// action the gesture will actually send, rather than an empty selection.
    private var selectedActionRawValue: Binding<String?> {
        Binding(
            get: {
                TerminalDoubleTapGesturePolicy
                    .resolvedAction(rawValue: doubleTapActionRaw)?
                    .rawValue
            },
            set: { doubleTapActionRaw = $0 ?? TerminalDoubleTapGesturePolicy.offRawValue }
        )
    }
}
