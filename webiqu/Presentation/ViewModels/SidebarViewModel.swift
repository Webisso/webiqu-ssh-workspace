import Foundation
import Combine
import SwiftData

enum SidebarViewModelError: LocalizedError {
    case emptyGroupName
    case emptyServerTitle
    case emptyHost
    case emptyUsername
    case invalidPort

    var errorDescription: String? {
        switch self {
        case .emptyGroupName:
            return "Group name cannot be empty."
        case .emptyServerTitle:
            return "Server title cannot be empty."
        case .emptyHost:
            return "Host cannot be empty."
        case .emptyUsername:
            return "Username cannot be empty."
        case .invalidPort:
            return "Port must be between 1 and 65535."
        }
    }
}

@MainActor
final class SidebarViewModel: ObservableObject {
    @Published var selectedServerID: UUID?
    @Published private(set) var connectedServerIDs: Set<UUID> = []

    func removeLegacyDemoDataIfPresent(context: ModelContext) {
        AppTrace.log("Data", "Checking legacy demo data")
        let groupDescriptor = FetchDescriptor<ServerGroup>()
        guard let groups = try? context.fetch(groupDescriptor) else {
            AppTrace.log("Data", "Legacy data check failed: could not fetch groups")
            return
        }

        var deletedAny = false

        for group in groups {
            if group.name == "Production",
               group.servers.contains(where: { $0.title == "Core API" && $0.host == "prod.example.com" }) {
                context.delete(group)
                deletedAny = true
                continue
            }

            if group.name == "Staging",
               group.servers.contains(where: { $0.title == "Staging API" && $0.host == "staging.example.com" }) {
                context.delete(group)
                deletedAny = true
            }
        }

        if deletedAny {
            try? context.save()
            AppTrace.log("Data", "Legacy demo data removed")
        } else {
            AppTrace.log("Data", "No legacy demo data found")
        }
    }

    func addGroup(name: String, context: ModelContext) throws -> ServerGroup {
        AppTrace.log("Data", "Adding group with raw name='\(name)'")
        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedName.isEmpty else {
            throw SidebarViewModelError.emptyGroupName
        }

        let group = ServerGroup(name: trimmedName)
        context.insert(group)
        try context.save()
        AppTrace.log("Data", "Group saved id=\(group.id.uuidString) name=\(group.name)")
        return group
    }

    func addServer(
        to group: ServerGroup,
        title: String,
        color: String,
        host: String,
        port: Int,
        username: String,
        authenticationMode: String,
        privateKeyPath: String?,
        publicKeyPath: String?,
        context: ModelContext
    ) throws -> Server {
        AppTrace.log("Data", "Adding server raw title='\(title)' host='\(host)' port=\(port) username='\(username)'")
        let trimmedTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedHost = host.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedUsername = username.trimmingCharacters(in: .whitespacesAndNewlines)

        guard !trimmedTitle.isEmpty else {
            throw SidebarViewModelError.emptyServerTitle
        }
        guard !trimmedHost.isEmpty else {
            throw SidebarViewModelError.emptyHost
        }
        guard !trimmedUsername.isEmpty else {
            throw SidebarViewModelError.emptyUsername
        }
        guard (1...65_535).contains(port) else {
            throw SidebarViewModelError.invalidPort
        }

        let server = Server(
            title: trimmedTitle,
            color: color,
            host: trimmedHost,
            port: port,
            username: trimmedUsername,
            authenticationMode: authenticationMode,
            privateKeyPath: privateKeyPath,
            publicKeyPath: publicKeyPath,
            group: group
        )
        group.servers.append(server)
        context.insert(server)
        try context.save()
        selectedServerID = server.id
        AppTrace.log("Data", "Server saved id=\(server.id.uuidString) title=\(server.title) host=\(server.host):\(server.port)")
        return server
    }

    func markConnected(serverID: UUID) {
        AppTrace.log("State", "Server marked connected id=\(serverID.uuidString)")
        connectedServerIDs.insert(serverID)
    }

    func markDisconnected(serverID: UUID) {
        AppTrace.log("State", "Server marked disconnected id=\(serverID.uuidString)")
        connectedServerIDs.remove(serverID)
    }

    func removeServer(_ server: Server, context: ModelContext) throws {
        AppTrace.log("Data", "Removing server id=\(server.id.uuidString) title=\(server.title)")
        connectedServerIDs.remove(server.id)
        if selectedServerID == server.id {
            selectedServerID = nil
        }
        context.delete(server)
        try context.save()
        AppTrace.log("Data", "Server removed id=\(server.id.uuidString)")
    }

    func isConnected(_ serverID: UUID) -> Bool {
        connectedServerIDs.contains(serverID)
    }
}
