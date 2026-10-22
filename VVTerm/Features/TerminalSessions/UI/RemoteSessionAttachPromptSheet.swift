import SwiftUI

struct RemoteSessionAttachPromptSheet: View {
    let prompt: RemoteSessionAttachPrompt
    let onConfirm: (RemoteSessionAttachSelection) -> Void

    @State private var isNamingSession = false

    private var hasSessions: Bool {
        !prompt.existingSessions.isEmpty
    }

    private var title: String {
        String(format: String(localized: "Choose %@ session"), prompt.backendName)
    }

    var body: some View {
        NavigationStack {
            contentBody
            .navigationTitle(title)
            .safeAreaInset(edge: .bottom, spacing: 0) {
                actionRow
            }
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    closeButton
                }
            }
            .navigationBarTitleDisplayMode(.inline)
            .interactiveDismissDisabled()
        }
        .adaptiveSoftScrollEdges()
        .sheet(isPresented: $isNamingSession) {
            NamedRemoteSessionSheet(
                backendIdentifier: prompt.backendIdentifier,
                existingNames: Set(prompt.existingSessions.map(\.displayName)),
                onStart: { identifier in
                    isNamingSession = false
                    confirm(.createNamed(identifier))
                },
                onCancel: { isNamingSession = false }
            )
        }
    }

    @ViewBuilder
    private var contentBody: some View {
        if hasSessions {
            List {
                Section {
                    ForEach(prompt.existingSessions) { session in
                        Button {
                            confirm(.attachExisting(session.attachment))
                        } label: {
                            HStack(spacing: 10) {
                                Image(systemName: "terminal")
                                    .foregroundStyle(.secondary)
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(session.displayName)
                                        .lineLimit(1)
                                        .truncationMode(.middle)
                                    Text(sessionDetailsText(for: session))
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                        .lineLimit(1)
                                }
                                Spacer(minLength: 0)
                                Image(systemName: "chevron.right")
                                    .font(.footnote.weight(.semibold))
                                    .foregroundStyle(.tertiary)
                            }
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                    }
                } header: {
                    Text("Existing sessions")
                } footer: {
                    Text("Select a session to attach immediately.")
                }
            }
            .listStyle(.insetGrouped)
        } else {
            VStack {
                Spacer(minLength: 0)
                noSessionsView
                    .frame(maxWidth: .infinity)
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 20)
        }
    }

    private func sessionDetailsText(for session: RemoteSessionSelectionInfo) -> String {
        var details: [String] = []
        if let attachedClientCount = session.attachedClientCount {
            details.append(
                attachedClientCount > 0
                    ? String(localized: "Attached")
                    : String(localized: "Detached")
            )
            if attachedClientCount == 1 {
                details.append(String(localized: "1 client"))
            } else {
                details.append(LocalizedFormat.string(
                    "%lld clients",
                    Int64(attachedClientCount)
                ))
            }
        }

        if let containerCount = session.containerCount {
            if containerCount == 1 {
                details.append(String(localized: "1 window"))
            } else {
                details.append(LocalizedFormat.string(
                    "%lld windows",
                    Int64(containerCount)
                ))
            }
        }

        return details.isEmpty ? String(localized: "Available") : details.joined(separator: " • ")
    }

    private var actionRow: some View {
        VStack(spacing: 10) {
            Button {
                confirm(.createManaged)
            } label: {
                Label("New session", systemImage: "plus.rectangle.on.rectangle")
                    .frame(maxWidth: .infinity)
                    .frame(minHeight: 52)
                    .font(.headline)
                    .foregroundStyle(.white)
                    .contentShape(Rectangle())
                    .background(
                        Capsule(style: .continuous)
                            .fill(Color.accentColor)
                    )
            }
            .buttonStyle(.plain)
            .contentShape(Rectangle())
            .accessibilityIdentifier("tmuxNewSessionButton")

            if prompt.supportsNamedSessions {
                Button {
                    isNamingSession = true
                } label: {
                    Label("Start named session", systemImage: "character.cursor.ibeam")
                        .frame(maxWidth: .infinity)
                        .frame(minHeight: 52)
                        .font(.headline)
                        .foregroundStyle(Color.accentColor)
                        .contentShape(Rectangle())
                        .background(
                            Capsule(style: .continuous)
                                .fill(Color(uiColor: .secondarySystemGroupedBackground))
                                .overlay(
                                    Capsule(style: .continuous)
                                        .strokeBorder(Color.accentColor, lineWidth: 1.5)
                                )
                        )
                }
                .buttonStyle(.plain)
                .contentShape(Rectangle())
                .accessibilityIdentifier("tmuxNamedSessionButton")
            }

            Button {
                confirm(.plainShell)
            } label: {
                Label("Continue without a remote session", systemImage: "arrow.right.circle")
                    .frame(maxWidth: .infinity)
                    .frame(minHeight: 52)
                    .font(.headline)
                    .foregroundStyle(.secondary)
                    .contentShape(Rectangle())
                    .background(
                        Capsule(style: .continuous)
                            .fill(Color(uiColor: .secondarySystemGroupedBackground))
                    )
            }
            .buttonStyle(.plain)
            .contentShape(Rectangle())
            .accessibilityIdentifier("tmuxSkipButton")
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
    }

    private var closeButton: some View {
        Button {
            confirm(.plainShell)
        } label: {
            Image(systemName: "xmark")
                .font(.system(size: 16, weight: .semibold))
                .symbolRenderingMode(.hierarchical)
                .foregroundStyle(.secondary)
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Close")
    }

    @ViewBuilder
    private var noSessionsView: some View {
        if #available(iOS 17.0, *) {
            ContentUnavailableView(
                String(format: String(localized: "No %@ sessions found"), prompt.backendName),
                systemImage: "terminal",
                description: Text("Create a new session, or continue without a remote session.")
            )
        } else {
            VStack(spacing: 8) {
                Label(
                    String(format: String(localized: "No %@ sessions found"), prompt.backendName),
                    systemImage: "terminal"
                )
                    .font(.headline)
                Text("Create a new session, or continue without a remote session.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
            .padding(.vertical, 8)
        }
    }

    private func confirm(_ selection: RemoteSessionAttachSelection) {
        onConfirm(selection)
    }
}
