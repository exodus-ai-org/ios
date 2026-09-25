import Foundation
import Models
import NetworkingKit
import Observation

/// Settings → Built-in Tools: one switch per tool in `BuiltinTools.switchable`, each written at once to
/// `settings.tools.disabledTools`. Names in the array this app does not switch (tools it does not know, or binds
/// on the desktop's own terms) are left exactly as they are.
@MainActor
@Observable
public final class ToolsSettingsViewModel {
    /// Wire names switched off, as the phone shows them (legacy names read as their wire name).
    public private(set) var disabled: Set<String> = []
    /// Names switched off on the computer that this app's table does not know: a newer desktop.
    public private(set) var unknownDisabledNames: [String] = []
    public private(set) var isLoading = false
    public private(set) var hasLoaded = false
    public private(set) var pendingWrites = 0
    public var errorMessage: String?

    private let store: SettingsStore
    /// Toggles are written one after another: each is a read-modify-write of the whole column.
    private var lastWrite: Task<Void, Never>?

    public init(store: SettingsStore) {
        self.store = store
    }

    public func isEnabled(_ name: String) -> Bool { !disabled.contains(name) }

    public func load() async {
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }
        do {
            let snapshot = try await store.load(requiring: [SettingsColumn.tools.name])
            apply(snapshot.tools ?? SettingsColumn.tools.emptyValue)
            hasLoaded = true
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    /// Pull to refresh: waits for the switches still being written, so the read cannot put one back.
    public func refresh() async {
        await lastWrite?.value
        guard pendingWrites == 0 else { return }
        await load()
    }

    /// Shows the switch in its new position at once, then writes it after any write still in flight; a failed
    /// write puts the switch back.
    @discardableResult
    public func setEnabled(_ name: String, _ enabled: Bool) -> Task<Void, Never>? {
        guard hasLoaded, isEnabled(name) != enabled else { return nil }
        if enabled { disabled.remove(name) } else { disabled.insert(name) }
        errorMessage = nil
        pendingWrites += 1
        let previous = lastWrite
        let write = Task { [weak self] in
            await previous?.value
            await self?.write(name, enabled)
        }
        lastWrite = write
        return write
    }

    private func write(_ name: String, _ enabled: Bool) async {
        do {
            let written = try await store.update(.tools) { Self.set(name, enabled: enabled, in: &$0.disabledTools) }
            pendingWrites -= 1
            // A later toggle still queued has already moved its switch; the server's column is shown once it lands.
            if pendingWrites == 0 { apply(written) }
        } catch {
            pendingWrites -= 1
            if enabled { disabled.insert(name) } else { disabled.remove(name) }
            errorMessage = error.localizedDescription
        }
    }

    /// Switches `name` on or off in a stored `disabledTools`: every spelling of it (its wire name and the
    /// pre-rename one) is removed, and the wire name is appended when it goes off. Other entries keep their order.
    static func set(_ name: String, enabled: Bool, in disabledTools: inout [String]) {
        disabledTools.removeAll { BuiltinTools.wireName($0) == name }
        if !enabled { disabledTools.append(name) }
    }

    private func apply(_ tools: ToolsSettings) {
        disabled = Set(tools.disabledTools.map(BuiltinTools.wireName))
        unknownDisabledNames = BuiltinTools.unknownNames(in: tools.disabledTools)
        if !unknownDisabledNames.isEmpty {
            store.reporter.report(
                .warn, scope: "settings.tools", message: "disabledTools names this app does not know",
                attributes: ["names": .string(unknownDisabledNames.joined(separator: ", "))])
        }
    }
}
