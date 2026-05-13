import AppKit
import SwiftData
import SwiftUI

struct ServerWorkspaceView: View {
    @Environment(\.modelContext) private var modelContext

    let server: Server
    let sessionManager: SSHSessionManager
    let onConnectionStateChanged: @MainActor (UUID, Bool) -> Void

    @StateObject private var viewModel: ServerWorkspaceViewModel
    @State private var selectedTab = WorkspaceTab.terminal
    @State private var showingCommandEditorSheet = false
    @State private var editingCommand: SavedCommand?
    @State private var commandEditorTitle = ""
    @State private var commandEditorBody = ""
    @State private var commandPendingDeletion: SavedCommand?
    @State private var showingSettingsSheet = false
    @State private var settingsAuthenticationMode = "agent"
    @State private var settingsPrivateKeyPath = ""
    @State private var settingsPublicKeyPath = ""
    @State private var settingsTerminalTextColor = "white"
    @State private var editingTerminalSessionID: UUID?
    @State private var editingTerminalTitle = ""
    @FocusState private var isTerminalTitleEditorFocused: Bool

    init(
        server: Server,
        sessionManager: SSHSessionManager,
        onConnectionStateChanged: @escaping @MainActor (UUID, Bool) -> Void
    ) {
        self.server = server
        self.sessionManager = sessionManager
        self.onConnectionStateChanged = onConnectionStateChanged
        _viewModel = StateObject(
            wrappedValue: ServerWorkspaceViewModel(
                sessionManager: sessionManager,
                onConnectionStateChanged: onConnectionStateChanged
            )
        )
    }

    var body: some View {
        VStack(spacing: 0) {
            header

            TabView(selection: $selectedTab) {
                terminalTabContent
                .tabItem { Label("Terminal", systemImage: "terminal") }
                .tag(WorkspaceTab.terminal)

                Group {
                    if viewModel.isConnected {
                        SFTPBrowserView(
                            currentPath: viewModel.currentDirectory,
                            files: viewModel.files,
                            availableUsers: viewModel.availableFileManagerUsers,
                            selectedUser: viewModel.selectedFileManagerUser,
                            onSelectUser: { user in
                                Task {
                                    do {
                                        try await viewModel.selectFileManagerUser(user, serverID: server.id)
                                    } catch {
                                        viewModel.errorMessage = error.localizedDescription
                                    }
                                }
                            },
                            onNavigate: { path in
                                Task {
                                    do {
                                        try await viewModel.loadDirectory(path: path, serverID: server.id)
                                    } catch {
                                        viewModel.errorMessage = error.localizedDescription
                                    }
                                }
                            },
                            onRename: { item, newName in
                                Task {
                                    do {
                                        try await viewModel.renameItem(item, to: newName, serverID: server.id)
                                    } catch {
                                        viewModel.errorMessage = error.localizedDescription
                                    }
                                }
                            },
                            onDelete: { item in
                                Task {
                                    do {
                                        try await viewModel.deleteItem(item, serverID: server.id)
                                    } catch {
                                        viewModel.errorMessage = error.localizedDescription
                                    }
                                }
                            },
                            onDownload: { item, destinationURL in
                                Task {
                                    do {
                                        try await viewModel.downloadItem(item, to: destinationURL, serverID: server.id)
                                    } catch {
                                        viewModel.errorMessage = error.localizedDescription
                                    }
                                }
                            },
                            onUpload: { urls in
                                Task {
                                    do {
                                        try await viewModel.uploadItems(urls, to: viewModel.currentDirectory, serverID: server.id)
                                    } catch {
                                        viewModel.errorMessage = error.localizedDescription
                                    }
                                }
                            },
                            onCreateFolder: { name in
                                Task {
                                    do {
                                        try await viewModel.createFolder(named: name, in: viewModel.currentDirectory, serverID: server.id)
                                    } catch {
                                        viewModel.errorMessage = error.localizedDescription
                                    }
                                }
                            },
                            onCreateFile: { name in
                                Task {
                                    do {
                                        try await viewModel.createFile(named: name, in: viewModel.currentDirectory, serverID: server.id)
                                    } catch {
                                        viewModel.errorMessage = error.localizedDescription
                                    }
                                }
                            },
                            onOpenTextFile: { item in
                                try await viewModel.readTextFile(item, serverID: server.id)
                            },
                            onSaveTextFile: { item, content in
                                try await viewModel.writeTextFile(item, content: content, serverID: server.id)
                            }
                        )
                    } else {
                        ContentUnavailableView(
                            "SFTP Is Not Connected",
                            systemImage: "folder",
                            description: Text("Click Connect to browse remote files.")
                        )
                    }
                }
                .tabItem { Label("Files", systemImage: "folder") }
                .tag(WorkspaceTab.files)

                MonitoringView(
                    snapshot: viewModel.monitoring,
                    history: viewModel.monitoringHistory,
                    selectedInterval: viewModel.monitoringRefreshInterval,
                    lastRefreshAt: viewModel.lastMonitoringRefreshAt,
                    isConnected: viewModel.isConnected,
                    onIntervalChange: { interval in
                        viewModel.updateMonitoringRefreshInterval(interval, serverID: server.id)
                    },
                    onRefreshNow: {
                        Task {
                            do {
                                try await viewModel.refreshMonitoring(serverID: server.id)
                            } catch {
                                viewModel.errorMessage = error.localizedDescription
                            }
                        }
                    }
                )
                .tabItem { Label("Monitoring", systemImage: "gauge") }
                .tag(WorkspaceTab.monitoring)

                savedCommandsTab
                    .tabItem { Label("Commands", systemImage: "command") }
                    .tag(WorkspaceTab.commands)
            }
        }
        .overlay {
            if viewModel.isDownloadInProgress || viewModel.isUploadInProgress {
                ZStack {
                    Color.black.opacity(0.18)
                        .ignoresSafeArea()

                    VStack(spacing: 12) {
                        Text(viewModel.isUploadInProgress ? "Uploading..." : "Downloading...")
                            .font(.headline)
                        ProgressView(
                            value: viewModel.isUploadInProgress ? viewModel.uploadProgress : viewModel.downloadProgress,
                            total: 1
                        )
                            .progressViewStyle(.linear)
                            .frame(width: 280)

                        Text(
                            "\(Int((viewModel.isUploadInProgress ? viewModel.uploadProgress : viewModel.downloadProgress) * 100))%"
                        )
                            .font(.system(.body, design: .monospaced).weight(.semibold))
                            .foregroundStyle(.secondary)

                        if viewModel.isUploadInProgress, !viewModel.uploadCurrentItemName.isEmpty {
                            Text(viewModel.uploadCurrentItemName)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                        }
                    }
                    .padding(20)
                    .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                            .stroke(Color.primary.opacity(0.1), lineWidth: 1)
                    )
                }
            }
        }
        .alert("Error", isPresented: errorBinding) {
            Button("OK") {
                viewModel.errorMessage = nil
            }
        } message: {
            Text(viewModel.errorMessage ?? "Unknown error")
        }
        .alert("Delete Command", isPresented: commandDeleteAlertBinding) {
            Button("Cancel", role: .cancel) {
                commandPendingDeletion = nil
            }
            Button("Delete", role: .destructive) {
                deletePendingCommand()
            }
        } message: {
            Text("This command will be deleted permanently.")
        }
        .sheet(isPresented: $showingCommandEditorSheet) {
            NavigationStack {
                Form {
                    TextField("Title", text: $commandEditorTitle)

                    VStack(alignment: .leading, spacing: 6) {
                        Text("Command")
                            .font(.caption)
                            .foregroundStyle(.secondary)

                        TextEditor(text: $commandEditorBody)
                            .font(.system(.body, design: .monospaced))
                            .frame(minHeight: 180)
                    }
                }
                .padding()
                .navigationTitle(editingCommand == nil ? "New Command" : "Edit Command")
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Cancel") {
                            closeCommandEditor()
                        }
                    }
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Save") {
                            saveCommandFromEditor()
                        }
                    }
                }
            }
            .frame(minWidth: 560, minHeight: 360)
        }
        .sheet(isPresented: $showingSettingsSheet) {
            NavigationStack {
                Form {
                    Picker("Terminal Text Color", selection: $settingsTerminalTextColor) {
                        ForEach(TerminalColorPalette.names, id: \.self) { name in
                            Text(TerminalColorPalette.title(named: name)).tag(name)
                        }
                    }

                    Picker("Authentication", selection: $settingsAuthenticationMode) {
                        Text("SSH Agent (Default)").tag("agent")
                        Text("Private Key File").tag("privateKey")
                    }

                    if settingsAuthenticationMode == "privateKey" {
                        HStack {
                            TextField("Private Key Path", text: $settingsPrivateKeyPath)
                            Button("Choose") {
                                if let path = pickAndImportKeyFile() {
                                    settingsPrivateKeyPath = path
                                }
                            }
                        }

                        HStack {
                            TextField("Public Key Path (Optional)", text: $settingsPublicKeyPath)
                            Button("Choose") {
                                if let path = pickAndImportKeyFile() {
                                    settingsPublicKeyPath = path
                                }
                            }
                        }
                    }
                }
                .padding()
                .navigationTitle("Server Settings")
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Cancel") {
                            showingSettingsSheet = false
                        }
                    }
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Save") {
                            saveSettings()
                        }
                    }
                }
            }
            .frame(minWidth: 560, minHeight: 280)
        }
        .onAppear {
            viewModel.setMonitoringActive(selectedTab == .monitoring, serverID: server.id)
        }
        .onChange(of: selectedTab) { _, newTab in
            viewModel.setMonitoringActive(newTab == .monitoring, serverID: server.id)
        }
        .onDisappear {
            viewModel.setMonitoringActive(false, serverID: server.id)
        }
    }

    private var header: some View {
        HStack {
            VStack(alignment: .leading) {
                Text(server.title)
                    .font(.title3.weight(.semibold))
                Text("\(server.username)@\(server.host):\(server.port)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Circle()
                .fill(viewModel.isConnected ? Color.green : Color.gray)
                .frame(width: 10, height: 10)
            Text(viewModel.isConnected ? "Connected" : "Disconnected")
                .font(.caption)
                .foregroundStyle(.secondary)
            Button(viewModel.isConnected ? "Disconnect" : "Connect") {
                if viewModel.isConnected {
                    viewModel.disconnect(serverID: server.id)
                } else {
                    viewModel.connect(to: server)
                }
            }
            .buttonStyle(.borderedProminent)
            Button("Settings") {
                settingsTerminalTextColor = server.terminalTextColor
                settingsAuthenticationMode = server.authenticationMode
                settingsPrivateKeyPath = server.privateKeyPath ?? ""
                settingsPublicKeyPath = server.publicKeyPath ?? ""
                showingSettingsSheet = true
            }
        }
        .padding(12)
    }

    private var terminalTabContent: some View {
        VStack(spacing: 0) {
            terminalTabsBar

            if let activeSession = viewModel.selectedTerminalSession {
                TerminalPanel(
                    output: Binding(
                        get: { viewModel.terminalOutput(for: activeSession.id) },
                        set: { viewModel.updateTerminalOutput($0, for: activeSession.id) }
                    ),
                    isConnected: activeSession.isConnected,
                    textColorName: server.terminalTextColor,
                    onInput: { text in
                        viewModel.sendTerminalInput(text, sessionID: activeSession.id)
                    },
                    onResize: { columns, rows in
                        viewModel.resizeTerminal(columns: columns, rows: rows, sessionID: activeSession.id)
                    }
                )
                .id(activeSession.id)
                .onAppear {
                    viewModel.ensureTerminalSessionConnected(activeSession.id, server: server)
                }
            } else {
                ContentUnavailableView(
                    "No Terminal Tab",
                    systemImage: "terminal",
                    description: Text("Create a new terminal tab to start an interactive shell.")
                )
            }
        }
        .onChange(of: viewModel.selectedTerminalSessionID) { _, newSessionID in
            editingTerminalSessionID = nil
            viewModel.ensureTerminalSessionConnected(newSessionID, server: server)
        }
    }

    private var terminalTabsBar: some View {
        HStack(spacing: 10) {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(viewModel.terminalSessions) { session in
                        terminalTabChip(session)
                    }
                }
                .padding(.vertical, 2)
            }

            Button {
                viewModel.addTerminalTab(for: server)
            } label: {
                Label("New Tab", systemImage: "plus")
            }
            .buttonStyle(.bordered)
        }
        .padding(.horizontal, 12)
        .padding(.top, 12)
    }

    private func terminalTabChip(_ session: TerminalSessionState) -> some View {
        HStack(spacing: 8) {
            Circle()
                .fill(session.isConnected ? Color.green : Color.secondary.opacity(0.5))
                .frame(width: 7, height: 7)

            if editingTerminalSessionID == session.id {
                TextField("Tab Name", text: $editingTerminalTitle)
                    .textFieldStyle(.plain)
                    .font(.subheadline.weight(.medium))
                    .frame(minWidth: 72)
                    .focused($isTerminalTitleEditorFocused)
                    .onSubmit {
                        commitTerminalRename(session.id)
                    }
            } else {
                Text(session.title)
                    .font(.subheadline.weight(.medium))
            }

            if viewModel.terminalSessions.count > 1 {
                Button {
                    viewModel.closeTerminalTab(session.id)
                } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 7)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(viewModel.selectedTerminalSessionID == session.id ? Color.accentColor.opacity(0.14) : Color.secondary.opacity(0.08))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .stroke(viewModel.selectedTerminalSessionID == session.id ? Color.accentColor.opacity(0.28) : Color.primary.opacity(0.06), lineWidth: 1)
        )
        .contentShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        .onTapGesture {
            viewModel.selectedTerminalSessionID = session.id
        }
        .onTapGesture(count: 2) {
            startTerminalRename(session)
        }
    }

    private func startTerminalRename(_ session: TerminalSessionState) {
        editingTerminalSessionID = session.id
        editingTerminalTitle = session.title
        viewModel.selectedTerminalSessionID = session.id
        isTerminalTitleEditorFocused = true
    }

    private func commitTerminalRename(_ sessionID: UUID) {
        viewModel.renameTerminalTab(sessionID, to: editingTerminalTitle)
        editingTerminalSessionID = nil
        isTerminalTitleEditorFocused = false
    }

    private var savedCommandsTab: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("Saved Commands")
                    .font(.title3.weight(.semibold))
                Spacer()
                Button {
                    openCreateCommandEditor()
                } label: {
                    Label("Add Command", systemImage: "plus")
                }
                .buttonStyle(.borderedProminent)
            }

            if server.savedCommands.isEmpty {
                VStack {
                    Spacer(minLength: 0)
                    ContentUnavailableView(
                        "No Commands Yet",
                        systemImage: "command",
                        description: Text("Add a command with title and content, then run it from this list.")
                    )
                    .frame(maxWidth: .infinity)
                    Spacer(minLength: 0)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                List(server.savedCommands.sorted(by: commandSort)) { command in
                    VStack(alignment: .leading, spacing: 8) {
                        Text(command.title)
                            .font(.headline)

                        Text(command.command)
                            .font(.system(.body, design: .monospaced))
                            .lineLimit(2)
                            .foregroundStyle(.secondary)

                        HStack(spacing: 8) {
                            Button("Run") {
                                selectedTab = .terminal
                                Task {
                                    do {
                                        try await viewModel.stageSavedCommand(command)
                                    } catch {
                                        viewModel.errorMessage = error.localizedDescription
                                    }
                                }
                            }
                            .buttonStyle(.borderedProminent)

                            Button("Edit") {
                                openEditCommandEditor(command)
                            }
                            .buttonStyle(.bordered)

                            Button("Delete", role: .destructive) {
                                commandPendingDeletion = command
                            }
                            .buttonStyle(.bordered)
                        }
                    }
                    .padding(.vertical, 4)
                }
            }
        }
        .padding(12)
    }

    private var errorBinding: Binding<Bool> {
        Binding(
            get: { viewModel.errorMessage != nil },
            set: { value in
                if !value {
                    viewModel.errorMessage = nil
                }
            }
        )
    }

    private var commandDeleteAlertBinding: Binding<Bool> {
        Binding(
            get: { commandPendingDeletion != nil },
            set: { value in
                if !value {
                    commandPendingDeletion = nil
                }
            }
        )
    }

    private func commandSort(_ lhs: SavedCommand, _ rhs: SavedCommand) -> Bool {
        lhs.title.localizedCaseInsensitiveCompare(rhs.title) == .orderedAscending
    }

    private func openCreateCommandEditor() {
        editingCommand = nil
        commandEditorTitle = ""
        commandEditorBody = ""
        showingCommandEditorSheet = true
    }

    private func openEditCommandEditor(_ command: SavedCommand) {
        editingCommand = command
        commandEditorTitle = command.title
        commandEditorBody = command.command
        showingCommandEditorSheet = true
    }

    private func closeCommandEditor() {
        showingCommandEditorSheet = false
        editingCommand = nil
        commandEditorTitle = ""
        commandEditorBody = ""
    }

    private func saveCommandFromEditor() {
        let titleText = commandEditorTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        let commandText = commandEditorBody.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !titleText.isEmpty else {
            viewModel.errorMessage = "Title cannot be empty."
            return
        }
        guard !commandText.isEmpty else {
            viewModel.errorMessage = "Command cannot be empty."
            return
        }

        if let editingCommand {
            editingCommand.title = titleText
            editingCommand.command = commandText
        } else {
            let command = SavedCommand(title: titleText, command: commandText, server: server)
            modelContext.insert(command)
            server.savedCommands.append(command)
        }

        server.markUpdated()

        do {
            try modelContext.save()
            closeCommandEditor()
        } catch {
            viewModel.errorMessage = error.localizedDescription
        }
    }

    private func deletePendingCommand() {
        guard let command = commandPendingDeletion else {
            return
        }

        server.savedCommands.removeAll { $0.id == command.id }
        modelContext.delete(command)
        server.markUpdated()

        do {
            try modelContext.save()
            commandPendingDeletion = nil
        } catch {
            viewModel.errorMessage = error.localizedDescription
        }
    }

    private func saveSettings() {
        server.terminalTextColor = settingsTerminalTextColor
        server.authenticationMode = settingsAuthenticationMode
        server.privateKeyPath = settingsPrivateKeyPath.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            ? nil
            : settingsPrivateKeyPath
        server.publicKeyPath = settingsPublicKeyPath.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            ? nil
            : settingsPublicKeyPath
        server.markUpdated()

        do {
            try modelContext.save()
            showingSettingsSheet = false
            if viewModel.isConnected {
                viewModel.disconnect(serverID: server.id)
            }
        } catch {
            viewModel.errorMessage = error.localizedDescription
        }
    }

    private func pickAndImportKeyFile() -> String? {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = false
        panel.canChooseFiles = true
        panel.allowsMultipleSelection = false
        panel.canCreateDirectories = false

        let response = panel.runModal()
        guard response == .OK else {
            return nil
        }
        guard let selectedURL = panel.url else {
            return nil
        }

        do {
            let importedPath = try SSHIdentityStorageService.importKey(from: selectedURL)
            return importedPath
        } catch {
            viewModel.errorMessage = error.localizedDescription
            AppTrace.log("UI", "Key import failed in Server Settings: \(error.localizedDescription)")
            return nil
        }
    }
}

enum WorkspaceTab: String, Hashable {
    case terminal
    case files
    case monitoring
    case commands
}
