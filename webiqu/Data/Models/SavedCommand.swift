import Foundation
import SwiftData

@Model
final class SavedCommand {
    @Attribute(.unique) var id: UUID
    var title: String
    var command: String
    var server: Server?

    init(id: UUID = UUID(), title: String = "Untitled", command: String, server: Server? = nil) {
        self.id = id
        self.title = title
        self.command = command
        self.server = server
    }
}
