import Foundation

protocol CloudSyncService {
    func save<T>(_ object: T) async throws
    func fetch<T>(_ type: T.Type) async throws -> [T]
}

extension CloudSyncService {
    func fetch<T>() async throws -> [T] {
        try await fetch(T.self)
    }
}

enum CloudSyncError: LocalizedError {
    case unsupportedType(String)

    var errorDescription: String? {
        switch self {
        case .unsupportedType(let typeName):
            return "Unsupported cloud sync model type: \(typeName)"
        }
    }
}
