import Foundation
import Testing
@testable import QuickWinsCore

@Suite("Mini HUD settings")
struct MiniHUDSettingsTests {

    @Test("The HUD is on screen by default, following the pointer, on a non-Shift shortcut")
    func defaults() {
        let settings = AppSettings.default
        #expect(settings.miniHUDAlwaysVisible)
        #expect(settings.miniHUDVisible)
        #expect(settings.miniHUDFollowsPointer)
        #expect(settings.miniHUDShortcutEnabled)
        #expect(settings.miniHUDAutoHideSeconds == 5)
        #expect(settings.miniHUDShortcut == ShortcutBinding.miniHUDDefault)
        #expect(settings.miniHUDShortcut.display == "⌥Q")
    }

    @Test("A global shortcut default never relies on Shift alone")
    func defaultsAvoidShiftOnlyCombinations() {
        // A hot key consumes its keystroke system-wide, so Shift+letter would make that capital
        // letter untypable everywhere.
        for binding in [ShortcutBinding.default, ShortcutBinding.miniHUDDefault] {
            let onlyShift = binding.carbonModifiers == ShortcutBinding.CarbonModifier.shift
            #expect(!onlyShift)
            #expect(binding.carbonModifiers != 0)
        }
    }

    @Test("HUD preferences survive a round trip")
    func roundTrips() throws {
        var settings = AppSettings.default
        settings.miniHUDFollowsPointer = false
        settings.miniHUDAutoHideSeconds = 0
        settings.miniHUDShortcut = ShortcutBinding(keyCode: 5, carbonModifiers: 4_096, display: "⌃G")

        let data = try JSONEncoder().encode(settings)
        let decoded = try JSONDecoder().decode(AppSettings.self, from: data)

        #expect(decoded.miniHUDFollowsPointer == false)
        #expect(decoded.miniHUDAutoHideSeconds == 0)
        #expect(decoded.miniHUDShortcut.display == "⌃G")
    }

    @Test("A settings blob from before the HUD existed picks up the new defaults")
    func olderBlobGetsTheNewDefaults() throws {
        let older = #"{"menuBarDisplay":"iconOnly","shortcutEnabled":true}"#
        let decoded = try JSONDecoder().decode(AppSettings.self, from: Data(older.utf8))

        #expect(decoded.menuBarDisplay == .iconOnly)
        #expect(decoded.miniHUDFollowsPointer)
        #expect(decoded.miniHUDAlwaysVisible)
        #expect(decoded.miniHUDVisible)
        #expect(decoded.miniHUDShortcut == ShortcutBinding.miniHUDDefault)
    }

    @Test("Switching the HUD off is remembered across a relaunch")
    func hiddenStatePersists() throws {
        var settings = AppSettings.default
        settings.miniHUDVisible = false

        let data = try JSONEncoder().encode(settings)
        let decoded = try JSONDecoder().decode(AppSettings.self, from: data)

        #expect(decoded.miniHUDAlwaysVisible)
        #expect(!decoded.miniHUDVisible)
    }

    @MainActor
    @Test("Toggling HUD visibility is written through to the settings store")
    func visibilityIsPersistedByTheStore() {
        let env = Fixture.coordinator()
        #expect(env.settingsStore.load().miniHUDVisible)

        env.coordinator.updateSettings { $0.miniHUDVisible = false }

        #expect(!env.settingsStore.load().miniHUDVisible)
    }

    @Test("An absurd auto-hide value is clamped rather than stored")
    func autoHideIsClamped() {
        var settings = AppSettings.default
        settings.miniHUDAutoHideSeconds = 9_999
        #expect(settings.sanitized().miniHUDAutoHideSeconds == 60)

        settings.miniHUDAutoHideSeconds = -5
        #expect(settings.sanitized().miniHUDAutoHideSeconds == 0)
    }
}
