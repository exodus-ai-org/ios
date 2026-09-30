#if DEBUG
import Foundation
import Models
import SwiftUI

/// Regenerate groups drawn by the real transcript rows from desktop-shaped rows: two answers compared, a chosen one
/// with its other version (swappable, then locked by a later message), and an older desktop's rows with no attempts.
/// Use this one and Use this instead act locally. `-CardPrototypesCompareSheet` opens the other version at launch.
struct ProtoCompareSection: View {
    @State private var comparing = Self.comparingRows
    @State private var chosen = Self.chosenRows
    @State private var version: OtherVersion?
    @State private var versionOwner: Int?

    private static let opensSheet = ProcessInfo.processInfo.arguments.contains("-CardPrototypesCompareSheet")

    var body: some View {
        VStack(alignment: .leading, spacing: 28) {
            ProtoStateTag(text: "Comparing: the question once, Answer 1 and Answer 2, each with Use this one")
            rows(comparing, owner: 0)
            ProtoStateTag(text: "Chosen: one answer and a quiet link to the other version (swap allowed)")
            rows(chosen, owner: 1)
            ProtoStateTag(text: "Chosen, then a later message: the other version opens without Use this instead")
            rows(Self.lockedRows, owner: 2)
            ProtoStateTag(text: "An older desktop: no attempt columns, every run shown as before")
            rows(Self.olderRows, owner: 3)
        }
        .sheet(item: $version) { version in
            OtherVersionSheet(version: version) {
                if versionOwner == 1, let next = RunAttempts.choose(chosen, runId: version.id) { chosen = next }
            }
        }
        .task {
            guard Self.opensSheet else { return }
            try? await Task.sleep(for: .milliseconds(400))
            open("r2", in: chosen, owner: 1)
        }
    }

    private func rows(_ messages: [ChatMessage], owner: Int) -> some View {
        var cache = RunGrouper.Cache()
        let segments = RunGrouper.group(messages, cache: &cache)
        return VStack(alignment: .leading, spacing: 24) {
            TranscriptRows(
                segments: segments, streamingTurnId: nil, showsTypingIndicator: false, liveError: nil,
                actions: TranscriptActions(
                    regenerableTurnId: nil, regenerate: {}, showSources: { _, _ in }, canChoose: owner == 0,
                    choose: { runId in
                        if owner == 0, let next = RunAttempts.choose(comparing, runId: runId) { comparing = next }
                    },
                    showOtherVersion: { runId in open(runId, in: messages, owner: owner) }))
        }
    }

    private func open(_ runId: String, in messages: [ChatMessage], owner: Int) {
        let rows = messages.filter { $0.role != "user" && $0.runId == runId }
        var cache = RunGrouper.Cache()
        let canSwap = RunGrouper.group(messages, cache: &cache).contains { segment in
            if case .assistantTurn(let turn) = segment, case .chosen(let others, let canSwap)? = turn.attempt {
                canSwap && others.contains(runId)
            } else {
                false
            }
        }
        versionOwner = owner
        version = OtherVersion(turn: RunGrouper.buildTurn(runId: runId, messages: rows), canSwap: canSwap)
    }

    private static func row(_ json: String) -> ChatMessage {
        ChatHistoryRows.uiMessages(from: [try! JSONDecoder().decode(ChatMessage.self, from: Data(json.utf8))])[0]
    }

    private static func user(_ id: String, _ text: String, alternateOf: String?, attempt: String?) -> ChatMessage {
        let alternate = alternateOf.map { "\"\($0)\"" } ?? "null"
        let state = attempt.map { "\"\($0)\"" } ?? "null"
        return row(
            #"{"id":"\#(id)","runId":"\#(id)","chatId":"c","role":"user","content":"\#(text)","alternateOf":\#(alternate),"attempt":\#(state),"createdAt":"2026-09-26T09:00:00.000Z"}"#
        )
    }

    private static func answer(_ id: String, _ run: String, _ text: String) -> ChatMessage {
        row(
            #"{"id":"\#(id)","runId":"\#(run)","chatId":"c","role":"assistant","content":[{"type":"text","text":"\#(text)"}],"stopReason":"stop","durationMs":4200,"alternateOf":null,"attempt":null,"createdAt":"2026-09-26T09:00:05.000Z"}"#
        )
    }

    private static let question = "Suggest a name for a small coffee shop by the river."
    private static let first =
        "**Riverbend Roasters** — warm and local, and it tells people where to find you.\\n\\nIf you want something shorter: *Bend*."
    private static let second =
        "A few that play on the water:\\n\\n- **Current Coffee**\\n- **The Eddy**\\n- **Slow Water Café**\\n\\n*The Eddy* is the easiest to remember."

    static let comparingRows = [
        user("r1", question, alternateOf: nil, attempt: "comparing"), answer("a1", "r1", first),
        user("r2", question, alternateOf: "r1", attempt: "comparing"), answer("a2", "r2", second),
    ]

    static let chosenRows = [
        user("r0", question, alternateOf: "r1", attempt: "hidden"),
        user("r1", question, alternateOf: nil, attempt: "chosen"), answer("a1", "r1", first),
        user("r2", question, alternateOf: "r1", attempt: "folded"), answer("a2", "r2", second),
    ]

    static let lockedRows =
        chosenRows + [
            user("r3", "Which one would work best on a sign?", alternateOf: nil, attempt: nil),
            answer("a3", "r3", "*Riverbend Roasters* — it reads well from across the street."),
        ]

    static let olderRows: [ChatMessage] = [
        try! JSONDecoder().decode(
            ChatMessage.self, from: Data(#"{"id":"o1","runId":"o1","role":"user","content":"\#(question)","timestamp":1}"#.utf8)),
        try! JSONDecoder().decode(
            ChatMessage.self,
            from: Data(#"{"id":"b1","runId":"o1","role":"assistant","content":[{"type":"text","text":"\#(first)"}],"stopReason":"stop","timestamp":2}"#.utf8)),
        try! JSONDecoder().decode(
            ChatMessage.self, from: Data(#"{"id":"o2","runId":"o2","role":"user","content":"\#(question)","timestamp":3}"#.utf8)),
        try! JSONDecoder().decode(
            ChatMessage.self,
            from: Data(#"{"id":"b2","runId":"o2","role":"assistant","content":[{"type":"text","text":"\#(second)"}],"stopReason":"stop","timestamp":4}"#.utf8)),
    ]
}
#endif
