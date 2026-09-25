import SwiftUI

/// Settings → Built-in Tools: a switch per tool, grouped like the desktop's page. Keys and options of the tools that
/// have them (Web Search, Image Generation, Map Itinerary) stay on the computer.
struct ToolsSettingsPage: View {
    @Bindable var viewModel: ToolsSettingsViewModel

    var body: some View {
        Form {
            Section {
                EmptyView()
            } footer: {
                Text("ios:settings.tools.intro")
            }

            ForEach(BuiltinTools.Group.allCases) { group in
                Section {
                    ForEach(BuiltinTools.switchable.filter { $0.group == group }) { tool in
                        toggle(for: tool)
                    }
                } header: {
                    Text(group.title)
                }
            }

            Section {
            } footer: {
                Text("ios:settings.tools.configureOnComputer")
            }

            if !viewModel.unknownDisabledNames.isEmpty {
                Section {
                    ForEach(viewModel.unknownDisabledNames, id: \.self) { name in
                        Text(verbatim: name).font(.body.monospaced())
                    }
                } header: {
                    Text("ios:settings.tools.unknownTitle")
                } footer: {
                    Text("ios:settings.tools.unknownFooter")
                }
            }

            SettingsErrorSection(message: viewModel.errorMessage)
        }
        .disabled(!viewModel.hasLoaded)
        .refreshable { await viewModel.refresh() }
        .overlay {
            if viewModel.isLoading && !viewModel.hasLoaded { ProgressView() }
        }
        .task {
            if viewModel.pendingWrites == 0 { await viewModel.load() }
        }
    }

    private func toggle(for tool: BuiltinTools.Tool) -> some View {
        Toggle(
            isOn: Binding(
                get: { viewModel.isEnabled(tool.name) },
                set: { viewModel.setEnabled(tool.name, $0) })
        ) {
            Text(tool.title)
            Text(tool.summary)
        }
    }
}
