//
//  GhosttyTerminalAccessoryPresentation+iOS.swift
//  VVTerm
//
//  iOS terminal keyboard accessory presentation.
//

import UIKit

// MARK: - Keyboard Accessory View

extension GhosttyTerminalView {
    /// The terminal owns its bar (modifier state, key routing, and keyboard
    /// dismissal), while the route layout decides where and whether it is mounted.
    func accessoryBarView() -> TerminalInputAccessoryView {
        if let keyboardToolbar {
            return keyboardToolbar
        }
        let toolbar = TerminalInputAccessoryView(
            terminalOwner: self,
            inputSnapshot: terminalAccessoryInputSnapshot,
            onKey: { [weak self] key in
                self?.handleToolbarKey(key)
            },
            onCustomAction: { [weak self] action in
                self?.handleToolbarCustomAction(action)
            },
            onDismissKeyboard: { [weak self] in
                self?.dismissKeyboardFromToolbar()
            }
        )
        keyboardToolbar = toolbar
        return toolbar
    }

    func applyTerminalAccessoryInputSnapshot(_ snapshot: TerminalAccessoryInputSnapshot) {
        guard snapshot != terminalAccessoryInputSnapshot else { return }
        terminalAccessoryInputSnapshot = snapshot
        keyboardToolbar?.apply(snapshot)
    }

    func refreshTerminalInputAccessoryAppearance() {
        keyboardToolbar?.refreshAppearance()
    }

    /// Drops the bar's cached intrinsic height after the gutter preference
    /// changes, so UIKit re-measures instead of fighting the host constraints.
    func invalidateTerminalInputAccessoryHeight() {
        keyboardToolbar?.invalidateIntrinsicContentSize()
    }

    private func handleToolbarKey(_ key: TerminalKey) {
        sendToolbarKey(key)
    }
}
