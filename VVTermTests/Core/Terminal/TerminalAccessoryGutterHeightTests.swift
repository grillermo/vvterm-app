import Foundation
import Testing
@testable import VVTerm

@Suite(.serialized)
@MainActor
struct TerminalAccessoryGutterHeightTests {
    @Test
    func missingValueUsesPolicyDefaultWithoutCreatingStoredPreference() throws {
        let suiteName = "TerminalAccessoryGutterHeightTests.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }

        #expect(TerminalDefaults.storedAccessoryGutterHeight(defaults: defaults) == 144)

        TerminalDefaults.applyIfNeeded(defaults: defaults)

        #expect(defaults.object(forKey: TerminalDefaults.accessoryGutterHeightKey) == nil)
    }

    @Test
    func storedValueIsReadBackClampedToSupportedRange() throws {
        let suiteName = "TerminalAccessoryGutterHeightTests.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }

        defaults.set(64.0, forKey: TerminalDefaults.accessoryGutterHeightKey)
        #expect(TerminalDefaults.storedAccessoryGutterHeight(defaults: defaults) == 64)

        defaults.set(1_000.0, forKey: TerminalDefaults.accessoryGutterHeightKey)
        #expect(TerminalDefaults.storedAccessoryGutterHeight(defaults: defaults) == 240)

        defaults.set(-30.0, forKey: TerminalDefaults.accessoryGutterHeightKey)
        #expect(TerminalDefaults.storedAccessoryGutterHeight(defaults: defaults) == 0)
    }

    @Test
    func storedInvalidValuesAreReplacedWithSafeValues() throws {
        let suiteName = "TerminalAccessoryGutterHeightTests.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        defaults.set(true, forKey: TerminalDefaults.accessoryGutterHeightKey)

        TerminalDefaults.applyIfNeeded(defaults: defaults)

        #expect(defaults.double(forKey: TerminalDefaults.accessoryGutterHeightKey) == 144)

        defaults.set(311.4, forKey: TerminalDefaults.accessoryGutterHeightKey)
        TerminalDefaults.applyIfNeeded(defaults: defaults)

        #expect(defaults.double(forKey: TerminalDefaults.accessoryGutterHeightKey) == 240)
    }

    /// The accessory reports one height everywhere; the gutter preference is
    /// the only part of it that moves.
    @Test
    func accessoryPreferredHeightIsBarPlusClampedGutter() {
        #expect(TerminalInputAccessoryView.preferredHeight(gutterHeight: 0) == 48)
        #expect(TerminalInputAccessoryView.preferredHeight(gutterHeight: 144) == 192)
        #expect(TerminalInputAccessoryView.preferredHeight(gutterHeight: 1_000) == 288)
    }
}
