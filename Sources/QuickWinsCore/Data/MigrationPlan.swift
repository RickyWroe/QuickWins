import CoreData
import Foundation

/// Versioned description of the on-disk schema.
///
/// The model is built in code rather than from an `.xcdatamodeld` bundle, so each version is a
/// function that returns an `NSManagedObjectModel`. Adding a version means appending a case and
/// a builder; lightweight migration then infers the mapping for additive changes (new optional
/// attributes, new entities). A change that cannot be inferred must ship an explicit mapping
/// before it is added here.
public enum SchemaVersion: Int, CaseIterable, Comparable, Sendable {
    case v1 = 1
    /// Adds the per-task colour label.
    case v2 = 2
    /// Adds focus-session history and day-type overrides.
    case v3 = 3

    public static var current: SchemaVersion { .v3 }

    public static func < (lhs: SchemaVersion, rhs: SchemaVersion) -> Bool {
        lhs.rawValue < rhs.rawValue
    }
}

public enum MigrationPlan {
    /// Metadata key holding the schema version that last wrote the store.
    public static let versionMetadataKey = "com.rickywroe.quickwins.schemaVersion"

    public static func model(for version: SchemaVersion) -> NSManagedObjectModel {
        switch version {
        case .v1: return makeModel(includeColor: false, includeHistory: false)
        case .v2: return makeModel(includeColor: true, includeHistory: false)
        case .v3: return makeModel(includeColor: true, includeHistory: true)
        }
    }

    public static var currentModel: NSManagedObjectModel { model(for: .current) }

    // MARK: - Version 1

    public enum TaskEntityKey {
        public static let entityName = "TaskEntity"
        public static let id = "id"
        public static let title = "title"
        public static let notes = "notes"
        public static let createdAt = "createdAt"
        public static let dayPacked = "dayPacked"
        public static let order = "order"
        public static let estimatedDuration = "estimatedDuration"
        public static let accumulatedFocus = "accumulatedFocus"
        public static let sessionStartedAt = "sessionStartedAt"
        public static let completedAt = "completedAt"
        public static let statusRaw = "statusRaw"
        public static let remindersEnabled = "remindersEnabled"
        public static let idleDetectionEnabled = "idleDetectionEnabled"
        public static let alertCount = "alertCount"
        public static let lastInteractionAt = "lastInteractionAt"
        /// Added in v2.
        public static let colorRaw = "colorRaw"
    }

    /// Added in v3. One row per completed stretch of focus.
    public enum SessionEntityKey {
        public static let entityName = "SessionEntity"
        public static let id = "id"
        public static let taskID = "taskID"
        public static let startedAt = "startedAt"
        public static let endedAt = "endedAt"
        public static let seconds = "seconds"
        public static let dayPacked = "dayPacked"
        public static let wasInterrupted = "wasInterrupted"
        public static let isBackfilled = "isBackfilled"
    }

    /// Added in v3. Only days whose type differs from the weekly pattern are stored.
    public enum DayMarkEntityKey {
        public static let entityName = "DayMarkEntity"
        public static let dayPacked = "dayPacked"
        public static let typeRaw = "typeRaw"
    }

    /// Builds the model for a given version.
    ///
    /// Every step so far is additive — v2 adds an optional attribute with a default, v3 adds two
    /// wholly new entities — and Core Data can infer a mapping for both, so lightweight migration
    /// handles existing stores without a mapping model. A change that cannot be inferred —
    /// renaming or retyping an attribute, or splitting an entity — must ship an explicit
    /// `NSMappingModel` before its version is added here.
    private static func makeModel(includeColor: Bool, includeHistory: Bool) -> NSManagedObjectModel {
        let model = NSManagedObjectModel()
        let entity = NSEntityDescription()
        entity.name = TaskEntityKey.entityName
        // Plain NSManagedObject with keyed access: the record is mapped to and from `DailyTask`
        // in exactly one place, so a generated subclass would add surface without value.
        entity.managedObjectClassName = NSStringFromClass(NSManagedObject.self)

        var properties: [NSAttributeDescription] = [
            attribute(TaskEntityKey.id, .UUIDAttributeType, optional: false),
            attribute(TaskEntityKey.title, .stringAttributeType, optional: false, defaultValue: ""),
            attribute(TaskEntityKey.notes, .stringAttributeType, optional: true),
            attribute(TaskEntityKey.createdAt, .dateAttributeType, optional: false),
            attribute(TaskEntityKey.dayPacked, .integer64AttributeType, optional: false, defaultValue: 0),
            attribute(TaskEntityKey.order, .integer64AttributeType, optional: false, defaultValue: 0),
            attribute(TaskEntityKey.estimatedDuration, .doubleAttributeType, optional: true),
            attribute(TaskEntityKey.accumulatedFocus, .doubleAttributeType, optional: false, defaultValue: 0.0),
            attribute(TaskEntityKey.sessionStartedAt, .dateAttributeType, optional: true),
            attribute(TaskEntityKey.completedAt, .dateAttributeType, optional: true),
            attribute(TaskEntityKey.statusRaw, .stringAttributeType, optional: false, defaultValue: TaskStatus.upcoming.rawValue),
            attribute(TaskEntityKey.remindersEnabled, .booleanAttributeType, optional: false, defaultValue: true),
            attribute(TaskEntityKey.idleDetectionEnabled, .booleanAttributeType, optional: false, defaultValue: true),
            attribute(TaskEntityKey.alertCount, .integer64AttributeType, optional: false, defaultValue: 0),
            attribute(TaskEntityKey.lastInteractionAt, .dateAttributeType, optional: false),
        ]

        if includeColor {
            properties.append(
                attribute(
                    TaskEntityKey.colorRaw,
                    .stringAttributeType,
                    optional: true,
                    defaultValue: TaskColor.fallback.rawValue
                )
            )
        }

        entity.properties = properties

        // Enforced by the store, not just by application code, so a crash mid-write or a second
        // process cannot produce two rows for one task.
        entity.uniquenessConstraints = [[TaskEntityKey.id]]

        var entities = [entity]
        if includeHistory {
            entities.append(makeSessionEntity())
            entities.append(makeDayMarkEntity())
        }
        model.entities = entities
        return model
    }

    private static func makeSessionEntity() -> NSEntityDescription {
        let entity = NSEntityDescription()
        entity.name = SessionEntityKey.entityName
        entity.managedObjectClassName = NSStringFromClass(NSManagedObject.self)
        entity.properties = [
            attribute(SessionEntityKey.id, .UUIDAttributeType, optional: false),
            attribute(SessionEntityKey.taskID, .UUIDAttributeType, optional: false),
            attribute(SessionEntityKey.startedAt, .dateAttributeType, optional: false),
            attribute(SessionEntityKey.endedAt, .dateAttributeType, optional: false),
            attribute(SessionEntityKey.seconds, .doubleAttributeType, optional: false, defaultValue: 0.0),
            attribute(SessionEntityKey.dayPacked, .integer64AttributeType, optional: false, defaultValue: 0),
            attribute(SessionEntityKey.wasInterrupted, .booleanAttributeType, optional: false, defaultValue: false),
            attribute(SessionEntityKey.isBackfilled, .booleanAttributeType, optional: false, defaultValue: false),
        ]
        entity.uniquenessConstraints = [[SessionEntityKey.id]]
        return entity
    }

    private static func makeDayMarkEntity() -> NSEntityDescription {
        let entity = NSEntityDescription()
        entity.name = DayMarkEntityKey.entityName
        entity.managedObjectClassName = NSStringFromClass(NSManagedObject.self)
        entity.properties = [
            attribute(DayMarkEntityKey.dayPacked, .integer64AttributeType, optional: false, defaultValue: 0),
            attribute(DayMarkEntityKey.typeRaw, .stringAttributeType, optional: false, defaultValue: DayType.working.rawValue),
        ]
        // One mark per day, enforced by the store rather than by application code.
        entity.uniquenessConstraints = [[DayMarkEntityKey.dayPacked]]
        return entity
    }

    private static func attribute(
        _ name: String,
        _ type: NSAttributeType,
        optional: Bool,
        defaultValue: Any? = nil
    ) -> NSAttributeDescription {
        let description = NSAttributeDescription()
        description.name = name
        description.attributeType = type
        description.isOptional = optional
        if let defaultValue { description.defaultValue = defaultValue }
        return description
    }
}
