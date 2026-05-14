//
//  webiquApp.swift
//  webiqu
//
//  Created by WebissoLLC on 5/13/26.
//

import Foundation
import SwiftUI
import SwiftData

@main
struct webiquApp: App {
    private static let sharedModelContainer: ModelContainer = {
        AppTrace.log("App", "Building shared ModelContainer")
        let schema = Schema([
            Server.self,
            ServerGroup.self,
            SavedCommand.self,
        ])
        let storeURL = storeFileURL()
        AppTrace.log("App", "Using SwiftData store URL: \(storeURL.path)")

        let modelConfiguration = ModelConfiguration(
            "Default",
            schema: schema,
            url: storeURL,
            cloudKitDatabase: .automatic
        )

        do {
            let container = try ModelContainer(for: schema, configurations: [modelConfiguration])
            AppTrace.log("App", "ModelContainer ready (CloudKit: automatic)")
            return container
        } catch {
            AppTrace.log("App", "ModelContainer init failed: \(error.localizedDescription)")

            do {
                AppTrace.log("App", "Attempting local store reset and retry")
                try resetStoreFiles(at: storeURL)
                let retryContainer = try ModelContainer(for: schema, configurations: [modelConfiguration])
                AppTrace.log("App", "ModelContainer recovered after local store reset")
                return retryContainer
            } catch {
                AppTrace.log("App", "ModelContainer retry failed: \(error.localizedDescription)")
                fatalError("Could not create ModelContainer: \(error)")
            }
        }
    }()

    private let appContainer: AppContainer
    private let sessionManager: SSHSessionManager

    init() {
        AppTrace.log("App", "webiquApp init started")
        let container = AppContainer(modelContainer: Self.sharedModelContainer)
        self.appContainer = container
        self.sessionManager = container.makeSessionManager()
        AppTrace.log("App", "webiquApp init completed")
    }

    @State private var showingAppSettings = false

    var body: some Scene {
        WindowGroup("Servers") {
            ContentView(sessionManager: sessionManager, showingAppSettings: $showingAppSettings)
        }
        .modelContainer(Self.sharedModelContainer)
        .commands {
            CommandGroup(replacing: .appInfo) {
                Button("About \(Bundle.main.object(forInfoDictionaryKey: "CFBundleName") as? String ?? "webiqu")") {
                    AboutWindowController.shared.showAboutWindow()
                }
            }

            CommandGroup(replacing: .appSettings) {
                Button("Settings…") {
                    showingAppSettings = true
                }
                .keyboardShortcut(",", modifiers: .command)
            }
        }

        WindowGroup("Quick Terminal") {
            ContentUnavailableView(
                "Open a Server",
                systemImage: "terminal",
                description: Text("Use the main window sidebar to choose a server and start a session.")
            )
        }
        .modelContainer(Self.sharedModelContainer)
    }

    private static func storeFileURL() -> URL {
        let baseURL = (try? FileManager.default.url(
            for: .applicationSupportDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        )) ?? FileManager.default.temporaryDirectory

        let directory = baseURL.appendingPathComponent("webiqu", isDirectory: true)
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory.appendingPathComponent("default.store", isDirectory: false)
    }

    private static func resetStoreFiles(at storeURL: URL) throws {
        let fm = FileManager.default
        let paths = [
            storeURL.path,
            storeURL.path + "-wal",
            storeURL.path + "-shm"
        ]

        for path in paths where fm.fileExists(atPath: path) {
            try fm.removeItem(atPath: path)
            AppTrace.log("App", "Removed store artifact: \(path)")
        }
    }
}
