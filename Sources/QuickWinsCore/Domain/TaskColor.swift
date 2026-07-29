import Foundation

/// A colour label the user assigns to a task, used to recognise it at a glance — most of all in
/// the mini HUD, where the dot is the only identifying mark.
///
/// Stored as a name rather than an RGB value so the palette can be retuned for light and dark
/// mode, and for increased contrast, without rewriting stored data.
public enum TaskColor: String, Codable, CaseIterable, Sendable, Identifiable {
    case graphite
    case red
    case orange
    case yellow
    case green
    case teal
    case blue
    case purple

    public var id: String { rawValue }

    /// Spoken by VoiceOver and shown in the picker, so the colour is never the only cue.
    public var displayName: String {
        switch self {
        case .graphite: return "Graphite"
        case .red: return "Red"
        case .orange: return "Orange"
        case .yellow: return "Yellow"
        case .green: return "Green"
        case .teal: return "Teal"
        case .blue: return "Blue"
        case .purple: return "Purple"
        }
    }

    /// Colours are handed out in rotation as tasks are created, so a day's tasks are
    /// distinguishable immediately without the user opening the editor for each one.
    public static func suggested(forOrder order: Int) -> TaskColor {
        let cycle = TaskColor.allCases.filter { $0 != .graphite }
        guard !cycle.isEmpty else { return .graphite }
        let index = ((order % cycle.count) + cycle.count) % cycle.count
        return cycle[index]
    }

    public static let fallback = TaskColor.graphite
}
