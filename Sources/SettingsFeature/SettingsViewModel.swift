import Foundation
import Models
import NetworkingKit
import Observation

@MainActor
@Observable
public final class SettingsViewModel {
    public var serverURLText: String
    public private(set) var selectedProvider: AiProviders = .anthropicClaude
    public var apiKeyText: String = ""
    public var modelText: String = ""
    public private(set) var availableModels: [CachedModelEntry] = []
    public var isLoading = false
    public var isSaving = false
    public var isLoadingModels = false
    public var errorMessage: String?
    public var didSave = false
    /// True only after a successful `loadSettings()` for the stored server address. `POST /api/settings`
    /// replaces `providers` and `providerConfig` wholesale and nulls `lastBackupAt`, so `save()` refuses
    /// without it: a form that never loaded must not overwrite a server it has not seen.
    public private(set) var hasLoadedSettings = false

    private let apiClient: APIClient
    private let serverConfig: ServerConfigStore

    /// The provider settings as last loaded/saved, plus keys the user typed for providers
    /// they have since switched away from. The selected provider's key lives in
    /// `apiKeyText` until it is parked (on a switch) or saved.
    private var workingProviders = ProvidersConfig()
    private var loadedProviderConfig: ProviderConfig?
    private var loadedLastBackupAt: String?

    public init(apiClient: APIClient, serverConfig: ServerConfigStore) {
        self.apiClient = apiClient
        self.serverConfig = serverConfig
        self.serverURLText = serverConfig.baseURLString
    }

    /// Ollama runs unauthenticated: `ProvidersSchema` has only `ollamaBaseUrl`, no key.
    public var providerUsesApiKey: Bool { selectedProvider != .ollama }
    public var canFetchModels: Bool { !providerUsesApiKey || !apiKeyText.isEmpty }

    /// Normalizes what was typed — trims, defaults a missing scheme to `http://` (the field
    /// takes a bare `192.168.1.10:60223` on a real device), drops trailing slashes — and
    /// stores it only if it is an http(s) URL with a host. Otherwise sets `errorMessage`
    /// and leaves the stored address untouched.
    @discardableResult
    public func saveServerURL() -> Bool {
        var text = serverURLText.trimmingCharacters(in: .whitespacesAndNewlines)
        if !text.isEmpty, !text.contains("://") { text = "http://" + text }
        while text.hasSuffix("/") { text.removeLast() }
        guard let url = URL(string: text),
              let scheme = url.scheme?.lowercased(), scheme == "http" || scheme == "https",
              let host = url.host, !host.isEmpty
        else {
            errorMessage = "Server address must look like http://192.168.1.10:60223"
            return false
        }
        errorMessage = nil
        serverURLText = text
        // Another address is another server: whatever was loaded belongs to the old one.
        if text != serverConfig.baseURLString { hasLoadedSettings = false }
        serverConfig.baseURLString = text
        return true
    }

    /// Switches the selected provider. Parks the key typed for the provider being left, loads
    /// the new provider's key, drops the model catalog (it belongs to one provider) and restores
    /// the loaded model only when the loaded provider is the one being selected again.
    public func select(provider: AiProviders) {
        guard provider != selectedProvider else { return }
        workingProviders = workingProviders.settingApiKey(apiKeyText.isEmpty ? nil : apiKeyText, for: selectedProvider)
        selectedProvider = provider
        apiKeyText = workingProviders.apiKey(for: provider) ?? ""
        availableModels = []
        modelText = provider.rawValue == loadedProviderConfig?.provider ? (loadedProviderConfig?.model ?? "") : ""
    }

    public func loadSettings() async {
        isLoading = true
        errorMessage = nil
        hasLoadedSettings = false  // stays false if this load fails, and while it is in flight
        defer { isLoading = false }
        do {
            let snapshot: SettingsSnapshot = try await apiClient.get("/api/settings")
            workingProviders = snapshot.providers ?? ProvidersConfig()
            loadedProviderConfig = snapshot.providerConfig
            loadedLastBackupAt = snapshot.lastBackupAt
            availableModels = []
            if let raw = snapshot.providerConfig?.provider, let provider = AiProviders(rawValue: raw) {
                selectedProvider = provider
                modelText = snapshot.providerConfig?.model ?? ""
            } else {
                modelText = ""
            }
            apiKeyText = workingProviders.apiKey(for: selectedProvider) ?? ""
            hasLoadedSettings = true
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    public func fetchModels() async {
        isLoadingModels = true
        errorMessage = nil
        defer { isLoadingModels = false }
        // A catalog belongs to the provider and key it was requested for. If either changed while the
        // request was in flight, its outcome (models or error) is stale and must not reach the form.
        let requestedProvider = selectedProvider
        let requestedKey = apiKeyText
        do {
            let request = ListModelsRequest(
                provider: requestedProvider.rawValue,
                apiKey: requestedKey.isEmpty ? nil : requestedKey,
                baseUrl: nil,
                apiVersion: nil
            )
            let response: ListModelsResponse = try await apiClient.post("/api/settings/models", body: request)
            guard isCurrent(provider: requestedProvider, apiKey: requestedKey) else { return }
            availableModels = response.models
        } catch {
            guard isCurrent(provider: requestedProvider, apiKey: requestedKey) else { return }
            errorMessage = error.localizedDescription
        }
    }

    /// Whether a model-list request sent for `provider` and `apiKey` still matches the form, i.e. the
    /// user has neither switched provider nor edited the key since it was sent.
    private func isCurrent(provider: AiProviders, apiKey: String) -> Bool {
        selectedProvider == provider && apiKeyText == apiKey
    }

    /// `POST /api/settings` replaces `providerConfig` wholesale and the desktop feeds
    /// `providerConfig.modelSnapshot` (context window, max output, reasoning levels, cost) to
    /// its model resolver, so never send `nil` for a model the desktop already knows: prefer
    /// the picked catalog entry; else keep the loaded snapshot only if provider AND model are
    /// unchanged (a snapshot for a different model would be wrong data); else none.
    private func resolvedModelSnapshot() -> ModelSnapshot? {
        if let entry = availableModels.first(where: { $0.id == modelText }) { return entry.snapshot }
        guard let loaded = loadedProviderConfig,
              loaded.provider == selectedProvider.rawValue,
              loaded.model == modelText
        else { return nil }
        return loaded.modelSnapshot
    }

    @discardableResult
    public func save() async -> Bool {
        guard hasLoadedSettings else {
            errorMessage = "Connect to the server and load its settings before saving."
            return false
        }
        isSaving = true
        errorMessage = nil
        didSave = false
        defer { isSaving = false }
        do {
            let providers = workingProviders.settingApiKey(apiKeyText.isEmpty ? nil : apiKeyText, for: selectedProvider)
            let providerConfig = ProviderConfig(
                provider: selectedProvider.rawValue,
                model: modelText.isEmpty ? nil : modelText,
                modelSnapshot: modelText.isEmpty ? nil : resolvedModelSnapshot()
            )
            // `lastBackupAt` is echoed because the server writes it unconditionally (see SettingsPatch).
            let patch = SettingsPatch(
                id: "global", providerConfig: providerConfig, providers: providers, lastBackupAt: loadedLastBackupAt)
            try await apiClient.post("/api/settings", body: patch)
            workingProviders = providers
            loadedProviderConfig = providerConfig
            didSave = true
            return true
        } catch {
            errorMessage = error.localizedDescription
            return false
        }
    }
}
