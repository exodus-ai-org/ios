import Foundation
import Models
import Observation

/// Settings → Color tone: `settings.colorTone`, written as soon as a tone is picked (the desktop autosaves it too).
@MainActor
@Observable
public final class ColorToneViewModel {
    public private(set) var selected: ColorTone = .neutral
    public private(set) var hasLoaded = false
    public var errorMessage: String?

    private let store: SettingsStore
    /// The tone the computer holds as far as the phone knows: what a failed write goes back to.
    private var confirmed: ColorTone = .neutral
    private var latestRequest = 0
    private var lastWrite: Task<Void, Never>?

    public init(store: SettingsStore) {
        self.store = store
    }

    public func load() async {
        do {
            adopt(try await store.load())
            errorMessage = nil
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    /// Takes the tone from a settings row read elsewhere (the hub's load), unless a pick is still being written.
    public func adopt(_ snapshot: SettingsSnapshot) {
        hasLoaded = true
        guard lastWrite == nil else { return }
        confirmed = ColorTone(stored: snapshot.colorTone)
        selected = confirmed
    }

    /// Shows `tone` at once and writes it; picks are written one after another, and a failed one goes back to the
    /// last written tone unless a later pick replaced it.
    public func select(_ tone: ColorTone) async {
        guard hasLoaded, tone != selected else { return }
        latestRequest += 1
        let request = latestRequest
        selected = tone
        errorMessage = nil
        let previous = lastWrite
        let write = Task {
            await previous?.value
            do {
                try await store.update(.colorTone) { $0 = tone.rawValue }
                confirmed = tone
            } catch {
                guard request == latestRequest else { return }
                selected = confirmed
                errorMessage = error.localizedDescription
            }
        }
        lastWrite = write
        await write.value
        if request == latestRequest { lastWrite = nil }
    }
}
