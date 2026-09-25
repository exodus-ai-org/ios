import Foundation
import Models
import NetworkingKit
import Observation
import SwiftUI
import Testing

@testable import ChatFeature

private func decode(_ json: String) -> ChatMessage {
    try! JSONDecoder().decode(ChatMessage.self, from: Data(json.utf8))
}

private func user(_ id: String) -> ChatMessage {
    decode(#"{"id":"\#(id)","runId":"\#(id)","role":"user","content":"q","timestamp":1}"#)
}

private func call(_ id: String, _ run: String, _ callId: String, _ name: String, _ arguments: String = "{}") -> ChatMessage {
    decode(
        #"{"id":"\#(id)","runId":"\#(run)","role":"assistant","content":[{"type":"toolCall","id":"\#(callId)","name":"\#(name)","arguments":\#(arguments)}],"stopReason":"toolUse","timestamp":2}"#
    )
}

private func result(
    _ id: String, _ run: String, _ callId: String, _ name: String, details: String, isError: Bool = false,
    content: String = #"[{"type":"text","text":"ok"}]"#
) -> ChatMessage {
    decode(
        #"{"id":"\#(id)","runId":"\#(run)","role":"toolResult","toolCallId":"\#(callId)","toolName":"\#(name)","content":\#(content),"details":\#(details),"isError":\#(isError),"timestamp":3}"#
    )
}

private func answer(_ id: String, _ run: String, _ text: String) -> ChatMessage {
    decode(
        #"{"id":"\#(id)","runId":"\#(run)","role":"assistant","content":[{"type":"text","text":"\#(text)"}],"stopReason":"stop","timestamp":4}"#
    )
}

private let search =
    #"[{"rank":1,"link":"https://example.com/a","title":"A","snippet":"a","media":[{"kind":"image","title":"I","url":"https://example.com/1.png","sourceUrl":"https://example.com/a"},{"kind":"video","title":"V","url":"https://example.com/v","sourceUrl":"https://example.com/a"}]}]"#

/// One settled run holding every card and foot item the transcript draws.
private let settledRun: [ChatMessage] = [
    user("u1"),
    call("a1", "u1", "k1", "terminal", #"{"command":"ls"}"#),
    result("t1", "u1", "k1", "terminal", details: #"{"command":"ls","cwd":"/tmp","exitCode":0,"stdout":"a","stderr":""}"#),
    call("a2", "u1", "k2", "read_file", #"{"path":"/a.md"}"#),
    result("t2", "u1", "k2", "read_file", details: #"{"path":"/a.md","content":"A","size":1}"#),
    call("a3", "u1", "k3", "write_file", #"{"path":"/b.md","content":"b","append":false}"#),
    result("t3", "u1", "k3", "write_file", details: #"{"path":"/b.md","bytes":1,"appended":false}"#),
    call("a4", "u1", "k4", "edit_file", #"{"path":"/c.swift","old_string":"let a = 1","new_string":"let a = 2"}"#),
    result("t4", "u1", "k4", "edit_file", details: #"{"path":"/c.swift","replacements":1,"linesBefore":3,"linesAfter":3}"#),
    call("a5", "u1", "k5", "weather", #"{"location":"Shanghai"}"#),
    result("t5", "u1", "k5", "weather", details: #"{"location":"Shanghai","current":{"tempC":"22","weatherCode":"2"},"forecast":[]}"#),
    call("a6", "u1", "k6", "image_generation", #"{"prompt":"A lighthouse"}"#),
    result(
        "t6", "u1", "k6", "image_generation",
        details: #"{"images":[{"mediaId":"a.png","chatId":"c1","mimeType":"image/png","width":1024,"height":1536}]}"#),
    call("a7", "u1", "k7", "map_itinerary", #"{"title":"Kyoto","days":[]}"#),
    result(
        "t7", "u1", "k7", "map_itinerary",
        details: #"{"type":"mapItinerary","title":"Kyoto","days":[{"label":"Day 1","places":[{"name":"A","lat":35,"lng":135.7}]}]}"#),
    call("a8", "u1", "k8", "computer_use", #"{"task":"Export","target":"Numbers"}"#),
    result(
        "t8", "u1", "k8", "computer_use",
        details: #"{"sessionId":"cu_1","outcome":"success","steps":3,"summary":"Exported."}"#,
        content: #"[{"type":"text","text":"Exported."},{"type":"image","data":"QUJD","mimeType":"image/png"}]"#),
    call("a9", "u1", "k9", "deep_research", #"{"subject":"Tea"}"#),
    result("t9", "u1", "k9", "deep_research", details: #"{"id":"dr_1","toolCallId":"k9"}"#),
    call("a10", "u1", "k10", "update_memory", #"{"instruction":"x"}"#),
    result(
        "t10", "u1", "k10", "update_memory",
        details:
            #"{"changes":[{"op":"create","id":"m2","before":null,"after":{"section":"profile","key":"Work","summary":"s","details":[],"isActive":true}}]}"#
    ),
    result("t11", "u1", "k11", "web_search", details: search),
    answer("b1", "u1", "Done 【1-source】"),
]

/// A later run, streaming: a live computer_use session and a growing answer.
private func streamingFrame(_ step: Int) -> [ChatMessage] {
    settledRun + [
        user("u2"),
        call("c1", "u2", "q1", "computer_use", #"{"task":"Open","target":"Notes"}"#),
        result(
            "r1", "u2", "q1", "computer_use",
            details: #"{"sessionId":"cu_2","step":\#(step),"action":"click","thumbnail":"f\#(step)"}"#, content: "[]"),
        answer("d1", "u2", String(repeating: "P", count: step)),
    ]
}

@MainActor
@Suite("Render guard: a settled turn holding every card stays put while a later turn streams")
struct CombinedRenderGuardTests {
    @Test("every card type in one settled turn: never rebuilt, its view equal, its foot stores untouched")
    func everyCardSettled() throws {
        var cache = RunGrouper.Cache()
        let first = RunGrouper.group(streamingFrame(1), cache: &cache)
        let built = cache.builtTurnCount
        guard case .assistantTurn(let settled)? = first.first(where: { $0.id == "run:u1" }) else {
            Issue.record("no settled turn")
            return
        }
        #expect(
            Set(settled.toolCards.map(\.toolName))
                == [
                    "terminal", "read_file", "write_file", "edit_file", "weather", "image_generation", "map_itinerary",
                    "computer_use", "deep_research",
                ])
        // Every registered card draws its own view: no settled card falls back to the generic one.
        for card in settled.toolCards {
            #expect(ToolCardRegistry.canDraw(card), "\(card.toolName) fell back to the generic card")
        }
        #expect(settled.foot.memoryUpdates.count == 1)
        #expect(!settled.foot.gallery.isEmpty)

        let approvals = RunApprovalStore(allowDelay: .zero) { _, _, _ in .allowed }
        let memory = MemoryFootStore(
            client: .init(entries: { [] }, usage: { _ in [:] }, undo: { _ in MemoryUndoResult(undone: [], skipped: []) }))
        let settledApprovals = approvals.list(for: "u1")
        let settledMemory = memory.run("u1")
        final class Flag: @unchecked Sendable { var raised = false }
        let touched = Flag()
        withObservationTracking {
            _ = settledApprovals.entries
            _ = settledMemory.used
            _ = settledMemory.undo
            _ = settledMemory.live
        } onChange: {
            touched.raised = true
        }

        let frames = ComputerUseFrameStore(decode: { _ in nil })
        var previous = first
        for step in 2...8 {
            let next = RunGrouper.group(streamingFrame(step), cache: &cache)
            frames.ingest(next)
            if step == 3 {
                approvals.apply(
                    .required(
                        ApprovalRequest(
                            runId: "u2", toolCallId: "q9", toolName: "terminal", summary: "cat ~/.ssh/id_rsa",
                            expiresAt: Date().addingTimeInterval(600))))
                memory.applyUsed(runId: "u2", memories: [UsedMemory(id: "m1", key: "Work", section: "profile")])
                memory.memoryChanged(inRun: "u2")
            }
            if step == 5 { approvals.apply(.resolved(runId: "u2", toolCallId: "q9", outcome: .denied)) }
            #expect(next.first { $0.id == "run:u1" } == previous.first { $0.id == "run:u1" })
            previous = next
        }
        #expect(cache.builtTurnCount == built + 7, "only the streaming turn is rebuilt per frame")
        #expect(!touched.raised, "the later run's approval and memory events reached the settled run's foot state")
        #expect(frames.keptSessions == ["q1"], "only the streaming run's session is recorded")

        guard case .assistantTurn(let after)? = previous.first(where: { $0.id == "run:u1" }) else {
            Issue.record("no settled turn after")
            return
        }
        let bar = TurnActions.bar(for: settled, isStreaming: false, canRegenerate: false)
        let lhs = AssistantTurnView(turn: settled, isStreaming: false, error: nil, actionBar: bar, regenerate: {})
        let rhs = AssistantTurnView(
            turn: after, isStreaming: false, error: nil, actionBar: TurnActions.bar(for: after, isStreaming: false, canRegenerate: false),
            regenerate: { print("new") }, showSources: { _, _ in print("new") })
        #expect(lhs == rhs)
    }
}
