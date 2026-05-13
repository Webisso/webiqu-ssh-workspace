import Foundation
import SwiftData

@Model
final class Server {
    @Attribute(.unique) var id: UUID
    var title: String
    var color: String
    var host: String
    var port: Int
    var username: String
    var authenticationMode: String
    var privateKeyPath: String?
    var publicKeyPath: String?
    var terminalTextColor: String = "white"
    var createdAt: Date
    var updatedAt: Date

    var group: ServerGroup?
    @Relationship(deleteRule: .cascade, inverse: \SavedCommand.server) var savedCommands: [SavedCommand]

    init(
        id: UUID = UUID(),
        title: String,
        color: String = "blue",
        host: String,
        port: Int = 22,
        username: String,
        authenticationMode: String = "agent",
        privateKeyPath: String? = nil,
        publicKeyPath: String? = nil,
        terminalTextColor: String = "white",
        createdAt: Date = .now,
        updatedAt: Date = .now,
        group: ServerGroup? = nil,
        savedCommands: [SavedCommand] = []
    ) {
        self.id = id
        self.title = title
        self.color = color
        self.host = host
        self.port = port
        self.username = username
        self.authenticationMode = authenticationMode
        self.privateKeyPath = privateKeyPath
        self.publicKeyPath = publicKeyPath
        self.terminalTextColor = terminalTextColor
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.group = group
        self.savedCommands = savedCommands
    }

    func markUpdated() {
        updatedAt = .now
    }
}
