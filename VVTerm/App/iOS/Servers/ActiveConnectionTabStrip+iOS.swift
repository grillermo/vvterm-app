import SwiftUI

/// Navigation-bar tab strip of active connections. It owns the status
/// projection so connection-state changes redraw only the strip.
struct ActiveConnectionTabStrip: View {
    let options: [ActiveConnectionSwitcherOption]
    let selectedServerId: UUID
    let onSelect: (UUID) -> Void
    let onClose: (UUID) -> Void

    @StateObject private var statusProjection: ActiveConnectionStatusProjection

    init(
        options: [ActiveConnectionSwitcherOption],
        selectedServerId: UUID,
        sessionState: TerminalSessionStateStore,
        onSelect: @escaping (UUID) -> Void,
        onClose: @escaping (UUID) -> Void
    ) {
        self.options = options
        self.selectedServerId = selectedServerId
        self.onSelect = onSelect
        self.onClose = onClose
        _statusProjection = StateObject(
            wrappedValue: ActiveConnectionStatusProjection(sessionState: sessionState)
        )
    }

    var body: some View {
        CapsuleTabStrip(
            items: options.map {
                CapsuleTabStripItem(
                    id: $0.id,
                    title: $0.title,
                    statusColor: ConnectionStatusDotColor.color(
                        for: statusProjection.statesByServer[$0.id]
                    )
                )
            },
            selectedId: selectedServerId,
            stripAccessibilityIdentifier: "vvterm.terminal.connectionStrip",
            closeAccessibilityIdentifier: "vvterm.terminal.connectionStrip.close",
            onSelect: onSelect,
            onClose: onClose
        )
        // The navigation bar sizes its principal item from the ideal width,
        // which the strip's GeometryReader reports as nearly zero. A wide ideal
        // width makes it fill the space between the bar buttons instead.
        .frame(idealWidth: 1_000, maxWidth: .infinity)
        .onAppear { statusProjection.track(serverIds: options.map(\.id)) }
        .onChange(of: options.map(\.id)) { statusProjection.track(serverIds: $0) }
    }
}
