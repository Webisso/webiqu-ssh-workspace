import Foundation
import Combine
import AppKit

struct TerminalSessionState: Identifiable, Equatable {
    let id: UUID
    var title: String
    var output: String
    var isConnected: Bool

    init(id: UUID = UUID(), title: String, output: String = "", isConnected: Bool = false) {
        self.id = id
        self.title = title
        self.output = output
        self.isConnected = isConnected
    }
}

@MainActor
final class ServerWorkspaceViewModel: ObservableObject {
    @Published var terminalSessions: [TerminalSessionState]
    @Published var selectedTerminalSessionID: UUID
    @Published var currentDirectory = "/"
    @Published var files: [SFTPFileItem] = []
    @Published var availableFileManagerUsers: [String] = []
    @Published var selectedFileManagerUser: String = ""
    @Published var monitoring = MonitoringSnapshot(
        cpuUsagePercent: 0,
        memoryUsedMB: 0,
        memoryFreeMB: 0,
        diskUsedGB: 0,
        diskAvailableGB: 0
    )
    @Published var monitoringHistory: [MonitoringSample] = []
    @Published var lastMonitoringRefreshAt: Date?
    @Published var monitoringRefreshInterval: MonitoringRefreshInterval = .second1
    @Published var isConnected = false
    @Published var errorMessage: String?
    @Published var isDownloadInProgress = false
    @Published var downloadProgress: Double = 0
    @Published var isUploadInProgress = false
    @Published var uploadProgress: Double = 0
    @Published var uploadCurrentItemName: String = ""

    private let sessionManager: SSHSessionManager
    private var parser = RemoteMonitoringParser()
    private let onConnectionStateChanged: @MainActor (UUID, Bool) -> Void
    private var terminalStreamTasks: [UUID: Task<Void, Never>] = [:]
    private var monitoringTask: Task<Void, Never>?
    private var isRefreshingMonitoring = false
    private var isMonitoringTabActive = false
    private var pendingTerminalInputs: [UUID: [String]] = [:]
    private var drainingTerminalSessionIDs: Set<UUID> = []
    private var connectingTerminalSessionIDs: Set<UUID> = []
    private var pendingTerminalCommands: [UUID: String] = [:]
    private var sessionUsername = ""
    private var nextTerminalTabNumber = 2

    init(
        sessionManager: SSHSessionManager,
        onConnectionStateChanged: @escaping @MainActor (UUID, Bool) -> Void
    ) {
        let initialTerminalSession = TerminalSessionState(title: "Tab 1")
        self.terminalSessions = [initialTerminalSession]
        self.selectedTerminalSessionID = initialTerminalSession.id
        self.sessionManager = sessionManager
        self.onConnectionStateChanged = onConnectionStateChanged
    }

    deinit {
        for task in terminalStreamTasks.values {
            task.cancel()
        }
        monitoringTask?.cancel()
    }

    var selectedTerminalSession: TerminalSessionState? {
        terminalSessions.first(where: { $0.id == selectedTerminalSessionID })
    }

    func terminalOutput(for sessionID: UUID) -> String {
        terminalSessions.first(where: { $0.id == sessionID })?.output ?? ""
    }

    func updateTerminalOutput(_ output: String, for sessionID: UUID) {
        guard let index = terminalSessions.firstIndex(where: { $0.id == sessionID }) else {
            return
        }
        terminalSessions[index].output = output
    }

    func addTerminalTab(for server: Server) {
        let session = TerminalSessionState(title: "Tab \(nextTerminalTabNumber)")
        nextTerminalTabNumber += 1
        terminalSessions.append(session)
        selectedTerminalSessionID = session.id

        if isConnected {
            Task {
                await connectTerminalSession(session.id, to: server)
            }
        }
    }

    func closeTerminalTab(_ sessionID: UUID) {
        guard terminalSessions.count > 1,
              let removedIndex = terminalSessions.firstIndex(where: { $0.id == sessionID })
        else {
            return
        }

        terminalStreamTasks[sessionID]?.cancel()
        terminalStreamTasks[sessionID] = nil
        pendingTerminalInputs[sessionID] = nil
        pendingTerminalCommands[sessionID] = nil
        drainingTerminalSessionIDs.remove(sessionID)

        terminalSessions.remove(at: removedIndex)

        if selectedTerminalSessionID == sessionID {
            let fallbackIndex = min(removedIndex, terminalSessions.count - 1)
            selectedTerminalSessionID = terminalSessions[fallbackIndex].id
        }

        Task {
            await sessionManager.disconnect(serverID: sessionID)
        }
    }

    func renameTerminalTab(_ sessionID: UUID, to rawTitle: String) {
        guard let index = terminalSessions.firstIndex(where: { $0.id == sessionID }) else {
            return
        }

        let trimmed = rawTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            return
        }

        terminalSessions[index].title = String(trimmed.prefix(40))
    }

    func ensureTerminalSessionConnected(_ sessionID: UUID, server: Server) {
        guard isConnected else { return }
        guard terminalSessions.contains(where: { $0.id == sessionID }) else { return }
        guard !isTerminalConnected(sessionID) else { return }
        guard !connectingTerminalSessionIDs.contains(sessionID) else { return }

        Task {
            await connectTerminalSession(sessionID, to: server)
        }
    }

    func connect(to server: Server) {
        AppTrace.log("VM", "Connect button tapped server=\(server.id.uuidString) title=\(server.title) host=\(server.host):\(server.port)")

        Task {
            do {
                try await ensurePrimarySessionConnected(to: server)

                await MainActor.run {
                    self.isConnected = true
                    self.onConnectionStateChanged(server.id, true)
                    AppTrace.log("VM", "UI marked connected server=\(server.id.uuidString)")
                }

                guard let client = await sessionManager.client(for: server.id) else {
                    AppTrace.log("VM", "Client missing right after connect server=\(server.id.uuidString)")
                    return
                }
                sessionUsername = server.username
                selectedFileManagerUser = server.username
                try await client.setFileOperationUser(nil)

                let terminalSessionIDs = await MainActor.run { self.terminalSessions.map(\.id) }
                for sessionID in terminalSessionIDs {
                    await connectTerminalSession(sessionID, to: server)
                }

                do {
                    try await loadFileManagerUsers(serverID: server.id, fallbackUsername: server.username)
                } catch {
                    AppTrace.log("VM", "File manager users discovery failed: \(error.localizedDescription)")
                    await MainActor.run {
                        self.availableFileManagerUsers = [server.username]
                        self.selectedFileManagerUser = server.username
                    }
                }

                try await loadDirectory(path: "/", serverID: server.id)
                if isMonitoringTabActive {
                    try await refreshMonitoring(serverID: server.id)
                    startMonitoringAutoRefresh(serverID: server.id)
                    AppTrace.log("VM", "Initial file/monitor refresh completed server=\(server.id.uuidString)")
                } else {
                    AppTrace.log("VM", "Initial file refresh completed; monitoring paused (tab inactive) server=\(server.id.uuidString)")
                }
            } catch {
                await MainActor.run {
                    self.isConnected = false
                    self.onConnectionStateChanged(server.id, false)
                    let message = friendlyMessage(for: error)
                    self.appendTerminalOutput("[connect error] \(message)\n", to: self.selectedTerminalSessionID)
                    self.errorMessage = message
                    AppTrace.log("VM", "Connect failed server=\(server.id.uuidString) error=\(message)")
                }
            }
        }
    }

    func disconnect(serverID: UUID) {
        AppTrace.log("VM", "Disconnect button tapped server=\(serverID.uuidString)")
        Task {
            let terminalSessionIDs = await MainActor.run { self.terminalSessions.map(\.id) }
            for sessionID in terminalSessionIDs {
                await sessionManager.disconnect(serverID: sessionID)
            }
            await sessionManager.disconnect(serverID: serverID)

            await MainActor.run {
                self.isConnected = false
                self.availableFileManagerUsers = []
                self.selectedFileManagerUser = ""
                self.sessionUsername = ""
                self.onConnectionStateChanged(serverID, false)
                for sessionID in terminalSessionIDs {
                    self.setTerminalConnection(false, for: sessionID)
                    self.terminalStreamTasks[sessionID]?.cancel()
                    self.terminalStreamTasks[sessionID] = nil
                    self.pendingTerminalInputs[sessionID] = []
                    self.pendingTerminalCommands[sessionID] = ""
                }
                self.drainingTerminalSessionIDs.removeAll()
                self.monitoringTask?.cancel()
                self.monitoringTask = nil
                AppTrace.log("VM", "UI marked disconnected server=\(serverID.uuidString)")
            }
        }
    }

    func submitCommand(serverID: UUID) {
        AppTrace.log("VM", "Submit command requested server=\(serverID.uuidString) isConnected=\(isConnected)")
        guard isConnected else {
            errorMessage = "Connect to the server first."
            AppTrace.log("VM", "Submit command blocked: not connected server=\(serverID.uuidString)")
            return
        }

        guard let terminalSession = selectedTerminalSession else {
            errorMessage = "No terminal tab is available."
            return
        }

        guard terminalSession.isConnected else {
            errorMessage = "Selected terminal tab is not connected."
            return
        }

        let command = pendingTerminalCommands[terminalSession.id, default: ""]
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard !command.isEmpty else {
            return
        }

        pendingTerminalCommands[terminalSession.id] = ""
        appendTerminalOutput("$ \(command)\n", to: terminalSession.id)
        AppTrace.log("VM", "Command queued server=\(serverID.uuidString) command=\(command)")

        Task {
            do {
                guard let client = await sessionManager.client(for: terminalSession.id) else {
                    throw SSHClientError.notConnected
                }
                try await client.sendToShell("\(command)\n")
                AppTrace.log("VM", "Command sent server=\(serverID.uuidString)")
            } catch {
                await MainActor.run {
                    self.errorMessage = friendlyMessage(for: error)
                    AppTrace.log("VM", "Command send failed server=\(serverID.uuidString) error=\(self.errorMessage ?? "unknown")")
                }
            }
        }
    }

    func sendTerminalInput(_ input: String, sessionID: UUID) {
        guard isTerminalConnected(sessionID) else { return }
        guard !input.isEmpty else { return }

        handleLocalInputEffects(input, sessionID: sessionID)

        pendingTerminalInputs[sessionID, default: []].append(input)
        guard !drainingTerminalSessionIDs.contains(sessionID) else { return }
        drainingTerminalSessionIDs.insert(sessionID)

        Task { [weak self] in
            guard let self else { return }

            while await MainActor.run(body: {
                !(self.pendingTerminalInputs[sessionID] ?? []).isEmpty && self.isTerminalConnected(sessionID)
            }) {
                let nextInput = await MainActor.run {
                    self.pendingTerminalInputs[sessionID]?.removeFirst() ?? ""
                }

                do {
                    guard let client = await self.sessionManager.client(for: sessionID) else {
                        throw SSHClientError.notConnected
                    }
                    try await client.sendToShell(nextInput)
                } catch {
                    await MainActor.run {
                        self.errorMessage = self.friendlyMessage(for: error)
                        self.pendingTerminalInputs[sessionID] = []
                    }
                    break
                }
            }

            await MainActor.run {
                _ = self.drainingTerminalSessionIDs.remove(sessionID)
            }
        }
    }

    func resizeTerminal(columns: Int, rows: Int, sessionID: UUID) {
        guard isTerminalConnected(sessionID) else { return }

        Task {
            do {
                guard let client = await sessionManager.client(for: sessionID) else {
                    throw SSHClientError.notConnected
                }
                try await client.resizeShell(columns: columns, rows: rows)
            } catch {
                await MainActor.run {
                    self.errorMessage = self.friendlyMessage(for: error)
                }
            }
        }
    }

    private func ensurePrimarySessionConnected(to server: Server) async throws {
        if await sessionManager.client(for: server.id) == nil {
            AppTrace.log("VM", "No existing primary client, creating new session server=\(server.id.uuidString)")
            try await sessionManager.connect(serverID: server.id, configuration: connectionConfiguration(for: server))
        }
    }

    private func connectTerminalSession(_ sessionID: UUID, to server: Server) async {
        guard terminalSessions.contains(where: { $0.id == sessionID }) else {
            return
        }

        guard !connectingTerminalSessionIDs.contains(sessionID) else {
            return
        }
        connectingTerminalSessionIDs.insert(sessionID)
        defer { connectingTerminalSessionIDs.remove(sessionID) }

        await MainActor.run {
            if self.terminalOutput(for: sessionID).isEmpty {
                self.appendTerminalOutput(
                    "Connecting to \(server.username)@\(server.host):\(server.port)...\n",
                    to: sessionID
                )
            }
        }

        do {
            if await sessionManager.client(for: sessionID) == nil {
                try await sessionManager.connect(serverID: sessionID, configuration: connectionConfiguration(for: server))
            }

            guard let client = await sessionManager.client(for: sessionID) else {
                return
            }

            let stream = await client.terminalStream()
            let streamTask = Task { @MainActor [weak self] in
                guard let self else { return }

                do {
                    for try await chunk in stream {
                        self.appendTerminalOutput(chunk.text, to: sessionID)
                    }

                    self.setTerminalConnection(false, for: sessionID)
                    AppTrace.log("VM", "Terminal stream completed session=\(sessionID.uuidString)")
                } catch {
                    self.setTerminalConnection(false, for: sessionID)
                    let message = self.friendlyMessage(for: error)
                    self.appendTerminalOutput("[stream error] \(message)\n", to: sessionID)
                    self.errorMessage = message
                    AppTrace.log("VM", "Terminal stream failed session=\(sessionID.uuidString) error=\(message)")
                }
            }

            await MainActor.run {
                self.terminalStreamTasks[sessionID]?.cancel()
                self.terminalStreamTasks[sessionID] = streamTask
                self.setTerminalConnection(true, for: sessionID)
                self.pendingTerminalInputs[sessionID] = []
                self.pendingTerminalCommands[sessionID] = ""
                self.appendTerminalOutput("Connected to \(server.title)\n", to: sessionID)
            }

            try await client.startInteractiveShell(columns: 120, rows: 36)
            AppTrace.log("VM", "Interactive shell started terminal session=\(sessionID.uuidString)")
        } catch {
            await MainActor.run {
                self.setTerminalConnection(false, for: sessionID)
                let message = self.friendlyMessage(for: error)
                self.appendTerminalOutput("[connect error] \(message)\n", to: sessionID)
                self.errorMessage = message
                AppTrace.log("VM", "Terminal connect failed session=\(sessionID.uuidString) error=\(message)")
            }
        }
    }

    func loadDirectory(path: String, serverID: UUID) async throws {
        AppTrace.log("VM", "Load directory server=\(serverID.uuidString) path=\(path)")
        guard let client = await sessionManager.client(for: serverID) else {
            AppTrace.log("VM", "Load directory failed: no client server=\(serverID.uuidString)")
            throw SSHClientError.notConnected
        }

        let result = try await client.listDirectory(at: path)
        await MainActor.run {
            self.currentDirectory = path
            self.files = result.sorted { lhs, rhs in
                if lhs.isDirectory != rhs.isDirectory {
                    return lhs.isDirectory
                }
                return lhs.name.localizedCaseInsensitiveCompare(rhs.name) == .orderedAscending
            }
            AppTrace.log("VM", "Directory loaded server=\(serverID.uuidString) path=\(path) items=\(result.count)")
        }
    }

    func loadFileManagerUsers(serverID: UUID, fallbackUsername: String) async throws {
        guard let client = await sessionManager.client(for: serverID) else {
            throw SSHClientError.notConnected
        }

        let output = try await client.execute(
            "getent passwd | awk -F: '(($3==0)||($3>=1000)) && $7 !~ /(nologin|false)$/ {print $1}'"
        )

        let parsed = output
            .split(separator: "\n")
            .map { String($0).trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }

        var users: [String] = [fallbackUsername]
        users.append(contentsOf: parsed)
        users = Array(Set(users)).sorted { $0.localizedCaseInsensitiveCompare($1) == .orderedAscending }

        await MainActor.run {
            self.availableFileManagerUsers = users
            if self.selectedFileManagerUser.isEmpty || !users.contains(self.selectedFileManagerUser) {
                self.selectedFileManagerUser = fallbackUsername
            }
        }
    }

    func selectFileManagerUser(_ username: String, serverID: UUID) async throws {
        let trimmed = username.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }

        guard let client = await sessionManager.client(for: serverID) else {
            throw SSHClientError.notConnected
        }

        if trimmed == sessionUsername {
            try await client.setFileOperationUser(nil)
        } else {
            try await client.setFileOperationUser(trimmed)
        }

        await MainActor.run {
            self.selectedFileManagerUser = trimmed
        }

        try await loadDirectory(path: currentDirectory, serverID: serverID)
    }

    func refreshMonitoring(serverID: UUID) async throws {
        guard !isRefreshingMonitoring else {
            return
        }

        let startedAt = Date()
        isRefreshingMonitoring = true
        defer { isRefreshingMonitoring = false }

        AppTrace.log("VM", "Refresh monitoring requested server=\(serverID.uuidString)")
        guard let client = await sessionManager.client(for: serverID) else {
            AppTrace.log("VM", "Refresh monitoring failed: no client server=\(serverID.uuidString)")
            throw SSHClientError.notConnected
        }

        let metricsOutput = try await client.execute(
            "printf '__WEBIQU_CPU__\\n'; head -n 1 /proc/stat; " +
            "printf '__WEBIQU_MEM__\\n'; grep -E \"^(MemTotal|MemAvailable):\" /proc/meminfo; " +
            "printf '__WEBIQU_DISK__\\n'; df -kP /"
        )

        guard let sections = parseMonitoringSections(from: metricsOutput) else {
            AppTrace.log("VM", "Monitoring payload parse failed server=\(serverID.uuidString) output=\(metricsOutput)")
            throw SSHClientError.unsupported("Monitoring output could not be parsed.")
        }

        let snapshot = parser.parseUbuntu(
            cpuStatOutput: sections.cpu,
            memInfoOutput: sections.mem,
            diskOutput: sections.disk
        )

        await MainActor.run {
            self.monitoring = snapshot
            self.lastMonitoringRefreshAt = .now
            self.monitoringHistory.append(MonitoringSample(timestamp: .now, snapshot: snapshot))
            if self.monitoringHistory.count > 120 {
                self.monitoringHistory.removeFirst(self.monitoringHistory.count - 120)
            }
            let duration = Date().timeIntervalSince(startedAt)
            let durationText = String(format: "%.3f", duration)
            AppTrace.log("VM", "Monitoring updated server=\(serverID.uuidString) cpu=\(snapshot.cpuUsagePercent) duration=\(durationText)s")
        }
    }

    func updateMonitoringRefreshInterval(_ interval: MonitoringRefreshInterval, serverID: UUID) {
        monitoringRefreshInterval = interval
        AppTrace.log("VM", "Monitoring refresh interval updated to \(interval.title)")

        if isConnected && isMonitoringTabActive {
            startMonitoringAutoRefresh(serverID: serverID)
        }
    }

    func setMonitoringActive(_ isActive: Bool, serverID: UUID) {
        isMonitoringTabActive = isActive

        guard isConnected else {
            monitoringTask?.cancel()
            monitoringTask = nil
            return
        }

        if isActive {
            if monitoringTask == nil {
                monitoringTask = Task { [weak self] in
                    guard let self else { return }
                    do {
                        try await self.refreshMonitoring(serverID: serverID)
                    } catch {
                        await MainActor.run {
                            self.errorMessage = self.friendlyMessage(for: error)
                        }
                    }
                    self.startMonitoringAutoRefresh(serverID: serverID)
                }
            }
        } else {
            monitoringTask?.cancel()
            monitoringTask = nil
            AppTrace.log("VM", "Monitoring auto refresh stopped (tab inactive) server=\(serverID.uuidString)")
        }
    }

    private func startMonitoringAutoRefresh(serverID: UUID) {
        monitoringTask?.cancel()
        monitoringTask = Task { [weak self] in
            guard let self else { return }

            while !Task.isCancelled {
                let startedAt = Date()

                do {
                    try await self.refreshMonitoring(serverID: serverID)
                } catch {
                    await MainActor.run {
                        self.errorMessage = self.friendlyMessage(for: error)
                    }
                }

                let delay = self.monitoringRefreshInterval.seconds
                let elapsed = Date().timeIntervalSince(startedAt)
                let remaining = max(0, delay - elapsed)

                if remaining > 0 {
                    let nanos = UInt64(remaining * 1_000_000_000)
                    try? await Task.sleep(nanoseconds: nanos)
                } else {
                    await Task.yield()
                }
            }
        }
    }

    private func parseMonitoringSections(from payload: String) -> (cpu: String, mem: String, disk: String)? {
        let cpuMarker = "__WEBIQU_CPU__\n"
        let memMarker = "\n__WEBIQU_MEM__\n"
        let diskMarker = "\n__WEBIQU_DISK__\n"

        guard
            let cpuStart = payload.range(of: cpuMarker),
            let memRange = payload.range(of: memMarker),
            let diskRange = payload.range(of: diskMarker),
            cpuStart.upperBound <= memRange.lowerBound,
            memRange.upperBound <= diskRange.lowerBound
        else {
            return nil
        }

        let cpu = String(payload[cpuStart.upperBound..<memRange.lowerBound]).trimmingCharacters(in: .whitespacesAndNewlines)
        let mem = String(payload[memRange.upperBound..<diskRange.lowerBound]).trimmingCharacters(in: .whitespacesAndNewlines)
        let disk = String(payload[diskRange.upperBound...]).trimmingCharacters(in: .whitespacesAndNewlines)

        guard !cpu.isEmpty, !mem.isEmpty, !disk.isEmpty else {
            return nil
        }

        return (cpu: cpu, mem: mem, disk: disk)
    }

    func renameItem(_ item: SFTPFileItem, to newName: String, serverID: UUID) async throws {
        let trimmed = newName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            throw SSHClientError.unsupported("Name cannot be empty.")
        }

        guard let client = await sessionManager.client(for: serverID) else {
            throw SSHClientError.notConnected
        }

        let parent = (item.path as NSString).deletingLastPathComponent
        let newPath = parent == "/" ? "/\(trimmed)" : "\(parent)/\(trimmed)"
        try await client.renameItem(at: item.path, to: newPath)
        try await loadDirectory(path: currentDirectory, serverID: serverID)
    }

    func deleteItem(_ item: SFTPFileItem, serverID: UUID) async throws {
        guard let client = await sessionManager.client(for: serverID) else {
            throw SSHClientError.notConnected
        }

        try await client.deleteItem(at: item.path, isDirectory: item.isDirectory)
        try await loadDirectory(path: currentDirectory, serverID: serverID)
    }

    func createFolder(named name: String, in directory: String, serverID: UUID) async throws {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            throw SSHClientError.unsupported("Folder name cannot be empty.")
        }

        guard let client = await sessionManager.client(for: serverID) else {
            throw SSHClientError.notConnected
        }

        let path = directory == "/" ? "/\(trimmed)" : "\(directory)/\(trimmed)"
        try await client.createDirectory(at: path)
        try await loadDirectory(path: directory, serverID: serverID)
    }

    func createFile(named name: String, in directory: String, serverID: UUID) async throws {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            throw SSHClientError.unsupported("File name cannot be empty.")
        }

        guard let client = await sessionManager.client(for: serverID) else {
            throw SSHClientError.notConnected
        }

        let path = directory == "/" ? "/\(trimmed)" : "\(directory)/\(trimmed)"
        try await client.createFile(at: path)
        try await loadDirectory(path: directory, serverID: serverID)
    }

    func readTextFile(_ item: SFTPFileItem, serverID: UUID) async throws -> String {
        guard !item.isDirectory else {
            throw SSHClientError.unsupported("Folders cannot be opened in text editor.")
        }

        guard let client = await sessionManager.client(for: serverID) else {
            throw SSHClientError.notConnected
        }

        return try await client.readTextFile(at: item.path)
    }

    func writeTextFile(_ item: SFTPFileItem, content: String, serverID: UUID) async throws {
        guard !item.isDirectory else {
            throw SSHClientError.unsupported("Folders cannot be saved as text files.")
        }

        guard let client = await sessionManager.client(for: serverID) else {
            throw SSHClientError.notConnected
        }

        try await client.writeTextFile(at: item.path, content: content)
        try await loadDirectory(path: currentDirectory, serverID: serverID)
    }

    func downloadItem(_ item: SFTPFileItem, to destinationURL: URL, serverID: UUID) async throws {
        guard !item.isDirectory else {
            throw SSHClientError.unsupported("Downloading folders is not supported yet.")
        }

        guard let client = await sessionManager.client(for: serverID) else {
            throw SSHClientError.notConnected
        }

        await MainActor.run {
            self.isDownloadInProgress = true
            self.downloadProgress = 0
        }

        do {
            try await client.download(
                remotePath: item.path,
                localURL: destinationURL,
                expectedSize: item.size,
                progress: { progress in
                    Task { @MainActor in
                        self.downloadProgress = progress
                    }
                }
            )

            await MainActor.run {
                self.isDownloadInProgress = false
                self.downloadProgress = 0
                let alert = NSAlert()
                alert.messageText = "Download Completed"
                alert.informativeText = "\(item.name) was saved to:\n\(destinationURL.path)"
                alert.alertStyle = .informational
                alert.addButton(withTitle: "OK")
                alert.runModal()
            }
        } catch {
            await MainActor.run {
                self.isDownloadInProgress = false
                self.downloadProgress = 0
            }
            throw error
        }
    }

    func uploadItems(_ localURLs: [URL], to directory: String, serverID: UUID) async throws {
        let candidates = localURLs.filter { $0.isFileURL }
        guard !candidates.isEmpty else {
            throw SSHClientError.unsupported("No file or folder selected for upload.")
        }

        guard let client = await sessionManager.client(for: serverID) else {
            throw SSHClientError.notConnected
        }

        await MainActor.run {
            self.isUploadInProgress = true
            self.uploadProgress = 0
            self.uploadCurrentItemName = ""
        }

        do {
            let total = Double(candidates.count)
            for (index, localURL) in candidates.enumerated() {
                let destinationPath = directory == "/" ? "/" : directory
                let baseProgress = Double(index) / total
                let segmentProgress = 1.0 / total

                await MainActor.run {
                    self.uploadCurrentItemName = localURL.lastPathComponent
                    self.uploadProgress = baseProgress
                }

                try await client.upload(localURL: localURL, remotePath: destinationPath)

                await MainActor.run {
                    self.uploadProgress = baseProgress + segmentProgress
                }
            }

            try await loadDirectory(path: directory, serverID: serverID)

            await MainActor.run {
                self.isUploadInProgress = false
                self.uploadProgress = 0
                self.uploadCurrentItemName = ""
            }
        } catch {
            await MainActor.run {
                self.isUploadInProgress = false
                self.uploadProgress = 0
                self.uploadCurrentItemName = ""
            }
            throw error
        }
    }

    func stageSavedCommand(_ savedCommand: SavedCommand) async throws {
        guard isConnected else {
            throw SSHClientError.notConnected
        }

        let stagedCommand = savedCommand.command.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !stagedCommand.isEmpty else {
            throw SSHClientError.unsupported("Saved command is empty.")
        }

        guard let selectedTerminalSession else {
            throw SSHClientError.unsupported("No terminal tab is available.")
        }

        guard selectedTerminalSession.isConnected else {
            throw SSHClientError.notConnected
        }

        guard let client = await sessionManager.client(for: selectedTerminalSession.id) else {
            throw SSHClientError.notConnected
        }

        await MainActor.run {
            self.updateTerminalOutput("", for: selectedTerminalSession.id)
            self.pendingTerminalCommands[selectedTerminalSession.id] = stagedCommand
        }

        try await client.sendToShell(stagedCommand)
    }

    private func friendlyMessage(for error: Error) -> String {
        if let sshError = error as? SSHClientError {
            switch sshError {
            case .notConnected:
                return "SSH bağlantısı açık değil. Connect'e tıklayıp tekrar deneyin. Eğer hemen düşüyorsa terminal çıktısında auth/network hatasını kontrol edin."
            default:
                break
            }
        }
        return error.localizedDescription
    }

    private func handleLocalInputEffects(_ input: String, sessionID: UUID) {
        var pendingCommand = pendingTerminalCommands[sessionID, default: ""]

        for scalar in input.unicodeScalars {
            switch scalar.value {
            case 8, 127:
                if !pendingCommand.isEmpty {
                    pendingCommand.removeLast()
                }
            case 10, 13:
                let command = pendingCommand.trimmingCharacters(in: .whitespacesAndNewlines)
                if command == "clear" {
                    updateTerminalOutput("", for: sessionID)
                }
                pendingCommand = ""
            case 27:
                // Ignore escape-leading sequences for command buffer tracking.
                break
            default:
                if CharacterSet.controlCharacters.contains(scalar) {
                    break
                }
                pendingCommand.append(String(scalar))
            }
        }

        pendingTerminalCommands[sessionID] = pendingCommand
    }

    private func appendTerminalOutput(_ text: String, to sessionID: UUID) {
        guard let index = terminalSessions.firstIndex(where: { $0.id == sessionID }) else {
            return
        }

        var rendered = ""
        var isEscaping = false
        var existingOutput = terminalSessions[index].output

        let normalized = text.replacingOccurrences(of: "\r\n", with: "\n")

        for scalar in normalized.unicodeScalars {
            let value = scalar.value

            if isEscaping {
                // End of CSI/ANSI sequence.
                if (64...126).contains(value) {
                    isEscaping = false
                }
                continue
            }

            if value == 27 {
                isEscaping = true
                continue
            }

            if value == 8 || value == 127 {
                if !rendered.isEmpty {
                    rendered.removeLast()
                } else if !existingOutput.isEmpty {
                    existingOutput.removeLast()
                }
                continue
            }

            if value == 13 {
                rendered.append("\n")
                continue
            }

            if value < 32, value != 9, value != 10 {
                continue
            }

            rendered.append(String(scalar))
        }

        if text.contains("\u{1B}[2J") || text.contains("\u{1B}c") {
            existingOutput = ""
        }

        if !rendered.isEmpty {
            existingOutput += rendered
        }

        if existingOutput.count > 200_000 {
            existingOutput = String(existingOutput.suffix(120_000))
        }

        terminalSessions[index].output = existingOutput
    }

    private func connectionConfiguration(for server: Server) -> SSHConnectionConfiguration {
        let authentication: SSHConnectionConfiguration.Authentication
        if server.authenticationMode == "privateKey",
           let privateKeyPath = server.privateKeyPath,
           !privateKeyPath.isEmpty {
            authentication = .privateKey(
                privateKeyPath: privateKeyPath,
                publicKeyPath: server.publicKeyPath
            )
        } else if server.authenticationMode == "agent" {
            let defaults = AppSettingsStore.shared.settings
            let defaultPrivateKeyPath = defaults.defaultPrivateKeyPath
                .trimmingCharacters(in: .whitespacesAndNewlines)
            let defaultPublicKeyPath = defaults.defaultPublicKeyPath
                .trimmingCharacters(in: .whitespacesAndNewlines)

            if !defaultPrivateKeyPath.isEmpty {
                authentication = .privateKey(
                    privateKeyPath: defaultPrivateKeyPath,
                    publicKeyPath: defaultPublicKeyPath.isEmpty ? nil : defaultPublicKeyPath
                )
            } else {
                authentication = .sshAgent
            }
        } else {
            authentication = .sshAgent
        }

        return SSHConnectionConfiguration(
            host: server.host,
            port: server.port,
            username: server.username,
            authentication: authentication
        )
    }

    private func setTerminalConnection(_ isConnected: Bool, for sessionID: UUID) {
        guard let index = terminalSessions.firstIndex(where: { $0.id == sessionID }) else {
            return
        }
        terminalSessions[index].isConnected = isConnected
    }

    private func isTerminalConnected(_ sessionID: UUID) -> Bool {
        terminalSessions.first(where: { $0.id == sessionID })?.isConnected == true
    }
}
