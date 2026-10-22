import SwiftUI

struct CapsuleTabStripItem: Identifiable, Equatable {
    let id: UUID
    let title: String
    /// Leading status dot; `nil` hides it.
    let statusColor: Color?
}

/// Capsule strip of closable tabs. Tabs share the width equally while each
/// stays at least `minTabWidth` wide; past that the strip scrolls horizontally
/// and keeps the selected tab in view.
struct CapsuleTabStrip: View {
    let items: [CapsuleTabStripItem]
    let selectedId: UUID?
    let stripAccessibilityIdentifier: String
    let closeAccessibilityIdentifier: String
    let onSelect: (UUID) -> Void
    let onClose: (UUID) -> Void

    private let minTabWidth: CGFloat = 120

    var body: some View {
        GeometryReader { proxy in
            let count = max(items.count, 1)
            let availableWidth = max(proxy.size.width - ServerViewTopTabBarMetrics.horizontalPadding * 2, 0)
            let totalSpacing = ServerViewTopTabBarMetrics.tabSpacing * CGFloat(max(count - 1, 0))
            let itemWidth = count > 0 ? (availableWidth - totalSpacing) / CGFloat(count) : 0
            let useEqualWidth = itemWidth >= minTabWidth

            Group {
                if useEqualWidth {
                    HStack(spacing: ServerViewTopTabBarMetrics.tabSpacing) {
                        ForEach(items) { item in
                            tabButton(for: item, fixedWidth: itemWidth)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, ServerViewTopTabBarMetrics.horizontalPadding)
                    .padding(.vertical, ServerViewTopTabBarMetrics.barVerticalInset)
                } else {
                    ScrollViewReader { scrollProxy in
                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(spacing: ServerViewTopTabBarMetrics.tabSpacing) {
                                ForEach(items) { item in
                                    tabButton(for: item, fixedWidth: nil)
                                        // Capped at the visible width so a long title
                                        // truncates instead of pushing the close
                                        // button out of reach.
                                        .frame(minWidth: minTabWidth, maxWidth: max(availableWidth, minTabWidth))
                                        .id(item.id)
                                }
                            }
                            .padding(.horizontal, ServerViewTopTabBarMetrics.horizontalPadding)
                            .padding(.vertical, ServerViewTopTabBarMetrics.barVerticalInset)
                            .animation(nil, value: items.map(\.id))
                        }
                        .accessibilityIdentifier(stripAccessibilityIdentifier)
                        // The selected tab must always be fully visible: a newly
                        // opened tab lands at the trailing end, past the visible
                        // width once the strip overflows, and its title can
                        // arrive after it opens and widen it again.
                        .onAppear { revealSelectedItem(with: scrollProxy) }
                        .onChange(of: selectedId) { _ in revealSelectedItem(with: scrollProxy) }
                        .onChange(of: items.map(\.id)) { _ in revealSelectedItem(with: scrollProxy) }
                        .onChange(of: selectedTitle) { _ in revealSelectedItem(with: scrollProxy) }
                    }
                }
            }
            .transaction { transaction in
                transaction.animation = nil
            }
        }
        .frame(height: ServerViewTopTabBarMetrics.barHeight)
        .background(
            Capsule(style: .continuous)
                .fill(Color.primary.opacity(0.08))
                .overlay(
                    Capsule(style: .continuous)
                        .stroke(Color.primary.opacity(0.12), lineWidth: 1)
                )
        )
        .clipShape(Capsule(style: .continuous))
    }

    private var selectedTitle: String? {
        items.first { $0.id == selectedId }?.title
    }

    private func tabButton(for item: CapsuleTabStripItem, fixedWidth: CGFloat?) -> some View {
        CapsuleTabButton(
            title: item.title,
            statusColor: item.statusColor,
            isSelected: selectedId == item.id,
            fixedWidth: fixedWidth,
            closeAccessibilityIdentifier: closeAccessibilityIdentifier,
            onSelect: { onSelect(item.id) },
            onClose: { onClose(item.id) }
        )
    }

    private func revealSelectedItem(with scrollProxy: ScrollViewProxy) {
        guard let selectedId, items.contains(where: { $0.id == selectedId }) else { return }
        // Defer one runloop so a just-inserted tab is laid out before scrolling.
        DispatchQueue.main.async {
            scrollProxy.scrollTo(selectedId)
        }
    }
}

private struct CapsuleTabButton: View {
    let title: String
    let statusColor: Color?
    let isSelected: Bool
    let fixedWidth: CGFloat?
    let closeAccessibilityIdentifier: String
    let onSelect: () -> Void
    let onClose: () -> Void

    var body: some View {
        HStack(spacing: 8) {
            if let statusColor {
                Circle()
                    .fill(statusColor)
                    .frame(width: 6, height: 6)
            }

            Text(title)
                .font(.callout)
                .lineLimit(1)
        }
        .padding(.leading, 14)
        .padding(.trailing, 36)
        .padding(.vertical, ServerViewTopTabBarMetrics.tabVerticalPadding)
        .frame(height: ServerViewTopTabBarMetrics.tabHeight)
        .frame(width: fixedWidth, alignment: .leading)
        .foregroundStyle(.primary)
        .background(
            isSelected ? Color.primary.opacity(0.18) : Color.clear,
            in: Capsule(style: .continuous)
        )
        .overlay(alignment: .trailing) {
            Button(action: onClose) {
                Image(systemName: "xmark")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(Color.primary.opacity(0.92))
                    .frame(width: 20, height: 20)
                    .background(
                        Circle()
                            .fill(Color.primary.opacity(isSelected ? 0.16 : 0.12))
                            .overlay(
                                Circle()
                                    .stroke(Color.primary.opacity(0.12), lineWidth: 1)
                            )
                    )
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier(closeAccessibilityIdentifier)
            .accessibilityValue(isSelected ? "selected" : "")
            .padding(.trailing, 8)
        }
        .contentShape(Rectangle())
        .onTapGesture {
            onSelect()
        }
        .accessibilityAddTraits(.isButton)
        .animation(.easeInOut(duration: 0.12), value: isSelected)
    }
}
