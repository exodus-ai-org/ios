import Foundation
import Models
import NetworkingKit
import Observation
import Synchronization
import Testing

@testable import ChatFeature

private func snapshot(_ key: String, _ summary: String = "s", details: [String] = [], section: String = "topic")
    -> MemorySnapshot
{
    MemorySnapshot(section: section, key: key, summary: summary, details: details)
}

private let update = MemoryChange(
    op: .update, id: "m1", before: snapshot("Music", "old", details: ["a"]), after: snapshot("Music", "new", details: ["a", "b"]))
private let create = MemoryChange(op: .create, id: "m2", before: nil, after: snapshot("Work setup", section: "profile"))
private let delete = MemoryChange(op: .delete, id: "m3", before: snapshot("Alex", section: "person"), after: nil)
/// The same entry changed twice in one run: its title is listed once.
private let updateAgain = MemoryChange(
    op: .update, id: "m1", before: snapshot("Music", "new", details: ["a", "b"]), after: snapshot("Music", "newer"))

private func entry(_ change: MemoryChange) -> MemoryEntry {
    let after = change.after!
    return MemoryEntry(
        id: change.id, section: after.section, key: after.key, summary: after.summary, details: after.details,
        isActive: after.isActive)
}

private func done(_ id: String, _ changes: [MemoryChange]) -> MemoryUpdate {
    let data = try! JSONEncoder().encode(MemoryUndoBody(changes: changes))
    let json = try! JSONDecoder().decode(JSONValue.self, from: data)
    return MemoryUpdate(id: id, status: .succeeded, result: MemoryUpdateResult(json: json))
}

private func changes(_ updates: MemoryUpdate...) -> RunMemoryChanges { RunMemoryChanges(updates)! }

@Suite("Memory strip: state from the run's own messages")
struct MemoryStripRulesTests {
    @Test("no update_memory call is nothing; running, failed and the changes in call order otherwise")
    func derived() {
        #expect(RunMemoryChanges([]) == nil)
        let run = changes(done("k1", [update]), MemoryUpdate(id: "k2", status: .failed), done("k3", [create, delete]))
        #expect(run.running == false)
        #expect(run.failed)
        #expect(run.changes.map(\.id) == ["m1", "m2", "m3"])
        #expect(changes(done("k1", [update]), MemoryUpdate(id: "k2", status: .pending)).running)
    }

    @Test("running while the run streams; after Stop with the call out and nothing changed, nothing is said")
    func runningAndStopped() {
        let out = changes(MemoryUpdate(id: "k1", status: .pending))
        #expect(MemoryStripRules.display(out, active: true, undo: .idle, live: false, entries: nil) == .running)
        #expect(MemoryStripRules.display(out, active: false, undo: .idle, live: false, entries: nil) == nil)
        let outAfterDone = changes(done("k1", [update]), MemoryUpdate(id: "k2", status: .pending))
        #expect(MemoryStripRules.display(outAfterDone, active: true, undo: .idle, live: true, entries: nil) == .running)
        #expect(
            MemoryStripRules.display(outAfterDone, active: false, undo: .idle, live: true, entries: nil)
                == .changes(.updated(keys: ["Music"]), warning: false, undoable: true))
    }

    @Test("failed alone reads failed; a run that needed no change says nothing; failed beside a change reads partly")
    func failedAndPartly() {
        #expect(
            MemoryStripRules.display(
                changes(MemoryUpdate(id: "k1", status: .failed)), active: false, undo: .idle, live: false, entries: nil)
                == .failed)
        #expect(MemoryStripRules.display(changes(done("k1", [])), active: false, undo: .idle, live: false, entries: nil) == nil)
        let partly = changes(done("k1", [update, updateAgain, create]), MemoryUpdate(id: "k2", status: .failed))
        #expect(
            MemoryStripRules.display(partly, active: false, undo: .idle, live: true, entries: nil)
                == .changes(.partlyUpdated(keys: ["Music", "Work setup"]), warning: true, undoable: true))
        #expect(
            MemoryStripRules.display(partly, active: false, undo: .undone, live: true, entries: nil)
                == .changes(.undone, warning: false, undoable: false))
    }

    @Test("after a reload: nothing still as the run left it reads stale; one entry still so keeps Undo")
    func stale() {
        let run = changes(done("k1", [update, create, delete]))
        let asLeft = [entry(update), entry(create)]
        #expect(
            MemoryStripRules.display(run, active: false, undo: .idle, live: false, entries: asLeft)
                == .changes(.updated(keys: ["Music", "Work setup", "Alex"]), warning: false, undoable: true))
        let editedSince = [
            MemoryEntry(id: "m1", section: "topic", key: "Music", summary: "edited on the computer"),
            MemoryEntry(id: "m3", section: "person", key: "Alex", summary: "s"),
        ]
        #expect(
            MemoryStripRules.display(run, active: false, undo: .idle, live: false, entries: editedSince)
                == .changes(.stale, warning: false, undoable: false))
        #expect(MemoryStripRules.stillAsLeft(delete, in: asLeft), "a deleted entry still missing is as the run left it")
        #expect(!MemoryStripRules.stillAsLeft(delete, in: editedSince))
        #expect(
            MemoryStripRules.display(run, active: false, undo: .idle, live: false, entries: nil)
                == .changes(.updated(keys: ["Music", "Work setup", "Alex"]), warning: false, undoable: true),
            "until the list is read, nothing is stale")
        #expect(
            MemoryStripRules.display(run, active: false, undo: .idle, live: true, entries: editedSince)
                == .changes(.updated(keys: ["Music", "Work setup", "Alex"]), warning: false, undoable: true),
            "a run seen live keeps Undo while the list still holds what came before")
    }

    @Test("the entry's current state compares field by field; an inactive entry is not the active snapshot")
    func snapshotCompare() {
        var current = entry(update)
        #expect(MemoryStripRules.stillAsLeft(update, in: [current]))
        current.isActive = false
        #expect(!MemoryStripRules.stillAsLeft(update, in: [current]))
        current = entry(update)
        current.details = ["b", "a"]
        #expect(!MemoryStripRules.stillAsLeft(update, in: [current]))
    }

    @Test("Undo's answer: nothing undone is stale, nothing skipped undone, else partial with both counts")
    func undoAnswer() {
        #expect(MemoryUndoState.after(MemoryUndoResult(undone: [], skipped: ["m1"])) == .stale)
        #expect(MemoryUndoState.after(MemoryUndoResult(undone: ["m1", "m2"], skipped: [])) == .undone)
        #expect(MemoryUndoState.after(MemoryUndoResult(undone: ["m1", "m2"], skipped: ["m3"])) == .partial(undone: 2, skipped: 1))
    }

    @Test("the strip's words, the used line's and the composer's prefill, in English")
    func texts() {
        #expect(MemoryStripRules.text(.updated(keys: ["Music"])) == "Memory updated · Music")
        #expect(MemoryStripRules.text(.partial(undone: 2, skipped: 1)) == "Undid 2 · 1 changed since and kept")
        #expect(MemoryStripRules.text(.stale) == "Undone or changed since")
        let one = [UsedMemory(id: "m1", key: "Music", section: "topic")]
        #expect(UsedMemoriesText.label(one) == "Used 1 memory · Music")
        let two = one + [UsedMemory(id: "m2", key: "Work setup", section: "profile")]
        #expect(UsedMemoriesText.label(two).hasPrefix("Used 2 memories · Music"))
        #expect(UsedMemoriesText.label(two).hasSuffix("Work setup"))
        #expect(UsedMemoriesText.prefill(key: "Music") == "The memory about 'Music' is wrong: ")
    }

    @Test("a used memory's row: its title as it reads now, and Wrong? on every entry but a deleted one")
    func usedMemoryRow() {
        let music = UsedMemory(id: "m1", key: "Music", section: "topic")
        let gone = UsedMemory(id: "m9", key: "Gone", section: "topic")
        // The list not read yet: shown as logged, and still fixable.
        let unread = UsedMemoryRowState(memory: music, entries: nil)
        #expect(unread.key == "Music" && !unread.deleted && unread.offersFix && unread.current == nil)
        let entries = [MemoryEntry(id: "m1", section: "topic", key: "Classical music", summary: "Goldberg")]
        let renamed = UsedMemoryRowState(memory: music, entries: entries)
        #expect(renamed.key == "Classical music" && renamed.current?.summary == "Goldberg" && renamed.offersFix)
        let deleted = UsedMemoryRowState(memory: gone, entries: entries)
        #expect(deleted.key == "Gone" && deleted.deleted && !deleted.offersFix)
    }
}

/// A stand-in computer for the store: counts calls, answers after a delay.
private final class FakeMemoryComputer: Sendable {
    let undoCalls = Mutex<[[MemoryChange]]>([])
    let entryReads = Mutex(0)
    let undoResult: Mutex<Result<MemoryUndoResult, URLError>>
    let entries: Mutex<[MemoryEntry]>
    let usage: Mutex<[String: [UsedMemory]]>

    init(
        undo: Result<MemoryUndoResult, URLError> = .success(MemoryUndoResult(undone: ["m1"], skipped: [])),
        entries: [MemoryEntry] = [], usage: [String: [UsedMemory]] = [:]
    ) {
        undoResult = Mutex(undo)
        self.entries = Mutex(entries)
        self.usage = Mutex(usage)
    }

    @MainActor
    func store(readDelay: @escaping @Sendable (Int) -> Duration = { _ in .milliseconds(20) }) -> MemoryFootStore {
        MemoryFootStore(
            client: .init(
                entries: { [self] in
                    let read = entryReads.withLock { $0 += 1; return $0 }
                    let list = entries.withLock { $0 }
                    try await Task.sleep(for: readDelay(read))
                    return list
                },
                usage: { [self] _ in usage.withLock { $0 } },
                undo: { [self] changes in
                    undoCalls.withLock { $0.append(changes) }
                    try await Task.sleep(for: .milliseconds(40))
                    return try undoResult.withLock { $0 }.get()
                }))
    }
}

@MainActor
@Suite("Memory foot store: Undo, usage and the list")
struct MemoryFootStoreTests {
    @Test("Undo posts the run's changes once for a double tap, settles on the answer, then re-reads the list")
    func undoOnce() async {
        let computer = FakeMemoryComputer()
        let store = computer.store()
        async let first: Void = store.undo(runId: "u1", changes: [update, create])
        async let second: Void = store.undo(runId: "u1", changes: [update, create])
        _ = await (first, second)
        #expect(computer.undoCalls.withLock { $0.map { $0.map(\.id) } } == [["m1", "m2"]])
        #expect(store.run("u1").undo == .undone)
        #expect(store.run("u1").undoing == false)
        #expect(computer.entryReads.withLock { $0 } == 1)
        await store.undo(runId: "u1", changes: [update])
        #expect(computer.undoCalls.withLock { $0.count } == 1, "an undone run sends nothing more")
    }

    @Test("skipped entries read as the desktop reports them; an Undo that cannot reach the computer keeps Undo")
    func partialAndFailure() async {
        let partial = FakeMemoryComputer(undo: .success(MemoryUndoResult(undone: ["m2"], skipped: ["m1"])))
        let store = partial.store()
        await store.undo(runId: "u1", changes: [update, create])
        #expect(store.run("u1").undo == .partial(undone: 1, skipped: 1))

        let offline = FakeMemoryComputer(undo: .failure(URLError(.notConnectedToInternet)))
        let other = offline.store()
        await other.undo(runId: "u1", changes: [update])
        #expect(other.run("u1").undo == .idle)
        #expect(other.run("u1").undoFailed)
        offline.undoResult.withLock { $0 = .success(MemoryUndoResult(undone: ["m1"], skipped: [])) }
        await other.undo(runId: "u1", changes: [update])
        #expect(other.run("u1").undo == .undone)
        #expect(other.run("u1").undoFailed == false)
    }

    @Test("history usage fills its runs; a run it does not name keeps what its stream said")
    func usageMerge() async {
        let music = UsedMemory(id: "m1", key: "Music", section: "topic")
        let work = UsedMemory(id: "m2", key: "Work setup", section: "profile")
        let computer = FakeMemoryComputer(usage: ["r1": [music]])
        let store = computer.store()
        store.applyUsed(runId: "live", memories: [work])
        await store.loadUsage(chatId: "c1")
        #expect(store.run("r1").used == [music])
        #expect(store.run("live").used == [work])
    }

    @Test("a reload keeps the feet of the runs still in the transcript and drops the rest")
    func pruneToTranscript() {
        let store = FakeMemoryComputer().store()
        store.applyUsed(runId: "r1", memories: [UsedMemory(id: "m1", key: "Music", section: "topic")])
        _ = store.run("r2")
        _ = store.run("gone")
        store.prune(keeping: ["r1", "r2", "r3"])
        #expect(store.keptRunIds == ["r1", "r2"])
        #expect(store.run("r1").used.map(\.id) == ["m1"])
    }

    @Test("the list is read once however many strips ask at the same time")
    func firstReadOnce() async {
        let computer = FakeMemoryComputer(entries: [entry(update)])
        let store = computer.store()
        async let a: Void = store.loadEntriesIfNeeded()
        async let b: Void = store.loadEntriesIfNeeded()
        async let c: Void = store.loadEntriesIfNeeded()
        _ = await (a, b, c)
        await store.loadEntriesIfNeeded()
        #expect(computer.entryReads.withLock { $0 } == 1)
        #expect(store.entries == [entry(update)])
    }

    @Test("a slow older read landing after a newer one does not put back what came before")
    func newestReadWins() async {
        let computer = FakeMemoryComputer(entries: [MemoryEntry(id: "m1", section: "topic", key: "Old")])
        let store = computer.store { read in read == 1 ? .milliseconds(200) : .milliseconds(10) }
        let slow = Task { await store.refreshEntries() }
        while computer.entryReads.withLock({ $0 }) < 1 { await Task.yield() }
        computer.entries.withLock { $0 = [MemoryEntry(id: "m1", section: "topic", key: "New")] }
        await store.refreshEntries()
        await slow.value
        #expect(store.entries?.map(\.key) == ["New"])
    }

    @Test("update_memory ending marks its run live; a list already read is read again, an unread one is not")
    func memoryChanged() async throws {
        let computer = FakeMemoryComputer(entries: [entry(update)])
        let store = computer.store()
        store.memoryChanged(inRun: "u1")
        #expect(store.run("u1").live)
        try await Task.sleep(for: .milliseconds(80))
        #expect(computer.entryReads.withLock { $0 } == 0)
        await store.refreshEntries()
        store.memoryChanged(inRun: nil)
        let deadline = ContinuousClock.now.advanced(by: .seconds(5))
        while computer.entryReads.withLock({ $0 }) < 2, ContinuousClock.now < deadline { try await Task.sleep(for: .milliseconds(5)) }
        #expect(computer.entryReads.withLock { $0 } == 2)
    }
}

@MainActor
@Suite("Memory foot: a run's line and strip redraw for their own run only")
struct MemoryFootRenderTests {
    @Test("another run's used memories or Undo do not invalidate what this run's views read; its own do")
    func perRunObservation() async {
        let computer = FakeMemoryComputer()
        let store = computer.store()
        let music = [UsedMemory(id: "m1", key: "Music", section: "topic")]
        store.applyUsed(runId: "A", memories: music)
        let runA = store.run("A")
        let fired = Mutex(0)
        withObservationTracking {
            _ = (runA.used, runA.undo, runA.undoing, runA.undoFailed, runA.live)
        } onChange: {
            fired.withLock { $0 += 1 }
        }
        store.applyUsed(runId: "B", memories: [UsedMemory(id: "m2", key: "Work", section: "profile")])
        await store.undo(runId: "B", changes: [update])
        store.memoryChanged(inRun: "B")
        store.applyUsed(runId: "A", memories: music)
        #expect(fired.withLock { $0 } == 0, "the same memories again for A change nothing")
        store.applyUsed(runId: "A", memories: [])
        #expect(fired.withLock { $0 } == 1)
    }

    @Test("a streaming frame of a later run leaves a settled run's turn, and so its strip's input, equal")
    func settledStripInput() {
        let settled = AssistantTurn(runId: "A", body: "Done.", foot: RunFoot(memoryUpdates: [done("k1", [update])]))
        let lhs = AssistantTurnView(turn: settled, isStreaming: false, error: nil, regenerate: {})
        let rhs = AssistantTurnView(turn: settled, isStreaming: false, error: nil, regenerate: { print("new") })
        #expect(lhs == rhs)
        #expect(RunMemoryChanges(settled.foot.memoryUpdates)?.changes == [update])
    }
}

private final class MemoryURLProtocol: URLProtocol, @unchecked Sendable {
    nonisolated(unsafe) static var handler: (@Sendable (URLRequest) -> (Int, String))?
    nonisolated(unsafe) static var seen: [(method: String, path: String, query: String?, body: Data)] = []

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        var body = request.httpBody ?? Data()
        if body.isEmpty, let stream = request.httpBodyStream {
            stream.open()
            var buffer = [UInt8](repeating: 0, count: 4096)
            while stream.hasBytesAvailable {
                let read = stream.read(&buffer, maxLength: buffer.count)
                if read <= 0 { break }
                body.append(buffer, count: read)
            }
            stream.close()
        }
        Self.seen.append((request.httpMethod ?? "GET", request.url?.path ?? "", request.url?.query, body))
        let (status, text) = Self.handler?(request) ?? (500, "")
        let response = HTTPURLResponse(url: request.url!, statusCode: status, httpVersion: "HTTP/1.1", headerFields: nil)!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: Data(text.utf8))
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {}

    static func client(_ suite: String) -> APIClient {
        let defaults = UserDefaults(suiteName: suite)!
        defaults.removePersistentDomain(forName: suite)
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [MemoryURLProtocol.self]
        return APIClient(session: URLSession(configuration: configuration), serverConfig: ServerConfigStore(userDefaults: defaults))
    }
}

@MainActor
@Suite("Memory foot: over the network", .serialized)
struct MemoryFootNetworkTests {
    @Test("Undo is POST /api/v1/memory/undo {changes} with explicit nulls, as update_memory reported them")
    func undoRoute() async throws {
        MemoryURLProtocol.seen = []
        MemoryURLProtocol.handler = { request in
            request.url?.path == "/api/v1/memory/undo" ? (200, #"{"undone":["m2"],"skipped":["m3"]}"#) : (200, "[]")
        }
        let store = MemoryFootStore(apiClient: MemoryURLProtocol.client(#function))
        await store.undo(runId: "u1", changes: [create, delete])
        #expect(store.run("u1").undo == .partial(undone: 1, skipped: 1))
        let sent = try #require(MemoryURLProtocol.seen.first)
        #expect(sent.method == "POST" && sent.path == "/api/v1/memory/undo")
        let body = try #require(try JSONSerialization.jsonObject(with: sent.body) as? [String: Any])
        let changes = try #require(body["changes"] as? [[String: Any]])
        #expect(changes.count == 2)
        #expect(changes[0]["op"] as? String == "create" && changes[0]["id"] as? String == "m2")
        #expect(changes[0]["before"] is NSNull, "a create's before is sent as null, not left out")
        let after = try #require(changes[0]["after"] as? [String: Any])
        #expect(Set(after.keys) == ["section", "key", "summary", "details", "isActive"])
        #expect(changes[1]["after"] is NSNull)
        #expect(MemoryURLProtocol.seen.map(\.path) == ["/api/v1/memory/undo", "/api/v1/memory"])
        MemoryURLProtocol.handler = nil
    }

    @Test("usage is GET /api/v1/memory/usage?chatId= grouped by run; an unreadable entry costs only itself")
    func usageRoute() async throws {
        MemoryURLProtocol.seen = []
        MemoryURLProtocol.handler = { _ in
            (200, #"{"r1":[{"id":"m1","key":"Music","section":"topic"},{"key":"no id"}],"r2":[]}"#)
        }
        let store = MemoryFootStore(apiClient: MemoryURLProtocol.client(#function))
        await store.loadUsage(chatId: "c-1")
        #expect(store.run("r1").used == [UsedMemory(id: "m1", key: "Music", section: "topic")])
        #expect(store.run("r2").used.isEmpty)
        let sent = try #require(MemoryURLProtocol.seen.first)
        #expect(sent.method == "GET" && sent.path == "/api/v1/memory/usage" && sent.query == "chatId=c-1")
        MemoryURLProtocol.handler = nil
    }

    @Test("the list is GET /api/v1/memory; a failed read leaves what was there")
    func listRoute() async {
        MemoryURLProtocol.seen = []
        MemoryURLProtocol.handler = { _ in
            (200, #"[{"id":"m1","userId":"local","section":"topic","key":"Music","summary":"s","details":[],"isActive":null}]"#)
        }
        let store = MemoryFootStore(apiClient: MemoryURLProtocol.client(#function))
        await store.refreshEntries()
        #expect(store.entries == [MemoryEntry(id: "m1", section: "topic", key: "Music", summary: "s")])
        MemoryURLProtocol.handler = { _ in (500, #"{"type":"error","error":{"code":"X","message":"down"}}"#) }
        await store.refreshEntries()
        #expect(store.entries?.count == 1)
        #expect(MemoryURLProtocol.seen.map(\.path) == ["/api/v1/memory", "/api/v1/memory"])
        MemoryURLProtocol.handler = nil
    }
}
