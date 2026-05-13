import AppKit
import SwiftUI

struct SFTPBrowserView: View {
    let currentPath: String
    let files: [SFTPFileItem]
    let availableUsers: [String]
    let selectedUser: String
    let onSelectUser: (String) -> Void
    let onNavigate: (String) -> Void
    let onRename: (SFTPFileItem, String) -> Void
    let onDelete: (SFTPFileItem) -> Void
    let onDownload: (SFTPFileItem, URL) -> Void
    let onUpload: ([URL]) -> Void
    let onCreateFolder: (String) -> Void
    let onCreateFile: (String) -> Void
    let onOpenTextFile: (SFTPFileItem) async throws -> String
    let onSaveTextFile: (SFTPFileItem, String) async throws -> Void

    @State private var searchText = ""
    @State private var selectedFileID: String?
    @State private var openingFolderPath: String?
    @State private var renameTarget: SFTPFileItem?
    @State private var renameText = ""
    @State private var deleteTarget: SFTPFileItem?
    @State private var createFolderName = ""
    @State private var createFileName = ""
    @State private var showingCreateFolderAlert = false
    @State private var showingCreateFileAlert = false
    @State private var editorTarget: SFTPFileItem?
    @State private var editorText = ""
    @State private var isEditorBusy = false
    @State private var editorErrorMessage: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            header
            statsRow

            VStack(spacing: 0) {
                Table(filteredFiles, selection: $selectedFileID) {
                        TableColumn("Name") { item in
                            HStack(spacing: 8) {
                                Image(systemName: iconName(for: item))
                                    .foregroundStyle(item.isDirectory ? Color.accentColor : Color.secondary)
                                if item.isDirectory, openingFolderPath == item.path {
                                    ProgressView()
                                        .controlSize(.small)
                                }
                                Text(item.name)
                                    .lineLimit(1)
                            }
                        }
                        .width(min: 240, ideal: 320)

                        TableColumn("Type") { item in
                            Text(typeLabel(for: item))
                                .foregroundStyle(.secondary)
                        }
                        .width(min: 120, ideal: 160)

                        TableColumn("Size") { item in
                            Text(formattedSize(for: item))
                                .font(.system(.body, design: .monospaced))
                        }
                        .width(min: 100, ideal: 120)

                        TableColumn("Modified") { item in
                            Text(formattedModifiedDate(item.modifiedAt))
                                .foregroundStyle(.secondary)
                        }
                        .width(min: 150, ideal: 190)
                    }
                    .contextMenu(forSelectionType: String.self) { selection in
                        if let item = selectedItem(from: selection) {
                            if item.isDirectory {
                                Button("Open") {
                                    openFolder(item)
                                }
                            }

                            Button("Rename") {
                                renameTarget = item
                                renameText = item.name
                            }

                            Button("Delete", role: .destructive) {
                                deleteTarget = item
                            }

                            if !item.isDirectory {
                                Button("Open & Edit") {
                                    openTextEditor(for: item)
                                }

                                Button("Download") {
                                    saveAndDownload(item)
                                }
                            }
                        } else {
                            Button("Upload...") {
                                pickAndUpload()
                            }

                            Button("New Folder") {
                                createFolderName = ""
                                showingCreateFolderAlert = true
                            }

                            Button("New File") {
                                createFileName = ""
                                showingCreateFileAlert = true
                            }
                        }
                    } primaryAction: { selection in
                        if let item = selectedItem(from: selection), item.isDirectory {
                            openFolder(item)
                        }
                    }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12, style: .continuous))

            if let selectedFile = filteredFiles.first(where: { $0.id == selectedFileID }) {
                HStack(spacing: 8) {
                    Image(systemName: iconName(for: selectedFile))
                        .foregroundStyle(selectedFile.isDirectory ? Color.accentColor : Color.secondary)
                    Text("Selected: \(selectedFile.name)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Spacer()
                }
                .padding(.horizontal, 8)
                .padding(.top, 2)
            }
        }
        .padding(12)
        .onChange(of: currentPath) { _, _ in
            openingFolderPath = nil
        }
        .alert("Rename", isPresented: renameAlertBinding) {
            TextField("New Name", text: $renameText)
            Button("Cancel", role: .cancel) {
                renameTarget = nil
            }
            Button("Save") {
                if let target = renameTarget {
                    onRename(target, renameText)
                }
                renameTarget = nil
            }
        } message: {
            Text("Enter a new name.")
        }
        .alert("Delete Item", isPresented: deleteAlertBinding) {
            Button("Cancel", role: .cancel) {
                deleteTarget = nil
            }
            Button("Delete", role: .destructive) {
                if let target = deleteTarget {
                    onDelete(target)
                }
                deleteTarget = nil
            }
        } message: {
            Text("Are you sure you want to delete this item?")
        }
        .alert("New Folder", isPresented: $showingCreateFolderAlert) {
            TextField("Folder Name", text: $createFolderName)
            Button("Cancel", role: .cancel) {}
            Button("Create") {
                onCreateFolder(createFolderName)
            }
        } message: {
            Text("Create a new folder in the current path.")
        }
        .alert("New File", isPresented: $showingCreateFileAlert) {
            TextField("File Name", text: $createFileName)
            Button("Cancel", role: .cancel) {}
            Button("Create") {
                onCreateFile(createFileName)
            }
        } message: {
            Text("Create a new file in the current path.")
        }
        .sheet(item: $editorTarget) { item in
            NavigationStack {
                VStack(spacing: 10) {
                    if isEditorBusy {
                        ProgressView("Loading file...")
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                    } else {
                        TextEditor(text: $editorText)
                            .font(.system(.body, design: .monospaced))
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                    }
                }
                .padding(12)
                .navigationTitle(item.name)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Close") {
                            editorTarget = nil
                        }
                    }
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Save") {
                            Task {
                                do {
                                    isEditorBusy = true
                                    try await onSaveTextFile(item, editorText)
                                    isEditorBusy = false
                                } catch {
                                    isEditorBusy = false
                                    editorErrorMessage = error.localizedDescription
                                }
                            }
                        }
                        .disabled(isEditorBusy)
                    }
                }
            }
            .frame(minWidth: 760, minHeight: 520)
        }
        .alert("Editor Error", isPresented: editorErrorBinding) {
            Button("OK") {
                editorErrorMessage = nil
            }
        } message: {
            Text(editorErrorMessage ?? "Unknown error")
        }
    }

    private var header: some View {
        HStack(spacing: 12) {
            Label("Remote Files", systemImage: "externaldrive.connected.to.line.below")
                .font(.title3.weight(.semibold))

            Picker("User", selection: userBinding) {
                ForEach(availableUsers, id: \.self) { user in
                    Text(user).tag(user)
                }
            }
            .pickerStyle(.menu)
            .frame(maxWidth: 180)

            Spacer()

            TextField("Search files", text: $searchText)
                .textFieldStyle(.roundedBorder)
                .frame(maxWidth: 260)

            Button {
                onNavigate(parentPath(of: currentPath))
            } label: {
                Label("Up", systemImage: "arrow.up")
            }
            .disabled(currentPath == "/")

            Button {
                pickAndUpload()
            } label: {
                Label("Upload", systemImage: "square.and.arrow.up")
            }
        }
    }

    private var userBinding: Binding<String> {
        Binding(
            get: { selectedUser },
            set: { onSelectUser($0) }
        )
    }

    private var statsRow: some View {
        HStack(spacing: 10) {
            statCard(title: "Folders", value: "\(folderCount)", systemImage: "folder")
            statCard(title: "Files", value: "\(fileCount)", systemImage: "doc")
            statCard(title: "Total Size", value: totalSizeText, systemImage: "externaldrive")
            statCard(title: "Current Path", value: currentPath, systemImage: "point.topleft.down.curvedto.point.bottomright.up")
        }
    }

    private var treeRoots: [FileTreeNode] {
        let folders = filteredFiles.filter(\.isDirectory)
        return folders.map { folder in
            FileTreeNode(item: folder, children: nil)
        }
    }

    private var filteredFiles: [SFTPFileItem] {
        let base = files.sorted { lhs, rhs in
            if lhs.isDirectory != rhs.isDirectory {
                return lhs.isDirectory
            }
            return lhs.name.localizedCaseInsensitiveCompare(rhs.name) == .orderedAscending
        }

        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else {
            return base
        }

        return base.filter {
            $0.name.localizedCaseInsensitiveContains(query) ||
            $0.path.localizedCaseInsensitiveContains(query) ||
            typeLabel(for: $0).localizedCaseInsensitiveContains(query)
        }
    }

    private var folderCount: Int {
        filteredFiles.filter(\.isDirectory).count
    }

    private var fileCount: Int {
        filteredFiles.filter { !$0.isDirectory }.count
    }

    private var totalSizeText: String {
        let total = filteredFiles
            .filter { !$0.isDirectory }
            .reduce(Int64.zero) { $0 + $1.size }
        return ByteCountFormatter.string(fromByteCount: total, countStyle: .file)
    }

    @ViewBuilder
    private func row(_ node: FileTreeNode) -> some View {
        Button {
            onNavigate(node.item.path)
        } label: {
            Label(node.item.name, systemImage: "folder.fill")
        }
        .buttonStyle(.plain)
    }

    private func statCard(title: String, value: String, systemImage: String) -> some View {
        HStack(spacing: 10) {
            Image(systemName: systemImage)
                .font(.headline)
                .foregroundStyle(Color.accentColor)
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text(value)
                    .font(.system(.body, design: .rounded).weight(.semibold))
                    .lineLimit(1)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
    }

    private func iconName(for item: SFTPFileItem) -> String {
        if item.isDirectory {
            return "folder.fill"
        }

        let ext = (item.name as NSString).pathExtension.lowercased()
        switch ext {
        case "jpg", "jpeg", "png", "gif", "webp", "heic", "svg":
            return "photo"
        case "mp4", "mov", "mkv", "avi":
            return "film"
        case "mp3", "wav", "m4a", "aac":
            return "music.note"
        case "zip", "tar", "gz", "rar", "7z":
            return "archivebox"
        case "json", "xml", "yaml", "yml", "toml", "ini":
            return "curlybraces"
        case "swift", "js", "ts", "py", "go", "java", "kt", "rs", "c", "cpp", "h":
            return "chevron.left.forwardslash.chevron.right"
        case "pdf":
            return "doc.richtext"
        case "md", "txt", "rtf", "log":
            return "doc.plaintext"
        default:
            return "doc"
        }
    }

    private func typeLabel(for item: SFTPFileItem) -> String {
        if item.isDirectory {
            return "Folder"
        }

        let ext = (item.name as NSString).pathExtension
        if ext.isEmpty {
            return "File"
        }

        return "\(ext.uppercased()) File"
    }

    private func formattedSize(for item: SFTPFileItem) -> String {
        if item.isDirectory {
            return "--"
        }
        return ByteCountFormatter.string(fromByteCount: item.size, countStyle: .file)
    }

    private func formattedModifiedDate(_ date: Date?) -> String {
        guard let date else {
            return "Unknown"
        }
        return date.formatted(date: .abbreviated, time: .shortened)
    }

    private var renameAlertBinding: Binding<Bool> {
        Binding(
            get: { renameTarget != nil },
            set: { value in
                if !value {
                    renameTarget = nil
                }
            }
        )
    }

    private var deleteAlertBinding: Binding<Bool> {
        Binding(
            get: { deleteTarget != nil },
            set: { value in
                if !value {
                    deleteTarget = nil
                }
            }
        )
    }

    private func selectedItem(from selection: Set<String>) -> SFTPFileItem? {
        guard let fileID = selection.first else {
            return nil
        }
        return filteredFiles.first(where: { $0.id == fileID })
    }

    private func openFolder(_ item: SFTPFileItem) {
        guard item.isDirectory else {
            return
        }
        openingFolderPath = item.path
        onNavigate(item.path)
    }

    private func saveAndDownload(_ item: SFTPFileItem) {
        DispatchQueue.main.async {
            let panel = NSSavePanel()
            panel.canCreateDirectories = true
            panel.nameFieldStringValue = item.name

            let response = panel.runModal()
            guard response == .OK, let url = panel.url else {
                return
            }

            onDownload(item, url)
        }
    }

    private func pickAndUpload() {
        DispatchQueue.main.async {
            let panel = NSOpenPanel()
            panel.canChooseFiles = true
            panel.canChooseDirectories = true
            panel.allowsMultipleSelection = true
            panel.canCreateDirectories = false
            panel.prompt = "Upload"

            let response = panel.runModal()
            guard response == .OK else {
                return
            }

            let urls = panel.urls
            guard !urls.isEmpty else {
                return
            }

            onUpload(urls)
        }
    }

    private func openTextEditor(for item: SFTPFileItem) {
        editorTarget = item
        editorText = ""
        isEditorBusy = true

        Task {
            do {
                let content = try await onOpenTextFile(item)
                await MainActor.run {
                    self.editorText = content
                    self.isEditorBusy = false
                }
            } catch {
                await MainActor.run {
                    self.editorTarget = nil
                    self.isEditorBusy = false
                    self.editorErrorMessage = error.localizedDescription
                }
            }
        }
    }

    private var editorErrorBinding: Binding<Bool> {
        Binding(
            get: { editorErrorMessage != nil },
            set: { value in
                if !value {
                    editorErrorMessage = nil
                }
            }
        )
    }

    private func parentPath(of path: String) -> String {
        guard path != "/" else {
            return "/"
        }
        let components = path.split(separator: "/").dropLast()
        return components.isEmpty ? "/" : "/" + components.joined(separator: "/")
    }
}

struct FileTreeNode: Identifiable {
    let id = UUID()
    let item: SFTPFileItem
    let children: [FileTreeNode]?
}
