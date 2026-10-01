import Foundation
import MarkdownKit
import Models
import SwiftUI
import Testing
import UIKit

@testable import ChatFeature

private func decode(_ json: String) -> ChatMessage {
    try! JSONDecoder().decode(ChatMessage.self, from: Data(json.utf8))
}

private func value(_ json: String) -> JSONValue {
    try! JSONDecoder().decode(JSONValue.self, from: Data(json.utf8))
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
    text: String = "ok"
) -> ChatMessage {
    decode(
        #"{"id":"\#(id)","runId":"\#(run)","role":"toolResult","toolCallId":"\#(callId)","toolName":"\#(name)","content":[{"type":"text","text":"\#(text)"}],"details":\#(details),"isError":\#(isError),"timestamp":3}"#
    )
}

private func answer(_ id: String, _ run: String, _ text: String) -> ChatMessage {
    decode(
        #"{"id":"\#(id)","runId":"\#(run)","role":"assistant","content":[{"type":"text","text":"\#(text)"}],"stopReason":"stop","timestamp":4}"#
    )
}

private func turns(_ segments: [Segment]) -> [AssistantTurn] {
    segments.compactMap { if case .assistantTurn(let turn) = $0 { turn } else { nil } }
}

private func group(_ messages: [ChatMessage]) -> [AssistantTurn] {
    var cache = RunGrouper.Cache()
    return turns(RunGrouper.group(messages, cache: &cache))
}

private let terminalDetails = #"{"command":"ls","cwd":"/tmp","exitCode":0,"stdout":"a","stderr":""}"#
private let weatherDetails = #"{"location":"Shanghai","current":{"tempC":"22","weatherCode":"2"},"forecast":[]}"#
private let mapDetails =
    #"{"type":"mapItinerary","title":"Kyoto","days":[{"label":"Day 1","places":[{"name":"A","lat":35,"lng":135.7},{"name":"B","lat":35.01,"lng":135.71},{"name":"C"}]}],"notice":{"level":"warning","message":"Key expired"}}"#
private let memoryDetails =
    #"{"changes":[{"op":"create","id":"m2","before":null,"after":{"section":"profile","key":"Work setup","summary":"s","details":[],"isActive":true}}]}"#
private let searchDetails =
    #"[{"rank":1,"link":"https://example.com/a","title":"A","snippet":"a","media":[{"kind":"image","title":"I","url":"https://img.invalid/1.png","sourceUrl":"https://example.com/a"},{"kind":"video","title":"V","url":"https://v.invalid/1","sourceUrl":"https://example.com/a"},{"kind":"gif","url":"https://x.invalid"}]}]"#

@Suite("Tool cards: content is decoded once, when the turn is built")
struct ToolCardContentTests {
    @Test("a card carries its decoded result and its call's arguments")
    func decodedAtBuild() throws {
        let turn = try #require(
            group([
                user("u1"),
                call("a1", "u1", "k1", "terminal", #"{"command":"ls"}"#),
                result("t1", "u1", "k1", "terminal", details: terminalDetails),
                call("a2", "u1", "k2", "weather", #"{"location":"Shanghai"}"#),
                result("t2", "u1", "k2", "weather", details: weatherDetails),
                result("t3", "u1", "k3", "weather", details: #"{"forecast":"sunny"}"#),
                result("t4", "u1", "k4", "github_create_issue", details: #"{"n":1}"#),
            ]).first)
        #expect(turn.toolCards.count == 4)
        #expect(turn.toolCards[0].content.terminal?.command == "ls")
        #expect(turn.toolCards[0].arguments == .object(["command": .string("ls")]))
        #expect(turn.toolCards[1].content.weather?.forecast?.location == "Shanghai")
        #expect(turn.toolCards[1].arguments == .object(["location": .string("Shanghai")]))
        #expect(turn.toolCards[2].content == .undecodable)
        #expect(turn.toolCards[2].arguments == nil)
        #expect(turn.toolCards[3].content == .untyped)
    }

    @Test("every tool with a typed shape maps to its case; arguments decode beside the result")
    func everyShape() {
        func content(_ name: String, _ arguments: String?, _ details: String) -> ToolCardContent {
            ToolCard(id: "t", toolName: name, kind: .generic, payload: value(details), arguments: arguments.map(value))
                .content
        }
        let read = content("read_file", #"{"path":"/a"}"#, #"{"path":"/a","content":"x","size":1}"#).readFile
        #expect(read?.path == "/a")
        #expect(read?.state == .read(FilePreview("x"), size: 1))
        let write = content("write_file", #"{"path":"/a","content":"x","append":true}"#, #"{"path":"/a","bytes":1,"appended":true}"#)
        #expect(write.writeFile?.state == .written(bytes: 1, appended: true))
        #expect(write.writeFile?.preview == FilePreview("x"))
        let edit = content("edit_file", #"{"path":"/a","old_string":"a","new_string":"b"}"#, #"{"path":"/a","replacements":1}"#)
        #expect(edit.editFile?.diff?.added == 1)
        #expect(edit.editFile?.state == .edited(replacements: 1, linesBefore: nil, linesAfter: nil, replaceAll: false))
        #expect(content("computer_use", nil, #"{"error":"disabled"}"#).computerUse?.phase == .refused("disabled"))
        #expect(content("deep_research", #"{"subject":"S"}"#, #"{"id":"d1"}"#).deepResearch == .init(subject: "S", phase: .job(id: "d1")))
        #expect(content("image_generation", #"{"prompt":"P"}"#, #"{"images":[]}"#).imageGeneration?.prompt == "P")
        #expect(content("map_itinerary", nil, #"{"type":"mapItinerary","days":[]}"#).mapItinerary?.model?.days == [])
        #expect(content("update_memory", nil, memoryDetails).memoryUpdate?.changes.first?.key == "Work setup")
        #expect(content("read_file", nil, #"{"size":1}"#) == .undecodable)
        #expect(content("edit_file", #"{"old_string":"a"}"#, #"{"path":"/a"}"#).editFile?.diff == nil)
    }
}

@MainActor
@Suite("Tool cards: the registry and its fallback")
struct ToolCardRegistryTests {
    @Test("a readable terminal result is drawn by its own card, and reports nothing")
    func terminalCard() {
        let card = ToolCard(id: "t", toolName: "terminal", kind: .terminal, payload: value(terminalDetails))
        guard case .card = ToolCardRegistry.resolve(card) else {
            Issue.record("terminal fell back")
            return
        }
        #expect(ToolPresentation.renderIssue(for: card) == nil)
    }

    @Test("a terminal result that does not decode falls back to the generic card with one issue, no payload")
    func badDetails() throws {
        let card = ToolCard(
            id: "t", toolName: "terminal", kind: .terminal, payload: .object(["stdout": .string("secret output")]))
        guard case .generic(let issue) = ToolCardRegistry.resolve(card) else {
            Issue.record("drew a card from bad details")
            return
        }
        let reported = try #require(issue)
        #expect(reported.message == "Unreadable terminal card shown as the generic card")
        #expect(reported.attributes == ["tool": "terminal", "kind": "terminal"])
        #expect(!reported.message.contains("secret"))
    }

    @Test("an unknown tool falls back to the generic card and is reported by name")
    func unknownTool() throws {
        let card = ToolCard(id: "t", toolName: "summon_llama", kind: .generic, payload: .string("private"))
        guard case .generic(let issue) = ToolCardRegistry.resolve(card) else {
            Issue.record("drew a card for an unknown tool")
            return
        }
        #expect(try #require(issue).message == "Unknown tool name: summon_llama")
    }

    @Test("create_artifact draws the artifact card; one without its id is generic and reported")
    func artifactCard() throws {
        let payload = value(#"{"type":"artifact","artifactId":"a1","chatId":"c1","title":"Chart","code":"x"}"#)
        let card = ToolCard(id: "t", toolName: "create_artifact", kind: .artifact, payload: payload)
        guard case .card = ToolCardRegistry.resolve(card) else {
            Issue.record("create_artifact drew no card")
            return
        }
        #expect(card.content.artifact == ArtifactResult(artifactId: "a1", chatId: "c1", title: "Chart", code: "x"))

        let broken = ToolCard(id: "u", toolName: "create_artifact", kind: .artifact, payload: value(#"{"id":"d1"}"#))
        guard case .generic(let issue) = ToolCardRegistry.resolve(broken) else {
            Issue.record("an unreadable create_artifact drew a card")
            return
        }
        #expect(try #require(issue).attributes == ["tool": "create_artifact", "kind": "artifact"])
    }

    @Test("terminal, the file cards, weather, image generation, the map, computer use and deep research are registered; which draw failures and running calls")
    func registered() {
        #expect(
            Set(ToolCardRegistry.cards.keys)
                == [
                    "terminal", "read_file", "write_file", "edit_file", "weather", "image_generation", "map_itinerary",
                    "computer_use", "deep_research", "update_memory", "create_artifact",
                ])
        #expect(ToolCardRegistry.drawsFailures(for: "image_generation"))
        #expect(ToolCardRegistry.drawsPending(for: "image_generation"))
        #expect(!["terminal", "read_file", "weather"].contains(where: ToolCardRegistry.drawsPending(for:)))
        #expect(ToolCardRegistry.hasCard(for: "read_file"))
        #expect(ToolCardRegistry.hasCard(for: "weather"))
        #expect(ToolCardRegistry.hasCard(for: "map_itinerary"))
        #expect(!ToolCardRegistry.drawsPending(for: "map_itinerary"))
        #expect(ToolCardRegistry.hasCard(for: "deep_research"))
        #expect(!ToolCardRegistry.drawsPending(for: "deep_research"))
        #expect(ToolCardRegistry.hasCard(for: "create_artifact"))
        #expect(
            ["read_file", "write_file", "edit_file", "weather", "map_itinerary", "deep_research"].allSatisfy(
                ToolCardRegistry.drawsFailures(for:)))
        #expect(!ToolCardRegistry.drawsFailures(for: "terminal"))
        #expect(!ToolCardRegistry.drawsFailures(for: "grep"))
    }

    @Test("a drawn card reports once when it falls back, and not at all when it draws its own card")
    func reportsOnce() async {
        let reports = ReportLog()
        let diagnostics = RenderDiagnostics { scope, message, _ in reports.append("\(scope): \(message)") }
        let cards = [
            ToolCard(id: "t1", toolName: "terminal", kind: .terminal, payload: value(terminalDetails)),
            ToolCard(id: "t2", toolName: "terminal", kind: .terminal, payload: .object(["stdout": .string("x")])),
        ]
        let root = VStack {
            ForEach(cards) { ToolCardView(card: $0) }
        }
        .environment(\.renderDiagnostics, diagnostics)
        let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 390, height: 800))
        window.rootViewController = UIHostingController(rootView: root)
        window.makeKeyAndVisible()
        for _ in 0..<20 where reports.entries.isEmpty {
            window.layoutIfNeeded()
            try? await Task.sleep(for: .milliseconds(20))
        }
        window.layoutIfNeeded()
        try? await Task.sleep(for: .milliseconds(100))
        #expect(reports.entries == ["chat.toolCard: Unreadable terminal card shown as the generic card"])
        window.isHidden = true
    }
}

private final class ReportLog: @unchecked Sendable {
    private let lock = NSLock()
    private var stored: [String] = []

    var entries: [String] { lock.withLock { stored } }

    func append(_ entry: String) { lock.withLock { stored.append(entry) } }
}

@Suite("Run foot: built with the turn")
struct RunFootTests {
    @Test("update_memory calls are listed in order: pending, done with its changes, failed with its message")
    func memoryUpdates() throws {
        let turn = try #require(
            group([
                user("u1"),
                call("a1", "u1", "k1", "update_memory", #"{"instruction":"remember"}"#),
                result("t1", "u1", "k1", "update_memory", details: memoryDetails),
                call("a2", "u1", "k2", "update_memory"),
                result("t2", "u1", "k2", "update_memory", details: "null", isError: true, text: "DB down"),
                call("a3", "u1", "k3", "update_memory"),
            ]).first)
        #expect(turn.foot.memoryUpdates.map(\.id) == ["k1", "k2", "k3"])
        #expect(turn.foot.memoryUpdates.map(\.status) == [.succeeded, .failed, .pending])
        #expect(turn.foot.memoryUpdates[0].result?.changes.map(\.key) == ["Work setup"])
        #expect(turn.foot.memoryUpdates[1].errorText == "DB down")
        #expect(turn.foot.memoryUpdates[2].result == nil)
    }

    @Test("a run's search media is collected from its results; one with no media has an empty foot")
    func searchMedia() throws {
        let turn = try #require(
            group([user("u1"), result("t1", "u1", "k1", "web_search", details: searchDetails), answer("a1", "u1", "Hi")])
                .first)
        #expect(turn.foot.searchMedia.map(\.kind) == [.image, .video])
        #expect(turn.foot.searchMedia.map(\.url) == ["https://img.invalid/1.png", "https://v.invalid/1"])
        #expect(try #require(group([user("u2"), answer("a2", "u2", "Hi")]).first).foot.isEmpty)
    }

    @MainActor
    @Test("the memory updates are part of the turn, so of its view's equality; the used memories are not (the store's)")
    func memoryInEquality() {
        let turn = AssistantTurn(runId: "r", body: "Answer")
        let base = AssistantTurnView(turn: turn, isStreaming: false, error: nil)
        #expect(base == AssistantTurnView(turn: turn, isStreaming: false, error: nil))
        let otherFoot = AssistantTurn(
            runId: "r", body: "Answer", foot: RunFoot(memoryUpdates: [MemoryUpdate(id: "k", status: .pending)]))
        #expect(base != AssistantTurnView(turn: otherFoot, isStreaming: false, error: nil))
    }

    @Test("an update_memory call in an aborted or failed message never ran: it is not a running update")
    func abortedCallNotRunning() throws {
        let aborted = decode(
            #"{"id":"a1","runId":"u1","role":"assistant","content":[{"type":"toolCall","id":"k1","name":"update_memory","arguments":{}}],"stopReason":"aborted","timestamp":2}"#
        )
        let errored = decode(
            #"{"id":"a2","runId":"u1","role":"assistant","content":[{"type":"toolCall","id":"k2","name":"update_memory","arguments":{}}],"stopReason":"error","errorMessage":"429","timestamp":3}"#
        )
        let turn = try #require(group([user("u1"), aborted, errored]).first)
        #expect(turn.foot.memoryUpdates.isEmpty)
        #expect(RunMemoryChanges(turn.foot.memoryUpdates) == nil)
    }

    @MainActor
    @Test("update_memory draws no timeline card; an unreadable result gets the generic card, which reports it")
    func updateMemoryCard() throws {
        let readable = try #require(
            group([user("u1"), call("a1", "u1", "k1", "update_memory"), result("t1", "u1", "k1", "update_memory", details: memoryDetails)])
                .first)
        #expect(readable.toolCards.isEmpty)
        let unreadable = try #require(
            group([
                user("u2"), call("a2", "u2", "k2", "update_memory"),
                result("t2", "u2", "k2", "update_memory", details: #"{"secret":"private"}"#),
            ]).first)
        let card = try #require(unreadable.toolCards.first)
        guard case .generic(let issue) = ToolCardRegistry.resolve(card) else {
            Issue.record("an unreadable update_memory result falls back to the generic card")
            return
        }
        #expect(issue?.message == "Unreadable update_memory card shown as the generic card")
        #expect(issue.map { !"\($0)".contains("private") } == true)
        #expect(unreadable.foot.memoryUpdates.map(\.status) == [.succeeded])
        #expect(unreadable.foot.memoryUpdates.first?.result == nil)
    }
}

@MainActor
@Suite("Render count: a settled turn with rich tools stays put while a later turn streams")
struct RichTurnRenderCountTests {
    private static let settled: [ChatMessage] = [
        user("u1"),
        call("a1", "u1", "k1", "terminal", #"{"command":"ls"}"#),
        result("t1", "u1", "k1", "terminal", details: terminalDetails),
        call("a2", "u1", "k2", "weather", #"{"location":"Shanghai"}"#),
        result("t2", "u1", "k2", "weather", details: weatherDetails),
        call("a3", "u1", "k3", "update_memory"),
        result("t3", "u1", "k3", "update_memory", details: memoryDetails),
        result("t4", "u1", "k4", "web_search", details: searchDetails),
        call("a5", "u1", "k5", "edit_file", #"{"path":"/a.swift","old_string":"let a = 1","new_string":"let a = 2"}"#),
        result("t5", "u1", "k5", "edit_file", details: #"{"path":"/a.swift","replacements":1,"linesBefore":3,"linesAfter":3}"#),
        call("a6", "u1", "k6", "read_file", #"{"path":"/b.md"}"#),
        result("t6", "u1", "k6", "read_file", details: "null", isError: true, text: "ENOENT"),
        call("a7", "u1", "k7", "image_generation", #"{"prompt":"A lighthouse"}"#),
        result(
            "t7", "u1", "k7", "image_generation",
            details: #"{"size":"1024x1536","images":[{"mediaId":"a.png","chatId":"c1","mimeType":"image/png","width":1024,"height":1536}]}"#),
        call("a8", "u1", "k8", "map_itinerary", #"{"title":"Kyoto","days":[]}"#),
        result("t8", "u1", "k8", "map_itinerary", details: mapDetails),
        answer("a4", "u1", "Done 【1-source】"),
        user("u2"),
    ]

    private func frame(_ text: String) -> [ChatMessage] { Self.settled + [answer("b1", "u2", text)] }

    @Test("each frame rebuilds only the streaming turn; the settled turn and its view compare equal")
    func settledTurnIsStable() throws {
        var cache = RunGrouper.Cache()
        let first = RunGrouper.group(frame("S"), cache: &cache)
        let built = cache.builtTurnCount
        var previous = first
        for text in ["St", "Str", "Stre", "Strea", "Stream"] {
            let next = RunGrouper.group(frame(text), cache: &cache)
            #expect(next.first(where: { $0.id == "run:u1" }) == previous.first(where: { $0.id == "run:u1" }))
            previous = next
        }
        #expect(cache.builtTurnCount == built + 5)
        let settledBefore = try #require(turns(first).first)
        let settledAfter = try #require(turns(previous).first)
        #expect(
            settledBefore.toolCards.map(\.toolName)
                == ["terminal", "weather", "edit_file", "read_file", "image_generation", "map_itinerary"],
            "in the order the calls were made")
        #expect(settledBefore.toolCards[5].content.mapItinerary?.model?.stopCount == 3)
        #expect(settledBefore.foot.memoryUpdates.count == 1)
        #expect(settledBefore.foot.searchMedia.count == 2)
        let before = AssistantTurnView(
            turn: settledBefore, isStreaming: false, error: nil, regenerate: {},
            showSources: { _, _ in })
        let after = AssistantTurnView(
            turn: settledAfter, isStreaming: false, error: nil, regenerate: { print("new") },
            showSources: { _, _ in print("new") })
        #expect(before == after)
    }
}
