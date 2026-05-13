import Foundation

struct SSHConnectionConfiguration: Sendable {
    enum Authentication: Sendable {
        case sshAgent
        case privateKey(privateKeyPath: String, publicKeyPath: String?)
    }

    let host: String
    let port: Int
    let username: String
    let authentication: Authentication
}

struct TerminalChunk: Sendable {
    enum Stream: Sendable {
        case stdout
        case stderr
    }

    let stream: Stream
    let text: String

    nonisolated init(stream: Stream, text: String) {
        self.stream = stream
        self.text = text
    }
}

struct SFTPFileItem: Identifiable, Hashable, Sendable {
    let id: String
    let name: String
    let path: String
    let isDirectory: Bool
    let size: Int64
    let modifiedAt: Date?

    nonisolated init(
        id: String = UUID().uuidString,
        name: String,
        path: String,
        isDirectory: Bool,
        size: Int64 = 0,
        modifiedAt: Date? = nil
    ) {
        self.id = id
        self.name = name
        self.path = path
        self.isDirectory = isDirectory
        self.size = size
        self.modifiedAt = modifiedAt
    }
}

protocol SSHClient: Sendable {
    func connect(configuration: SSHConnectionConfiguration) async throws
    func disconnect() async
    func setFileOperationUser(_ username: String?) async throws
    func startInteractiveShell(columns: Int, rows: Int) async throws
    func sendToShell(_ input: String) async throws
    func resizeShell(columns: Int, rows: Int) async throws
    func execute(_ command: String) async throws -> String
    func terminalStream() async -> AsyncThrowingStream<TerminalChunk, Error>

    func listDirectory(at path: String) async throws -> [SFTPFileItem]
    func renameItem(at path: String, to newPath: String) async throws
    func deleteItem(at path: String, isDirectory: Bool) async throws
    func createDirectory(at path: String) async throws
    func createFile(at path: String) async throws
    func readTextFile(at path: String) async throws -> String
    func writeTextFile(at path: String, content: String) async throws
    func upload(localURL: URL, remotePath: String) async throws
    func download(
        remotePath: String,
        localURL: URL,
        expectedSize: Int64?,
        progress: @escaping @Sendable (Double) -> Void
    ) async throws
}

extension SSHClient {
    func download(remotePath: String, localURL: URL) async throws {
        try await download(remotePath: remotePath, localURL: localURL, expectedSize: nil) { _ in }
    }
}

enum SSHClientError: LocalizedError {
    case notConnected
    case alreadyConnected
    case invalidHost
    case unsupported(String)

    var errorDescription: String? {
        switch self {
        case .notConnected:
            return "SSH client is not connected."
        case .alreadyConnected:
            return "SSH client is already connected."
        case .invalidHost:
            return "Host is invalid."
        case .unsupported(let detail):
            return detail
        }
    }
}
