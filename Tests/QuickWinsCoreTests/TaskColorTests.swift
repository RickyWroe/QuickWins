import CoreData
import Foundation
import Testing
@testable import QuickWinsCore

@Suite("Task colour")
struct TaskColorTests {

    @Test("New tasks are handed distinct colours so a day's list is legible at a glance")
    func newTasksRotateThroughThePalette() throws {
        var tasks: [DailyTask] = []
        for index in 0..<5 {
            let created = try TaskRules.makeTask(
                title: "T\(index)", day: Fixture.day, in: tasks, at: Fixture.epoch
            )
            tasks.append(created)
        }
        let colors = tasks.map(\.color)
        #expect(Set(colors).count == colors.count)
        // Graphite is the neutral fallback and is never auto-assigned.
        #expect(!colors.contains(.graphite))
    }

    @Test("An explicit colour overrides the suggestion")
    func explicitColorWins() throws {
        let created = try TaskRules.makeTask(
            title: "A", day: Fixture.day, color: .purple, in: [], at: Fixture.epoch
        )
        #expect(created.color == .purple)
    }

    @Test("The rotation is stable and never crashes on a negative order")
    func suggestionHandlesAnyOrder() {
        #expect(TaskColor.suggested(forOrder: 0) == TaskColor.suggested(forOrder: 7))
        #expect(TaskColor.suggested(forOrder: -3) != .graphite)
    }

    @Test("Every colour has a spoken name, so colour is never the only cue")
    func everyColorIsNamed() {
        for color in TaskColor.allCases {
            #expect(!color.displayName.isEmpty)
        }
    }

    @MainActor
    @Test("Changing a task's colour persists it")
    func colorChangePersists() throws {
        let task = Fixture.task("A", color: .red)
        let env = Fixture.coordinator(tasks: [task])

        env.coordinator.setColor(.teal, for: task.id)

        #expect(env.coordinator.tasks.first?.color == .teal)
        #expect(try env.repository.task(id: task.id)?.color == .teal)
    }

    @Test("Colour survives a round trip through the store")
    func colorRoundTripsThroughCoreData() throws {
        let logger = NullDiagnosticLogger()
        let stack = try CoreDataStack(storage: .temporaryOnDisk, logger: logger)
        let repository = CoreDataTaskRepository(stack: stack, logger: logger)

        let id = UUID()
        try repository.save([Fixture.task("A", id: id, color: .purple)])
        #expect(try repository.task(id: id)?.color == .purple)
    }

    @Test("A row written before colours existed reads back as the neutral fallback")
    func missingColorFallsBack() throws {
        let logger = NullDiagnosticLogger()
        let stack = try CoreDataStack(storage: .temporaryOnDisk, logger: logger)
        let repository = CoreDataTaskRepository(stack: stack, logger: logger)

        let id = UUID()
        try repository.save([Fixture.task("A", id: id, color: .blue)])

        // Simulate a v1 row: the column exists after migration but holds no value.
        let context = stack.container.viewContext
        let request = NSFetchRequest<NSManagedObject>(entityName: MigrationPlan.TaskEntityKey.entityName)
        let object = try #require(try context.fetch(request).first)
        object.setValue(nil, forKey: MigrationPlan.TaskEntityKey.colorRaw)
        try context.save()

        #expect(try repository.task(id: id)?.color == .fallback)
    }

    @Test("An unrecognised colour name falls back rather than failing the read")
    func unknownColorFallsBack() throws {
        let logger = NullDiagnosticLogger()
        let stack = try CoreDataStack(storage: .temporaryOnDisk, logger: logger)
        let repository = CoreDataTaskRepository(stack: stack, logger: logger)

        let id = UUID()
        try repository.save([Fixture.task("A", id: id, color: .green)])

        let context = stack.container.viewContext
        let request = NSFetchRequest<NSManagedObject>(entityName: MigrationPlan.TaskEntityKey.entityName)
        let object = try #require(try context.fetch(request).first)
        object.setValue("chartreuse", forKey: MigrationPlan.TaskEntityKey.colorRaw)
        try context.save()

        #expect(try repository.task(id: id)?.color == .fallback)
    }

    @Test("The v1 model has no colour attribute and v2 does")
    func schemaVersionsDifferByColorOnly() throws {
        let v1 = MigrationPlan.model(for: .v1)
        let v2 = MigrationPlan.model(for: .v2)
        let key = MigrationPlan.TaskEntityKey.colorRaw

        let v1Entity = try #require(v1.entitiesByName[MigrationPlan.TaskEntityKey.entityName])
        let v2Entity = try #require(v2.entitiesByName[MigrationPlan.TaskEntityKey.entityName])

        #expect(v1Entity.attributesByName[key] == nil)
        #expect(v2Entity.attributesByName[key] != nil)
        // Optional with a default is what makes lightweight migration inferrable.
        #expect(v2Entity.attributesByName[key]?.isOptional == true)
        #expect(v2Entity.attributesByName.count == v1Entity.attributesByName.count + 1)
    }
}
