import XCTest
@testable import TerminalCore

final class ShortcutTests: XCTestCase {
    func testNewDefaultsAndLegacyConfigurationMigration() throws {
        let config = try JSONDecoder().decode(Configuration.self, from: Data("{}".utf8))
        XCTAssertEqual(config.binding(for: .previousTab), KeyChord(key: "left", modifiers: ["command"]))
        XCTAssertEqual(config.binding(for: .nextTab), KeyChord(key: "right", modifiers: ["command"]))
        XCTAssertTrue(config.binding(for: .fitHeight).isEmpty)
        XCTAssertEqual(config.binding(for: .metaLeft), KeyChord(key: "left", modifiers: ["option"]))
        XCTAssertEqual(config.localShells, ["/bin/zsh", "/bin/bash"])
    }

    func testReassignmentRemovesPreviousShortcutAndCanDisableDefault() throws {
        var config = Configuration()
        let custom = KeyChord(key: "t", modifiers: ["command"])
        config.assign(custom, to: .nextTab)
        XCTAssertTrue(config.binding(for: .newTab).isEmpty)
        XCTAssertEqual(config.binding(for: .nextTab), custom)
        XCTAssertEqual(config.action(for: custom, context: .terminal), .nextTab)
        XCTAssertNil(config.action(for: KeyChord(key: "right", modifiers: ["command"]), context: .terminal))
        config.assign(.unbound, to: .previousTab)
        let restored = try JSONDecoder().decode(Configuration.self, from: JSONEncoder().encode(config))
        XCTAssertTrue(restored.binding(for: .previousTab).isEmpty)
        XCTAssertEqual(restored.binding(for: .nextTab), custom)
    }

    func testTerminalAndSearchBindingsDoNotStealTextFieldInput() {
        let config = Configuration()
        XCTAssertNil(config.action(for: config.binding(for: .metaLeft), context: .settings))
        XCTAssertNil(config.action(for: config.binding(for: .nextTab), context: .settings))
        XCTAssertNil(config.action(for: config.binding(for: .searchNext), context: .terminal))
        XCTAssertEqual(config.action(for: config.binding(for: .searchNext), context: .search), .searchNext)
    }

    func testInvalidAndDuplicateBindingsAreRejected() {
        var config = Configuration()
        config.keyBindings[ShortcutAction.newTab.rawValue] = KeyChord(key: "not-a-key", modifiers: ["command"])
        XCTAssertThrowsError(try config.validated())
        config.keyBindings = [ShortcutAction.nextTab.rawValue: config.binding(for: .previousTab)]
        XCTAssertThrowsError(try config.validated())
    }

    func testEscapeCanBeReassignedAndGlobalConflictsAreDisabled() {
        var config = Configuration()
        config.assign(KeyChord(key: "escape"), to: .connectionPicker)
        XCTAssertTrue(config.binding(for: .closeSearch).isEmpty)
        XCTAssertEqual(config.action(for: KeyChord(key: "escape"), context: .terminal), .connectionPicker)
        config.assign(KeyChord(key: "v", modifiers: ["option", "shift"]), to: .newTab)
        XCTAssertFalse(config.hotkey.enabled)
    }

    func testReenablingGlobalShortcutReleasesConflictingAppBinding() throws {
        var config = Configuration()
        let chord = KeyChord(key: "v", modifiers: ["option", "shift"])
        config.assign(chord, to: .newTab)
        config.assignGlobal(chord, enabled: true)
        XCTAssertTrue(config.binding(for: .newTab).isEmpty)
        XCTAssertTrue(config.hotkey.enabled)
        XCTAssertNoThrow(try config.validated())
    }

    func testPaletteChangesLeaveFontAndOtherPreferencesIntact() {
        var config = Configuration(); config.fontSize = 21; config.opacity = 0.8
        TerminalTheme.light.apply(to: &config)
        XCTAssertEqual(config.foreground, TerminalTheme.light.foreground)
        XCTAssertEqual(config.background, TerminalTheme.light.background)
        XCTAssertEqual(config.ansiColors.count, 16)
        XCTAssertEqual(config.fontSize, 21)
        XCTAssertEqual(config.opacity, 0.8)
    }
}
