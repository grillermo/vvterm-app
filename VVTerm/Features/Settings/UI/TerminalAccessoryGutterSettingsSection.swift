import SwiftUI

struct TerminalAccessoryGutterSettingsSection: View {
    private static let supportedRange =
        TerminalDefaults.minimumAccessoryGutterHeight...TerminalDefaults.maximumAccessoryGutterHeight

    @AppStorage(TerminalDefaults.accessoryGutterHeightKey)
    private var gutterHeight = TerminalDefaults.defaultAccessoryGutterHeight

    var body: some View {
        Section {
            VStack(spacing: 10) {
                LabeledContent("Height") {
                    Text(pointLabel(for: gutterHeightBinding.wrappedValue))
                        .foregroundStyle(.secondary)
                }

                Slider(
                    value: gutterHeightBinding,
                    in: Self.supportedRange,
                    step: TerminalDefaults.accessoryGutterHeightStep
                ) {
                    Text("Height")
                }
                .accessibilityValue(pointLabel(for: gutterHeightBinding.wrappedValue))
                .accessibilityIdentifier("vvterm.settings.accessoryGutter.height")
            }

            Button("Reset to Default") {
                gutterHeight = TerminalDefaults.defaultAccessoryGutterHeight
            }
            .disabled(isDefault)
            .accessibilityIdentifier("vvterm.settings.accessoryGutter.reset")
        } header: {
            Text("Accessory Gutter")
        } footer: {
            Text("Space kept below the accessory controls on this device. The terminal shrinks by it.")
        }
    }

    private var gutterHeightBinding: Binding<Double> {
        Binding(
            get: { TerminalDefaults.clampedAccessoryGutterHeight(gutterHeight) },
            set: { gutterHeight = TerminalDefaults.clampedAccessoryGutterHeight($0) }
        )
    }

    private var isDefault: Bool {
        gutterHeight == TerminalDefaults.defaultAccessoryGutterHeight
    }

    private func pointLabel(for value: Double) -> String {
        String(
            format: String(localized: "%lld pt"),
            Int64(TerminalDefaults.clampedAccessoryGutterHeight(value))
        )
    }
}
