import SwiftUI
import UIKit

typealias LocalSSHDiscoveryManagerFactory = @MainActor () -> LocalSSHDiscoveryManager

@MainActor
struct LocalDeviceDiscoveryPresentation: Identifiable {
    let manager: LocalSSHDiscoveryManager

    init(makeManager: LocalSSHDiscoveryManagerFactory) {
        manager = makeManager()
    }

    var id: ObjectIdentifier {
        ObjectIdentifier(manager)
    }
}

struct LocalDeviceDiscoverySheet: View {
    let onUse: (DiscoveredSSHHost) -> Void

    @Environment(\.dismiss) private var dismiss
    @StateObject private var manager: LocalSSHDiscoveryManager

    init(
        manager: LocalSSHDiscoveryManager,
        onUse: @escaping (DiscoveredSSHHost) -> Void
    ) {
        self.onUse = onUse
        _manager = StateObject(wrappedValue: manager)
    }

    var body: some View {
        NavigationStack {
            Form {
                nearbyHostsSection
                scanningStatusSection
                helpSection
            }
            .formStyle(.grouped)
            .navigationTitle(String(localized: "Discover Local Devices"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(String(localized: "Cancel")) { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(String(localized: "Rescan")) {
                        manager.rescan()
                    }
                    .disabled(manager.isScanning)
                }
            }
        }
        .task {
            manager.startScan()
        }
        .onDisappear {
            manager.stopScan()
        }
        .adaptiveSoftScrollEdges()
    }

    private var nearbyHostsSection: some View {
        Section {
            if manager.hosts.isEmpty {
                emptyHostsView
            } else {
                ForEach(manager.hosts) { host in
                    Button {
                        useHost(host)
                    } label: {
                        DiscoveryHostRow(host: host)
                    }
                    .buttonStyle(.plain)
                }
            }
        } header: {
            Text(String(localized: "Nearby SSH Hosts"))
        }
    }

    private var scanningStatusSection: some View {
        Section {
            HStack(spacing: 10) {
                if manager.isScanning {
                    ProgressView()
                        .controlSize(.small)
                }
                Text(manager.statusText)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }

            sourceStatusRows
        } header: {
            Text(String(localized: "Scanning Status"))
        }
    }

    private var helpSection: some View {
        Section {
            if manager.permissionState == .denied {
                Button {
                    guard let url = URL(string: UIApplication.openSettingsURLString) else { return }
                    UIApplication.shared.open(url)
                } label: {
                    Label(String(localized: "Open Settings"), systemImage: "gear")
                }
            }

            Button(String(localized: "Add Manually")) {
                dismiss()
            }
        } header: {
            Text(String(localized: "No Results Help"))
        } footer: {
            Text(String(localized: "Discovery only prefills host details. Credentials are still configured in Add Server."))
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    @ViewBuilder
    private var sourceStatusRows: some View {
        HStack(spacing: 8) {
            statusChip(
                title: String(localized: "Bonjour"),
                active: manager.bonjourActive
            )
            statusChip(
                title: String(localized: "Port 22"),
                active: manager.probeActive
            )
        }
    }

    private var emptyHostsView: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(String(localized: "No SSH hosts discovered yet."))
                .font(.subheadline)
                .foregroundStyle(.secondary)

            if manager.isScanning {
                ProgressView()
                    .controlSize(.small)
            }
        }
        .padding(.vertical, 4)
    }

    private func useHost(_ host: DiscoveredSSHHost) {
        onUse(host)
        dismiss()
    }

    private func statusChip(title: String, active: Bool) -> some View {
        HStack(spacing: 6) {
            Circle()
                .fill(active ? .green : .secondary.opacity(0.5))
                .frame(width: 7, height: 7)
            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(Color.primary.opacity(0.06), in: Capsule())
    }
}

private struct DiscoveryHostRow: View {
    let host: DiscoveredSSHHost
    @Environment(\.privacyModeEnabled) private var privacyModeEnabled

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "server.rack")
                .font(.body)
                .foregroundStyle(.secondary)
                .frame(width: 18)

            VStack(alignment: .leading, spacing: 2) {
                Text(host.visibleDisplayName(privacyModeEnabled: privacyModeEnabled))
                    .font(.body)
                    .foregroundStyle(.primary)
                    .lineLimit(1)

                Text(host.visibleEndpoint(privacyModeEnabled: privacyModeEnabled))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            Spacer(minLength: 8)

            HStack(spacing: 6) {
                ForEach(Array(host.sources).sorted(by: { $0.rawValue < $1.rawValue }), id: \.self) { source in
                    Text(source.label)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 3)
                        .background(Color.primary.opacity(0.06), in: Capsule())
                }

                if let latencyMs = host.latencyMs {
                    Text(String(format: String(localized: "%lldms"), Int64(latencyMs)))
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .contentShape(Rectangle())
    }
}
