import Foundation

extension Ghostty {
    struct RuntimeConfiguration: Equatable {
        let fontSelection: TerminalFontRuntimeSelection
        let fontSize: Double
        let contentPadding: TerminalContentPadding
        let cursorStyle: TerminalCursorStyle
        let cursorBlink: Bool
        let optionAsAltMode: TerminalOptionAsAltMode
        let remoteClipboardReadPolicy: TerminalRemoteClipboardReadPolicy
        let remoteClipboardWritePolicy: TerminalRemoteClipboardWritePolicy

        init(
            fontSelection: TerminalFontRuntimeSelection,
            fontSize: Double,
            contentPadding: TerminalContentPadding,
            cursorStyleRawValue: String,
            cursorBlink: Bool,
            optionAsAltModeRawValue: String,
            remoteClipboardReadPolicyRawValue: String,
            remoteClipboardWritePolicyRawValue: String
        ) {
            self.fontSelection = fontSelection
            self.fontSize = TerminalDefaults.clampedFontSize(fontSize)
            self.contentPadding = contentPadding
            self.cursorStyle = TerminalCursorStyle(rawValue: cursorStyleRawValue)
                ?? TerminalDefaults.defaultCursorStyle
            self.cursorBlink = cursorBlink
            self.optionAsAltMode = TerminalOptionAsAltMode(rawValue: optionAsAltModeRawValue)
                ?? .none
            self.remoteClipboardReadPolicy = TerminalRemoteClipboardReadPolicy(
                rawValue: remoteClipboardReadPolicyRawValue
            ) ?? .defaultValue
            self.remoteClipboardWritePolicy = TerminalRemoteClipboardWritePolicy(
                rawValue: remoteClipboardWritePolicyRawValue
            ) ?? .defaultValue
        }

        @MainActor static var defaultValue: Self {
            Self(
                fontSelection: .defaultValue,
                fontSize: TerminalDefaults.defaultFontSize,
                contentPadding: .defaultValue,
                cursorStyleRawValue: TerminalDefaults.defaultCursorStyle.rawValue,
                cursorBlink: TerminalDefaults.defaultCursorBlink,
                optionAsAltModeRawValue: TerminalOptionAsAltMode.none.rawValue,
                remoteClipboardReadPolicyRawValue: TerminalRemoteClipboardReadPolicy.defaultValue.rawValue,
                remoteClipboardWritePolicyRawValue: TerminalRemoteClipboardWritePolicy.defaultValue.rawValue
            )
        }
    }
}
