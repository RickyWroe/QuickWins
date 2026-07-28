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

    public static var current: SchemaVersion { .v1 }

    public static func < (lhs: SchemaVersion, rhs: SchemaVersion) -> Bool {
        lhs.rawValue < rhs.rawValue
    }
}

public enum MigrationPlan {
    /// Metadata key holding the schema version that last wrote the store.
    public static let versionMetadataKey = "com.rickywroe.quickwins.schemaVersion"

    public static func model(for version: SchemaVersion) -> NSManagedObjectModel {
        switch version {
        case .v1: return makeV1Model()
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
    }

    private static func makeV1Model() -> NSManagedObjectModel {
        let model = NSManagedObjectModel()
        let entity = NSEntityDescription()
        entity.name = TaskEntityKey.entityName
        // Plain NSManagedObject with keyed access: the record is mapped to and from `DailyTask`
        // in exactly one place, so a generated subclass would add surface without value.
        entity.managedObjectClassName = NSStringFromClass(NSManagedObject.self)

        entity.properties = [
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

        // Enforced by the store, not just by application code, so a crash mid-write or a second
        // process cannot produce two rows for one task.
        entity.uniquenessConstraints = [[TaskEntityKey.id]]

        model.entities = [entity]
        return model
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
