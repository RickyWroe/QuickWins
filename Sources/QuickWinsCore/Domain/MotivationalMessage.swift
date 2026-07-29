import Foundation

/// Short encouragements shown in the HUD once the pointer has been parked for a while.
///
/// The tone is deliberately quiet. QuickWins does not know whether the work is going well, so a
/// message never congratulates an outcome or claims progress — it only acknowledges that the
/// user is still in it. Anything louder would sit badly next to an accountability prompt.
public enum MotivationalMessage {
    /// Hard ceiling the user asked for. Enforced by a test, not just by care.
    public static let maximumWords = 10

    public static let all: [String] = [
        "One thing at a time.",
        "This is the work.",
        "Steady counts more than fast.",
        "Still here. Still going.",
        "Quiet effort adds up.",
        "Stay with it.",
        "Small steps are still steps.",
        "Focus often looks like nothing happening.",
        "Keep the thread.",
        "Progress rarely feels like progress.",
        "You picked this. Keep going.",
        "Deep work is slow work.",
        "No rush. Just keep moving.",
        "Hard things take the time they take.",
        "Good. Carry on.",
        "Finishing beats starting something new.",
    ]

    /// Picks a message, never repeating the one already on screen.
    ///
    /// Takes a random source so tests can pin the choice instead of asserting on chance.
    public static func next(
        after previous: String?,
        using generator: inout some RandomNumberGenerator
    ) -> String {
        let candidates = all.filter { $0 != previous }
        guard let choice = candidates.randomElement(using: &generator) else {
            return all.first ?? ""
        }
        return choice
    }

    public static func next(after previous: String?) -> String {
        var generator = SystemRandomNumberGenerator()
        return next(after: previous, using: &generator)
    }

    public static func wordCount(_ message: String) -> Int {
        message.split(whereSeparator: { $0 == " " || $0 == "\n" }).count
    }
}
