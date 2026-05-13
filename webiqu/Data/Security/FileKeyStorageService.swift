import Foundation

final class FileKeyStorageService: KeyStorageService {
    private let fileManager: FileManager
    private let baseDirectory: URL

    init(fileManager: FileManager = .default, baseDirectory: URL? = nil) throws {
        self.fileManager = fileManager

        if let baseDirectory {
            self.baseDirectory = baseDirectory
        } else {
            let appSupport = try fileManager.url(
                for: .applicationSupportDirectory,
                in: .userDomainMask,
                appropriateFor: nil,
                create: true
            )
            self.baseDirectory = appSupport
                .appendingPathComponent("webiqu", isDirectory: true)
                .appendingPathComponent("keys", isDirectory: true)
        }

        try createStorageIfNeeded()
    }

    func storePrivateKey(_ keyData: Data, for serverID: UUID) throws {
        try createStorageIfNeeded()
        let fileURL = keyURL(for: serverID)
        try keyData.write(to: fileURL, options: .atomic)

        var values = URLResourceValues()
        values.isExcludedFromBackup = true
        var mutableURL = fileURL
        try mutableURL.setResourceValues(values)
    }

    func loadPrivateKey(for serverID: UUID) throws -> Data? {
        let fileURL = keyURL(for: serverID)
        guard fileManager.fileExists(atPath: fileURL.path) else {
            return nil
        }

        return try Data(contentsOf: fileURL)
    }

    func deletePrivateKey(for serverID: UUID) throws {
        let fileURL = keyURL(for: serverID)
        guard fileManager.fileExists(atPath: fileURL.path) else {
            return
        }

        try fileManager.removeItem(at: fileURL)
    }

    private func createStorageIfNeeded() throws {
        var isDirectory: ObjCBool = false
        let exists = fileManager.fileExists(atPath: baseDirectory.path, isDirectory: &isDirectory)
        guard exists, isDirectory.boolValue else {
            do {
                try fileManager.createDirectory(at: baseDirectory, withIntermediateDirectories: true)
                return
            } catch {
                throw KeyStorageError.directoryCreationFailed
            }
        }
    }

    private func keyURL(for serverID: UUID) -> URL {
        baseDirectory.appendingPathComponent("\(serverID.uuidString).pem", isDirectory: false)
    }
}
