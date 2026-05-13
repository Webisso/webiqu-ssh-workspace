import AppKit
import SwiftData
import SwiftUI

struct ContentView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: [SortDescriptor(\ServerGroup.name)]) private var groups: [ServerGroup]

    let sessionManager: SSHSessionManager

    @StateObject private var viewModel = SidebarViewModel()
    @State private var showingAddGroupSheet = false
    @State private var showingAddServerSheet = false
    @State private var addErrorMessage: String?

    @State private var groupName = ""

    @State private var selectedGroupIDForServer: UUID?
    @State private var serverTitle = ""
    @State private var serverColor = "blue"
    @State private var serverHost = ""
    @State private var serverPort = "22"
    @State private var serverUsername = ""
    @State private var serverAuthenticationMode = "agent"
    @State private var serverPrivateKeyPath = ""
    @State private var serverPublicKeyPath = ""
    @State private var serverPendingDeletion: Server?

    private let serverColorOptions: [String] = [
        "blue",
        "green",
        "orange",
        "red",
        "purple",
        "teal",
        "pink",
        "gray"
    ]
    @Binding var showingAppSettings: Bool

    var body: some View {
        NavigationSplitView {
            List(selection: $viewModel.selectedServerID) {
                ForEach(groups) { group in
                    Section(group.name) {
                        ForEach(group.servers) { server in
                            HStack(spacing: 8) {
                                Label(server.title, systemImage: "server.rack")
                                Spacer()
                                Circle()
                                    .fill(viewModel.isConnected(server.id) ? Color.green : Color.clear)
                                    .overlay {
                                        if !viewModel.isConnected(server.id) {
                                            Circle().stroke(Color.secondary.opacity(0.25), lineWidth: 1)
                                        }
                                    }
                                    .frame(width: 8, height: 8)
                            }
                            .contentShape(Rectangle())
                            .contextMenu {
                                Button(role: .destructive) {
                                    AppTrace.log("UI", "Delete requested for server id=\(server.id.uuidString) title=\(server.title)")
                                    serverPendingDeletion = server
                                } label: {
                                    Label("Delete Server", systemImage: "trash")
                                }
                            }
                                .tag(server.id)
                        }
                    }
                }
            }
            .navigationTitle("Servers")
            .toolbar {
                ToolbarItemGroup {
                    Button {
                        showingAddGroupSheet = true
                    } label: {
                        Label("Add Group", systemImage: "folder.badge.plus")
                    }

                    Button {
                        selectedGroupIDForServer = groups.first?.id
                        showingAddServerSheet = true
                    } label: {
                        Label("Add Server", systemImage: "plus")
                    }
                    .disabled(groups.isEmpty)
                }
            }
        } detail: {
            if let server = selectedServer {
                ServerWorkspaceView(
                    server: server,
                    sessionManager: sessionManager,
                    onConnectionStateChanged: { serverID, isConnected in
                        AppTrace.log("UI", "Connection state callback server=\(serverID.uuidString) connected=\(isConnected)")
                        if isConnected {
                            viewModel.markConnected(serverID: serverID)
                        } else {
                            viewModel.markDisconnected(serverID: serverID)
                        }
                    }
                )
            } else {
                ZStack {
                    LinearGradient(
                        colors: [Color.blue.opacity(0.06), Color.teal.opacity(0.03)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                    .ignoresSafeArea()

                    VStack(spacing: 20) {
                        Image(systemName: "server.rack")
                            .font(.system(size: 40, weight: .semibold))
                            .foregroundStyle(Color.accentColor)
                            .padding(14)
                            .background(Color.accentColor.opacity(0.12), in: Circle())

                        VStack(spacing: 8) {
                            Text("No Server Selected")
                                .font(.title2.weight(.semibold))
                            Text("Create a server group, add a host, then connect to start using terminal, files, and monitoring.")
                                .font(.body)
                                .foregroundStyle(.secondary)
                                .multilineTextAlignment(.center)
                                .frame(maxWidth: 500)
                        }

                        HStack(spacing: 10) {
                            Button {
                                showingAddGroupSheet = true
                            } label: {
                                Label("Add Group", systemImage: "folder.badge.plus")
                            }

                            Button {
                                selectedGroupIDForServer = groups.first?.id
                                showingAddServerSheet = true
                            } label: {
                                Label("Add Server", systemImage: "plus")
                            }
                            .disabled(groups.isEmpty)
                        }
                        .buttonStyle(.borderedProminent)

                        if groups.isEmpty {
                            Text("Create at least one group before adding a server.")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                    .padding(28)
                    .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: 20, style: .continuous)
                            .stroke(Color.primary.opacity(0.08), lineWidth: 1)
                    )
                    .padding(32)
                }
            }
        }
        .onAppear {
            AppTrace.log("UI", "ContentView onAppear groups=\(groups.count) selected=\(viewModel.selectedServerID?.uuidString ?? "nil")")
            viewModel.removeLegacyDemoDataIfPresent(context: modelContext)
            if viewModel.selectedServerID == nil {
                viewModel.selectedServerID = groups.flatMap(\.servers).first?.id
                AppTrace.log("UI", "Auto-selected first server: \(viewModel.selectedServerID?.uuidString ?? "nil")")
            }
        }
        .sheet(isPresented: $showingAddGroupSheet) {
            NavigationStack {
                Form {
                    TextField("Group Name", text: $groupName)
                }
                .padding()
                .navigationTitle("New Group")
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Cancel") {
                            groupName = ""
                            showingAddGroupSheet = false
                        }
                    }
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Create") {
                            createGroup()
                        }
                    }
                }
            }
            .frame(minWidth: 420, minHeight: 180)
        }
        .sheet(isPresented: $showingAddServerSheet) {
            NavigationStack {
                Form {
                    Picker("Group", selection: $selectedGroupIDForServer) {
                        ForEach(groups) { group in
                            Text(group.name).tag(Optional(group.id))
                        }
                    }

                    TextField("Title", text: $serverTitle)
                    TextField("Host", text: $serverHost)
                    TextField("Port", text: $serverPort)
                    TextField("Username", text: $serverUsername)
                    Picker("Color", selection: $serverColor) {
                        ForEach(serverColorOptions, id: \.self) { colorName in
                            HStack(spacing: 8) {
                                Circle()
                                    .fill(swatchColor(for: colorName))
                                    .frame(width: 10, height: 10)
                                Text(colorTitle(for: colorName))
                            }
                            .tag(colorName)
                        }
                    }

                    Picker("Authentication", selection: $serverAuthenticationMode) {
                        Text("SSH Agent (Default)").tag("agent")
                        Text("Private Key File").tag("privateKey")
                    }

                    if serverAuthenticationMode == "privateKey" {
                        HStack {
                            TextField("Private Key Path", text: $serverPrivateKeyPath)
                            Button("Choose") {
                                if let path = pickAndImportKeyFile() {
                                    serverPrivateKeyPath = path
                                }
                            }
                        }

                        HStack {
                            TextField("Public Key Path (Optional)", text: $serverPublicKeyPath)
                            Button("Choose") {
                                if let path = pickAndImportKeyFile() {
                                    serverPublicKeyPath = path
                                }
                            }
                        }
                    }
                }
                .padding()
                .navigationTitle("New Server")
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Cancel") {
                            resetAddServerForm()
                            showingAddServerSheet = false
                        }
                    }
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Create") {
                            createServer()
                        }
                    }
                }
            }
            .frame(minWidth: 520, minHeight: 320)
        }
        .alert("Operation Failed", isPresented: errorBinding) {
            Button("OK", role: .cancel) {
                addErrorMessage = nil
            }
        } message: {
            Text(addErrorMessage ?? "Unknown error")
        }
        .alert("Delete Server?", isPresented: deleteAlertBinding) {
            Button("Cancel", role: .cancel) {
                serverPendingDeletion = nil
            }
            Button("Delete", role: .destructive) {
                deleteSelectedServer()
            }
        } message: {
            Text("This will permanently remove the server and saved commands.")
        }
        .sheet(isPresented: $showingAppSettings) {
            AppSettingsView()
        }
    }

    private var selectedServer: Server? {
        guard let selectedID = viewModel.selectedServerID else {
            return groups.flatMap(\.servers).first
        }
        return groups.flatMap(\.servers).first(where: { $0.id == selectedID })
    }

    private var errorBinding: Binding<Bool> {
        Binding(
            get: { addErrorMessage != nil },
            set: { newValue in
                if !newValue {
                    addErrorMessage = nil
                }
            }
        )
    }

    private var deleteAlertBinding: Binding<Bool> {
        Binding(
            get: { serverPendingDeletion != nil },
            set: { newValue in
                if !newValue {
                    serverPendingDeletion = nil
                }
            }
        )
    }

    private func createGroup() {
        AppTrace.log("UI", "Create group tapped name=\(groupName)")
        do {
            let created = try viewModel.addGroup(name: groupName, context: modelContext)
            groupName = ""
            selectedGroupIDForServer = created.id
            showingAddGroupSheet = false
            AppTrace.log("UI", "Group created id=\(created.id.uuidString) name=\(created.name)")
        } catch {
            addErrorMessage = error.localizedDescription
            AppTrace.log("UI", "Group create failed: \(error.localizedDescription)")
        }
    }

    private func createServer() {
        AppTrace.log("UI", "Create server tapped title=\(serverTitle) host=\(serverHost) port=\(serverPort) user=\(serverUsername)")
        guard
            let selectedGroupIDForServer,
            let selectedGroup = groups.first(where: { $0.id == selectedGroupIDForServer })
        else {
            addErrorMessage = "Please choose a valid group."
            AppTrace.log("UI", "Create server failed: invalid selected group")
            return
        }

        guard let port = Int(serverPort) else {
            addErrorMessage = "Port must be a number."
            AppTrace.log("UI", "Create server failed: port parse error value=\(serverPort)")
            return
        }

        do {
            _ = try viewModel.addServer(
                to: selectedGroup,
                title: serverTitle,
                color: serverColor,
                host: serverHost,
                port: port,
                username: serverUsername,
                authenticationMode: serverAuthenticationMode,
                privateKeyPath: serverPrivateKeyPath.isEmpty ? nil : serverPrivateKeyPath,
                publicKeyPath: serverPublicKeyPath.isEmpty ? nil : serverPublicKeyPath,
                context: modelContext
            )
            resetAddServerForm()
            showingAddServerSheet = false
            AppTrace.log("UI", "Server created in group=\(selectedGroup.name)")
        } catch {
            addErrorMessage = error.localizedDescription
            AppTrace.log("UI", "Create server failed: \(error.localizedDescription)")
        }
    }

    private func resetAddServerForm() {
        selectedGroupIDForServer = groups.first?.id
        serverTitle = ""
        serverColor = "blue"
        serverHost = ""
        serverPort = "22"
        serverUsername = ""
        serverAuthenticationMode = "agent"
        serverPrivateKeyPath = ""
        serverPublicKeyPath = ""
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
            addErrorMessage = error.localizedDescription
            AppTrace.log("UI", "Key import failed in Add Server: \(error.localizedDescription)")
            return nil
        }
    }

    private func colorTitle(for name: String) -> String {
        switch name {
        case "blue": return "Blue"
        case "green": return "Green"
        case "orange": return "Orange"
        case "red": return "Red"
        case "purple": return "Purple"
        case "teal": return "Teal"
        case "pink": return "Pink"
        case "gray": return "Gray"
        default: return "Blue"
        }
    }

    private func swatchColor(for name: String) -> Color {
        switch name {
        case "green": return .green
        case "orange": return .orange
        case "red": return .red
        case "purple": return .purple
        case "teal": return .teal
        case "pink": return .pink
        case "gray": return .gray
        default: return .blue
        }
    }

    private func deleteSelectedServer() {
        guard let server = serverPendingDeletion else {
            return
        }

        AppTrace.log("UI", "Deleting server id=\(server.id.uuidString) title=\(server.title)")
        Task {
            await sessionManager.disconnect(serverID: server.id)
            await MainActor.run {
                do {
                    try viewModel.removeServer(server, context: modelContext)
                    if viewModel.selectedServerID == nil {
                        viewModel.selectedServerID = groups.flatMap(\.servers).first(where: { $0.id != server.id })?.id
                    }
                    AppTrace.log("UI", "Server deleted id=\(server.id.uuidString)")
                } catch {
                    addErrorMessage = error.localizedDescription
                    AppTrace.log("UI", "Delete server failed: \(error.localizedDescription)")
                }
                serverPendingDeletion = nil
            }
        }
    }
}
