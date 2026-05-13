import Combine
import SwiftUI
import AppKit

struct AppSettings: Codable {
    var defaultPrivateKeyPath: String = ""
    var defaultPublicKeyPath: String = ""
    var defaultColor: String = "blue"
}

class AppSettingsStore: ObservableObject {
    static let shared = AppSettingsStore()
    @Published var settings: AppSettings {
        didSet { save() }
    }
    private let key = "AppSettingsStore.settings"
    private init() {
        if let data = UserDefaults.standard.data(forKey: key),
           let decoded = try? JSONDecoder().decode(AppSettings.self, from: data) {
            self.settings = decoded
        } else {
            self.settings = AppSettings()
        }
    }
    private func save() {
        if let data = try? JSONEncoder().encode(settings) {
            UserDefaults.standard.set(data, forKey: key)
        }
    }
}

struct AppSettingsView: View {
    @ObservedObject var store: AppSettingsStore = .shared
    @Environment(\.dismiss) private var dismiss
    let colorOptions = ["blue", "green", "orange", "red", "purple", "teal", "pink", "gray"]

    var body: some View {
        GeometryReader { proxy in
            let isCompact = proxy.size.width < 760

            VStack(spacing: 0) {
                header

                ScrollView {
                    Group {
                        if isCompact {
                            VStack(alignment: .leading, spacing: 18) {
                                sshKeysSection
                                defaultsSection
                            }
                        } else {
                            HStack(alignment: .top, spacing: 20) {
                                sshKeysSection
                                    .frame(maxWidth: .infinity)
                                defaultsSection
                                    .frame(width: min(max(proxy.size.width * 0.34, 260), 320))
                            }
                        }
                    }
                    .padding(20)
                }
            }
            .background(Color(nsColor: .windowBackgroundColor))
            .navigationTitle("Settings")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") {
                        dismiss()
                    }
                }
            }
        }
        .frame(minWidth: 560, idealWidth: 760, minHeight: 460, idealHeight: 560)
    }

    private var header: some View {
        HStack(alignment: .center, spacing: 14) {
            Image(systemName: "gearshape.2.fill")
                .font(.system(size: 28, weight: .semibold))
                .foregroundStyle(Color.accentColor)
                .frame(width: 46, height: 46)
                .background(.quaternary.opacity(0.8), in: RoundedRectangle(cornerRadius: 12, style: .continuous))

            VStack(alignment: .leading, spacing: 4) {
                Text("Workspace Defaults")
                    .font(.title2.weight(.semibold))

                Text("Set the SSH key paths and default server color used when creating new connections.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer()

            Label("Auto-saved", systemImage: "checkmark.circle.fill")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 16)
    }

    private var sshKeysSection: some View {
        GroupBox {
            VStack(alignment: .leading, spacing: 18) {
                settingsPathField(
                    title: "Private Key",
                    prompt: "~/.ssh/id_ed25519",
                    text: $store.settings.defaultPrivateKeyPath,
                    action: {
                        if let path = pickKeyFile() {
                            store.settings.defaultPrivateKeyPath = path
                        }
                    }
                )

                settingsPathField(
                    title: "Public Key",
                    prompt: "~/.ssh/id_ed25519.pub",
                    text: $store.settings.defaultPublicKeyPath,
                    action: {
                        if let path = pickKeyFile() {
                            store.settings.defaultPublicKeyPath = path
                        }
                    }
                )
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        } label: {
            sectionLabel(
                title: "SSH Keys",
                subtitle: "Defaults for new server connections.",
                systemImage: "key.horizontal.fill"
            )
        }
    }

    private var defaultsSection: some View {
        GroupBox {
            VStack(alignment: .leading, spacing: 16) {
                Picker("Default Color", selection: $store.settings.defaultColor) {
                    ForEach(colorOptions, id: \.self) { color in
                        Label {
                            Text(color.capitalized)
                        } icon: {
                            Circle()
                                .fill(swatchColor(for: color))
                        }
                        .tag(color)
                    }
                }
                .pickerStyle(.menu)

                Divider()

                HStack(spacing: 12) {
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .fill(swatchColor(for: store.settings.defaultColor))
                        .frame(width: 40, height: 40)
                        .overlay(
                            RoundedRectangle(cornerRadius: 10, style: .continuous)
                                .strokeBorder(Color.primary.opacity(0.08))
                        )

                    VStack(alignment: .leading, spacing: 3) {
                        Text("Preview")
                            .font(.headline)
                        Text("New servers will use \(store.settings.defaultColor.capitalized) as their default label color.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }

                    Spacer()
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        } label: {
            sectionLabel(
                title: "Appearance",
                subtitle: "System-friendly defaults.",
                systemImage: "paintpalette"
            )
        }
    }

    private func settingsPathField(
        title: String,
        prompt: String,
        text: Binding<String>,
        action: @escaping () -> Void
    ) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text(title)
                    .font(.headline)
                Spacer(minLength: 0)
                if !text.wrappedValue.isEmpty {
                    Label("Configured", systemImage: "checkmark.circle.fill")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            HStack(spacing: 10) {
                TextField(prompt, text: text, prompt: Text(prompt))
                    .textFieldStyle(.roundedBorder)
                    .font(.body.monospaced())

                Button("Choose", action: action)
                    .buttonStyle(.bordered)
            }
        }
    }

    private func sectionLabel(title: String, subtitle: String, systemImage: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Label(title, systemImage: systemImage)
                .font(.headline)
            Text(subtitle)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    private func pickKeyFile() -> String? {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = false
        panel.canChooseFiles = true
        panel.allowsMultipleSelection = false
        panel.canCreateDirectories = false
        let response = panel.runModal()
        guard response == .OK, let url = panel.url else { return nil }
        return url.path
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
}
