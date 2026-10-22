import CoreGraphics
import Testing
@testable import VVTerm

struct TerminalAccessoryAppearancePolicyTests {
    @Test
    func ownerAppearanceOverridesDetachedInputHostAppearance() {
        #expect(
            TerminalAccessoryAppearancePolicy.resolvedInterfaceStyle(
                owner: .dark,
                host: .light
            ) == .dark
        )
        #expect(
            TerminalAccessoryAppearancePolicy.resolvedInterfaceStyle(
                owner: .light,
                host: .dark
            ) == .light
        )
    }

    @Test
    func hostAppearanceIsFallbackWhenOwnerIsUnspecified() {
        #expect(
            TerminalAccessoryAppearancePolicy.resolvedInterfaceStyle(
                owner: .unspecified,
                host: .dark
            ) == .dark
        )
    }

    @Test
    func classifiesThemeBackgroundLuminance() {
        #expect(TerminalAccessoryAppearancePolicy.isDarkBackground(
            red: 0.04,
            green: 0.05,
            blue: 0.06
        ))
        #expect(!TerminalAccessoryAppearancePolicy.isDarkBackground(
            red: 0.95,
            green: 0.96,
            blue: 0.97
        ))
    }

    @Test
    func defaultGutterBelowControlsIsThreeBarHeights() {
        #expect(TerminalAccessoryAppearancePolicy.barHeight == 48)
        #expect(TerminalAccessoryAppearancePolicy.defaultBottomGutterHeight == 144)
        #expect(
            TerminalAccessoryAppearancePolicy.defaultBottomGutterHeight
                == 3 * TerminalAccessoryAppearancePolicy.barHeight
        )
    }

    @Test
    func gutterHeightRoundsAndClampsToSupportedRange() {
        #expect(TerminalAccessoryAppearancePolicy.clampedBottomGutterHeight(-12) == 0)
        #expect(TerminalAccessoryAppearancePolicy.clampedBottomGutterHeight(0) == 0)
        #expect(TerminalAccessoryAppearancePolicy.clampedBottomGutterHeight(63.6) == 64)
        #expect(TerminalAccessoryAppearancePolicy.clampedBottomGutterHeight(1_000) == 240)
        #expect(
            TerminalAccessoryAppearancePolicy.clampedBottomGutterHeight(
                TerminalAccessoryAppearancePolicy.maximumBottomGutterHeight
            ) == 240
        )
    }

    @Test
    func nonFiniteGutterHeightResolvesToDefault() {
        #expect(
            TerminalAccessoryAppearancePolicy.clampedBottomGutterHeight(.nan)
                == TerminalAccessoryAppearancePolicy.defaultBottomGutterHeight
        )
        #expect(TerminalAccessoryAppearancePolicy.clampedBottomGutterHeight(.infinity) == 144)
        #expect(TerminalAccessoryAppearancePolicy.clampedBottomGutterHeight(-.infinity) == 144)
        #expect(
            TerminalAccessoryAppearancePolicy.clampedBottomGutterHeight(.greatestFiniteMagnitude)
                == 240
        )
    }
}
