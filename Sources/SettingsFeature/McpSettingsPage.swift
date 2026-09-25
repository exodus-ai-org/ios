import Models
import SwiftUI

/// Settings → MCP Servers: the desktop's server cards without edit and delete — name, local or remote, description,
/// the tools a connected server offers, and the on/off switch. Commands, URLs and headers are never shown.
struct McpSettingsPage: View {
    @Bindable var viewModel: McpSettingsViewModel

    var body: some View {
        Form {
            if let message = viewModel.errorMessage {
                Section {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("settings:mcpServers.toast.toggleFailed").font(.headline)
                        Text(verbatim: message).foregroundStyle(.secondary)
                    }
                }
            }
            SettingsErrorSection(message: viewModel.refreshError)
            switch viewModel.listState {
            case .idle, .loading:
                Section { ProgressView().frame(maxWidth: .infinity) }
            case .failed(let message):
                ListLoadFailedSection(title: Text("ios:settings.mcp.loadFailed"), message: message) {
                    await viewModel.load()
                }
            case .loaded where viewModel.servers.isEmpty:
                Section {
                    ContentUnavailableView {
                        Label("settings:mcpServers.empty", systemImage: "powerplug")
                    } description: {
                        Text("settings:mcpServers.emptyHint")
                    }
                } footer: {
                    Text("ios:settings.mcp.desktopOnly")
                }
            case .loaded:
                ForEach(Array(viewModel.servers.enumerated()), id: \.element.id) { index, server in
                    Section {
                        McpServerRows(server: server, tools: viewModel.tools(for: server), viewModel: viewModel)
                    } footer: {
                        if index == viewModel.servers.count - 1 { Text("ios:settings.mcp.desktopOnly") }
                    }
                }
            }
        }
        .refreshable { await viewModel.load() }
        .task { if viewModel.pending.isEmpty { await viewModel.load() } }
    }
}

private struct McpServerRows: View {
    let server: McpServer
    let tools: [McpTool]
    let viewModel: McpSettingsViewModel
    @State private var showsTools = Self.galleryShowsTools

    var body: some View {
        Toggle(isOn: Binding(get: { server.isActive }, set: { viewModel.setActive(server.id, $0) })) {
            Label {
                VStack(alignment: .leading, spacing: 3) {
                    Text(verbatim: server.name)
                    if !server.description.isEmpty {
                        Text(verbatim: server.description).font(.footnote).foregroundStyle(.secondary)
                    }
                    if !tools.isEmpty {
                        Text(verbatim: Self.toolCount(tools.count)).font(.footnote).foregroundStyle(.secondary)
                    }
                }
            } icon: {
                Image(systemName: iconName)
            }
        }
        .disabled(viewModel.pending.contains(server.id))
        if !tools.isEmpty {
            Button {
                withAnimation(.snappy) { showsTools.toggle() }
            } label: {
                HStack {
                    if showsTools {
                        Text("settings:mcpServers.serverCard.hideTools")
                    } else {
                        Text("settings:mcpServers.serverCard.showTools")
                    }
                    Spacer()
                    Image(systemName: "chevron.right")
                        .rotationEffect(.degrees(showsTools ? 90 : 0))
                        .foregroundStyle(.tertiary)
                }
            }
            if showsTools {
                ForEach(tools) { tool in
                    VStack(alignment: .leading, spacing: 2) {
                        Text(verbatim: tool.name).font(.footnote.monospaced().weight(.medium))
                        if !tool.description.isEmpty {
                            Text(verbatim: tool.description).font(.caption).foregroundStyle(.secondary).lineLimit(4)
                        }
                    }
                }
            }
        }
    }

    private static var galleryShowsTools: Bool {
        #if DEBUG
        SettingsGalleryLaunch.isEnabled && SettingsGalleryLaunch.action == "tools"
        #else
        false
        #endif
    }

    private var iconName: String {
        if server.isRemote { return "cloud" }
        return "terminal"
    }

    private static func toolCount(_ count: Int) -> String {
        String(
            localized: "ios:settings.mcp.toolCount", defaultValue: "Tools: \(count)",
            comment: "How many tools a connected MCP server offers. %lld is the number.")
    }
}
