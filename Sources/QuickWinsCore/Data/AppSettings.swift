import Foundation

public enum MenuBarDisplayStyle: String, Codable, CaseIterable, Sendable, Identifiable {
    case iconOnly
    case iconAndTime
    case iconAndTitle

    public var id: String { rawValue }

    public var label: String {
        switch self {
        case .iconOnly: return "Icon only"
        case .iconAndTime: return "Icon and elapsed time"
        case .iconAndTitle: return "Icon and task title"
        }
    }
}

/// A global hot key expressed in Carbon virtual key code plus Carbon modifier mask, which is
/// what `RegisterEventHotKey` consumes.
public struct ShortcutBinding: Codable, Equatable, Sendable {
    public var keyCode: UInt32
    public var carbonModifiers: UInt32
    /// Human-readable form captured at record time, e.g. `⌥Space`.
    public var display: String

    public init(keyCode: UInt32, carbonModifiers: UInt32, display: String) {
        self.keyCode = keyCode
        self.carbonModifiers = carbonModifiers
        self.display = display
    }

    public enum CarbonModifier {
        public static let command: UInt32 = 256
        public static let shift: UInt32 = 512
        public static let option: UInt32 = 2_048
        public static let control: UInt32 = 4_096
    }

    /// Option+Space. Chosen because it is unassigned in a default macOS install; Command+Space
    /// belongs to Spotlight and Control+Space to input-source switching.
    public static let `default` = ShortcutBinding(
        keyCode: 49,
        carbonModifiers: CarbonModifier.option,
        display: "⌥Space"
    )

    /// Option+Q for the mini HUD, pairing with Option+Space for the full panel.
    ///
    /// A global hot key consumes the keystroke system-wide, so a bare Shift+letter combination
    /// would make that capital letter untypable everywhere. Every default here carries a
    /// non-shift modifier for that reason.
    public static let miniHUDDefault = ShortcutBinding(
        keyCode: 12,
        carbonModifiers: CarbonModifier.option,
        display: "⌥Q"
    )
}

public struct AppSettings: Codable, Equatable, Sendable {
    public var accountability: AccountabilityConfig
    public var menuBarDisplay: MenuBarDisplayStyle
    /// Open the panel next to the pointer rather than centred on the active screen.
    public var openPanelBesideCursor: Bool
    public var automaticallySelectNextTask: Bool
    public var launchAtLogin: Bool
    public var shortcut: ShortcutBinding
    public var shortcutEnabled: Bool
    /// Opens the compact cursor HUD rather than the full panel.
    public var miniHUDShortcut: ShortcutBinding
    public var miniHUDShortcutEnabled: Bool
    /// Seconds before the HUD fades on its own. Zero keeps it up until dismissed.
    public var miniHUDAutoHideSeconds: TimeInterval
    public var hasSeenWelcome: Bool

    public static let `default` = AppSettings(
        accountability: .default,
        menuBarDisplay: .iconAndTime,
        openPanelBesideCursor: true,
        automaticallySelectNextTask: true,
        launchAtLogin: false,
        shortcut: .default,
        shortcutEnabled: true,
        miniHUDShortcut: .miniHUDDefault,
        miniHUDShortcutEnabled: true,
        miniHUDAutoHideSeconds: 5,
        hasSeenWelcome: false
    )

    public init(
        accountability: AccountabilityConfig,
        menuBarDisplay: MenuBarDisplayStyle,
        openPanelBesideCursor: Bool,
        automaticallySelectNextTask: Bool,
        launchAtLogin: Bool,
        shortcut: ShortcutBinding,
        shortcutEnabled: Bool,
        miniHUDShortcut: ShortcutBinding,
        miniHUDShortcutEnabled: Bool,
        miniHUDAutoHideSeconds: TimeInterval,
        hasSeenWelcome: Bool
    ) {
        self.accountability = accountability
        self.menuBarDisplay = menuBarDisplay
        self.openPanelBesideCursor = openPanelBesideCursor
        self.automaticallySelectNextTask = automaticallySelectNextTask
        self.launchAtLogin = launchAtLogin
        self.shortcut = shortcut
        self.shortcutEnabled = shortcutEnabled
        self.miniHUDShortcut = miniHUDShortcut
        self.miniHUDShortcutEnabled = miniHUDShortcutEnabled
        self.miniHUDAutoHideSeconds = miniHUDAutoHideSeconds
        self.hasSeenWelcome = hasSeenWelcome
    }

    /// Tolerates a settings blob written by a build that did not have every key yet.
    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let fallback = AppSettings.default
        accountability = (try? container.decode(AccountabilityConfig.self, forKey: .accountability)) ?? fallback.accountability
        menuBarDisplay = (try? container.decode(MenuBarDisplayStyle.self, forKey: .menuBarDisplay)) ?? fallback.menuBarDisplay
        openPanelBesideCursor = (try? container.decode(Bool.self, forKey: .openPanelBesideCursor)) ?? fallback.openPanelBesideCursor
        automaticallySelectNextTask = (try? container.decode(Bool.self, forKey: .automaticallySelectNextTask)) ?? fallback.automaticallySelectNextTask
        launchAtLogin = (try? container.decode(Bool.self, forKey: .launchAtLogin)) ?? fallback.launchAtLogin
        shortcut = (try? container.decode(ShortcutBinding.self, forKey: .shortcut)) ?? fallback.shortcut
        shortcutEnabled = (try? container.decode(Bool.self, forKey: .shortcutEnabled)) ?? fallback.shortcutEnabled
        miniHUDShortcut = (try? container.decode(ShortcutBinding.self, forKey: .miniHUDShortcut)) ?? fallback.miniHUDShortcut
        miniHUDShortcutEnabled = (try? container.decode(Bool.self, forKey: .miniHUDShortcutEnabled)) ?? fallback.miniHUDShortcutEnabled
        miniHUDAutoHideSeconds = (try? container.decode(TimeInterval.self, forKey: .miniHUDAutoHideSeconds)) ?? fallback.miniHUDAutoHideSeconds
        hasSeenWelcome = (try? container.decode(Bool.self, forKey: .hasSeenWelcome)) ?? fallback.hasSeenWelcome
    }

    public func sanitized() -> AppSettings {
        var copy = self
        copy.accountability = accountability.sanitized()
        copy.miniHUDAutoHideSeconds = min(max(0, miniHUDAutoHideSeconds), 60)
        return copy
    }
}

public protocol SettingsStoring: AnyObject {
    func load() -> AppSettings
    func save(_ settings: AppSettings)
    func reset()
}

/// Preferences live in `UserDefaults` as a single JSON blob, which keeps related values written
/// atomically and avoids a key-per-field migration burden.
public final class UserDefaultsSettingsStore: SettingsStoring {
    public static let storageKey = "com.rickywroe.quickwins.settings"

    private let defaults: UserDefaults
    private let logger: DiagnosticLogging

    public init(defaults: UserDefaults = .standard, logger: DiagnosticLogging) {
        self.defaults = defaults
        self.logger = logger
    }

    public func load() -> AppSettings {
        guard let data = defaults.data(forKey: Self.storageKey) else { return .default }
        do {
            return try JSONDecoder().decode(AppSettings.self, from: data).sanitized()
        } catch {
            logger.error("settings", "Stored settings could not be decoded (\(error.localizedDescription)); using defaults.")
            return .default
        }
    }

    public func save(_ settings: AppSettings) {
        do {
            let data = try JSONEncoder().encode(settings.sanitized())
            defaults.set(data, forKey: Self.storageKey)
        } catch {
            logger.error("settings", "Settings could not be encoded: \(error.localizedDescription)")
        }
    }

    public func reset() {
        defaults.removeObject(forKey: Self.storageKey)
    }
}

public final class InMemorySettingsStore: SettingsStoring {
    private var current: AppSettings
    public private(set) var saveCount = 0

    public init(_ settings: AppSettings = .default) {
        self.current = settings
    }

    public func load() -> AppSettings { current }

    public func save(_ settings: AppSettings) {
        current = settings.sanitized()
        saveCount += 1
    }

    public func reset() {
        current = .default
    }
}
