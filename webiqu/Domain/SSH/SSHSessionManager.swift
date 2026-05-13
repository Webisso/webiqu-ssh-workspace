import Foundation

actor SSHSessionManager {
    private var clients: [UUID: SSHClient] = [:]
    private let factory: @MainActor @Sendable () -> SSHClient

    init(factory: @escaping @MainActor @Sendable () -> SSHClient) {
        self.factory = factory
        AppTrace.log("Session", "SSHSessionManager initialized")
    }

    func connect(serverID: UUID, configuration: SSHConnectionConfiguration) async throws {
        AppTrace.log("Session", "Connect requested server=\(serverID.uuidString) host=\(configuration.host):\(configuration.port) user=\(configuration.username)")
        if clients[serverID] != nil {
            AppTrace.log("Session", "Connect rejected: already connected server=\(serverID.uuidString)")
            throw SSHClientError.alreadyConnected
        }

        let client = await MainActor.run {
            factory()
        }
        try await client.connect(configuration: configuration)
        clients[serverID] = client
        AppTrace.log("Session", "Connect success server=\(serverID.uuidString)")
    }

    func disconnect(serverID: UUID) async {
        AppTrace.log("Session", "Disconnect requested server=\(serverID.uuidString)")
        guard let client = clients[serverID] else {
            AppTrace.log("Session", "Disconnect ignored: no client for server=\(serverID.uuidString)")
            return
        }
        await client.disconnect()
        clients[serverID] = nil
        AppTrace.log("Session", "Disconnect completed server=\(serverID.uuidString)")
    }

    func disconnectAll() async {
        for (serverID, client) in clients {
            await client.disconnect()
            clients[serverID] = nil
        }
    }

    func client(for serverID: UUID) -> SSHClient? {
        let exists = clients[serverID] != nil
        AppTrace.log("Session", "Client lookup server=\(serverID.uuidString) exists=\(exists)")
        return clients[serverID]
    }
}
