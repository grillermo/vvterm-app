//
//  TerminalSplitContainerView.swift
//  VVTerm
//
//  Split menu commands and focused values for terminal splits
//

import Foundation
import SwiftUI

struct ServerViewTabActions {
    let openNew: () -> Void
    let closeSelected: () -> Void
    let selectPrevious: () -> Void
    let selectNext: () -> Void
    /// Select the tab at a zero-based index (Cmd+1…9). No-op if out of range.
    let selectIndex: (Int) -> Void
}

// MARK: - Split Actions

/// Actions that can be performed on a terminal split layout
struct TerminalSplitActions {
    let perform: (TerminalSplitCommand) -> Void
    let isEnabled: (TerminalSplitCommand) -> Bool
    let isZoomed: () -> Bool
}

// MARK: - Focused Values

struct ActiveServerIdKey: FocusedValueKey {
    typealias Value = UUID
}

struct ActivePaneIdKey: FocusedValueKey {
    typealias Value = UUID
}

struct TerminalSplitActionsKey: FocusedValueKey {
    typealias Value = TerminalSplitActions
}

struct OpenTerminalTabActionKey: FocusedValueKey {
    typealias Value = () -> Void
}

struct ServerViewTabActionsKey: FocusedValueKey {
    typealias Value = ServerViewTabActions
}

struct OpenLocalSSHDiscoveryActionKey: FocusedValueKey {
    typealias Value = () -> Void
}

extension FocusedValues {
    var activeServerId: UUID? {
        get { self[ActiveServerIdKey.self] }
        set { self[ActiveServerIdKey.self] = newValue }
    }

    var activePaneId: UUID? {
        get { self[ActivePaneIdKey.self] }
        set { self[ActivePaneIdKey.self] = newValue }
    }

    var terminalSplitActions: TerminalSplitActions? {
        get { self[TerminalSplitActionsKey.self] }
        set { self[TerminalSplitActionsKey.self] = newValue }
    }

    var openTerminalTab: (() -> Void)? {
        get { self[OpenTerminalTabActionKey.self] }
        set { self[OpenTerminalTabActionKey.self] = newValue }
    }

    var serverViewTabActions: ServerViewTabActions? {
        get { self[ServerViewTabActionsKey.self] }
        set { self[ServerViewTabActionsKey.self] = newValue }
    }

    var openLocalSSHDiscovery: (() -> Void)? {
        get { self[OpenLocalSSHDiscoveryActionKey.self] }
        set { self[OpenLocalSSHDiscoveryActionKey.self] = newValue }
    }
}
