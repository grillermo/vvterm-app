import SwiftUI

struct TerminalFontSettingsSection: View {
    @Binding var fontSize: Double

    @EnvironmentObject private var fontStore: TerminalFontStore

    var body: some View {
        Section {
            Picker("Family", selection: primaryFamilyBinding) {
                fontGroups(
                    fontStore.catalog.availableFamilies(
                        ensuring: fontStore.preference.primaryFamily
                    )
                )
            }
            .accessibilityIdentifier("vvterm.settings.appearance.primaryFont")

            VStack(spacing: 10) {
                LabeledContent("Size") {
                    Text(fontSizeLabel)
                        .foregroundStyle(.secondary)
                }

                Slider(
                    value: Binding(
                        get: { fontSize },
                        set: { fontSize = $0.rounded() }
                    ),
                    in: TerminalDefaults.minimumFontSize...TerminalDefaults.maximumFontSize,
                    step: TerminalDefaults.fontSizeStep
                ) {
                    Text("Size")
                } minimumValueLabel: {
                    Text(verbatim: "A")
                        .font(.caption2)
                } maximumValueLabel: {
                    Text(verbatim: "A")
                        .font(.title3)
                }
                .accessibilityIdentifier("vvterm.settings.appearance.fontSize")
                .accessibilityValue(fontSizeLabel)
            }

            Picker(selection: cjkFamilyBinding) {
                Text("Automatic").tag("")
                fontGroups(
                    fontStore.catalog.availableFamilies(
                        ensuring: fontStore.preference.cjkFamily ?? ""
                    )
                )
            } label: {
                Text("CJK Font")
            }
            .accessibilityIdentifier("vvterm.settings.appearance.cjkFont")

            customFontsControl
        } header: {
            Text("Font")
        } footer: {
            Text("Automatic uses the primary font and standard fallback fonts.")
        }
        .onAppear {
            fontStore.refreshCatalog()
        }
    }

    private var primaryFamilyBinding: Binding<String> {
        Binding(
            get: { fontStore.preference.primaryFamily },
            set: { newValue in
                updateSelection {
                    try fontStore.selectPrimaryFamily(
                        newValue,
                        allowsProFeatures: ProAccess.isUnlocked
                    )
                }
            }
        )
    }

    private var cjkFamilyBinding: Binding<String> {
        Binding(
            get: { fontStore.preference.cjkFamily ?? "" },
            set: { newValue in
                updateSelection {
                    try fontStore.selectCJKFamily(
                        newValue.isEmpty ? nil : newValue,
                        allowsProFeatures: ProAccess.isUnlocked
                    )
                }
            }
        )
    }

    private func updateSelection(_ action: () throws -> Void) {
        do {
            try action()
        } catch {
            fontStore.refreshCatalog()
        }
    }

    private var fontSizeLabel: String {
        String(format: String(localized: "%lld pt"), Int64(fontSize))
    }

    @ViewBuilder
    private var customFontsControl: some View {
        NavigationLink {
            CustomFontLibraryView()
        } label: {
            customFontsLabel
        }
        .accessibilityIdentifier("vvterm.settings.appearance.customFonts")
    }

    private var customFontsLabel: some View {
        HStack(spacing: 10) {
            Text("Custom Fonts")
            Spacer(minLength: 8)
            Text(fontStore.customFonts.count, format: .number)
                .foregroundStyle(.secondary)
        }
        .contentShape(Rectangle())
    }

    @ViewBuilder
    private func fontGroups(_ families: [TerminalFontFamily]) -> some View {
        ForEach(TerminalFontFamily.Source.allCases, id: \.self) { source in
            let sourceFamilies = families.filter { $0.source == source }
            if !sourceFamilies.isEmpty {
                Section {
                    ForEach(sourceFamilies) { family in
                        Text(family.name)
                            .tag(family.name)
                    }
                } header: {
                    sourceHeader(source)
                }
            }
        }
    }

    @ViewBuilder
    private func sourceHeader(_ source: TerminalFontFamily.Source) -> some View {
        switch source {
        case .builtIn:
            Text("Built-in")
        case .system:
            Text("System")
        case .custom:
            Text("Custom")
        }
    }
}
