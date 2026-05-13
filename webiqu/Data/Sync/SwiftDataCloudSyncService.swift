import Foundation
import Combine
import SwiftData

@MainActor
final class SwiftDataCloudSyncService: CloudSyncService {
    private let modelContext: ModelContext

    init(modelContext: ModelContext) {
        self.modelContext = modelContext
    }

    func save<T>(_ object: T) async throws {
        guard let persistentObject = object as? any PersistentModel else {
            throw CloudSyncError.unsupportedType(String(describing: T.self))
        }

        modelContext.insert(persistentObject)
        try modelContext.save()
    }

    func fetch<T>(_ type: T.Type) async throws -> [T] {
        if type == Server.self {
            let results = try modelContext.fetch(FetchDescriptor<Server>())
            return results as? [T] ?? []
        }

        if type == ServerGroup.self {
            let results = try modelContext.fetch(FetchDescriptor<ServerGroup>())
            return results as? [T] ?? []
        }

        if type == SavedCommand.self {
            let results = try modelContext.fetch(FetchDescriptor<SavedCommand>())
            return results as? [T] ?? []
        }

        throw CloudSyncError.unsupportedType(String(describing: type))
    }
}
