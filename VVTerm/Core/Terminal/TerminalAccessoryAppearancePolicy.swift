import CoreGraphics

nonisolated enum TerminalAccessoryAppearancePolicy {
    enum InterfaceStyle: Equatable {
        case unspecified
        case light
        case dark
    }

    static func resolvedInterfaceStyle(
        owner: InterfaceStyle,
        host: InterfaceStyle
    ) -> InterfaceStyle {
        owner == .unspecified ? host : owner
    }

    /// Height of the accessory's control row.
    static let barHeight: CGFloat = 48

    /// Theme-colored space kept below the control row so the controls clear
    /// the home indicator. It is real accessory height, so the terminal
    /// shrinks by it. The height is a per-device preference; read the
    /// resolved value through `TerminalDefaults.storedAccessoryGutterHeight`.
    static let defaultBottomGutterHeight: CGFloat = 3 * barHeight
    static let minimumBottomGutterHeight: CGFloat = 0
    static let maximumBottomGutterHeight: CGFloat = 5 * barHeight
    static let bottomGutterHeightStep: CGFloat = 1

    /// Rounds to whole points and holds the value inside the supported range
    /// so a corrupt or out-of-range preference can never size the accessory.
    static func clampedBottomGutterHeight(_ height: CGFloat) -> CGFloat {
        guard height.isFinite else { return defaultBottomGutterHeight }
        return min(
            max(height.rounded(), minimumBottomGutterHeight),
            maximumBottomGutterHeight
        )
    }

    static func isDarkBackground(red: CGFloat, green: CGFloat, blue: CGFloat) -> Bool {
        let luminance = (0.2126 * red) + (0.7152 * green) + (0.0722 * blue)
        return luminance < 0.55
    }
}
