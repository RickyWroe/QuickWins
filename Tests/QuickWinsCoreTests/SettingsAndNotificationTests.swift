import Foundation
import Testing
@testable import QuickWinsCore

@Suite("Settings storage")
struct SettingsStoreTests {

    private func makeStore() -> (UserDefaultsSettingsStore, UserDefaults, String) {
        let suite = "quickwins.tests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        return (UserDefaultsSettingsStore(defaults: defaults, logger: NullDiagnosticLogger()), defaults, suite)
    }

    @Test("A first launch reads defaults, including the Option+Space shortcut")
    func defaultsOnFirstLaunch() {
        let (store, _, suite) = makeStore()
        defer { UserDefaults.standard.removePersistentDomain(forName: suite) }

        let settings = store.load()
        #expect(settings == AppSettings.default)
        #expect(settings.shortcut.display == "⌥Space")
        #expect(settings.accountability.gentleThreshold == 300)
    }

    @Test("Settings survive a store round trip")
    func roundTrips() {
        let (store, _, suite) = makeStore()
        defer { UserDefaults.standard.removePersistentDomain(forName: suite) }

        var settings = AppSettings.default
        settings.menuBarDisplay = .iconAndTitle
        settings.openPanelBesideCursor = false
        settings.accountability.quietHours = QuietHours(startMinute: 1_320, endMinute: 420)
        settings.shortcut = ShortcutBinding(keyCode: 11, carbonModifiers: 256, display: "⌘B")
        store.save(settings)

        let loaded = store.load()
        #expect(loaded.menuBarDisplay == .iconAndTitle)
        #expect(loaded.openPanelBesideCursor == false)
        #expect(loaded.accountability.quietHours == QuietHours(startMinute: 1_320, endMinute: 420))
        #expect(loaded.shortcut.display == "⌘B")
    }

    @Test("A corrupt settings blob falls back to defaults instead of throwing at launch")
    func corruptBlobFallsBack() {
        let (store, defaults, suite) = makeStore()
        defer { UserDefaults.standard.removePersistentDomain(forName: suite) }

        defaults.set(Data("{ not json".utf8), forKey: UserDefaultsSettingsStore.storageKey)
        #expect(store.load() == AppSettings.default)
    }

    @Test("A blob written by an older build keeps its known keys and defaults the rest")
    func partialBlobIsTolerated() throws {
        let (store, defaults, suite) = makeStore()
        defer { UserDefaults.standard.removePersistentDomain(forName: suite) }

        let partial = #"{"menuBarDisplay":"iconOnly","hasSeenWelcome":true}"#
        defaults.set(Data(partial.utf8), forKey: UserDefaultsSettingsStore.storageKey)

        let loaded = store.load()
        #expect(loaded.menuBarDisplay == .iconOnly)
        #expect(loaded.hasSeenWelcome)
        // Everything absent from the blob comes from defaults.
        #expect(loaded.shortcut == ShortcutBinding.default)
        #expect(loaded.accountability == AccountabilityConfig.default)
    }

    @Test("Resetting removes the stored blob entirely")
    func resetClearsStorage() {
        let (store, defaults, suite) = makeStore()
        defer { UserDefaults.standard.removePersistentDomain(forName: suite) }

        store.save(AppSettings.default)
        store.reset()
        #expect(defaults.data(forKey: UserDefaultsSettingsStore.storageKey) == nil)
    }
}

@Suite("Notification scheduling")
struct NotificationSchedulingTests {

    private func alert(_ level: AccountabilityLevel = .strong) -> AccountabilityAlert {
        AccountabilityAlert(
            level: level, taskID: UUID(), taskTitle: "Write spec", idleSeconds: 600, playSound: false
        )
    }

    @Test("Delivery is refused while permission has not been granted")
    func deniedAuthorizationBlocksDelivery() async {
        let service = RecordingNotificationService(authorization: .denied)
        await #expect(throws: NotificationServiceError.self) {
            try await service.post(alert())
        }
        #expect(service.posted.isEmpty)
    }

    @Test("Provisional permission is enough to deliver")
    func provisionalAuthorizationDelivers() async throws {
        let service = RecordingNotificationService(authorization: .provisional)
        try await service.post(alert())
        #expect(service.posted.count == 1)
    }

    @Test("Requesting permission moves an undecided state to a decided one")
    func requestResolvesUndetermined() async {
        let service = RecordingNotificationService(authorization: .notDetermined)
        #expect(await service.currentAuthorization() == .notDetermined)
        let result = await service.requestAuthorization()
        #expect(result.allowsDelivery)
    }

    @Test("An unbundled process reports notifications unavailable rather than trapping")
    func unbundledProcessDegradesGracefully() async {
        // The test runner has no bundle identifier, which is exactly the unbundled case.
        let service = UserNotificationService(logger: NullDiagnosticLogger())
        let status = await service.currentAuthorization()
        #expect(status == .unavailable)
        await #expect(throws: NotificationServiceError.self) {
            try await service.post(alert())
        }
    }

    @Test("Every alert action offers a way out that is not completing the task")
    func actionsIncludeNonDestructiveChoices() {
        let identifiers = NotificationAction.allCases.map(\.rawValue)
        #expect(identifiers.contains(NotificationAction.stillWorking.rawValue))
        #expect(identifiers.contains(NotificationAction.pauseTask.rawValue))
        #expect(identifiers.contains(NotificationAction.snooze.rawValue))
    }
}

@Suite("Diagnostics")
struct DiagnosticLoggerTests {

    @Test("The export contains recent entries in order")
    func exportIncludesEntries() {
        let logger = DiagnosticLogger(capacity: 100)
        logger.info("timer", "session started")
        logger.error("persistence", "save failed")

        let text = logger.exportText()
        #expect(text.contains("session started"))
        #expect(text.contains("save failed"))
        #expect(text.contains("QuickWins diagnostic log"))
    }

    @Test("The buffer is bounded so a long-running session cannot grow memory without limit")
    func bufferIsBounded() {
        let logger = DiagnosticLogger(capacity: 50)
        for index in 0..<500 { logger.info("test", "entry \(index)") }

        let text = logger.exportText()
        #expect(text.contains("entry 499"))
        #expect(!text.contains("entry 1 "))
        #expect(text.contains("Entries: 50"))
    }

    @Test("Clearing empties the buffer")
    func clearEmptiesBuffer() {
        let logger = DiagnosticLogger()
        logger.info("test", "something")
        logger.clear()
        #expect(logger.exportText().contains("Entries: 0"))
    }
}

@Suite("Idle detection")
struct IdleDetectionTests {

    @Test("The system provider reports a usable, non-negative reading")
    func systemProviderIsSane() {
        let provider = SystemIdleTimeProvider()
        #expect(provider.isAvailable)
        #expect(provider.idleSeconds() >= 0)
        #expect(provider.idleSeconds().isFinite)
    }

    @Test("The stub reports exactly what a test sets")
    func stubIsDeterministic() {
        let provider = StubIdleTimeProvider(seconds: 42)
        #expect(provider.idleSeconds() == 42)
        provider.set(600)
        #expect(provider.idleSeconds() == 600)
    }
}

@Suite("Tick scheduling")
struct TimerServiceTests {

    @Test("Starting twice replaces the schedule rather than leaving two tickers running")
    func startReplacesPreviousSchedule() {
        let scheduler = ManualTickScheduler()
        var firstCount = 0
        var secondCount = 0

        scheduler.start(interval: 1) { firstCount += 1 }
        scheduler.start(interval: 1) { secondCount += 1 }
        scheduler.fire(times: 3)

        #expect(firstCount == 0)
        #expect(secondCount == 3)
        #expect(scheduler.stopCount == 1)
    }

    @Test("Stopping halts delivery")
    func stopHaltsDelivery() {
        let scheduler = ManualTickScheduler()
        var count = 0
        scheduler.start(interval: 1) { count += 1 }
        scheduler.fire()
        scheduler.stop()
        scheduler.fire()
        #expect(count == 1)
        #expect(!scheduler.isRunning)
    }
}
