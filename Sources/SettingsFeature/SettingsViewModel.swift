import CryptoKit
import Foundation
import Models
import NetworkingKit
import Observation

@MainActor
@Observable
public final class SettingsViewModel {
    public var serverURLText: String
    public private(set) var selectedProvider: AiProviders = .anthropicClaude
    /// A key typed to replace the selected provider's: empty means "keep what is saved". The computer hands saved keys
    /// out only as masks (`•••• abcd`), so the field never shows them; `savedKeyState` describes the saved one.
    public var apiKeyText: String = "" {
        didSet {
            guard apiKeyText != oldValue else { return }
            keyReentryMessage = nil
            if !apiKeyText.isEmpty { keysClearedByMove.remove(selectedProvider) }
        }
    }
    /// A `SECRET_REENTRY_REQUIRED` answer about the key (`params.field == "apiKey"`), shown under the key field.
    public private(set) var keyReentryMessage: String?
    /// Keys the last save cleared because their provider's address moved (the desktop's rule): each asks to be typed
    /// again until it is.
    public private(set) var keysClearedByMove: Set<AiProviders> = []
    public var modelText: String = ""
    /// Each provider's model list: the computer's stored catalog (`settings.modelCatalog`), or what was fetched on
    /// the phone since. It outlives a provider switch, so the picker never falls back to an empty list.
    public private(set) var catalogs: [AiProviders: [CachedModelEntry]] = [:]
    public var availableModels: [CachedModelEntry] { catalogs[selectedProvider] ?? [] }
    public var hasCatalog: Bool { catalogs[selectedProvider] != nil }
    /// The desktop's stale warning: a list is there and the saved model is not in it.
    public var isModelStale: Bool { hasCatalog && !modelText.isEmpty && !availableModels.contains { $0.id == modelText } }
    public var isLoading = false
    public var isSaving = false
    public var isLoadingModels = false
    public var errorMessage: String?
    public var didSave = false
    /// The keys the last successful save cleared for a new address: the page stays open to ask for them.
    public private(set) var lastSaveClearedKeys: Set<AiProviders> = []
    /// True only after a successful `loadSettings()` for the stored server address. `POST /api/v1/settings`
    /// replaces `providers` and `providerConfig` wholesale and nulls `lastBackupAt`, so `save()` refuses
    /// without it: a form that never loaded must not overwrite a server it has not seen.
    public private(set) var hasLoadedSettings = false

    private static let exampleServerURL = "http://192.168.1.10:60223"

    private let apiClient: APIClient
    private let serverConfig: ServerConfigStore
    private let store: SettingsStore

    /// The provider settings as last loaded/saved, plus keys the user typed for providers
    /// they have since switched away from. The selected provider's key lives in
    /// `apiKeyText` until it is parked (on a switch) or saved.
    private var workingProviders = ProvidersConfig()
    /// `providers` and `providerConfig` as last loaded or saved: a save writes only what differs from them over the
    /// columns as the server holds them then, so a desktop edit made meanwhile survives.
    private var baselineProviders = ProvidersConfig()
    private var loadedProviderConfig: ProviderConfig?
    /// The key each provider's list was fetched with (the stored key for a stored list): a changed key refetches.
    /// A digest, never the key: a key typed here must not stay in memory once it is saved.
    private var catalogKeys: [AiProviders: String] = [:]
    /// Providers whose list was fetched on the phone: a reload keeps it, even if saving it to the computer failed.
    private var fetchedProviders: Set<AiProviders> = []

    public init(apiClient: APIClient, serverConfig: ServerConfigStore, store: SettingsStore? = nil) {
        self.apiClient = apiClient
        self.serverConfig = serverConfig
        self.store = store ?? SettingsStore(apiClient: apiClient)
        // The manual address, not the effective one: while paired, requests go to the
        // computer over HTTPS and this field is only what the Simulator would use.
        self.serverURLText = serverConfig.manualBaseURLString
    }

    /// Ollama runs unauthenticated: `ProvidersSchema` has only `ollamaBaseUrl`, no key.
    public var providerUsesApiKey: Bool { selectedProvider != .ollama }
    /// The desktop has no model-list call for Azure: its model is the deployment name, typed.
    public var providerListsModels: Bool { selectedProvider != .azureOpenAi }
    public var canFetchModels: Bool { providerListsModels && (!providerUsesApiKey || effectiveApiKey != nil) }

    /// What the key field stands for: a typed key, or the saved one (its mask, which the computer resolves itself).
    var effectiveApiKey: String? {
        apiKeyText.isEmpty ? workingProviders.apiKey(for: selectedProvider) : apiKeyText
    }

    /// The saved key, as the page describes it beside an empty field.
    public enum SavedKeyState: Equatable, Sendable {
        case none
        /// Saved on the computer; `lastFour` is nil for a key too short to show any of.
        case saved(lastFour: String?)
        /// The saved key goes when the page is saved.
        case willClear
        /// A key is being typed over the saved one (or where there was none).
        case replacing(hadKey: Bool)
    }

    public var savedKeyState: SavedKeyState {
        let saved = baselineProviders.apiKey(for: selectedProvider)
        if !apiKeyText.isEmpty { return .replacing(hadKey: saved != nil) }
        let working = workingProviders.apiKey(for: selectedProvider)
        if let working, working == saved { return .saved(lastFour: SecretMask.lastFour(of: saved)) }
        if working == nil, saved != nil { return .willClear }
        return .none
    }

    /// Whether the computer holds a key for the selected provider, whatever is being typed over it.
    public var hasSavedKey: Bool { baselineProviders.apiKey(for: selectedProvider) != nil }

    /// Clear: the saved key is removed (posted as `null`) when the page is saved.
    public func clearKey() {
        apiKeyText = ""
        workingProviders = workingProviders.settingApiKey(nil, for: selectedProvider)
    }

    /// Takes a pending Clear back.
    public func keepSavedKey() {
        workingProviders = workingProviders.settingApiKey(baselineProviders.apiKey(for: selectedProvider), for: selectedProvider)
    }

    /// Whether the selected provider's address is a place its saved key is sent to: then changing it clears the key
    /// (the desktop's `DestinationInput`, guarded while the key is saved).
    public var addressGuardsSavedKey: Bool {
        guard providerUsesApiKey, apiKeyText.isEmpty, let saved = baselineProviders.apiKey(for: selectedProvider) else {
            return false
        }
        return workingProviders.apiKey(for: selectedProvider) == saved
    }

    /// The address was edited here and would take the saved key somewhere else.
    public var addressMovesSavedKey: Bool {
        addressGuardsSavedKey
            && SecretDestinations.moves(
                selectedProvider, from: baselineProviders.baseUrl(for: selectedProvider), to: baseURLText)
    }

    /// The key must be typed again: a save here cleared it for a new address, or the computer lists it
    /// (`needsReentry`: it no longer decrypts, or a change of address elsewhere cleared it).
    public func keyNeedsReentry(status: SecretsStatus?) -> Bool {
        guard providerUsesApiKey, apiKeyText.isEmpty, workingProviders.apiKey(for: selectedProvider) == nil else {
            return false
        }
        if keysClearedByMove.contains(selectedProvider) { return true }
        guard let path = SecretDestinations.keyPath(for: selectedProvider) else { return false }
        return status?.needsReentry.contains(path) == true
    }

    /// The selected provider's address: its base URL, Azure's endpoint or Ollama's server. Every provider's
    /// address lives in `workingProviders`, so switching provider keeps what was typed for the one left.
    public var baseURLText: String {
        get { workingProviders.baseUrl(for: selectedProvider) ?? "" }
        set {
            workingProviders = workingProviders.settingBaseUrl(newValue, for: selectedProvider)
            keyReentryMessage = nil
        }
    }

    public var azureApiVersionText: String {
        get { workingProviders.azureOpenAiApiVersion ?? "" }
        set { workingProviders.azureOpenAiApiVersion = newValue }
    }

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
            errorMessage = String(
                localized: "ios:settings.connection.invalidAddress",
                defaultValue: "Server address must look like \(Self.exampleServerURL)",
                comment: "Validation error. %@ is an example address such as http://192.168.1.10:60223 and must stay unchanged.")
            return false
        }
        errorMessage = nil
        serverURLText = text
        // Another address is another server: whatever was loaded belongs to the old one.
        if text != serverConfig.manualBaseURLString { hasLoadedSettings = false }
        serverConfig.manualBaseURLString = text
        return true
    }

    /// Switches the selected provider. Parks the key typed for the provider being left, loads
    /// the new provider's key, drops the model catalog (it belongs to one provider) and restores
    /// the loaded model only when the loaded provider is the one being selected again.
    public func select(provider: AiProviders) {
        guard provider != selectedProvider else { return }
        workingProviders = editedProviders
        selectedProvider = provider
        apiKeyText = typedKey(for: provider)
        keyReentryMessage = nil
        modelText = provider.rawValue == loadedProviderConfig?.provider ? (loadedProviderConfig?.model ?? "") : ""
    }

    public func loadSettings() async {
        isLoading = true
        errorMessage = nil
        hasLoadedSettings = false  // stays false if this load fails, and while it is in flight
        defer { isLoading = false }
        // A load belongs to the address it was started for. If the user moved to another server while it
        // was in flight, its outcome (settings or error) is stale: applying it would show, and mark as
        // loaded, the old server's settings under the new address, and a Save would write them there.
        let requestedAddress = serverConfig.baseURLString
        do {
            let snapshot = try await store.load(requiring: Self.columns)
            guard isCurrent(address: requestedAddress) else { return }
            apply(snapshot)
            hasLoadedSettings = true
        } catch {
            guard isCurrent(address: requestedAddress) else { return }
            errorMessage = error.localizedDescription
        }
    }

    /// Something typed or picked on the page that is not saved yet.
    public var hasUnsavedChanges: Bool {
        hasLoadedSettings && (editedProviders != baselineProviders || selectionChanged)
    }

    /// Opening the page re-reads the computer's settings, unless there are edits it would replace.
    public func reloadIfUnchanged() async {
        guard !hasUnsavedChanges else { return }
        if hasLoadedSettings {
            await refresh()
        } else {
            await loadSettings()
        }
    }

    /// Pull to refresh: the columns as the server holds them now, with the fields edited here kept on top.
    public func refresh() async {
        guard hasLoadedSettings else { return await loadSettings() }
        errorMessage = nil
        let requestedAddress = serverConfig.baseURLString
        do {
            let fresh = try await store.load(requiring: Self.columns)
            guard isCurrent(address: requestedAddress) else { return }
            let edits = mergedProviders(over: fresh.providers, edited: editedProviders)
            let keepSelection = selectionChanged
            let selection = (provider: selectedProvider, model: modelText)
            apply(fresh)
            if keepSelection {
                selectedProvider = selection.provider
                modelText = selection.model
            }
            workingProviders = edits
            apiKeyText = typedKey(for: selectedProvider)
        } catch {
            guard isCurrent(address: requestedAddress) else { return }
            errorMessage = error.localizedDescription
        }
    }

    private static let columns = [SettingsColumn.providerConfig.name, SettingsColumn.providers.name]

    /// `workingProviders` with the key being typed parked in it; an empty field keeps the saved key (or a Clear).
    private var editedProviders: ProvidersConfig {
        apiKeyText.isEmpty ? workingProviders : workingProviders.settingApiKey(apiKeyText, for: selectedProvider)
    }

    /// The key typed (and parked) for `provider`, never a saved one: that stays on the computer.
    private func typedKey(for provider: AiProviders) -> String {
        let working = workingProviders.apiKey(for: provider)
        guard let working, working != baselineProviders.apiKey(for: provider) else { return "" }
        return working
    }

    /// The provider or model differs from the stored `providerConfig`.
    private var selectionChanged: Bool {
        selectedProvider.rawValue != loadedProviderConfig?.provider || modelText != (loadedProviderConfig?.model ?? "")
    }

    /// `fresh` with every key and address field that `edited` changed from the baseline written into it, as `values`
    /// holds it (the normalized form when saving).
    private func mergedProviders(
        over fresh: ProvidersConfig?, edited: ProvidersConfig, values: ProvidersConfig? = nil
    ) -> ProvidersConfig {
        var merged = fresh ?? SettingsColumn.providers.emptyValue
        for keyPath in ProvidersConfig.fieldKeyPaths where edited[keyPath: keyPath] != baselineProviders[keyPath: keyPath] {
            merged[keyPath: keyPath] = (values ?? edited)[keyPath: keyPath]
        }
        return merged
    }

    /// `fresh` with the provider and model picked here, when they differ from the stored ones.
    private func mergedProviderConfig(over fresh: ProviderConfig?) -> ProviderConfig {
        var config = fresh ?? SettingsColumn.providerConfig.emptyValue
        guard selectionChanged else { return config }
        config.provider = selectedProvider.rawValue
        config.model = modelText.isEmpty ? nil : modelText
        config.modelSnapshot = modelText.isEmpty ? nil : resolvedModelSnapshot()
        return config
    }

    /// Shows the two columns as read, and makes them the baseline.
    private func apply(_ snapshot: SettingsSnapshot) {
        workingProviders = snapshot.providers ?? SettingsColumn.providers.emptyValue
        baselineProviders = workingProviders
        loadedProviderConfig = snapshot.providerConfig
        for provider in AiProviders.allCases where !fetchedProviders.contains(provider) {
            catalogs[provider] = snapshot.modelCatalog?.models(for: provider)
            catalogKeys[provider] = Self.fingerprint(workingProviders.apiKey(for: provider))
        }
        if let raw = snapshot.providerConfig?.provider, let provider = AiProviders(rawValue: raw) {
            selectedProvider = provider
            modelText = snapshot.providerConfig?.model ?? ""
        } else {
            modelText = ""
        }
        apiKeyText = ""
    }

    /// Whether `address` is still the stored server address, i.e. the user has not moved to another server.
    private func isCurrent(address: String) -> Bool {
        serverConfig.baseURLString == address
    }

    /// Pull to refresh: the computer's settings, then the selected provider's model list.
    public func pullToRefresh() async {
        await refresh()
        if canFetchModels { await fetchModels() }
    }

    /// Fetches the selected provider's list quietly when there is none yet, or it was fetched with another key.
    public func fetchModelsIfStale() async {
        guard hasLoadedSettings, canFetchModels, !isLoadingModels,
              !hasCatalog || catalogKeys[selectedProvider] != Self.fingerprint(effectiveApiKey)
        else { return }
        await fetchModels(quietly: true)
    }

    /// Fetches the selected provider's list (the desktop's Refresh) and stores it in `settings.modelCatalog`, as the
    /// desktop does, so the next visit, here or there, opens with it. A quiet fetch reports no error.
    public func fetchModels(quietly: Bool = false) async {
        isLoadingModels = true
        if !quietly { errorMessage = nil }
        defer { isLoadingModels = false }
        // A catalog belongs to the provider, key and address it was requested for. If any changed while the
        // request was in flight, its outcome (models or error) is stale and must not reach the form.
        let requestedProvider = selectedProvider
        let requestedKey = effectiveApiKey ?? ""
        let requestedBaseURL = baseURLText
        do {
            // A saved key goes as its mask: the computer swaps it for the key, but only toward the saved address.
            let request = ListModelsRequest(
                provider: requestedProvider.rawValue,
                apiKey: requestedKey.isEmpty ? nil : requestedKey,
                baseUrl: Self.normalizedField(requestedBaseURL),
                apiVersion: nil
            )
            let response: ListModelsResponse = try await apiClient.post("/api/v1/settings/models", body: request)
            guard isCurrent(provider: requestedProvider, apiKey: requestedKey, baseURL: requestedBaseURL) else { return }
            catalogs[requestedProvider] = response.models
            catalogKeys[requestedProvider] = Self.fingerprint(requestedKey)
            fetchedProviders.insert(requestedProvider)
            await storeCatalog(response.models, for: requestedProvider)
        } catch {
            guard isCurrent(provider: requestedProvider, apiKey: requestedKey, baseURL: requestedBaseURL) else { return }
            if (error as? HTTPError)?.reentryField == "apiKey" {
                keyReentryMessage = Self.keyReentryText
                return
            }
            guard !quietly else { return }
            errorMessage = error.localizedDescription
        }
    }

    /// Tells one key from another without keeping it: SHA-256, hex.
    static func fingerprint(_ key: String?) -> String {
        guard let key, !key.isEmpty else { return "" }
        return SHA256.hash(data: Data(key.utf8)).map { String(format: "%02x", $0) }.joined()
    }

    static var keyReentryText: String {
        String(
            localized: "ios:settings.providers.keyReentry",
            defaultValue: "The saved key only works with the address it was saved for. Enter the key again to use this address.",
            comment: "Under the API key field when the computer refused to send the saved key to a new base URL.")
    }

    /// Writes one provider's list into `settings.modelCatalog`, leaving every other provider's list as stored. A
    /// failure keeps the list on the phone for this session only: it is a cache, not a setting the user chose.
    private func storeCatalog(_ models: [CachedModelEntry], for provider: AiProviders) async {
        guard hasLoadedSettings else { return }
        do {
            try await store.update(.modelCatalog) { $0 = $0.setting(models, for: provider) }
        } catch {
            apiClient.reporter.report(
                .error, scope: "settings.providers", message: "Model list not stored on the computer",
                attributes: LogReporter.attributes(for: error))
        }
    }

    /// Whether a model-list request sent for `provider`, `apiKey` and `baseURL` still matches the form, i.e.
    /// the user has neither switched provider nor edited the key or the address since it was sent.
    private func isCurrent(provider: AiProviders, apiKey: String, baseURL: String) -> Bool {
        selectedProvider == provider && (effectiveApiKey ?? "") == apiKey && baseURLText == baseURL
    }

    /// Trimmed, and `nil` when empty: the desktop falls back to the provider's default only for a missing value.
    static func normalizedField(_ text: String?) -> String? {
        guard let trimmed = text?.trimmingCharacters(in: .whitespacesAndNewlines), !trimmed.isEmpty else { return nil }
        return trimmed
    }

    /// The desktop's `optionalUrl` (zod `url()`, i.e. WHATWG `new URL`): anything with a scheme, and a host when it
    /// has an authority. Ollama's address is a plain string there, so it is not checked.
    static func isValidProviderURL(_ text: String) -> Bool {
        guard let components = URLComponents(string: text), let scheme = components.scheme, !scheme.isEmpty else {
            return false
        }
        return !text.contains("://") || !(components.host ?? "").isEmpty
    }

    /// Every provider's address, trimmed; or the first provider (in the picker's order) whose address is not a URL.
    private func normalizedProviders(_ providers: ProvidersConfig) -> Result<ProvidersConfig, InvalidAddress> {
        var result = providers
        for provider in AiProviders.allCases {
            let url = Self.normalizedField(providers.baseUrl(for: provider))
            if provider != .ollama, let url, !Self.isValidProviderURL(url) { return .failure(InvalidAddress(provider: provider)) }
            result = result.settingBaseUrl(url, for: provider)
        }
        result.azureOpenAiApiVersion = Self.normalizedField(providers.azureOpenAiApiVersion)
        return .success(result)
    }

    /// The desktop's `clearMovedSecrets`: a saved key posted back unchanged while its address was edited here to
    /// somewhere else is cleared (the computer would clear it anyway: a stored key never follows a new host).
    private func keysMovedAway(edited: ProvidersConfig, values: ProvidersConfig) -> Set<AiProviders> {
        Set(AiProviders.allCases.filter { provider in
            guard let saved = baselineProviders.apiKey(for: provider), edited.apiKey(for: provider) == saved,
                edited.baseUrl(for: provider) != baselineProviders.baseUrl(for: provider)
            else { return false }
            return SecretDestinations.moves(
                provider, from: baselineProviders.baseUrl(for: provider), to: values.baseUrl(for: provider))
        })
    }

    private struct InvalidAddress: Error {
        let provider: AiProviders
    }

    /// `POST /api/v1/settings` replaces `providerConfig` wholesale and the desktop feeds
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
            errorMessage = String(
                localized: "ios:settings.error.notLoaded",
                defaultValue: "Connect to the server and load its settings before saving.",
                comment: "Error shown when saving is attempted before the server's settings were loaded.")
            return false
        }
        var edited = editedProviders
        var providers: ProvidersConfig
        switch normalizedProviders(edited) {
        case .success(let normalized):
            providers = normalized
        case .failure(let invalid):
            errorMessage = String(
                localized: "ios:settings.providers.invalidURL",
                defaultValue: "The address for \(invalid.provider.rawValue) isn't a valid URL. Include the scheme, such as https://.",
                comment: "Validation error when saving AI provider settings. %@ is a provider name such as OpenAI GPT.")
            return false
        }
        let moved = keysMovedAway(edited: edited, values: providers)
        for provider in moved {
            edited = edited.settingApiKey(nil, for: provider)
            providers = providers.settingApiKey(nil, for: provider)
        }
        let cleared = Set(AiProviders.allCases.filter {
            baselineProviders.apiKey(for: $0) != nil && edited.apiKey(for: $0) == nil
        })
        let (finalEdited, finalValues) = (edited, providers)
        isSaving = true
        errorMessage = nil
        didSave = false
        lastSaveClearedKeys = []
        defer { isSaving = false }
        do {
            // Only the fields changed here go over the columns as they are now; both are written in one request.
            let written = try await store.update { fresh in
                [
                    SettingsColumn.providerConfig.assigning(self.mergedProviderConfig(over: fresh.providerConfig)),
                    SettingsColumn.providers.assigning(
                        self.mergedProviders(over: fresh.providers, edited: finalEdited, values: finalValues),
                        clearing: cleared),
                ]
            }
            apply(written)
            keysClearedByMove = keysClearedByMove.filter { finalEdited.apiKey(for: $0) == nil }.union(moved)
            lastSaveClearedKeys = moved
            didSave = true
            return true
        } catch {
            errorMessage = error.localizedDescription
            return false
        }
    }
}
