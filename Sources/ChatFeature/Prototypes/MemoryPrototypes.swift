#if DEBUG
import Foundation
import Models
import SwiftUI

/// The run's foot as the transcript draws it: the real `MemoryChangeStrip` and `UsedMemoriesLine` over a stand-in
/// computer whose Undo takes a second and reverts everything. `-CardPrototypesMemorySheet` opens the used-memories
/// sheet on launch, for screenshots.
struct ProtoMemorySection: View {
    @State private var store = Self.makeStore()
    @State private var composer = ""
    @State private var sheetOnLaunch = ProcessInfo.processInfo.arguments.contains("-CardPrototypesMemorySheet")

    private static let changes = ProtoFixtures.memoryChanges

    private static func result(_ changes: [MemoryChange]) -> MemoryUpdateResult? {
        let data = (try? JSONEncoder().encode(["changes": changes])) ?? Data()
        return (try? JSONDecoder().decode(JSONValue.self, from: data)).flatMap(MemoryUpdateResult.init(json:))
    }

    private static func done(_ id: String, _ changes: [MemoryChange]) -> MemoryUpdate {
        MemoryUpdate(id: id, status: .succeeded, result: result(changes))
    }

    private static func makeStore() -> MemoryFootStore {
        let store = MemoryFootStore(
            client: .init(
                entries: { ProtoFixtures.currentMemories },
                usage: { _ in [:] },
                undo: { changes in
                    try await Task.sleep(for: .seconds(1))
                    return MemoryUndoResult(undone: changes.map(\.id), skipped: [])
                }))
        store.applyUsed(runId: "used3", memories: ProtoFixtures.usedMemories)
        store.applyUsed(runId: "used1", memories: [ProtoFixtures.usedMemories[0]])
        store.run("undone").undo = .undone
        store.run("partial").undo = .partial(undone: 2, skipped: 1)
        store.run("undoFailed").undoFailed = true
        return store
    }

    /// A change the entry no longer reads as: the stale strip after a reload.
    private static var editedSince: MemoryChange {
        let change = changes[0]
        let after = MemorySnapshot(section: "topic", key: "Classical Music", summary: "Edited on the computer since.", details: [])
        return MemoryChange(op: .update, id: change.id, before: change.before, after: after)
    }

    private func strip(
        _ runId: String, _ updates: [MemoryUpdate], active: Bool = false, startsOpen: Bool = false
    ) -> some View {
        MemoryChangeStrip(
            runId: runId, changes: RunMemoryChanges(updates)!, active: active, run: store.run(runId), store: store,
            startsOpen: startsOpen)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 28) {
            UserBubble(text: "I've started learning the Goldberg Variations. Also, forget Alex — I changed jobs.")
            ProtoInReply(state: "update_memory · running") {
                strip("running", [MemoryUpdate(id: "k1", status: .pending)], active: true)
            }
            ProtoInReply(
                state: "Done (tap the line to open; Undo reverts after a second)",
                answer: "Noted — I've updated what I know about your music and removed Alex."
            ) {
                strip("done", [Self.done("k1", Self.changes)])
            }
            ProtoInReply(state: "Done · opened (before → after)") {
                strip("opened", [Self.done("k1", Self.changes)], startsOpen: true)
            }
            ProtoInReply(state: "Partly updated (one call failed, one applied)") {
                strip("partly", [Self.done("k1", [Self.changes[0]]), MemoryUpdate(id: "k2", status: .failed)])
            }
            ProtoInReply(state: "Undone") { strip("undone", [Self.done("k1", Self.changes)]) }
            ProtoInReply(state: "Undo partly applied") { strip("partial", [Self.done("k1", Self.changes)]) }
            ProtoInReply(state: "Undone or changed since (after a reload)") {
                strip("stale", [Self.done("k1", [Self.editedSince])])
            }
            ProtoInReply(state: "Undo could not reach the computer") {
                strip("undoFailed", [Self.done("k1", Self.changes)])
            }
            ProtoInReply(state: "Failed") { strip("failed", [MemoryUpdate(id: "k1", status: .failed)]) }
            ProtoInReply(state: "Stopped with the call out: nothing to say") {
                strip("stopped", [MemoryUpdate(id: "k1", status: .pending)])
            }

            UserBubble(text: "Which laptop should I use for the trip?")
            ProtoInReply(state: "Used memories (tap: the sheet; \"This is wrong\" fills the composer)") {
                UsedMemoriesLine(run: store.run("used3"), store: store)
            }
            ProtoInReply(state: "One memory") { UsedMemoriesLine(run: store.run("used1"), store: store) }
            ProtoInReply(state: "What the sheet lists (drawn in place; the deleted entry greyed)") {
                VStack(alignment: .leading, spacing: 18) {
                    ForEach(ProtoFixtures.usedMemories) { memory in
                        UsedMemoryRow(memory: memory, entries: store.entries) { composer = UsedMemoriesText.prefill(key: $0) }
                    }
                }
                .padding(16)
                .protoCard()
            }
            ProtoInReply(state: "The composer now reads") {
                Text(verbatim: composer.isEmpty ? "—" : composer).font(.footnote.monospaced())
            }
        }
        .environment(\.memoryFoot, store)
        .environment(\.openMemorySettings, OpenMemorySettingsAction { composer = "Settings → Memory would open" })
        .task {
            store.onWrong = { composer = $0 }
            await store.refreshEntries()
        }
        .sheet(isPresented: $sheetOnLaunch) {
            UsedMemoriesSheet(used: ProtoFixtures.usedMemories, store: store, opensSettings: true) { _ in
                sheetOnLaunch = false
            }
        }
    }
}
#endif
