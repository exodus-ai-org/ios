import Foundation
import Models
import NetworkingKit
import Observation
import SwiftUI

extension EnvironmentValues {
    @Entry var memoryFoot: MemoryFootStore?
    /// Opens Settings on its Memory page. Nil where there is no Settings to open (the galleries).
    @Entry public var openMemorySettings: OpenMemorySettingsAction?
}

/// Opens Settings on its Memory page, like `DismissAction`: what it does never changes, so every value is equal and
/// handing a new one down does not redraw the lines that read it.
public struct OpenMemorySettingsAction: Equatable, Sendable {
    private let action: @MainActor @Sendable () -> Void

    public init(_ action: @escaping @MainActor @Sendable () -> Void) {
        self.action = action
    }

    @MainActor
    public func callAsFunction() { action() }

    public static func == (lhs: Self, rhs: Self) -> Bool { true }
}

/// What one run did to memory, read from its own messages (the desktop's `runMemoryChanges`): the strip is drawn
/// from this and the run's own undo state, never from a separate fetch.
struct RunMemoryChanges: Equatable, Sendable {
    /// An `update_memory` call is out with no result yet.
    var running: Bool
    /// An `update_memory` call came back as an error.
    var failed: Bool
    /// Every result's changes, in call order.
    var changes: [MemoryChange]

    /// Nil for a run that never called `update_memory`.
    init?(_ updates: [MemoryUpdate]) {
        guard !updates.isEmpty else { return nil }
        running = updates.contains { $0.status == .pending }
        failed = updates.contains { $0.status == .failed }
        changes = updates.flatMap { $0.result?.changes ?? [] }
    }
}

/// Where Undo left a run's changes. Kept per run in the store, so it outlives the strip scrolling away.
enum MemoryUndoState: Equatable, Sendable {
    case idle
    case undone
    case partial(undone: Int, skipped: Int)
    /// Nothing still reads as the run left it: undone already, or edited since.
    case stale

    /// The desktop's reading of the route's answer: nothing undone is stale, nothing skipped is undone.
    static func after(_ result: MemoryUndoResult) -> MemoryUndoState {
        if result.undone.isEmpty { return .stale }
        if result.skipped.isEmpty { return .undone }
        return .partial(undone: result.undone.count, skipped: result.skipped.count)
    }
}

/// What the strip shows.
enum MemoryStripDisplay: Equatable {
    enum Label: Equatable {
        case updated(keys: [String])
        case partlyUpdated(keys: [String])
        case undone
        case partial(undone: Int, skipped: Int)
        case stale
    }

    case running
    case failed
    /// `warning`: some call failed while another changed something. `undoable`: Undo is offered.
    case changes(Label, warning: Bool, undoable: Bool)
}

enum MemoryStripRules {
    /// Nil when there is nothing to say: no call, or calls that needed no change.
    ///
    /// `active` is whether the run still streams: a call still out once it does not was cut off by Stop, so it no
    /// longer counts as running. `live` is whether this client saw the call out: then Undo is known to be good even
    /// while the memory list still holds what came before. `entries` is the memory list as last read, nil until read.
    static func display(
        _ run: RunMemoryChanges, active: Bool, undo: MemoryUndoState, live: Bool, entries: [MemoryEntry]?
    ) -> MemoryStripDisplay? {
        if run.running && active { return .running }
        if run.changes.isEmpty { return run.failed ? .failed : nil }
        let stale =
            !live && undo == .idle && entries.map { list in !run.changes.contains { stillAsLeft($0, in: list) } } == true
        let shown: MemoryUndoState = stale ? .stale : undo
        let keys = keys(of: run.changes)
        let label: MemoryStripDisplay.Label =
            switch shown {
            case .undone: .undone
            case .partial(let undone, let skipped): .partial(undone: undone, skipped: skipped)
            case .stale: .stale
            case .idle: run.failed ? .partlyUpdated(keys: keys) : .updated(keys: keys)
            }
        return .changes(label, warning: run.failed && shown == .idle, undoable: shown == .idle)
    }

    /// The entry still reads exactly as the change left it; a missing entry matches only a delete. The same test the
    /// computer's undo applies.
    static func stillAsLeft(_ change: MemoryChange, in entries: [MemoryEntry]) -> Bool {
        entries.first { $0.id == change.id }.map(MemorySnapshot.init(entry:)) == change.after
    }

    /// Each entry's title once, in the order the run touched them.
    static func keys(of changes: [MemoryChange]) -> [String] {
        var seen = Set<String>()
        return changes.map(\.key).filter { seen.insert($0).inserted }
    }

    static func text(_ label: MemoryStripDisplay.Label) -> String {
        switch label {
        case .updated(let keys):
            let list = keys.formatted(.list(type: .and))
            return String(
                localized: "chat:memoryStrip.updated", defaultValue: "Memory updated · \(list)",
                comment: "A reply's foot after it changed memory. %@ lists the entries.")
        case .partlyUpdated(let keys):
            let list = keys.formatted(.list(type: .and))
            return String(
                localized: "chat:memoryStrip.partlyUpdated", defaultValue: "Memory partly updated · \(list)",
                comment: "A reply's foot after one memory change failed and another applied. %@ lists the entries.")
        case .undone:
            return String(localized: "chat:memoryStrip.undone", defaultValue: "Undone", comment: "The memory strip after Undo.")
        case .partial(let undone, let skipped):
            let (undone, skipped) = (undone.formatted(), skipped.formatted())
            return String(
                localized: "chat:memoryStrip.partial", defaultValue: "Undid \(undone) · \(skipped) changed since and kept",
                comment: "The memory strip after an Undo that kept entries edited since.")
        case .stale:
            return String(
                localized: "chat:memoryStrip.stale", defaultValue: "Undone or changed since",
                comment: "The memory strip when nothing still reads as the reply left it.")
        }
    }

    static var updatingText: String {
        String(localized: "chat:memoryStrip.updating", defaultValue: "Updating memory…", comment: "While update_memory runs.")
    }

    static var failedText: String {
        String(
            localized: "chat:memoryStrip.failed", defaultValue: "Couldn't update memory",
            comment: "The memory strip when update_memory failed.")
    }
}

enum UsedMemoriesText {
    /// "Used 2 memories · Work setup and Classical Music", with the titles as the run logged them.
    static func label(_ used: [UsedMemory]) -> String {
        let keys = used.map(\.key).formatted(.list(type: .and))
        let count = used.count
        // The catalog's plural picks the form; the branch only gives the hostless tests (no catalog) the right English.
        if count == 1 {
            return String(
                localized: "chat:usedMemories.label", defaultValue: "Used \(count) memory · \(keys)",
                comment: "Under a reply that read memory entries. The number is how many (plural); %@ lists their titles.")
        }
        return String(
            localized: "chat:usedMemories.label", defaultValue: "Used \(count) memories · \(keys)",
            comment: "Under a reply that read memory entries. The number is how many (plural); %@ lists their titles.")
    }

    static func prefill(key: String) -> String {
        String(
            localized: "chat:usedMemories.prefill", defaultValue: "The memory about '\(key)' is wrong: ",
            comment: "Put in the composer by \"This is wrong\". %@ is the memory entry's title.")
    }
}

/// One run's memory foot: the memories it read and where Undo left its changes. One object per run, so a line or a
/// strip redraws only when its own run's state changes.
@MainActor
@Observable
final class RunMemoryFoot {
    var used: [UsedMemory] = []
    var undo: MemoryUndoState = .idle
    var undoing = false
    /// The last Undo could not reach the computer; Undo is still offered.
    var undoFailed = false
    /// This client saw the run's `update_memory` call out (the desktop's `live`).
    var live = false
    /// Memory was re-read once after the run stopped with a call still out.
    @ObservationIgnored var rereadAfterStop = false
}

/// The memory foot of one chat screen: which memories each run used (from its stream and the usage route), the memory
/// list the strips and the sheet compare with, and Undo through the paired session.
@MainActor
@Observable
final class MemoryFootStore {
    struct Client: Sendable {
        let entries: @Sendable () async throws -> [MemoryEntry]
        let usage: @Sendable (_ chatId: String) async throws -> [String: [UsedMemory]]
        let undo: @Sendable (_ changes: [MemoryChange]) async throws -> MemoryUndoResult

        init(
            entries: @escaping @Sendable () async throws -> [MemoryEntry],
            usage: @escaping @Sendable (_ chatId: String) async throws -> [String: [UsedMemory]],
            undo: @escaping @Sendable (_ changes: [MemoryChange]) async throws -> MemoryUndoResult
        ) {
            self.entries = entries
            self.usage = usage
            self.undo = undo
        }

        init(apiClient: APIClient) {
            self.init(
                entries: { try await apiClient.get("/api/v1/memory") },
                usage: { chatId in
                    let raw: [String: [JSONValue]] = try await apiClient.get(
                        "/api/v1/memory/usage", query: [URLQueryItem(name: "chatId", value: chatId)])
                    return raw.mapValues { $0.compactMap(UsedMemory.init(json:)) }
                },
                undo: { changes in try await apiClient.post("/api/v1/memory/undo", body: MemoryUndoBody(changes: changes)) })
        }
    }

    /// The memory list as last read; nil until first read.
    private(set) var entries: [MemoryEntry]?
    @ObservationIgnored private var runs: [String: RunMemoryFoot] = [:]
    @ObservationIgnored private let client: Client
    /// Only the newest read lands: an older one finishing late must not put back what came before.
    @ObservationIgnored private var readGeneration = 0
    @ObservationIgnored private var firstRead: Task<Void, Never>?
    /// "This is wrong": the prefilled text, for the composer.
    @ObservationIgnored var onWrong: @MainActor (String) -> Void = { _ in }

    init(client: Client) {
        self.client = client
    }

    convenience init(apiClient: APIClient) {
        self.init(client: Client(apiClient: apiClient))
    }

    /// The run's foot; created empty on first read, so a view can subscribe before anything arrives.
    func run(_ runId: String) -> RunMemoryFoot {
        if let run = runs[runId] { return run }
        let run = RunMemoryFoot()
        runs[runId] = run
        return run
    }

    /// Drops the feet of runs the transcript no longer has (deleted on the computer, seen on a reload), so the store
    /// holds this chat's runs and no more.
    func prune(keeping runIds: Set<String>) {
        runs = runs.filter { runIds.contains($0.key) }
    }

    var keptRunIds: Set<String> { Set(runs.keys) }

    func applyUsed(runId: String, memories: [UsedMemory]) {
        let run = run(runId)
        if run.used != memories { run.used = memories }
    }

    /// The history's usage, grouped by run. A run the answer does not name keeps what its stream said.
    func loadUsage(chatId: String) async {
        guard let usage = try? await client.usage(chatId) else { return }
        for (runId, memories) in usage { applyUsed(runId: runId, memories: memories) }
    }

    /// Reads the memory list once, for the first strip that needs to compare with it.
    func loadEntriesIfNeeded() async {
        guard entries == nil else { return }
        if let firstRead { return await firstRead.value }
        let read = Task { await refreshEntries() }
        firstRead = read
        await read.value
        firstRead = nil
    }

    func refreshEntries() async {
        readGeneration += 1
        let generation = readGeneration
        guard let list = try? await client.entries(), generation == readGeneration, list != entries else { return }
        entries = list
    }

    /// An `update_memory` call just ended on this client's stream: its run is live, and a list already read is stale.
    func memoryChanged(inRun runId: String?) {
        if let runId { run(runId).live = true }
        guard entries != nil else { return }
        Task { await refreshEntries() }
    }

    /// Undo: posts the run's changes once. The computer reverts only what still reads as the run left it and reports
    /// the rest as skipped.
    func undo(runId: String, changes: [MemoryChange]) async {
        let run = run(runId)
        guard !run.undoing, run.undo == .idle else { return }
        run.undoing = true
        run.undoFailed = false
        do {
            run.undo = .after(try await client.undo(changes))
        } catch {
            if !(error is CancellationError) && (error as? URLError)?.code != .cancelled { run.undoFailed = true }
        }
        run.undoing = false
        // Whatever the computer did, the list read before may be out of date.
        await refreshEntries()
    }
}
