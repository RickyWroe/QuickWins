import Foundation
import Testing
@testable import QuickWinsCore

@Suite("Mini HUD settings")
struct MiniHUDSettingsTests {

    @Test("The HUD follows the pointer by default and is bound to a non-Shift shortcut")
    func defaults() {
        let settings = AppSettings.default
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

    @Test("A settings blob from before the HUD existed defaults to following")
    func olderBlobGetsTheNewDefaults() throws {
        let older = #"{"menuBarDisplay":"iconOnly","shortcutEnabled":true}"#
        let decoded = try JSONDecoder().decode(AppSettings.self, from: Data(older.utf8))

        #expect(decoded.menuBarDisplay == .iconOnly)
        #expect(decoded.miniHUDFollowsPointer)
        #expect(decoded.miniHUDShortcut == ShortcutBinding.miniHUDDefault)
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
