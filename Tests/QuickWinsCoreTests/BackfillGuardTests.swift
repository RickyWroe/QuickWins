import Foundation
import Testing
@testable import QuickWinsCore

@Suite("Backfill guard")
@MainActor
struct BackfillGuardTests {

    @Test("Losing the settings marker does not cause history to be backfilled twice")
    func storeIsTheWitnessNotTheSettings() throws {
        var task = Fixture.task("Existing", accumulated: 3_600)
        task.lastInteractionAt = Fixture.epoch
        let env = Fixture.coordinator(tasks: [task])

        #expect(try env.history.allSessions().count == 1)

        // Preferences can be reset independently of the store — a defaults wipe, a corrupt blob,
        // a new machine restoring the database but not UserDefaults.
        env.coordinator.updateSettings { $0.historyBackfilledAt = nil }
        env.coordinator.backfillHistoryIfNeeded()

        // A second backfill would recreate a session for the task's current total, which by now
        // may already include genuinely recorded sessions.
        #expect(try env.history.allSessions().count == 1)
        #expect(env.coordinator.settings.historyBackfilledAt != nil)
    }

    @Test("The marker is restored so the check is not repeated on every launch")
    func markerIsRestored() throws {
        var task = Fixture.task("Existing", accumulated: 1_800)
        task.lastInteractionAt = Fixture.epoch
        let env = Fixture.coordinator(tasks: [task])

        env.coordinator.updateSettings { $0.historyBackfilledAt = nil }
        env.coordinator.backfillHistoryIfNeeded()
        #expect(env.coordinator.settings.historyBackfilledAt != nil)
    }

    @Test("Real recorded sessions do not block a genuine first backfill")
    func realSessionsDoNotBlockBackfill() throws {
        // A store can hold real sessions without ever having been backfilled — for instance when
        // history began on an empty task list and tasks were added afterwards.
        let task = Fixture.task("Focus", accumulated: 0)
        var settings = AppSettings.default
        settings.historyBackfilledAt = nil
        let env = Fixture.coordinator(tasks: [task], settings: settings)

        env.coordinator.start(task.id)
        env.time.advance(by: 600)
        env.coordinator.pause(task.id)

        let realSessions = try env.history.allSessions()
        #expect(realSessions.count == 1)
        #expect(realSessions.allSatisfy { !$0.isBackfilled })
    }
}
