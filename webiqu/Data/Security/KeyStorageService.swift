import Foundation

protocol KeyStorageService {
    func storePrivateKey(_ keyData: Data, for serverID: UUID) throws
    func loadPrivateKey(for serverID: UUID) throws -> Data?
    func deletePrivateKey(for serverID: UUID) throws
}

enum KeyStorageError: LocalizedError {
    case directoryCreationFailed

    var errorDescription: String? {
        switch self {
        case .directoryCreationFailed:
            return "Failed to create key storage directory."
        }
    }
}
