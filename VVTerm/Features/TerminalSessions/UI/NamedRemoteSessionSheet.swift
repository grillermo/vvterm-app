import SwiftUI

/// Asks for the name of a new remote session and validates it before the
/// picker confirms `.createNamed`.
struct NamedRemoteSessionSheet: View {
    let backendIdentifier: RemoteSessionBackendIdentifier
    let existingNames: Set<String>
    let onStart: (RemoteSessionIdentifier) -> Void
    let onCancel: () -> Void

    @State private var name = ""
    @FocusState private var isNameFocused: Bool

    private var validation: Result<RemoteSessionIdentifier, RemoteSessionNamePolicy.ValidationError> {
        do {
            return .success(try RemoteSessionNamePolicy.identifier(
                for: name,
                backendIdentifier: backendIdentifier,
                existingNames: existingNames
            ))
        } catch let error as RemoteSessionNamePolicy.ValidationError {
            return .failure(error)
        } catch {
            return .failure(.invalidCharacters)
        }
    }

    private var identifier: RemoteSessionIdentifier? {
        try? validation.get()
    }

    /// An empty field is not an error yet; it only disables Start.
    private var errorMessage: String? {
        guard case .failure(let error) = validation, error != .empty else { return nil }
        return error.message
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Session name", text: $name)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .submitLabel(.go)
                        .focused($isNameFocused)
                        .onSubmit(start)
                        .accessibilityIdentifier("tmuxNamedSessionNameField")
                } footer: {
                    if let errorMessage {
                        Text(errorMessage)
                            .foregroundStyle(.red)
                            .accessibilityIdentifier("tmuxNamedSessionError")
                    } else {
                        Text("Use only letters, numbers, hyphens, and underscores.")
                    }
                }
            }
            .navigationTitle("Start named session")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel", action: onCancel)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Start", action: start)
                        .disabled(identifier == nil)
                        .accessibilityIdentifier("tmuxNamedSessionStartButton")
                }
            }
        }
        .presentationDetents([.medium])
        .onAppear { isNameFocused = true }
    }

    private func start() {
        guard let identifier else { return }
        onStart(identifier)
    }
}

private extension RemoteSessionNamePolicy.ValidationError {
    var message: String {
        switch self {
        case .empty:
            return ""
        case .tooLong:
            return LocalizedFormat.string(
                "Use at most %lld characters.",
                Int64(RemoteSessionNamePolicy.maximumLength)
            )
        case .invalidCharacters:
            return String(localized: "Use only letters, numbers, hyphens, and underscores.")
        case .reservedPrefix:
            return String(localized: "Names starting with vvterm- are reserved for VVTerm.")
        case .alreadyExists:
            return String(localized: "A session with this name already exists.")
        }
    }
}
