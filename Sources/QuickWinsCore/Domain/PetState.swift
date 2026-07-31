import Foundation

/// How the companion is drawn.
///
/// Deliberately a scale of *wakefulness*, not of health. QuickWins can only observe how long the
/// system has gone without input — it cannot see whether the user is working. A creature that
/// sickened would assert knowledge the app does not have, and would wilt through every meeting,
/// every long read, and every thinking session. Getting sleepy is literally true, and it recovers
/// the instant a key is pressed.
public enum PetState: String, Sendable, CaseIterable {
    /// A task is running and input is recent.
    case working
    /// Quiet for a few minutes.
    case noticing
    case drowsy
    case sleepy
    /// Quiet past the interruption ceiling. This is the floor: there is no state below it.
    case asleep
    /// Nothing running — paused, or no task chosen.
    case resting
    /// Snoozed, or a task with inactivity check-ins switched off. Low input is expected here,
    /// so the pet is comfortable rather than concerned.
    case settled

    /// 0 is wide awake, 1 is fast asleep. The view interpolates posture and tint from this, so
    /// the visual ramp stays in one place rather than being re-derived per surface.
    public var restfulness: Double {
        switch self {
        case .working: return 0
        case .noticing: return 0.2
        case .drowsy: return 0.45
        case .sleepy: return 0.7
        case .asleep: return 1
        case .resting: return 0.5
        case .settled: return 0.35
        }
    }

    /// Shown only when genuinely asleep, so the marker means something.
    public var showsSleepMarker: Bool { self == .asleep }

    /// A filled form reads as settled, an outline as alert.
    public var prefersFilledSymbol: Bool { self != .working && self != .noticing }

    /// Spoken by VoiceOver. The pet must never be the only way a state is conveyed.
    public var accessibilityDescription: String {
        switch self {
        case .working: return "Working"
        case .noticing: return "Quiet for a few minutes"
        case .drowsy: return "Getting drowsy"
        case .sleepy: return "Nearly asleep"
        case .asleep: return "Asleep"
        case .resting: return "Resting"
        case .settled: return "Settled, check-ins paused"
        }
    }
}

public enum PetStateRules {

    /// Derives the pet's state from what the app already knows.
    ///
    /// Reuses the accountability ladder rather than inventing a second notion of inactivity, so
    /// the pet inherits every suppression rule that ladder already respects — a paused task, a
    /// snooze, quiet hours, and per-task opt-out.
    public static func state(
        hasFocusTask: Bool,
        isRunning: Bool,
        idleDetectionEnabled: Bool,
        isSnoozed: Bool,
        level: AccountabilityLevel
    ) -> PetState {
        guard hasFocusTask, isRunning else { return .resting }
        guard !isSnoozed, idleDetectionEnabled else { return .settled }

        switch level {
        case .calm: return .working
        case .subtle: return .noticing
        case .gentle: return .drowsy
        case .strong: return .sleepy
        case .interrupted: return .asleep
        }
    }

    /// How much of today's goal has been met, clamped to 0...1.
    ///
    /// Drives brightness only. Reward for showing up; there is no matching penalty for a low
    /// number, because a quiet day is not evidence of anything.
    public static func vitality(focusedSeconds: TimeInterval, goalSeconds: TimeInterval) -> Double {
        guard goalSeconds > 0 else { return 1 }
        guard focusedSeconds > 0 else { return 0 }
        return min(1, max(0, focusedSeconds / goalSeconds))
    }
}
