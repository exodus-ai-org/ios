import Models
import NetworkingKit
import SwiftUI

/// Settings: a hub of groups, each row pushing one page. The pages share one `SettingsStore`, and each page's view
/// model lives as long as the hub, so unsaved edits survive going back until Settings closes.
public struct SettingsView: View {
    @State private var viewModel: SettingsViewModel
    @State private var personality: PersonalityViewModel
    @State private var tools: ToolsSettingsViewModel
    @State private var memory: MemorySettingsViewModel
    @State private var skills: SkillsSettingsViewModel
    @State private var mcp: McpSettingsViewModel
    @State private var profile: ProfileViewModel
    @State private var backup: BackupSettingsViewModel
    @State private var colorTone: ColorToneViewModel
    @State private var store: SettingsStore
    @State private var secrets: SecretsStatusModel
    @Environment(ColorToneModel.self) private var toneModel: ColorToneModel?
    @State private var path: [SettingsPage]
    /// Bumped when pairing changes: `ServerConnection` is not observable.
    @State private var pairingRevision = 0
    @Environment(\.dismiss) private var dismiss
    private let connection: ServerConnection?

    public init(apiClient: APIClient, serverConfig: ServerConfigStore, opensMemory: Bool = false) {
        self.init(apiClient: apiClient, serverConfig: serverConfig, path: opensMemory ? [.memory] : [])
    }

    init(apiClient: APIClient, serverConfig: ServerConfigStore, path: [SettingsPage]) {
        let store = SettingsStore(apiClient: apiClient)
        _viewModel = State(
            initialValue: SettingsViewModel(apiClient: apiClient, serverConfig: serverConfig, store: store))
        _personality = State(initialValue: PersonalityViewModel(store: store))
        _tools = State(initialValue: ToolsSettingsViewModel(store: store))
        _memory = State(initialValue: MemorySettingsViewModel(store: store, apiClient: apiClient))
        _skills = State(initialValue: SkillsSettingsViewModel(apiClient: apiClient))
        _mcp = State(initialValue: McpSettingsViewModel(apiClient: apiClient))
        _profile = State(initialValue: ProfileViewModel(apiClient: apiClient))
        _backup = State(initialValue: BackupSettingsViewModel(apiClient: apiClient))
        _colorTone = State(initialValue: ColorToneViewModel(store: store))
        _store = State(initialValue: store)
        _secrets = State(initialValue: SecretsStatusModel(apiClient: apiClient))
        _path = State(initialValue: path)
        connection = serverConfig.connection
    }

    public var body: some View {
        NavigationStack(path: $path) {
            List {
                SecretsNoticeSections(status: secrets.status) { item in
                    SecretNoticeJump.open(item, path: &path, settings: viewModel)
                }
                ForEach(SettingsGroup.allCases) { group in
                    let rows = SettingsHubRow.rows(in: group)
                    if !rows.isEmpty {
                        Section {
                            ForEach(rows) { row in
                                NavigationLink(value: row.page) { label(for: row) }
                            }
                        } header: {
                            Text(group.title)
                        }
                    }
                }
                #if DEBUG
                SettingsDebugSection()
                #endif
            }
            .navigationTitle("common:nav.settings")
            .navigationDestination(for: SettingsPage.self) { page in
                destination(for: page)
                    .navigationTitle(Text(SettingsHubRow.row(for: page).title))
            }
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("common:action.close", role: .close) { dismiss() }
                }
            }
            .task {
                await viewModel.reloadIfUnchanged()
                await secrets.load()
            }
            // Back on the hub from a page that may have changed a key: the notice follows the computer.
            .onChange(of: path) { _, now in
                if now.isEmpty { Task { await secrets.load() } }
            }
        }
        // Icons in Settings are ink: the colour tone is the chat's, and a list of tinted symbols read as one of links.
        .listItemTint(.primary)
        .onChange(of: store.snapshot?.colorTone, initial: true) {
            if let snapshot = store.snapshot { colorTone.adopt(snapshot) }
        }
        .onChange(of: colorTone.selected) {
            if colorTone.hasLoaded { toneModel?.apply(colorTone.selected) }
        }
    }

    @ViewBuilder
    private func destination(for page: SettingsPage) -> some View {
        switch page {
        case .colorTone:
            ColorToneSettingsPage(viewModel: colorTone)
        case .connection:
            ConnectionSettingsPage(viewModel: viewModel, connection: connection, pairingRevision: $pairingRevision)
        case .providers:
            ProviderSettingsPage(viewModel: viewModel, secrets: secrets)
        case .tools:
            ToolsSettingsPage(viewModel: tools)
        case .personality:
            PersonalitySettingsPage(viewModel: personality)
        case .memory:
            MemorySettingsPage(viewModel: memory)
        case .skills:
            SkillsSettingsPage(viewModel: skills)
        case .mcp:
            McpSettingsPage(viewModel: mcp)
        case .profile:
            ProfileSettingsPage(viewModel: profile)
        case .backup:
            BackupSettingsPage(viewModel: backup)
        }
    }

    private func label(for row: SettingsHubRow) -> some View {
        LabeledContent {
            if row.page == .connection { connectionStatus }
            if row.page == .colorTone, colorTone.hasLoaded {
                HStack(spacing: 8) {
                    Text(colorTone.selected.title)
                    ColorToneSwatch(tone: colorTone.selected)
                }
            }
        } label: {
            Label {
                Text(row.title)
            } icon: {
                // Ink, not the accent: the colour tone is the chat's, and Settings reads as the system's own.
                Image(systemName: row.systemImage)
                    .foregroundStyle(.primary)
            }
        }
    }

    /// Reads `pairingRevision` so that pairing or unpairing re-evaluates it.
    @ViewBuilder
    private var connectionStatus: some View {
        if pairingRevision >= 0, let connection {
            if !connection.isPaired {
                Text("ios:settings.hub.notPaired")
            } else if let name = connection.serverName {
                Text(verbatim: name)
            }
        }
    }
}
