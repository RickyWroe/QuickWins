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
    /// The daily goal expressed the way the domain wants it.
    public var dailyFocusGoalSeconds: TimeInterval { TimeInterval(dailyFocusGoalMinutes) * 60 }
    public var workingWeekdaySet: Set<Int> { DayTypeRules.sanitized(workingWeekdays: Set(workingWeekdays)) }

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
    /// Keeps the HUD on screen indefinitely; the shortcut becomes a show/hide switch rather
    /// than a peek. When false the HUD behaves as a glance and hides itself.
    public var miniHUDAlwaysVisible: Bool
    /// Whether the HUD is currently showing. Persisted so an always-on HUD comes back after a
    /// relaunch, and so hiding it stays hidden.
    public var miniHUDVisible: Bool
    /// Seconds before the HUD fades on its own. Ignored while `miniHUDAlwaysVisible` is set.
    public var miniHUDAutoHideSeconds: TimeInterval
    /// Shows a short encouragement in the HUD once the pointer has been parked.
    public var miniHUDMessagesEnabled: Bool
    /// How long the pointer must be still before a message appears.
    public var miniHUDMessageDelay: TimeInterval
    /// Keeps the HUD glued to the pointer instead of placing it once where the pointer was.
    ///
    /// While following, the HUD is click-through: a window that moves with the cursor cannot be
    /// clicked, and one that accepted clicks would swallow them on whatever is underneath.
    public var miniHUDFollowsPointer: Bool
    /// Shows the companion instead of a plain colour dot.
    public var petEnabled: Bool
    /// Which weekdays count as working days, `Calendar` numbering with 1 for Sunday. Days
    /// outside this set are rest days: skipped in streaks, drawn distinctly in the graph.
    public var workingWeekdays: [Int]
    /// Focus target that defines a "full" day in the contribution graph and drives streaks.
    public var dailyFocusGoalMinutes: Int
    /// Set once history has been reconstructed from pre-existing tasks, so it happens only once.
    public var historyBackfilledAt: Date?
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
        miniHUDAlwaysVisible: true,
        miniHUDVisible: true,
        miniHUDAutoHideSeconds: 5,
        miniHUDFollowsPointer: true,
        miniHUDMessagesEnabled: true,
        miniHUDMessageDelay: 15,
        petEnabled: true,
        workingWeekdays: [2, 3, 4, 5, 6],
        dailyFocusGoalMinutes: 120,
        historyBackfilledAt: nil,
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
        miniHUDAlwaysVisible: Bool,
        miniHUDVisible: Bool,
        miniHUDAutoHideSeconds: TimeInterval,
        miniHUDFollowsPointer: Bool,
        miniHUDMessagesEnabled: Bool,
        miniHUDMessageDelay: TimeInterval,
        petEnabled: Bool,
        workingWeekdays: [Int],
        dailyFocusGoalMinutes: Int,
        historyBackfilledAt: Date?,
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
        self.miniHUDAlwaysVisible = miniHUDAlwaysVisible
        self.miniHUDVisible = miniHUDVisible
        self.miniHUDAutoHideSeconds = miniHUDAutoHideSeconds
        self.miniHUDFollowsPointer = miniHUDFollowsPointer
        self.miniHUDMessagesEnabled = miniHUDMessagesEnabled
        self.miniHUDMessageDelay = miniHUDMessageDelay
        self.petEnabled = petEnabled
        self.workingWeekdays = workingWeekdays
        self.dailyFocusGoalMinutes = dailyFocusGoalMinutes
        self.historyBackfilledAt = historyBackfilledAt
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
        miniHUDAlwaysVisible = (try? container.decode(Bool.self, forKey: .miniHUDAlwaysVisible)) ?? fallback.miniHUDAlwaysVisible
        miniHUDVisible = (try? container.decode(Bool.self, forKey: .miniHUDVisible)) ?? fallback.miniHUDVisible
        miniHUDAutoHideSeconds = (try? container.decode(TimeInterval.self, forKey: .miniHUDAutoHideSeconds)) ?? fallback.miniHUDAutoHideSeconds
        miniHUDFollowsPointer = (try? container.decode(Bool.self, forKey: .miniHUDFollowsPointer)) ?? fallback.miniHUDFollowsPointer
        miniHUDMessagesEnabled = (try? container.decode(Bool.self, forKey: .miniHUDMessagesEnabled)) ?? fallback.miniHUDMessagesEnabled
        miniHUDMessageDelay = (try? container.decode(TimeInterval.self, forKey: .miniHUDMessageDelay)) ?? fallback.miniHUDMessageDelay
        petEnabled = (try? container.decode(Bool.self, forKey: .petEnabled)) ?? fallback.petEnabled
        workingWeekdays = (try? container.decode([Int].self, forKey: .workingWeekdays)) ?? fallback.workingWeekdays
        dailyFocusGoalMinutes = (try? container.decode(Int.self, forKey: .dailyFocusGoalMinutes)) ?? fallback.dailyFocusGoalMinutes
        historyBackfilledAt = try? container.decodeIfPresent(Date.self, forKey: .historyBackfilledAt)
        hasSeenWelcome = (try? container.decode(Bool.self, forKey: .hasSeenWelcome)) ?? fallback.hasSeenWelcome
    }

    public func sanitized() -> AppSettings {
        var copy = self
        copy.accountability = accountability.sanitized()
        copy.miniHUDAutoHideSeconds = min(max(0, miniHUDAutoHideSeconds), 60)
        copy.miniHUDMessageDelay = min(max(5, miniHUDMessageDelay), 300)
        copy.workingWeekdays = DayTypeRules.sanitized(workingWeekdays: Set(workingWeekdays)).sorted()
        copy.dailyFocusGoalMinutes = min(max(5, dailyFocusGoalMinutes), 16 * 60)
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
