import Foundation
import Testing
@testable import QuickWinsCore

@Suite("Accountability escalation")
struct AccountabilityTests {
    private let taskID = UUID()

    private var runningContext: AccountabilityContext {
        AccountabilityContext(
            activeTaskID: taskID,
            activeTaskTitle: "Build landing page",
            isRunning: true,
            idleDetectionEnabled: true
        )
    }

    private func evaluate(
        state: AccountabilityState,
        idle: TimeInterval,
        context: AccountabilityContext? = nil,
        config: AccountabilityConfig = .default,
        at offset: TimeInterval = 0
    ) -> (state: AccountabilityState, effects: [AccountabilityEffect]) {
        AccountabilityEngine.evaluate(
            state: state,
            context: context ?? runningContext,
            idleSeconds: idle,
            config: config,
            now: Fixture.epoch.addingTimeInterval(offset),
            calendar: Fixture.calendar
        )
    }

    private var starting: AccountabilityState {
        AccountabilityEngine.reset(for: taskID)
    }

    // MARK: - The ladder

    @Test("Below the first threshold nothing happens at all")
    func quietBelowFirstThreshold() {
        let result = evaluate(state: starting, idle: 120)
        #expect(result.state.level == .calm)
        #expect(result.effects.isEmpty)
    }

    @Test("Three minutes idle changes only the indicator — no notification")
    func threeMinutesIsIndicatorOnly() {
        let result = evaluate(state: starting, idle: 200)
        #expect(result.state.level == .subtle)
        #expect(result.effects == [.updateIndicator(.subtle)])
    }

    @Test("Five minutes idle sends a gentle notification")
    func fiveMinutesNotifies() throws {
        let result = evaluate(state: starting, idle: 320)
        #expect(result.state.level == .gentle)
        let alert = try #require(result.effects.compactMap { effect -> AccountabilityAlert? in
            if case .notify(let alert) = effect { return alert }
            return nil
        }.first)
        #expect(alert.level == .gentle)
        #expect(result.state.alertsSent == 1)
        #expect(!result.effects.contains(.surfacePanel))
    }

    @Test("Ten minutes idle escalates and surfaces the panel when configured")
    func tenMinutesSurfacesPanel() {
        let result = evaluate(state: starting, idle: 620)
        #expect(result.state.level == .strong)
        #expect(result.effects.contains(.surfacePanel))
    }

    @Test("Surfacing the panel is suppressed when the user turned it off")
    func panelSurfacingIsOptional() {
        var config = AccountabilityConfig.default
        config.surfacePanelOnStrongAlert = false
        let result = evaluate(state: starting, idle: 620, config: config)
        #expect(!result.effects.contains(.surfacePanel))
    }

    @Test("Fifteen minutes marks the session interrupted but never touches the task")
    func fifteenMinutesInterruptsSessionOnly() {
        let result = evaluate(state: starting, idle: 1_000)
        #expect(result.state.level == .interrupted)
        #expect(result.state.sessionInterrupted)
        #expect(result.effects.contains(.markSessionInterrupted(taskID)))
    }

    @Test("The interruption is flagged once, not on every subsequent evaluation")
    func interruptionIsNotRepeated() {
        let first = evaluate(state: starting, idle: 1_000)
        let second = evaluate(state: first.state, idle: 1_100, at: 10)
        #expect(!second.effects.contains(.markSessionInterrupted(taskID)))
    }

    // MARK: - Suppression

    @Test("No alerts fire while no task is running")
    func silentWithoutActiveTask() {
        let result = evaluate(state: starting, idle: 3_600, context: .inactive)
        #expect(result.state.level == .calm)
        #expect(!result.effects.contains { if case .notify = $0 { return true }; return false })
    }

    @Test("No alerts fire while the active task is paused")
    func silentWhilePaused() {
        let paused = AccountabilityContext(
            activeTaskID: taskID, activeTaskTitle: "Paused", isRunning: false, idleDetectionEnabled: true
        )
        let result = evaluate(state: starting, idle: 3_600, context: paused)
        #expect(result.state.level == .calm)
    }

    @Test("A task with idle detection switched off is never escalated")
    func perTaskOptOutIsRespected() {
        let optedOut = AccountabilityContext(
            activeTaskID: taskID, activeTaskTitle: "Reading", isRunning: true, idleDetectionEnabled: false
        )
        #expect(evaluate(state: starting, idle: 3_600, context: optedOut).state.level == .calm)
    }

    @Test("Disabling accountability entirely silences the system")
    func globalDisableSilencesEverything() {
        var config = AccountabilityConfig.default
        config.enabled = false
        #expect(evaluate(state: starting, idle: 3_600, config: config).state.level == .calm)
    }

    // MARK: - Acknowledgment

    @Test("Still working clears escalation and opens a grace window")
    func acknowledgeStartsGracePeriod() {
        let alerted = evaluate(state: starting, idle: 620).state
        let acknowledged = AccountabilityEngine.acknowledge(
            state: alerted, config: .default, at: Fixture.epoch.addingTimeInterval(620)
        )
        #expect(acknowledged.level == .calm)
        #expect(acknowledged.isInGracePeriod(at: Fixture.epoch.addingTimeInterval(700)))
        #expect(!acknowledged.sessionInterrupted)
    }

    @Test("An acknowledgment stops the very next evaluation from re-alerting")
    func acknowledgePreventsImmediateRealert() {
        let alerted = evaluate(state: starting, idle: 620).state
        let acknowledged = AccountabilityEngine.acknowledge(
            state: alerted, config: .default, at: Fixture.epoch.addingTimeInterval(620)
        )
        // Idle time keeps climbing — the system reads no input either way.
        let next = evaluate(state: acknowledged, idle: 700, at: 621)
        #expect(next.state.level == .calm)
        #expect(!next.effects.contains { if case .notify = $0 { return true }; return false })
    }

    @Test("Alerts resume once the grace period expires")
    func alertsResumeAfterGrace() {
        let alerted = evaluate(state: starting, idle: 620).state
        let acknowledged = AccountabilityEngine.acknowledge(
            state: alerted, config: .default, at: Fixture.epoch.addingTimeInterval(620)
        )
        // Default grace is 300 seconds.
        let later = evaluate(state: acknowledged, idle: 1_000, at: 621 + 300)
        #expect(later.state.level == .interrupted)
    }

    // MARK: - Snooze

    @Test("Snoozing suppresses alerts for its duration")
    func snoozeSuppressesAlerts() {
        let snoozed = AccountabilityEngine.snooze(state: starting, duration: .fifteenMinutes, at: Fixture.epoch)
        let during = evaluate(state: snoozed, idle: 3_600, at: 600)
        #expect(during.state.level == .calm)
        #expect(during.effects.isEmpty)
    }

    @Test("Alerts return once the snooze expires")
    func snoozeExpires() {
        let snoozed = AccountabilityEngine.snooze(state: starting, duration: .fiveMinutes, at: Fixture.epoch)
        let after = evaluate(state: snoozed, idle: 700, at: 400)
        #expect(after.state.level == .strong)
    }

    @Test("Snooze until resumed has no expiry")
    func indefiniteSnoozeNeverExpires() {
        let snoozed = AccountabilityEngine.snooze(state: starting, duration: .untilResumed, at: Fixture.epoch)
        let muchLater = evaluate(state: snoozed, idle: 100_000, at: 1_000_000)
        #expect(muchLater.state.level == .calm)
    }

    @Test("An indefinite snooze survives switching tasks, since it is a standing choice")
    func indefiniteSnoozeSurvivesTaskSwitch() {
        let snoozed = AccountabilityEngine.snooze(state: starting, duration: .untilResumed, at: Fixture.epoch)
        let reset = AccountabilityEngine.reset(for: UUID(), preservingSnoozeFrom: snoozed)
        #expect(reset.snoozedUntil == .distantFuture)
    }

    @Test("A timed snooze does not carry over to a different task")
    func timedSnoozeDoesNotCarryOver() {
        let snoozed = AccountabilityEngine.snooze(state: starting, duration: .fifteenMinutes, at: Fixture.epoch)
        let reset = AccountabilityEngine.reset(for: UUID(), preservingSnoozeFrom: snoozed)
        #expect(reset.snoozedUntil == nil)
    }

    // MARK: - Repetition and quiet hours

    @Test("Repeat reminders wait for the cooldown instead of firing every tick")
    func repeatsRespectCooldown() {
        let first = evaluate(state: starting, idle: 620)
        #expect(first.state.alertsSent == 1)

        // One second later, still strong: no second alert.
        let immediate = evaluate(state: first.state, idle: 621, at: 1)
        #expect(immediate.state.alertsSent == 1)

        // After the 300-second cooldown, one repeat.
        let later = evaluate(state: immediate.state, idle: 921, at: 301)
        #expect(later.state.alertsSent == 2)
    }

    @Test("Repeat reminders can be switched off entirely")
    func repeatsCanBeDisabled() {
        var config = AccountabilityConfig.default
        config.repeatRemindersEnabled = false
        let first = evaluate(state: starting, idle: 620, config: config)
        let later = evaluate(state: first.state, idle: 700, config: config, at: 1_000)
        #expect(later.state.alertsSent == 1)
    }

    @Test("Quiet hours suppress delivery while still advancing the alert clock")
    func quietHoursSuppressDelivery() {
        var config = AccountabilityConfig.default
        // Fixture.epoch is 2023-11-14 22:13:20 UTC; this window covers it.
        config.quietHours = QuietHours(startMinute: 22 * 60, endMinute: 7 * 60)

        let result = evaluate(state: starting, idle: 620, config: config)
        #expect(!result.effects.contains { if case .notify = $0 { return true }; return false })
        #expect(result.state.alertsSent == 0)
        // The indicator still reflects reality.
        #expect(result.state.level == .strong)
    }

    @Test("A quiet-hours window that wraps past midnight is evaluated correctly")
    func quietHoursWrapMidnight() {
        let overnight = QuietHours(startMinute: 22 * 60, endMinute: 7 * 60)
        let calendar = Fixture.calendar
        func at(hour: Int, minute: Int) -> Date {
            calendar.date(bySettingHour: hour, minute: minute, second: 0, of: Fixture.epoch) ?? Fixture.epoch
        }
        #expect(overnight.contains(at(hour: 23, minute: 0), calendar: calendar))
        #expect(overnight.contains(at(hour: 2, minute: 0), calendar: calendar))
        #expect(!overnight.contains(at(hour: 12, minute: 0), calendar: calendar))
    }

    // MARK: - Task switching

    @Test("Switching tasks restarts escalation from calm")
    func taskSwitchResetsEscalation() {
        let escalated = evaluate(state: starting, idle: 1_000).state
        #expect(escalated.alertsSent == 1)

        let otherID = UUID()
        let other = AccountabilityContext(
            activeTaskID: otherID, activeTaskTitle: "Other", isRunning: true, idleDetectionEnabled: true
        )
        let afterSwitch = evaluate(state: escalated, idle: 10, context: other, at: 1)
        #expect(afterSwitch.state.level == .calm)
        #expect(afterSwitch.state.alertsSent == 0)
        #expect(!afterSwitch.state.sessionInterrupted)
    }

    // MARK: - Configuration

    @Test("Out-of-order thresholds are repaired so escalation cannot skip a rung")
    func thresholdsAreForcedIncreasing() {
        var config = AccountabilityConfig.default
        config.subtleThreshold = 900
        config.gentleThreshold = 60
        config.strongThreshold = 30
        config.interruptThreshold = 10

        let fixed = config.sanitized()
        #expect(fixed.subtleThreshold < fixed.gentleThreshold)
        #expect(fixed.gentleThreshold < fixed.strongThreshold)
        #expect(fixed.strongThreshold < fixed.interruptThreshold)
    }

    @Test("Alert copy asks a question rather than accusing the user")
    func alertCopyIsNotAccusatory() {
        let alert = AccountabilityAlert(
            level: .strong, taskID: taskID, taskTitle: "Write spec", idleSeconds: 600, playSound: false
        )
        #expect(alert.body.contains("Are you still working"))
        #expect(!alert.body.lowercased().contains("slack"))
    }
}
