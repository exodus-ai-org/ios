import Foundation
import Models
import NetworkingKit
import Observation

/// Settings → Memory: the `settings.memory` switches and limits (each written at once through `SettingsStore`), and
/// the entries of `/api/v1/memory` with the operations the desktop's `memory.tsx` has: add, edit, disable or
/// restore, delete. The list is re-read after every entry write.
@MainActor
@Observable
public final class MemorySettingsViewModel {
    /// `contextWindowPercent`: the schema's range and the desktop's default (`chat.ts`).
    public static let percentRange = 50...95
    public static let defaultPercent = 75
    /// `freshTailSize` counts runs; the range and default of the desktop's `freshTailRuns()`.
    public static let freshTailRange = 2...24
    public static let defaultFreshTail = 6

    public enum ListState: Equatable {
        case idle, loading, loaded
        case failed(String)
    }

    /// A failed entry operation: which one (the view shows the desktop's title for it) and the server's message.
    public enum Failure: Equatable {
        case load(String), create(String), save(String), delete(String)
        case titleRequired
    }

    public private(set) var autoCapture = true
    public private(set) var useInChat = true
    public private(set) var lcmEnabled = true
    public private(set) var contextWindowPercent = defaultPercent
    public private(set) var freshTailSize = defaultFreshTail
    public private(set) var hasLoadedSettings = false
    public private(set) var isLoadingSettings = false
    public private(set) var pendingWrites = 0
    /// A failed load or write of `settings.memory`.
    public var errorMessage: String?

    public private(set) var entries: [MemoryEntry] = []
    public private(set) var listState: ListState = .idle
    public var failure: Failure?
    /// The entry waiting for the user to confirm its deletion; nothing is deleted without `confirmDelete()`.
    public private(set) var pendingDeletion: MemoryEntry?
    public private(set) var isWriting = false

    private let store: SettingsStore
    private let apiClient: APIClient
    private var lastWrite: Task<Void, Never>?
    private static let path = "/api/v1/memory"

    public init(store: SettingsStore, apiClient: APIClient) {
        self.store = store
        self.apiClient = apiClient
    }

    // MARK: Settings

    public func load() async {
        await loadSettings()
        await loadList()
    }

    /// Pull to refresh: the entries, and the switches once no write of them is in flight.
    public func refresh() async {
        await lastWrite?.value
        if pendingWrites == 0 { await loadSettings() }
        await loadList()
    }

    public func loadSettings() async {
        isLoadingSettings = true
        errorMessage = nil
        defer { isLoadingSettings = false }
        do {
            let snapshot = try await store.load(requiring: [SettingsColumn.memory.name])
            apply(snapshot.memory ?? SettingsColumn.memory.emptyValue)
            hasLoadedSettings = true
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    @discardableResult
    public func setAutoCapture(_ on: Bool) -> Task<Void, Never>? {
        guard autoCapture != on else { return nil }
        autoCapture = on
        return write { $0.autoCapture = on }
    }

    @discardableResult
    public func setUseInChat(_ on: Bool) -> Task<Void, Never>? {
        guard useInChat != on else { return nil }
        useInChat = on
        return write { $0.useInChat = on }
    }

    @discardableResult
    public func setLcmEnabled(_ on: Bool) -> Task<Void, Never>? {
        guard lcmEnabled != on else { return nil }
        lcmEnabled = on
        return write { $0.lcmEnabled = on }
    }

    /// Clamped to 50–95, as the desktop's form only accepts.
    @discardableResult
    public func setContextWindowPercent(_ value: Int) -> Task<Void, Never>? {
        let clamped = Self.clamp(value, to: Self.percentRange)
        guard contextWindowPercent != clamped else { return nil }
        contextWindowPercent = clamped
        return write { $0.contextWindowPercent = Double(clamped) }
    }

    /// Clamped to 2–24 runs, as the desktop's form only accepts.
    @discardableResult
    public func setFreshTailSize(_ value: Int) -> Task<Void, Never>? {
        let clamped = Self.clamp(value, to: Self.freshTailRange)
        guard freshTailSize != clamped else { return nil }
        freshTailSize = clamped
        return write { $0.freshTailSize = Double(clamped) }
    }

    /// The threshold a stored value means: the default when unset, else rounded into range.
    static func percent(from raw: Double?) -> Int {
        guard let raw, raw.isFinite else { return defaultPercent }
        return clamp(Int(raw.rounded()), to: percentRange)
    }

    /// The desktop's `freshTailRuns()`: the default when unset, else clamped (a value saved when it counted
    /// messages, up to 64, reads as 24 runs).
    static func freshTail(from raw: Double?) -> Int {
        guard let raw, raw.isFinite else { return defaultFreshTail }
        return clamp(Int(raw.rounded()), to: freshTailRange)
    }

    private static func clamp(_ value: Int, to range: ClosedRange<Int>) -> Int {
        min(range.upperBound, max(range.lowerBound, value))
    }

    /// Writes one field over the column as the server holds it now, after any write still in flight; a failed
    /// write shows the column as last read from the server again.
    private func write(_ modify: @escaping @MainActor (inout MemorySettings) -> Void) -> Task<Void, Never>? {
        guard hasLoadedSettings else {
            apply(store.snapshot?.memory ?? SettingsColumn.memory.emptyValue)
            return nil
        }
        errorMessage = nil
        pendingWrites += 1
        let previous = lastWrite
        let task = Task { [weak self] in
            await previous?.value
            guard let self else { return }
            do {
                let written = try await self.store.update(.memory) { modify(&$0) }
                self.pendingWrites -= 1
                if self.pendingWrites == 0 { self.apply(written) }
            } catch {
                self.pendingWrites -= 1
                self.errorMessage = error.localizedDescription
                if self.pendingWrites == 0 {
                    self.apply(self.store.snapshot?.memory ?? SettingsColumn.memory.emptyValue)
                }
            }
        }
        lastWrite = task
        return task
    }

    private func apply(_ memory: MemorySettings) {
        autoCapture = memory.autoCapture
        useInChat = memory.useInChat
        lcmEnabled = memory.lcmEnabled
        contextWindowPercent = Self.percent(from: memory.contextWindowPercent)
        freshTailSize = Self.freshTail(from: memory.freshTailSize)
    }

    // MARK: Entries

    /// Active entries grouped like the desktop: You, Topics, People, each in the server's order (newest first).
    public var activeGroups: [(section: MemorySection, entries: [MemoryEntry])] {
        MemorySection.allCases.compactMap { section in
            let rows = entries.filter { $0.isActive && $0.section == section.rawValue }
            return rows.isEmpty ? nil : (section, rows)
        }
    }

    public var disabledEntries: [MemoryEntry] { entries.filter { !$0.isActive } }

    public func loadList() async {
        if entries.isEmpty { listState = .loading }
        do {
            entries = try await apiClient.get(Self.path)
            listState = .loaded
        } catch {
            // With entries on screen the list stays, stale, and the failure is shown beside it.
            if entries.isEmpty {
                listState = .failed(error.localizedDescription)
            } else {
                failure = .load(error.localizedDescription)
            }
        }
    }

    /// Adds an entry as the desktop does (`source: "explicit"`). The title is required.
    @discardableResult
    public func create(_ draft: MemoryDraft) async -> Bool {
        let key = draft.trimmedKey
        guard !key.isEmpty else {
            failure = .titleRequired
            return false
        }
        let body = MemoryCreateBody(
            section: draft.section.rawValue, key: key, summary: draft.trimmedSummary, details: draft.details)
        return await perform(Failure.create) { try await self.apiClient.post(Self.path, body: body) }
    }

    /// Sends only the fields that differ from `entry`, as the desktop saves one field on blur. Nothing is sent
    /// when nothing changed.
    @discardableResult
    public func save(_ draft: MemoryDraft, for entry: MemoryEntry) async -> Bool {
        guard !draft.trimmedKey.isEmpty else {
            failure = .titleRequired
            return false
        }
        let patch = draft.patch(from: entry)
        if patch.isEmpty { return true }
        return await perform(Failure.save) { try await self.apiClient.patch(Self.entryPath(entry), body: patch) }
    }

    /// Disable keeps the entry but stops it being used in chats; restore brings it back.
    @discardableResult
    public func setActive(_ entry: MemoryEntry, _ active: Bool) async -> Bool {
        guard entry.isActive != active else { return true }
        return await perform(Failure.save) {
            try await self.apiClient.patch(Self.entryPath(entry), body: MemoryPatchBody(isActive: active))
        }
    }

    public func requestDelete(_ entry: MemoryEntry) { pendingDeletion = entry }

    public func cancelDelete() { pendingDeletion = nil }

    /// Deletes the entry the user confirmed, for good (`?hard=true`, as the desktop's Delete does). The entry is
    /// taken at once, so the confirmation closing cannot race the request.
    @discardableResult
    public func confirmDelete() -> Task<Bool, Never>? {
        guard let entry = pendingDeletion else { return nil }
        pendingDeletion = nil
        return Task {
            await perform(Failure.delete) {
                try await self.apiClient.delete(
                    Self.entryPath(entry), query: [URLQueryItem(name: "hard", value: "true")])
            }
        }
    }

    private func perform(_ failed: (String) -> Failure, _ request: () async throws -> Void) async -> Bool {
        isWriting = true
        failure = nil
        defer { isWriting = false }
        var succeeded = true
        do {
            try await request()
        } catch {
            failure = failed(error.localizedDescription)
            succeeded = false
        }
        let failedWrite = failure
        await loadList()
        if !succeeded { failure = failedWrite }
        return succeeded
    }

    private static func entryPath(_ entry: MemoryEntry) -> String { "\(path)/\(entry.id)" }
}

/// An entry's fields as the add and edit sheets hold them: details are one per line, as on the desktop.
public struct MemoryDraft: Equatable, Sendable {
    public var section: MemorySection
    public var key: String
    public var summary: String
    public var detailsText: String

    public init(section: MemorySection = .topic, key: String = "", summary: String = "", detailsText: String = "") {
        self.section = section
        self.key = key
        self.summary = summary
        self.detailsText = detailsText
    }

    public init(entry: MemoryEntry) {
        self.init(
            section: MemorySection(rawValue: entry.section) ?? .topic, key: entry.key, summary: entry.summary,
            detailsText: entry.details.joined(separator: "\n"))
    }

    var trimmedKey: String { key.trimmingCharacters(in: .whitespacesAndNewlines) }
    var trimmedSummary: String { summary.trimmingCharacters(in: .whitespacesAndNewlines) }

    /// The desktop's `detailsFromText`: a line each, a leading `-` or `*` bullet dropped, blank lines skipped.
    public var details: [String] { Self.details(from: detailsText) }

    public static func details(from text: String) -> [String] {
        text.split(whereSeparator: \.isNewline).compactMap { line in
            var rest = Substring(line)
            if let first = rest.first, first == "-" || first == "*" {
                rest = rest.dropFirst().drop { $0.isWhitespace }
            }
            let item = rest.trimmingCharacters(in: .whitespacesAndNewlines)
            return item.isEmpty ? nil : item
        }
    }

    func patch(from entry: MemoryEntry) -> MemoryPatchBody {
        var patch = MemoryPatchBody()
        if trimmedKey != entry.key { patch.key = trimmedKey }
        if trimmedSummary != entry.summary { patch.summary = trimmedSummary }
        if details != entry.details { patch.details = details }
        return patch
    }
}
