import Foundation
import Testing
@testable import QuickWinsCore

@Suite("Focus timer")
struct FocusTimerTests {

    @Test("Elapsed time is derived from timestamps, so it survives the app not running")
    func elapsedDerivesFromTimestamps() {
        let task = Fixture.task("A", status: .active, accumulated: 120, sessionStartedAt: Fixture.epoch)
        // No ticks happened in between; the value comes from the clock alone.
        #expect(task.elapsedFocus(at: Fixture.epoch.addingTimeInterval(180)) == 300)
    }

    @Test("A stopped task reports only its banked time")
    func stoppedTaskUsesAccumulated() {
        let task = Fixture.task("A", status: .paused, accumulated: 90)
        #expect(task.elapsedFocus(at: Fixture.epoch.addingTimeInterval(10_000)) == 90)
    }

    @Test("A backwards clock adjustment never subtracts banked focus time")
    func backwardsClockCannotReduceElapsed() {
        let task = Fixture.task("A", status: .active, accumulated: 500, sessionStartedAt: Fixture.epoch)
        let elapsed = task.elapsedFocus(at: Fixture.epoch.addingTimeInterval(-3_600))
        #expect(elapsed == 500)
    }

    @Test("Remaining time counts down against the estimate and stops at zero")
    func remainingClampsAtZero() {
        let task = Fixture.task("A", status: .active, estimate: 600, sessionStartedAt: Fixture.epoch)
        #expect(task.remaining(at: Fixture.epoch.addingTimeInterval(200)) == 400)
        #expect(task.remaining(at: Fixture.epoch.addingTimeInterval(900)) == 0)
    }

    @Test("Overtime is reported only once the estimate is exceeded")
    func overtimeAppearsAfterEstimate() {
        let task = Fixture.task("A", status: .active, estimate: 600, sessionStartedAt: Fixture.epoch)
        #expect(task.overtime(at: Fixture.epoch.addingTimeInterval(200)) == nil)
        #expect(task.overtime(at: Fixture.epoch.addingTimeInterval(900)) == 300)
    }

    @Test("Without an estimate there is neither remaining nor overtime")
    func noEstimateMeansNoProjection() {
        let task = Fixture.task("A", status: .active, sessionStartedAt: Fixture.epoch)
        #expect(task.remaining(at: Fixture.epoch.addingTimeInterval(60)) == nil)
        #expect(task.overtime(at: Fixture.epoch.addingTimeInterval(60)) == nil)
    }

    // MARK: - Restoration

    @MainActor
    @Test("Relaunching mid-session keeps the timer running when the heartbeat is fresh")
    func freshSessionKeepsRunning() {
        let id = UUID()
        var task = Fixture.task("A", id: id, status: .active, sessionStartedAt: Fixture.epoch)
        task.lastInteractionAt = Fixture.epoch.addingTimeInterval(120)

        // Only 30 seconds since the last heartbeat: a normal quit-and-reopen.
        let env = Fixture.coordinator(tasks: [task], at: Fixture.epoch.addingTimeInterval(150))
        let restored = env.coordinator.activeTask

        #expect(restored?.status == .active)
        #expect(restored?.sessionStartedAt == Fixture.epoch)
        #expect(env.coordinator.sessionWasInterrupted == false)
    }

    @MainActor
    @Test("A crash or force quit banks time only up to the last heartbeat")
    func staleSessionIsTruncatedAtHeartbeat() throws {
        let id = UUID()
        var task = Fixture.task("A", id: id, status: .active, sessionStartedAt: Fixture.epoch)
        task.lastInteractionAt = Fixture.epoch.addingTimeInterval(300)

        // Two hours of wall clock, but the app stopped writing heartbeats after 300 seconds.
        let env = Fixture.coordinator(tasks: [task], at: Fixture.epoch.addingTimeInterval(7_200))
        let restored = try #require(env.coordinator.tasks.first { $0.id == id })

        #expect(restored.status == .paused)
        #expect(restored.accumulatedFocus == 300)
        #expect(restored.sessionStartedAt == nil)
        #expect(env.coordinator.sessionWasInterrupted)
    }

    @MainActor
    @Test("Sleeping through a session does not credit the sleep as focus time")
    func sleepDoesNotInflateElapsed() throws {
        let id = UUID()
        let env = Fixture.coordinator(tasks: [Fixture.task("A", id: id)])
        env.coordinator.start(id)

        // Heartbeats keep up for two minutes of real work.
        env.time.advance(by: 60)
        env.coordinator.tick()
        env.time.advance(by: 60)
        env.coordinator.tick()

        // The machine sleeps for eight hours; no ticks fire.
        env.time.advance(by: 28_800)
        env.coordinator.restoreInterruptedSessionIfNeeded()

        let restored = try #require(env.coordinator.tasks.first { $0.id == id })
        #expect(restored.status == .paused)
        #expect(restored.accumulatedFocus == 120)
        #expect(env.coordinator.sessionWasInterrupted)
    }

    @MainActor
    @Test("A running session writes at most one heartbeat per minute")
    func heartbeatDoesNotWriteEverySecond() {
        let id = UUID()
        let env = Fixture.coordinator(tasks: [Fixture.task("A", id: id)])
        env.coordinator.start(id)

        var writes = 0
        let before = env.coordinator.tasks.first { $0.id == id }?.lastInteractionAt

        // Simulate 120 one-second ticks.
        var previous = before
        for _ in 0..<120 {
            env.time.advance(by: 1)
            env.coordinator.tick()
            let current = env.coordinator.tasks.first { $0.id == id }?.lastInteractionAt
            if current != previous { writes += 1 }
            previous = current
        }

        // Two minutes of ticking must produce two heartbeats, not 120.
        #expect(writes == 2)
    }

    // MARK: - Formatting

    @Test("Clock formatting adds an hours field only once needed")
    func clockFormatting() {
        #expect(FocusTimeFormatter.clock(0) == "0:00")
        #expect(FocusTimeFormatter.clock(2_058) == "34:18")
        #expect(FocusTimeFormatter.clock(3_753) == "1:02:33")
    }

    @Test("Non-finite or negative durations render as zero instead of crashing the label")
    func formattingHandlesGarbage() {
        #expect(FocusTimeFormatter.clock(-40) == "0:00")
        #expect(FocusTimeFormatter.clock(.nan) == "0:00")
        #expect(FocusTimeFormatter.abbreviated(.infinity) == "0s")
    }

    @Test("VoiceOver time is spoken as a duration, not as a time of day")
    func spokenFormatting() {
        #expect(FocusTimeFormatter.spoken(2_058) == "34 minutes 18 seconds")
        #expect(FocusTimeFormatter.spoken(3_600) == "1 hour")
    }
}
