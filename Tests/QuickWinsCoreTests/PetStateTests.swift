import Foundation
import Testing
@testable import QuickWinsCore

@Suite("Companion state")
struct PetStateTests {

    private func state(
        hasFocusTask: Bool = true,
        isRunning: Bool = true,
        idleDetectionEnabled: Bool = true,
        isSnoozed: Bool = false,
        level: AccountabilityLevel = .calm
    ) -> PetState {
        PetStateRules.state(
            hasFocusTask: hasFocusTask,
            isRunning: isRunning,
            idleDetectionEnabled: idleDetectionEnabled,
            isSnoozed: isSnoozed,
            level: level
        )
    }

    @Test("Each rung of the accountability ladder has its own posture")
    func ladderMapsToStates() {
        #expect(state(level: .calm) == .working)
        #expect(state(level: .subtle) == .noticing)
        #expect(state(level: .gentle) == .drowsy)
        #expect(state(level: .strong) == .sleepy)
        #expect(state(level: .interrupted) == .asleep)
    }

    @Test("Nothing running means resting, whatever the idle reading says")
    func restingWithoutARunningTask() {
        #expect(state(isRunning: false, level: .interrupted) == .resting)
        #expect(state(hasFocusTask: false, level: .strong) == .resting)
    }

    @Test("A snooze settles the pet rather than letting it doze off")
    func snoozeSettles() {
        // Snoozing says low input is expected. The pet should look comfortable, not concerned.
        #expect(state(isSnoozed: true, level: .interrupted) == .settled)
    }

    @Test("A task with check-ins switched off settles the pet too")
    func perTaskOptOutSettles() {
        #expect(state(idleDetectionEnabled: false, level: .strong) == .settled)
    }

    @Test("Asleep is the floor — there is no state below it")
    func asleepIsTheFloor() {
        // The whole design rests on this: the companion never dies, never sickens, and never
        // reaches a state the user has to repair.
        let deepest = PetState.allCases.max { $0.restfulness < $1.restfulness }
        #expect(deepest == .asleep)
        #expect(PetState.asleep.restfulness == 1)
    }

    @Test("Restfulness increases monotonically down the ladder")
    func restfulnessIsOrdered() {
        let ladder: [PetState] = [.working, .noticing, .drowsy, .sleepy, .asleep]
        let values = ladder.map(\.restfulness)
        #expect(values == values.sorted())
        #expect(PetState.working.restfulness == 0)
    }

    @Test("Only genuine sleep shows the sleep marker")
    func sleepMarkerIsEarned() {
        let marked = PetState.allCases.filter { $0.showsSleepMarker }
        #expect(marked == [.asleep])
    }

    @Test("Every state describes itself, so the pet is never the only signal")
    func everyStateIsSpoken() {
        for petState in PetState.allCases {
            #expect(!petState.accessibilityDescription.isEmpty)
        }
    }

    @Test("No state description implies fault or damage")
    func descriptionsAreNotJudgemental() {
        // The pet must not imply the app knows the user has stopped working, since it cannot.
        let forbidden = ["dying", "sick", "hurt", "starving", "unhappy", "neglected", "failing"]
        for petState in PetState.allCases {
            let lowered = petState.accessibilityDescription.lowercased()
            for word in forbidden {
                #expect(!lowered.contains(word), "\"\(petState.accessibilityDescription)\" implies harm")
            }
        }
    }

    // MARK: - Vitality

    @Test("Vitality tracks progress toward the daily goal and clamps at both ends")
    func vitalityIsClamped() {
        #expect(PetStateRules.vitality(focusedSeconds: 0, goalSeconds: 7_200) == 0)
        #expect(PetStateRules.vitality(focusedSeconds: 3_600, goalSeconds: 7_200) == 0.5)
        #expect(PetStateRules.vitality(focusedSeconds: 7_200, goalSeconds: 7_200) == 1)
        #expect(PetStateRules.vitality(focusedSeconds: 100_000, goalSeconds: 7_200) == 1)
        #expect(PetStateRules.vitality(focusedSeconds: -50, goalSeconds: 7_200) == 0)
    }

    @Test("A goal of zero never divides by zero")
    func vitalityHandlesNoGoal() {
        #expect(PetStateRules.vitality(focusedSeconds: 600, goalSeconds: 0) == 1)
    }

    @Test("The companion can be switched off")
    func petCanBeDisabled() {
        #expect(AppSettings.default.petEnabled)
        var settings = AppSettings.default
        settings.petEnabled = false
        #expect(!settings.sanitized().petEnabled)
    }
}
