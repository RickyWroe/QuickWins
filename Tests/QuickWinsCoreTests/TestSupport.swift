import Foundation
@testable import QuickWinsCore

enum Fixture {
    /// A fixed instant so every duration assertion is exact rather than approximate.
    static let epoch = Date(timeIntervalSince1970: 1_700_000_000)

    static var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC") ?? .gmt
        return calendar
    }

    static var day: DayKey { DayKey(date: epoch, calendar: calendar) }

    static func task(
        _ title: String = "Task",
        id: UUID = UUID(),
        order: Int = 0,
        status: TaskStatus = .upcoming,
        day: DayKey? = nil,
        estimate: TimeInterval? = nil,
        accumulated: TimeInterval = 0,
        sessionStartedAt: Date? = nil,
        createdAt: Date = Fixture.epoch
    ) -> DailyTask {
        DailyTask(
            id: id,
            title: title,
            createdAt: createdAt,
            day: day ?? Fixture.day,
            order: order,
            estimatedDuration: estimate,
            accumulatedFocus: accumulated,
            sessionStartedAt: sessionStartedAt,
            status: status,
            lastInteractionAt: createdAt
        )
    }

    @MainActor
    static func coordinator(
        tasks: [DailyTask] = [],
        settings: AppSettings = .default,
        idleSeconds: TimeInterval = 0,
        at start: Date = Fixture.epoch
    ) -> (
        coordinator: TaskCoordinator,
        time: MutableTimeSource,
        idle: StubIdleTimeProvider,
        notifications: RecordingNotificationService,
        repository: InMemoryTaskRepository,
        settingsStore: InMemorySettingsStore
    ) {
        let time = MutableTimeSource(start)
        let idle = StubIdleTimeProvider(seconds: idleSeconds)
        let notifications = RecordingNotificationService()
        let repository = InMemoryTaskRepository(seed: tasks)
        let settingsStore = InMemorySettingsStore(settings)
        let coordinator = TaskCoordinator(
            repository: repository,
            settingsStore: settingsStore,
            time: time,
            idleProvider: idle,
            notifications: notifications,
            logger: NullDiagnosticLogger(),
            calendar: Fixture.calendar
        )
        coordinator.load()
        return (coordinator, time, idle, notifications, repository, settingsStore)
    }
}
