import Foundation

enum SSHIdentityStorageError: LocalizedError {
    case invalidSource
    case copyFailed(String)

    var errorDescription: String? {
        switch self {
        case .invalidSource:
            return "Selected key file is invalid."
        case .copyFailed(let reason):
            return "Failed to import SSH key: \(reason)"
        }
    }
}

enum SSHIdentityStorageService {
    static func importKey(from sourceURL: URL) throws -> String {
        guard sourceURL.isFileURL else {
            throw SSHIdentityStorageError.invalidSource
        }

        let fileManager = FileManager.default
        let destinationDirectory = try keyStorageDirectory()
        let originalName = sourceURL.lastPathComponent
        let safeName = sanitizeFilename(originalName.isEmpty ? "key" : originalName)
        let destinationURL = destinationDirectory
            .appendingPathComponent("\(UUID().uuidString)_\(safeName)", isDirectory: false)

        let hasSecurityScope = sourceURL.startAccessingSecurityScopedResource()
        defer {
            if hasSecurityScope {
                sourceURL.stopAccessingSecurityScopedResource()
            }
        }

        do {
            if fileManager.fileExists(atPath: destinationURL.path) {
                try fileManager.removeItem(at: destinationURL)
            }
            try fileManager.copyItem(at: sourceURL, to: destinationURL)
            try fileManager.setAttributes([.posixPermissions: 0o600], ofItemAtPath: destinationURL.path)
            AppTrace.log("Security", "SSH key imported to app storage path=\(destinationURL.path)")
            return destinationURL.path
        } catch {
            throw SSHIdentityStorageError.copyFailed(error.localizedDescription)
        }
    }

    private static func keyStorageDirectory() throws -> URL {
        let fileManager = FileManager.default
        let base = try fileManager.url(
            for: .applicationSupportDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        )

        let directory = base
            .appendingPathComponent("webiqu", isDirectory: true)
            .appendingPathComponent("ssh-keys", isDirectory: true)

        try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory
    }

    private static func sanitizeFilename(_ input: String) -> String {
        let allowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "._-"))
        let scalars = input.unicodeScalars.map { scalar in
            allowed.contains(scalar) ? Character(scalar) : "_"
        }
        return String(scalars)
    }
}
