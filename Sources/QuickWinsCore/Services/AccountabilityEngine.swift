import Foundation

/// What the engine needs to know about the current focus session.
public struct AccountabilityContext: Equatable, Sendable {
    public let activeTaskID: UUID?
    public let activeTaskTitle: String
    /// True only while the task's timer is running; a paused task never raises alerts.
    public let isRunning: Bool
    /// Per-task opt-out.
    public let idleDetectionEnabled: Bool

    public init(activeTaskID: UUID?, activeTaskTitle: String, isRunning: Bool, idleDetectionEnabled: Bool) {
        self.activeTaskID = activeTaskID
        self.activeTaskTitle = activeTaskTitle
        self.isRunning = isRunning
        self.idleDetectionEnabled = idleDetectionEnabled
    }

    /// Not named `none`, which would collide with `Optional.none` at call sites.
    public static let inactive = AccountabilityContext(
        activeTaskID: nil,
        activeTaskTitle: "",
        isRunning: false,
        idleDetectionEnabled: false
    )
}

/// Deterministic state machine translating idle time into escalating, dismissible prompts.
///
/// Pure by design: given the same state, idle reading, config and instant it always produces
/// the same result, which is what makes the escalation ladder testable without waiting fifteen
/// real minutes.
public enum AccountabilityEngine {

    public static func evaluate(
        state: AccountabilityState,
        context: AccountabilityContext,
        idleSeconds: TimeInterval,
        config rawConfig: AccountabilityConfig,
        now: Date,
        calendar: Calendar = .current
    ) -> (state: AccountabilityState, effects: [AccountabilityEffect]) {
        let config = rawConfig.sanitized()

        // No running session means nothing to be accountable for. Snooze survives this so a
        // "snooze until resumed" choice is not silently cleared by a pause.
        guard config.enabled,
              context.isRunning,
              context.idleDetectionEnabled,
              let taskID = context.activeTaskID
        else {
            var cleared = AccountabilityState.idle
            cleared.snoozedUntil = state.snoozedUntil
            cleared.taskID = context.activeTaskID
            let effects: [AccountabilityEffect] = state.level == .calm ? [] : [.updateIndicator(.calm)]
            return (cleared, effects)
        }

        // Switching tasks restarts escalation; carried-over alert counts would misrepresent
        // the new session.
        var working = state.taskID == taskID ? state : reset(for: taskID, preservingSnoozeFrom: state)

        var effects: [AccountabilityEffect] = []

        // Suppressed windows report calm so the panel does not nag during legitimate low input.
        if working.isSnoozed(at: now) || working.isInGracePeriod(at: now) {
            if working.level != .calm {
                working.level = .calm
                effects.append(.updateIndicator(.calm))
            }
            return (working, effects)
        }

        // An expired snooze should not linger as state.
        if working.snoozedUntil != nil, working.snoozedUntil! <= now {
            working.snoozedUntil = nil
        }

        let newLevel = config.level(forIdle: max(0, idleSeconds))
        let escalated = newLevel > working.level

        if newLevel != working.level {
            working.level = newLevel
            effects.append(.updateIndicator(newLevel))
        }

        if newLevel == .interrupted && !working.sessionInterrupted {
            working.sessionInterrupted = true
            effects.append(.markSessionInterrupted(taskID))
        }

        // Below `.gentle` the app only changes the indicator — no notification is ever sent.
        guard newLevel >= .gentle else { return (working, effects) }

        let cooldownElapsed = working.lastAlertAt.map { now.timeIntervalSince($0) >= config.repeatCooldown } ?? true
        let shouldRepeat = config.repeatRemindersEnabled && cooldownElapsed
        guard escalated || shouldRepeat else { return (working, effects) }

        // Quiet hours suppress delivery but still advance the clock, so the user is not
        // ambushed by a backlog of alerts the moment quiet hours end.
        if let quiet = config.quietHours, quiet.contains(now, calendar: calendar) {
            working.lastAlertAt = now
            return (working, effects)
        }

        let alert = AccountabilityAlert(
            level: newLevel,
            taskID: taskID,
            taskTitle: context.activeTaskTitle,
            idleSeconds: idleSeconds,
            playSound: config.soundEnabled
        )
        effects.append(.notify(alert))
        working.lastAlertAt = now
        working.alertsSent += 1

        if newLevel >= .strong && config.surfacePanelOnStrongAlert {
            effects.append(.surfacePanel)
        }

        return (working, effects)
    }

    // MARK: - User responses

    /// "Still working": clears escalation, records the acknowledgment, and opens a grace window
    /// so the next evaluation cannot immediately re-alert.
    public static func acknowledge(
        state: AccountabilityState,
        config: AccountabilityConfig,
        at now: Date
    ) -> AccountabilityState {
        var updated = state
        updated.level = .calm
        updated.acknowledgedUntil = now.addingTimeInterval(config.sanitized().gracePeriod)
        updated.lastAlertAt = now
        updated.sessionInterrupted = false
        return updated
    }

    public static func snooze(
        state: AccountabilityState,
        duration: SnoozeDuration,
        at now: Date
    ) -> AccountabilityState {
        var updated = state
        updated.level = .calm
        updated.snoozedUntil = duration.seconds.map { now.addingTimeInterval($0) } ?? .distantFuture
        updated.sessionInterrupted = false
        return updated
    }

    public static func clearSnooze(state: AccountabilityState) -> AccountabilityState {
        var updated = state
        updated.snoozedUntil = nil
        return updated
    }

    public static func reset(for taskID: UUID?, preservingSnoozeFrom previous: AccountabilityState? = nil) -> AccountabilityState {
        var fresh = AccountabilityState.idle
        fresh.taskID = taskID
        // A "until I resume" snooze is a standing user preference, not session state.
        if let previous, previous.snoozedUntil == .distantFuture {
            fresh.snoozedUntil = previous.snoozedUntil
        }
        return fresh
    }
}
