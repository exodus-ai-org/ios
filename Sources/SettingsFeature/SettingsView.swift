import Models
import NetworkingKit
import SwiftUI

public struct SettingsView: View {
    @State private var viewModel: SettingsViewModel
    @Environment(\.dismiss) private var dismiss

    public init(apiClient: APIClient, serverConfig: ServerConfigStore) {
        _viewModel = State(initialValue: SettingsViewModel(apiClient: apiClient, serverConfig: serverConfig))
    }

    public var body: some View {
        NavigationStack {
            Form {
                Section("连接") {
                    TextField("http://192.168.1.10:60223", text: $viewModel.serverURLText)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .keyboardType(.URL)
                        .onSubmit {
                            // A new address means a different server: reload its provider settings.
                            if viewModel.saveServerURL() {
                                Task { await viewModel.loadSettings() }
                            }
                        }
                }

                Section("AI Providers") {
                    Picker(
                        "Provider",
                        selection: Binding(
                            get: { viewModel.selectedProvider },
                            set: { viewModel.select(provider: $0) })
                    ) {
                        ForEach(AiProviders.allCases) { provider in
                            Text(provider.rawValue).tag(provider)
                        }
                    }

                    if viewModel.providerUsesApiKey {
                        SecureField("API Key", text: $viewModel.apiKeyText)
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                    } else {
                        Text("Ollama runs on your Mac and needs no API key.")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }

                    if viewModel.availableModels.isEmpty {
                        TextField("Model", text: $viewModel.modelText)
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                    } else {
                        Picker("Model", selection: $viewModel.modelText) {
                            // Keep the current value selectable even when it isn't in the catalog.
                            if viewModel.modelText.isEmpty {
                                Text("Select a model").tag("")
                            } else if !viewModel.availableModels.contains(where: { $0.id == viewModel.modelText }) {
                                Text(viewModel.modelText).tag(viewModel.modelText)
                            }
                            ForEach(viewModel.availableModels) { model in
                                Text(model.displayName).tag(model.id)
                            }
                        }
                    }

                    Button {
                        Task { await viewModel.fetchModels() }
                    } label: {
                        if viewModel.isLoadingModels {
                            ProgressView()
                        } else {
                            Text("Refresh model list")
                        }
                    }
                    .disabled(!viewModel.canFetchModels)
                }

                if let errorMessage = viewModel.errorMessage {
                    Section {
                        Text(errorMessage).foregroundStyle(.red)
                    }
                }
            }
            .navigationTitle("Settings")
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button(viewModel.hasLoadedSettings ? "Save" : "Connect") {
                        Task {
                            guard viewModel.saveServerURL() else { return }
                            // Not loaded (first run, or the address just changed): connect to that server and
                            // load its settings instead of writing. Never write to a server we haven't read.
                            guard viewModel.hasLoadedSettings else {
                                await viewModel.loadSettings()
                                return
                            }
                            if await viewModel.save() {
                                dismiss()
                            }
                        }
                    }
                    .disabled(viewModel.isSaving || viewModel.isLoading)
                }
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
            .task { await viewModel.loadSettings() }
        }
    }
}
