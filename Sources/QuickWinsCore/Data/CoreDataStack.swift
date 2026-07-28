import CoreData
import Foundation

public enum PersistenceError: Error, LocalizedError {
    case initializationFailed(String)
    case saveFailed(String)
    case storeUnavailable

    public var errorDescription: String? {
        switch self {
        case .initializationFailed(let reason):
            return "QuickWins could not open its task database: \(reason)"
        case .saveFailed(let reason):
            return "QuickWins could not save your change: \(reason)"
        case .storeUnavailable:
            return "The task database is not available."
        }
    }
}

/// Owns the Core Data stack and its recovery behaviour.
///
/// Core Data is used directly rather than through SwiftData because the SwiftData `@Model`
/// macro plugin ships only with Xcode and is unavailable in a Command Line Tools toolchain.
/// The storage engine is identical; see the README for the swap path.
public final class CoreDataStack {
    public enum Storage {
        case onDisk(URL)
        case temporaryOnDisk
        case inMemory
    }

    public let container: NSPersistentContainer
    /// Set when the previous store could not be opened and was quarantined to recover.
    public private(set) var recoveredFromCorruptStore = false
    public private(set) var quarantinedStoreURL: URL?

    private let logger: DiagnosticLogging

    public init(storage: Storage = .onDisk(CoreDataStack.defaultStoreURL()), logger: DiagnosticLogging) throws {
        self.logger = logger
        self.container = NSPersistentContainer(name: "QuickWins", managedObjectModel: MigrationPlan.currentModel)

        let description: NSPersistentStoreDescription
        switch storage {
        case .inMemory:
            description = NSPersistentStoreDescription()
            description.type = NSInMemoryStoreType
        case .temporaryOnDisk:
            let url = FileManager.default.temporaryDirectory
                .appendingPathComponent("QuickWins-\(UUID().uuidString)", isDirectory: true)
                .appendingPathComponent("QuickWins.sqlite")
            try FileManager.default.createDirectory(
                at: url.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            description = Self.sqliteDescription(url: url)
        case .onDisk(let url):
            try FileManager.default.createDirectory(
                at: url.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            description = Self.sqliteDescription(url: url)
        }

        container.persistentStoreDescriptions = [description]

        do {
            try Self.load(container: container)
        } catch {
            // A store that will not open is almost always a truncated or foreign-format file.
            // Losing today's tasks is bad, but refusing to launch is worse — quarantine the
            // file so it can be inspected, and start clean.
            guard let url = description.url, description.type == NSSQLiteStoreType else {
                throw PersistenceError.initializationFailed(error.localizedDescription)
            }
            logger.error("persistence", "Store failed to open (\(error.localizedDescription)); quarantining and recreating.")
            let quarantine = try? Self.quarantine(storeAt: url)
            quarantinedStoreURL = quarantine
            recoveredFromCorruptStore = true
            do {
                try Self.load(container: container)
            } catch {
                throw PersistenceError.initializationFailed(error.localizedDescription)
            }
        }

        container.viewContext.mergePolicy = NSMergePolicy(merge: .mergeByPropertyObjectTrumpMergePolicyType)
        container.viewContext.automaticallyMergesChangesFromParent = true
        // The app writes on transitions rather than continuously; undo tracking would only add
        // retained object graphs.
        container.viewContext.undoManager = nil

        try stampSchemaVersion()
    }

    private static func sqliteDescription(url: URL) -> NSPersistentStoreDescription {
        let description = NSPersistentStoreDescription(url: url)
        description.type = NSSQLiteStoreType
        description.shouldMigrateStoreAutomatically = true
        description.shouldInferMappingModelAutomatically = true
        return description
    }

    private static func load(container: NSPersistentContainer) throws {
        var loadError: Error?
        container.loadPersistentStores { _, error in loadError = error }
        if let loadError { throw loadError }
    }

    /// Moves a bad store (and its sidecar journal files) aside, keeping it for diagnosis.
    private static func quarantine(storeAt url: URL) throws -> URL {
        let stamp = ISO8601DateFormatter().string(from: Date()).replacingOccurrences(of: ":", with: "-")
        let destination = url.deletingLastPathComponent()
            .appendingPathComponent("\(url.lastPathComponent).corrupt-\(stamp)")
        let manager = FileManager.default
        if manager.fileExists(atPath: url.path) {
            try manager.moveItem(at: url, to: destination)
        }
        for suffix in ["-wal", "-shm"] {
            let sidecar = URL(fileURLWithPath: url.path + suffix)
            if manager.fileExists(atPath: sidecar.path) {
                try? manager.moveItem(at: sidecar, to: URL(fileURLWithPath: destination.path + suffix))
            }
        }
        return destination
    }

    /// Records which schema version wrote the store so a future version can branch on it.
    private func stampSchemaVersion() throws {
        guard let store = container.persistentStoreCoordinator.persistentStores.first else { return }
        var metadata = store.metadata ?? [:]
        let existing = metadata[MigrationPlan.versionMetadataKey] as? Int
        if existing != SchemaVersion.current.rawValue {
            if let existing {
                logger.info("persistence", "Store schema \(existing) opened by app schema \(SchemaVersion.current.rawValue).")
            }
            metadata[MigrationPlan.versionMetadataKey] = SchemaVersion.current.rawValue
            store.metadata = metadata
        }
    }

    public static func defaultStoreURL() -> URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Application Support")
        return base
            .appendingPathComponent("QuickWins", isDirectory: true)
            .appendingPathComponent("QuickWins.sqlite")
    }

    /// Deletes every task row. Used by the "Reset data" settings action.
    public func destroyAllData() throws {
        let context = container.viewContext
        var thrown: Error?
        // A row-by-row delete rather than NSBatchDeleteRequest: the daily task count is tiny,
        // and batch deletes are unsupported by the in-memory store used in some test setups.
        context.performAndWait {
            let request = NSFetchRequest<NSManagedObject>(entityName: MigrationPlan.TaskEntityKey.entityName)
            do {
                for object in try context.fetch(request) {
                    context.delete(object)
                }
                try context.save()
            } catch {
                context.rollback()
                thrown = error
            }
        }
        if let thrown { throw PersistenceError.saveFailed(thrown.localizedDescription) }
    }
}
