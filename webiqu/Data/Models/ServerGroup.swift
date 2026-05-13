import Foundation
import SwiftData

@Model
final class ServerGroup {
    @Attribute(.unique) var id: UUID
    var name: String
    @Relationship(deleteRule: .cascade, inverse: \Server.group) var servers: [Server]

    init(id: UUID = UUID(), name: String, servers: [Server] = []) {
        self.id = id
        self.name = name
        self.servers = servers
    }
}
