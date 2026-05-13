//
//  webiquTests.swift
//  webiquTests
//
//  Created by WebissoLLC on 5/13/26.
//

import Testing
import Foundation
import SwiftData
@testable import webiqu

struct webiquTests {

    @Test
    func monitoringParserParsesStructuredMetrics() {
        var parser = RemoteMonitoringParser()

        _ = parser.parseUbuntu(
            cpuStatOutput: "cpu  100 0 100 800 0 0 0 0 0 0",
            memInfoOutput: "MemTotal:       32768000 kB\nMemAvailable:   24576000 kB",
            diskOutput: "Filesystem 1024-blocks Used Available Capacity Mounted on\n/dev/sda1 104857600 52428800 52428800 50% /"
        )

        let snapshot = parser.parseUbuntu(
            cpuStatOutput: "cpu  160 0 140 900 0 0 0 0 0 0",
            memInfoOutput: "MemTotal:       32768000 kB\nMemAvailable:   24576000 kB",
            diskOutput: "Filesystem 1024-blocks Used Available Capacity Mounted on\n/dev/sda1 104857600 52428800 52428800 50% /"
        )

        #expect(snapshot.cpuUsagePercent == 50)
        #expect(snapshot.memoryUsedMB == 8000)
        #expect(snapshot.memoryFreeMB == 24000)
        #expect(snapshot.diskUsedGB == 50)
        #expect(snapshot.diskAvailableGB == 50)
    }

    @Test
    func fileKeyStorageRoundTrip() throws {
        let temporaryRoot = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        let keyStorage = try FileKeyStorageService(baseDirectory: temporaryRoot)
        let serverID = UUID()
        let source = Data("private-key-data".utf8)

        try keyStorage.storePrivateKey(source, for: serverID)
        let loaded = try keyStorage.loadPrivateKey(for: serverID)
        #expect(loaded == source)

        try keyStorage.deletePrivateKey(for: serverID)
        let deleted = try keyStorage.loadPrivateKey(for: serverID)
        #expect(deleted == nil)
    }

    @Test
    @MainActor
    func cloudSyncServiceSavesAndFetchesServers() async throws {
        let schema = Schema([Server.self, ServerGroup.self, SavedCommand.self])
        let configuration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
        let modelContainer = try ModelContainer(for: schema, configurations: [configuration])
        let context = ModelContext(modelContainer)
        let service = SwiftDataCloudSyncService(modelContext: context)

        let server = Server(title: "Test", host: "example.com", username: "root")
        try await service.save(server)

        let fetched: [Server] = try await service.fetch()
        #expect(fetched.count == 1)
        #expect(fetched.first?.host == "example.com")
    }

}
