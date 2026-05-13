import Foundation
import SwiftData

@MainActor
final class AppContainer {
    let modelContainer: ModelContainer
    let keyStorageService: KeyStorageService

    init(modelContainer: ModelContainer) {
        AppTrace.log("DI", "AppContainer init")
        self.modelContainer = modelContainer
        do {
            self.keyStorageService = try FileKeyStorageService()
            AppTrace.log("DI", "KeyStorageService initialized")
        } catch {
            AppTrace.log("DI", "KeyStorageService init failed: \(error.localizedDescription)")
            fatalError("Unable to initialize key storage: \(error.localizedDescription)")
        }
    }

    func makeCloudSyncService(context: ModelContext) -> CloudSyncService {
        AppTrace.log("DI", "Creating CloudSyncService")
        return SwiftDataCloudSyncService(modelContext: context)
    }

    func makeSessionManager() -> SSHSessionManager {
        AppTrace.log("DI", "Creating SSHSessionManager")
        return SSHSessionManager(factory: {
            AppTrace.log("DI", "Instantiating NIOSSHClient")
            return NIOSSHClient()
        })
    }
}
