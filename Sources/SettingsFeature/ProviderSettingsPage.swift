import Models
import SwiftUI

/// Settings → AI Providers: the provider, its key, its address and the model, saved together. These are the
/// computer's settings, so the page says that a change here changes the desktop's chats too.
struct ProviderSettingsPage: View {
    @Bindable var viewModel: SettingsViewModel
    var secrets: SecretsStatusModel?
    @Environment(\.dismiss) private var dismiss
    @FocusState private var keyFieldFocused: Bool
    @FocusState private var addressFocused: Bool

    var body: some View {
        ScrollViewReader { proxy in
            form
                #if DEBUG
                .task {
                    guard SettingsGalleryLaunch.isEnabled, SettingsGalleryLaunch.value(after: "-SettingsGalleryScroll") == "key"
                    else { return }
                    try? await Task.sleep(for: .seconds(2))
                    proxy.scrollTo("providerFields", anchor: .top)
                }
                #endif
        }
    }

    private var form: some View {
        Form {
            Section {
                Picker(
                    "settings:providers.config.label",
                    selection: Binding(
                        get: { viewModel.selectedProvider },
                        set: { viewModel.select(provider: $0) })
                ) {
                    ForEach(AiProviders.allCases) { provider in
                        Text(provider.rawValue).tag(provider)
                    }
                }
            } footer: {
                VStack(alignment: .leading, spacing: 6) {
                    Text("settings:providers.config.description")
                    Text("ios:settings.providers.appliesToComputer")
                }
            }

            Section {
                providerFields
            } header: {
                Text(verbatim: viewModel.selectedProvider.rawValue)
            }
            .id("providerFields")

            Section {
                modelField
                if viewModel.providerListsModels {
                    Button {
                        Task { await viewModel.fetchModels() }
                    } label: {
                        fetchLabel
                    }
                    .disabled(!viewModel.canFetchModels || viewModel.isLoadingModels)
                }
            } header: {
                Text("settings:providers.model.label")
            } footer: {
                modelFooter
            }

            SettingsErrorSection(message: viewModel.errorMessage)
        }
        .task {
            await viewModel.reloadIfUnchanged()
            #if DEBUG
            if SettingsGalleryLaunch.isEnabled {
                switch SettingsGalleryLaunch.action {
                case "moveAddress": viewModel.baseURLText = "https://gateway.example.net/anthropic"
                case "clear": viewModel.clearKey()
                default: break
                }
            }
            #endif
            await viewModel.fetchModelsIfStale()
            await secrets?.load()
        }
        .onChange(of: viewModel.selectedProvider) {
            Task { await viewModel.fetchModelsIfStale() }
        }
        .refreshable { await viewModel.pullToRefresh() }
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                Button {
                    Task {
                        guard viewModel.saveServerURL() else { return }
                        // Not loaded (first run, or the address just changed): connect to that server and
                        // load its settings instead of writing. Never write to a server we haven't read.
                        guard viewModel.hasLoadedSettings else {
                            await viewModel.loadSettings()
                            return
                        }
                        // A save that cleared a key for a new address stays, to ask for the key.
                        if await viewModel.save(), viewModel.lastSaveClearedKeys.isEmpty {
                            dismiss()
                        }
                        await secrets?.load()
                    }
                } label: {
                    if viewModel.hasLoadedSettings {
                        Text("common:action.save")
                    } else {
                        Text("ios:settings.toolbar.connect")
                    }
                }
                .disabled(viewModel.isSaving || viewModel.isLoading)
            }
        }
    }

    @ViewBuilder
    private var providerFields: some View {
        let provider = viewModel.selectedProvider
        switch provider {
        case .ollama:
            SettingsFieldRow(description: Text("settings:providers.ollama.baseUrl.description")) {
                Text("settings:providers.ollama.baseUrl.label")
            } field: {
                TextField(
                    "settings:providers.ollama.baseUrl.label", text: $viewModel.baseURLText,
                    prompt: Text(verbatim: Self.baseURLPlaceholder(provider)))
                    .urlEntry()
            }
            Text("ios:settings.providers.ollamaNoApiKey")
                .font(.footnote)
                .foregroundStyle(.secondary)
        case .azureOpenAi:
            apiKeyRow(provider: provider)
            SettingsFieldRow(description: Text("settings:providers.azure.endpoint.description")) {
                Text("settings:providers.azure.endpoint.label")
            } field: {
                TextField(
                    "settings:providers.azure.endpoint.label", text: $viewModel.baseURLText,
                    prompt: Text(verbatim: Self.baseURLPlaceholder(provider)))
                    .urlEntry()
                    .focused($addressFocused)
                    .accessibilityHint(addressHintForVoiceOver)
                destinationHint
            }
            SettingsFieldRow(description: Text("settings:providers.azure.apiVersion.description")) {
                Text("settings:providers.azure.apiVersion.label")
            } field: {
                TextField(
                    "settings:providers.azure.apiVersion.label", text: $viewModel.azureApiVersionText,
                    prompt: Text(verbatim: "2024-12-01-preview"))
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
            }
        case .openAiGpt, .anthropicClaude, .googleGemini, .xaiGrok:
            apiKeyRow(provider: provider)
            SettingsFieldRow(description: Text("settings:providers.fields.baseUrl.description")) {
                Text("settings:providers.fields.baseUrl.label")
            } field: {
                TextField(
                    "settings:providers.fields.baseUrl.label", text: $viewModel.baseURLText,
                    prompt: Text(verbatim: Self.baseURLPlaceholder(provider)))
                    .urlEntry()
                    .focused($addressFocused)
                    .accessibilityHint(addressHintForVoiceOver)
                destinationHint
            }
        }
    }

    private func apiKeyRow(provider: AiProviders) -> some View {
        let name = provider.rawValue
        let description = String(
            localized: "settings:providers.fields.apiKey.description", defaultValue: "Your \(name) API key",
            comment: "Under the API key field. %@ is a provider name such as OpenAI GPT.")
        return SettingsFieldRow(description: Text(verbatim: description)) {
            Text("settings:providers.fields.apiKey.label")
        } field: {
            SecureField(
                "settings:providers.fields.apiKey.label", text: $viewModel.apiKeyText,
                prompt: Self.keyPlaceholder(provider).map { Text(verbatim: $0) })
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .focused($keyFieldFocused)
                .onSubmit { Task { await viewModel.fetchModelsIfStale() } }
                .onChange(of: keyFieldFocused) { _, focused in
                    if !focused { Task { await viewModel.fetchModelsIfStale() } }
                }
            SavedKeyLine(state: viewModel.savedKeyState, clear: viewModel.clearKey, keep: viewModel.keepSavedKey)
            if let message = viewModel.keyReentryMessage {
                Text(verbatim: message)
                    .font(.footnote)
                    .foregroundStyle(.red)
            } else if viewModel.keyNeedsReentry(status: secrets?.status) {
                Text("settings:secrets.input.reenter")
                    .font(.footnote)
                    .foregroundStyle(.red)
            }
        }
    }

    /// The desktop's `DestinationInput`: while a key is saved, changing the address clears it, and the field says so
    /// from focus until the edit is saved.
    @ViewBuilder
    private var destinationHint: some View {
        if viewModel.addressGuardsSavedKey, addressFocused || viewModel.addressMovesSavedKey {
            Label {
                Text("settings:secrets.destinationHint")
            } icon: {
                Image(systemName: "exclamationmark.triangle")
            }
            .font(.footnote)
            .foregroundStyle(.orange)
        }
    }

    /// VoiceOver hears the warning whenever it applies, not only once it is drawn on focus.
    private var addressHintForVoiceOver: Text {
        if viewModel.addressGuardsSavedKey {
            Text("settings:secrets.destinationHint")
        } else {
            Text(verbatim: "")
        }
    }

    @ViewBuilder
    private var modelField: some View {
        if viewModel.selectedProvider == .azureOpenAi {
            TextField(
                "settings:providers.azure.model.label", text: $viewModel.modelText,
                prompt: Text(verbatim: "gpt-5.6"))
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
        } else {
            // The desktop picks from the list only; the saved id stays an option so it shows while the list
            // loads, when it fails, and after the provider dropped the model.
            Picker("settings:providers.model.label", selection: $viewModel.modelText) {
                if viewModel.modelText.isEmpty {
                    Text("ios:settings.providers.selectModel").tag("")
                } else if !viewModel.availableModels.contains(where: { $0.id == viewModel.modelText }) {
                    Text(verbatim: viewModel.modelText).tag(viewModel.modelText)
                }
                ForEach(viewModel.availableModels) { model in
                    Text(verbatim: model.displayName).tag(model.id)
                }
            }
            .pickerStyle(.menu)
            .disabled(viewModel.availableModels.isEmpty)
        }
    }

    @ViewBuilder
    private var fetchLabel: some View {
        HStack {
            if viewModel.isLoadingModels {
                if viewModel.hasCatalog {
                    Text("settings:providers.model.refreshing")
                } else {
                    Text("settings:providers.model.retrieving")
                }
                Spacer()
                ProgressView()
                    .accessibilityLabel("ios:settings.providers.loadingModels")
            } else if viewModel.hasCatalog {
                Text("settings:providers.model.refresh")
            } else {
                Text("settings:providers.model.retrieve")
            }
        }
    }

    @ViewBuilder
    private var modelFooter: some View {
        if viewModel.selectedProvider == .azureOpenAi {
            Text("settings:providers.azure.model.description")
        } else {
            VStack(alignment: .leading, spacing: 6) {
                Text("settings:providers.model.description")
                if viewModel.isModelStale {
                    let model = viewModel.modelText
                    Text(
                        verbatim: String(
                            localized: "settings:providers.model.staleWarning",
                            defaultValue: "\"\(model)\" is no longer offered by this provider — pick a current model.",
                            comment: "Under the model picker when the saved model is not in the fetched list. %@ is a model id."))
                        .foregroundStyle(.red)
                } else if !viewModel.hasCatalog && !viewModel.modelText.isEmpty {
                    Text("settings:providers.model.refreshHint")
                }
            }
        }
    }

    /// The desktop's placeholders (`providers/*.tsx`).
    static func keyPlaceholder(_ provider: AiProviders) -> String? {
        switch provider {
        case .openAiGpt: "sk-..."
        case .anthropicClaude: "sk-ant-..."
        case .googleGemini: "AIza..."
        case .xaiGrok: "xai-..."
        case .azureOpenAi, .ollama: nil
        }
    }

    static func baseURLPlaceholder(_ provider: AiProviders) -> String {
        switch provider {
        case .openAiGpt: "https://api.openai.com/v1"
        case .anthropicClaude: "https://api.anthropic.com"
        case .googleGemini: "https://generativelanguage.googleapis.com"
        case .xaiGrok: "https://api.x.ai/v1"
        case .azureOpenAi: "https://{resource}.openai.azure.com/openai/deployments/{model}"
        case .ollama: "http://localhost:11434"
        }
    }
}

extension View {
    fileprivate func urlEntry() -> some View {
        keyboardType(.URL)
            .textContentType(.URL)
            .textInputAutocapitalization(.never)
            .autocorrectionDisabled()
    }
}

/// Beside the empty key field: whether a key is saved on the computer (its last four characters), with Clear; or what
/// the save will do to it. VoiceOver hears "Saved key ending in abcd", never the mask's bullets.
struct SavedKeyLine: View {
    let state: SettingsViewModel.SavedKeyState
    let clear: () -> Void
    let keep: () -> Void

    var body: some View {
        switch state {
        case .none:
            Text("settings:secrets.input.noneAria")
                .font(.footnote)
                .foregroundStyle(.secondary)
        case .saved(let lastFour):
            ViewThatFits(in: .horizontal) {
                HStack(spacing: 8) { saved(lastFour, spaced: true) }
                VStack(alignment: .leading, spacing: 6) { saved(lastFour, spaced: false) }
            }
        case .willClear:
            HStack(spacing: 8) {
                Text("ios:settings.secrets.willClear")
                    .font(.footnote)
                    .foregroundStyle(.red)
                Spacer(minLength: 8)
                Button(action: keep) {
                    Text("ios:settings.secrets.keep")
                }
                .buttonStyle(.borderless)
                .font(.footnote.weight(.medium))
            }
        case .replacing(let hadKey):
            if hadKey {
                Text("ios:settings.secrets.replacing")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
    }

    @ViewBuilder
    private func saved(_ lastFour: String?, spaced: Bool) -> some View {
        Label {
            if let lastFour {
                Text(verbatim: Self.savedText(lastFour))
                    .accessibilityLabel(Text(verbatim: Self.savedSpoken(lastFour)))
            } else {
                Text("settings:secrets.input.saved")
                    .accessibilityLabel(Text("settings:secrets.input.savedShortAria"))
            }
        } icon: {
            Image(systemName: "checkmark.seal")
                .accessibilityHidden(true)
        }
        .font(.footnote)
        .foregroundStyle(.secondary)
        if spaced { Spacer(minLength: 8) }
        Button(role: .destructive, action: clear) {
            Text("ios:settings.secrets.clear")
        }
        .buttonStyle(.borderless)
        .font(.footnote.weight(.medium))
    }

    static func savedText(_ lastFour: String) -> String {
        String(
            localized: "ios:settings.secrets.savedEnding", defaultValue: "Saved · ends in \(lastFour)",
            comment: "Beside an empty API key field when a key is saved on the computer. %@ is the key's last four characters.")
    }

    static func savedSpoken(_ lastFour: String) -> String {
        String(
            localized: "settings:secrets.input.savedAria", defaultValue: "Saved key ending in \(lastFour)",
            comment: "What VoiceOver says for a saved key. %@ is its last four characters.")
    }
}
