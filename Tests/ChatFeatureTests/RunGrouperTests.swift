import Foundation
import Models
import Testing

@testable import ChatFeature

private let r1 = "11111111-1111-4111-8111-111111111111"
private let r2 = "22222222-2222-4222-8222-222222222222"

private func decode(_ json: String) -> ChatMessage {
    try! JSONDecoder().decode(ChatMessage.self, from: Data(json.utf8))
}

private func user(_ id: String, runId: String? = nil) -> ChatMessage {
    let run = runId.map { #","runId":"\#($0)""# } ?? #","runId":"\#(id)""#
    return decode(#"{"id":"\#(id)"\#(run),"role":"user","content":"q","timestamp":1}"#)
}

private func legacyUser(_ id: String) -> ChatMessage {
    decode(#"{"id":"\#(id)","role":"user","content":"q","timestamp":1}"#)
}

private func assistant(
    _ id: String, runId: String?, blocks: String, stopReason: String = "stop", extra: String = ""
) -> ChatMessage {
    let run = runId.map { #""runId":"\#($0)","# } ?? ""
    return decode(
        #"{"id":"\#(id)",\#(run)"role":"assistant","content":[\#(blocks)],"stopReason":"\#(stopReason)","timestamp":2\#(extra)}"#
    )
}

private func text(_ id: String, _ runId: String?, _ value: String, stopReason: String = "stop") -> ChatMessage {
    assistant(id, runId: runId, blocks: #"{"type":"text","text":"\#(value)"}"#, stopReason: stopReason)
}

private func toolCall(_ id: String, _ name: String, _ arguments: String = "{}") -> String {
    #"{"type":"toolCall","id":"\#(id)","name":"\#(name)","arguments":\#(arguments)}"#
}

private func toolResult(
    _ id: String, _ runId: String?, callId: String, name: String, details: String = "null",
    content: String = #"[{"type":"text","text":"ok"}]"#, isError: Bool = false
) -> ChatMessage {
    let run = runId.map { #""runId":"\#($0)","# } ?? ""
    return decode(
        #"{"id":"\#(id)",\#(run)"role":"toolResult","toolCallId":"\#(callId)","toolName":"\#(name)","content":\#(content),"details":\#(details),"isError":\#(isError),"timestamp":3}"#
    )
}

private let sourcesAB = #"""
    [{"rank":1,"link":"https://example.com/a","title":"Source A","content":"full a","snippet":"snippet a","siteName":"Example A"},
     {"rank":2,"link":"https://example.com/b","title":"Source B","content":"full b","snippet":"snippet b","siteName":"Example B"}]
    """#

private let sourcesCD = #"""
    [{"rank":1,"link":"https://example.com/c","title":"Source C","content":"c","snippet":"c"},
     {"rank":2,"link":"https://example.com/d","title":"Source D","content":"d","snippet":"d"}]
    """#

private func group(_ messages: [ChatMessage]) -> [Segment] {
    var cache = RunGrouper.Cache()
    return RunGrouper.group(messages, cache: &cache)
}

private func turns(_ segments: [Segment]) -> [AssistantTurn] {
    segments.compactMap { if case .assistantTurn(let turn) = $0 { turn } else { nil } }
}

private func labels(_ segments: [Segment]) -> [String] {
    segments.map { if case .assistantTurn(let turn) = $0 { turn.runId } else { "user" } }
}

private func toolSteps(_ turn: AssistantTurn) -> [AssistantTurn.ToolCallStep] {
    turn.steps.compactMap { if case .toolCall(let step) = $0 { step } else { nil } }
}

@Suite("RunGrouper: grouping by runId")
struct RunGrouperGroupingTests {
    @Test("one run with two assistant steps, tool calls and results is one turn whose body joins the texts")
    func oneRunIsOneTurn() throws {
        let segments = group([
            user(r1),
            assistant(
                "a1", runId: r1,
                blocks: #"{"type":"text","text":"Looking that up."},"# + toolCall("c1", "weather", #"{"location":"Paris"}"#),
                stopReason: "toolUse"),
            toolResult("t1", r1, callId: "c1", name: "weather", details: #"{"current":{"temp":21}}"#),
            text("a2", r1, "It is sunny."),
        ])
        #expect(labels(segments) == ["user", r1])
        let turn = try #require(turns(segments).first)
        #expect(turn.id == "run:\(r1)")
        #expect(segments[1].id == "run:\(r1)")
        #expect(segments[0].id == r1)
        #expect(turn.body == "Looking that up.\n\nIt is sunny.")
        #expect(turn.messageIds == ["a1", "t1", "a2"])
        #expect(turn.hasBody)
        #expect(turn.pendingToolCalls.isEmpty)
        let step = try #require(toolSteps(turn).first)
        #expect(step.name == "weather")
        #expect(step.argumentSummary == "Paris")
        #expect(step.status == .succeeded)
        #expect(turn.toolCards.map(\.kind) == [.weather])
        #expect(turn.toolCards.first?.payload == .object(["current": .object(["temp": .number(21)])]))
    }

    @Test("two runs are two turns, in order, and user rows stay user segments")
    func twoRunsTwoTurns() {
        let segments = group([user(r1), text("a1", r1, "one"), user(r2), text("a2", r2, "two")])
        #expect(labels(segments) == ["user", r1, "user", r2])
        if case .user(let message) = segments[2] { #expect(message.id == r2) } else { Issue.record("not a user row") }
        #expect(turns(segments).map(\.body) == ["one", "two"])
    }

    @Test("two runs are two segments even with no user message between them")
    func noUserBetween() {
        #expect(labels(group([user(r1), user(r2), text("a1", r2, "hi")])) == ["user", "user", r2])
        #expect(labels(group([user(r1), text("a1", r1, "one"), text("a2", r2, "two")])) == ["user", r1, r2])
    }

    @Test("a message without a runId joins the run of the user message before it")
    func legacyMessageJoinsPreviousRun() {
        let segments = group([user(r1), text("a1", nil, "hi")])
        #expect(labels(segments) == ["user", r1])
        let legacy = group([legacyUser("u1"), text("a1", nil, "one"), toolResult("t1", nil, callId: "c", name: "grep")])
        #expect(labels(legacy) == ["user", "u1"])
        #expect(turns(legacy).first?.messageIds == ["a1", "t1"])
    }

    @Test("an orphan run renders, and a leading message with no runId is a run of its own")
    func orphans() {
        #expect(labels(group([text("a1", r1, "hi")])) == [r1])
        #expect(labels(group([text("a1", nil, "hi")])) == ["a1"])
    }

    @Test("an empty-string runId counts as a real id, as with the desktop's ??")
    func emptyRunId() {
        #expect(labels(group([user(r1), text("a1", "", "hi")])) == ["user", ""])
    }

    @Test("a run with only tool calls and no text yet is a turn with steps and no body")
    func toolCallsOnly() throws {
        let segments = group([
            user(r1),
            assistant("a1", runId: r1, blocks: toolCall("c1", "web_search", #"{"query":"swift 6"}"#), stopReason: "toolUse"),
        ])
        let turn = try #require(turns(segments).first)
        #expect(turn.body.isEmpty)
        #expect(!turn.hasBody)
        #expect(turn.hasContent)
        #expect(toolSteps(turn).map(\.argumentSummary) == ["swift 6"])
    }

    @Test("a run with nothing to show yet is not a segment")
    func emptyRunIsHidden() {
        let segments = group([user(r1), assistant("a1", runId: r1, blocks: #"{"type":"text","text":"  "}"#)])
        #expect(labels(segments) == ["user"])
    }
}

@Suite("RunGrouper: steps and tool cards")
struct RunGrouperStepsTests {
    @Test("a tool call without its result is pending")
    func pendingToolCall() throws {
        let turn = try #require(
            turns(
                group([
                    user(r1),
                    assistant(
                        "a1", runId: r1,
                        blocks: toolCall("c1", "terminal", #"{"command":"ls -la"}"#) + "," + toolCall("c2", "read_file", #"{"path":"/tmp/x"}"#),
                        stopReason: "toolUse"),
                    toolResult("t1", r1, callId: "c1", name: "terminal", details: #"{"stdout":"x"}"#),
                ])
            ).first)
        #expect(turn.pendingToolCalls == [PendingToolCall(id: "c2", name: "read_file")])
        let steps = toolSteps(turn)
        #expect(steps.map(\.status) == [.succeeded, .pending])
        #expect(steps[0].codeArgument == "ls -la")
        #expect(steps[0].argumentSummary == nil)
        #expect(steps[1].argumentSummary == "/tmp/x")
        #expect(turn.toolCards.map(\.kind) == [.terminal])
    }

    @Test("a failed file tool is an error step and a failed card, both carrying its message")
    func toolError() throws {
        let turn = try #require(
            turns(
                group([
                    user(r1),
                    assistant("a1", runId: r1, blocks: toolCall("c1", "read_file", #"{"filePath":"/nope"}"#), stopReason: "toolUse"),
                    toolResult(
                        "t1", r1, callId: "c1", name: "read_file", content: #"[{"type":"text","text":"ENOENT"}]"#,
                        isError: true),
                ])
            ).first)
        let step = try #require(toolSteps(turn).first)
        #expect(step.status == .failed)
        #expect(step.isError)
        #expect(step.errorText == "ENOENT")
        #expect(step.argumentSummary == "/nope")
        let card = try #require(turn.toolCards.first)
        #expect(turn.toolCards.count == 1)
        #expect(card.isError)
        #expect(card.errorText == "ENOENT")
        #expect(card.content.readFile == ReadFileCardModel(FailedFileCall(path: "/nope", message: "ENOENT")))
        #expect(turn.pendingToolCalls.isEmpty)
    }

    @Test("a failed tool with no text says nothing itself (the view supplies the label)")
    func toolErrorWithoutText() throws {
        let turn = try #require(
            turns(
                group([
                    user(r1),
                    toolResult("t1", r1, callId: "c9", name: "grep", content: "[]", isError: true),
                ])
            ).first)
        let step = try #require(toolSteps(turn).first)
        #expect(step.name == "grep")
        #expect(step.status == .failed)
        #expect(step.errorText == nil)
        #expect(turn.toolCards.isEmpty)
    }

    @Test("the thinking title is the first **bold**, else the first line cut to 60 characters")
    func thinkingTitle() throws {
        let long = String(repeating: "x", count: 70)
        let turn = try #require(
            turns(
                group([
                    user(r1),
                    assistant(
                        "a1", runId: r1,
                        blocks: #"""
                            {"type":"thinking","thinking":"Some intro **Planning the answer** then **Other**"},
                            {"type":"thinking","thinking":"\n\nfirst line\nsecond"},
                            {"type":"thinking","thinking":"\#(long)"},
                            {"type":"thinking","thinking":"   "},
                            {"type":"text","text":"Done."}
                            """#),
                ])
            ).first)
        let thinking = turn.steps.compactMap { if case .thinking(let step) = $0 { step } else { nil } }
        #expect(thinking.map(\.title) == ["Planning the answer", "first line", String(repeating: "x", count: 60)])
        #expect(turn.hasThinking)
        #expect(turn.body == "Done.")
    }

    @Test("built-ins the desktop keeps silent produce no card")
    func silentBuiltIns() throws {
        let names = [
            "list_directory", "find_files", "grep", "web_fetch", "web_search",
            "lcm_grep", "call_mcp_tool", "list_mcp_tools", "rag",
        ]
        let messages = [user(r1)] + names.enumerated().map { index, name in
            toolResult("t\(index)", r1, callId: "c\(index)", name: name, details: #"{"some":"payload"}"#)
        }
        let turn = try #require(turns(group(messages)).first)
        #expect(turn.toolCards.isEmpty)
    }

    @Test("the file tools have cards of their own now, done or failed")
    func fileToolCards() throws {
        let names = ["read_file", "write_file", "edit_file"]
        let messages = [user(r1)] + names.enumerated().flatMap { index, name in
            [
                toolResult("t\(index)", r1, callId: "c\(index)", name: name, details: #"{"path":"/a","content":"x"}"#),
                toolResult(
                    "e\(index)", r1, callId: "f\(index)", name: name, content: #"[{"type":"text","text":"EACCES"}]"#,
                    isError: true),
            ]
        }
        let turn = try #require(turns(group(messages)).first)
        #expect(turn.toolCards.map(\.toolName) == names.flatMap { [$0, $0] })
        #expect(turn.toolCards.map(\.isError) == [false, true, false, true, false, true])
        #expect(turn.toolCards.allSatisfy(ToolCardRegistry.canDraw))
    }

    @Test("an MCP or unknown tool falls back to the generic card with its payload")
    func genericCard() throws {
        let turn = try #require(
            turns(
                group([
                    user(r1),
                    toolResult("t1", r1, callId: "c1", name: "github_create_issue", details: #"{"some":"payload"}"#),
                    toolResult(
                        "t2", r1, callId: "c2", name: "mcp_thing",
                        details: #"{"content":[{"type":"text","text":"{\"n\":1}"}]}"#),
                    toolResult(
                        "t3", r1, callId: "c3", name: "plain_text", content: #"[{"type":"text","text":"not json"}]"#),
                ])
            ).first)
        #expect(turn.toolCards.map(\.kind) == [.generic, .generic, .generic])
        #expect(turn.toolCards.map(\.toolName) == ["github_create_issue", "mcp_thing", "plain_text"])
        #expect(turn.toolCards[0].payload == .object(["some": .string("payload")]))
        #expect(turn.toolCards[1].payload == .object(["n": .number(1)]))
        #expect(turn.toolCards[2].payload == .string("not json"))
        #expect(turn.toolCards[0].id == "t1")
        #expect(turn.toolCards[0].toolCallId == "c1")
    }

    @Test("a payload without its shape is still drawn, generically, and reported (spec §2 Errors)")
    func shapedCards() throws {
        let turn = try #require(
            turns(
                group([
                    user(r1),
                    toolResult("t1", r1, callId: "c1", name: "create_artifact", details: #"{"type":"artifact","id":"x"}"#),
                    toolResult("t2", r1, callId: "c2", name: "create_artifact", details: #"{"type":"other"}"#),
                    toolResult("t3", r1, callId: "c3", name: "map_itinerary", details: #"{"type":"mapItinerary"}"#),
                    toolResult("t4", r1, callId: "c4", name: "deep_research", details: #"{"id":"d"}"#),
                    toolResult("t5", r1, callId: "c5", name: "computer_use", details: #"{"steps":[]}"#),
                    toolResult("t6", r1, callId: "c6", name: "map_itinerary", details: #"{"days":"not an itinerary"}"#),
                ])
            ).first)
        #expect(
            turn.toolCards.map(\.kind) == [.artifact, .generic, .mapItinerary, .deepResearch, .computerUse, .generic])
        let issues = turn.toolCards.map { ToolPresentation.renderIssue(for: $0)?.attributes }
        #expect(issues[0] == nil)
        #expect(issues[1] == ["tool": "create_artifact", "kind": "generic"])
        #expect(issues[5] == ["tool": "map_itinerary", "kind": "generic"])
    }

    @Test("map_itinerary's call line counts its days and stops")
    func itineraryScale() throws {
        let turn = try #require(
            turns(
                group([
                    user(r1),
                    assistant(
                        "a1", runId: r1,
                        blocks: toolCall(
                            "c1", "map_itinerary", #"{"days":[{"places":[1,2]},{"places":[3]},{"title":"rest"}]}"#),
                        stopReason: "toolUse"),
                ])
            ).first)
        #expect(toolSteps(turn).first?.itinerary == ItineraryScale(days: 3, stops: 3))
    }

    @Test("durationMs comes from the last assistant message that has one")
    func duration() throws {
        let turn = try #require(
            turns(
                group([
                    user(r1),
                    assistant(
                        "a1", runId: r1, blocks: toolCall("c1", "grep"), stopReason: "toolUse", extra: #","durationMs":100"#),
                    toolResult("t1", r1, callId: "c1", name: "grep"),
                    assistant(
                        "a2", runId: r1, blocks: #"{"type":"text","text":"ok"}"#, extra: #","durationMs":12345"#),
                ])
            ).first)
        #expect(turn.durationMs == 12345)
        #expect(turn.timestampMs == 2)
    }

    @Test("without a stamped duration the timestamps' span is used")
    func durationFallback() throws {
        let turn = try #require(
            turns(group([user(r1), text("a1", r1, "x"), toolResult("t1", r1, callId: "c", name: "grep")])).first)
        #expect(turn.durationMs == 1)
    }

    @Test("a run that ended in error carries the provider's message; one that did not, none")
    func runError() throws {
        let failed = try #require(
            turns(
                group([
                    user(r1),
                    assistant(
                        "a1", runId: r1, blocks: #"{"type":"text","text":"Partial"}"#, stopReason: "error",
                        extra: #","errorMessage":"429 rate limited""#),
                ])
            ).first)
        #expect(failed.error == "429 rate limited")
        #expect(failed.body == "Partial")

        let empty = try #require(
            turns(group([user(r1), assistant("a1", runId: r1, blocks: "", stopReason: "error")])).first)
        #expect(empty.error == "")
        #expect(!empty.hasBody)

        let fine = try #require(turns(group([user(r1), text("a1", r1, "ok")])).first)
        #expect(fine.error == nil)
    }
}

@Suite("RunGrouper: citations")
struct RunGrouperCitationTests {
    @Test("two web_search results in one turn resolve markers 1 and 2, and show as the step's result count")
    func oneTurn() throws {
        let turn = try #require(
            turns(
                group([
                    user(r1),
                    assistant("a0", runId: r1, blocks: toolCall("call_1", "web_search", #"{"query":"rain"}"#), stopReason: "toolUse"),
                    toolResult("t1", r1, callId: "call_1", name: "web_search", details: sourcesAB),
                    text("a1", r1, "It rained 【1-source】 and cleared 【2-source】."),
                ])
            ).first)
        #expect(turn.citations.map(\.rank) == [1, 2])
        #expect(turn.sources.map(\.link) == ["https://example.com/a", "https://example.com/b"])
        #expect(turn.citation(forMarker: 1)?.link == "https://example.com/a")
        #expect(turn.citation(forMarker: 2)?.siteName == "Example B")
        #expect(turn.citation(forMarker: 3) == nil)
        let step = try #require(toolSteps(turn).first)
        #expect(step.resultCount == 2)
        #expect(step.results.map(\.title) == ["Source A", "Source B"])
        #expect(turn.toolCards.isEmpty)
    }

    @Test("a later turn keeps an earlier turn's sources; a re-run search resets numbering, last one wins")
    func acrossTurns() throws {
        let all = turns(
            group([
                user("u1"),
                toolResult("t1", "u1", callId: "call_1", name: "web_search", details: sourcesAB),
                text("a1", "u1", "It rained 【1-source】."),
                user("u2"),
                text("a2", "u2", "More on 【2-source】."),
                user("u3"),
                toolResult("t3", "u3", callId: "call_3", name: "web_search", details: sourcesCD),
                text("a3", "u3", "New 【1-source】."),
            ]))
        #expect(all.count == 3)
        #expect(all[0].citation(forMarker: 1)?.link == "https://example.com/a")
        #expect(all[1].sources.isEmpty)
        #expect(all[1].citation(forMarker: 2)?.link == "https://example.com/b")
        #expect(all[2].citations.count == 4)
        #expect(all[2].citation(forMarker: 1)?.link == "https://example.com/c")
        #expect(all[0].citation(forMarker: 1)?.link == "https://example.com/a")
    }

    @Test("a fetched page is a citeable source too")
    func webFetch() throws {
        let turn = try #require(
            turns(
                group([
                    user("u"),
                    toolResult(
                        "tf", "u", callId: "call_f", name: "web_fetch",
                        details: #"{"rank":1,"link":"https://bls.gov/x","title":"BLS PPI","content":"p","snippet":"p"}"#),
                    text("af", "u", "PPI rose 0.4% 【1-source】."),
                ])
            ).first)
        #expect(turn.sources.map(\.link) == ["https://bls.gov/x"])
        #expect(turn.toolCards.isEmpty)
    }

    @Test("an empty or failed search adds no sources")
    func emptySearch() throws {
        let turn = try #require(
            turns(
                group([
                    user("u"),
                    toolResult("t1", "u", callId: "c1", name: "web_search", details: "[]"),
                    toolResult("t2", "u", callId: "c2", name: "web_search", details: sourcesAB, isError: true),
                    text("a", "u", "x"),
                ])
            ).first)
        #expect(turn.citations.isEmpty)
    }
}

@Suite("RunGrouper: cache")
struct RunGrouperCacheTests {
    private static let history: [ChatMessage] = [
        user("u1"),
        toolResult("t1", "u1", callId: "call-t1", name: "web_search", details: sourcesAB),
        text("a1", "u1", "First answer 【1-source】"),
        user("u2"),
        text("a2", "u2", "Second answer"),
        user("u3"),
    ]

    private func frame(_ value: String) -> [ChatMessage] { Self.history + [text("a3", "u3", value)] }

    @Test("a streaming frame that lengthens the last message rebuilds only the last turn")
    func streamingFrame() {
        var cache = RunGrouper.Cache()
        let before = RunGrouper.group(frame("Th"), cache: &cache)
        #expect(cache.builtTurnCount == 3)
        let after = RunGrouper.group(frame("Thi"), cache: &cache)
        #expect(cache.builtTurnCount == 4)
        #expect(after.count == before.count)
        #expect(Array(after.dropLast()) == Array(before.dropLast()))
        #expect(after.last != before.last)
        #expect(turns(after).last?.citations.map(\.rank) == [1, 2])
    }

    @Test("an unchanged transcript rebuilds nothing")
    func unchanged() {
        var cache = RunGrouper.Cache()
        let first = RunGrouper.group(frame("Third"), cache: &cache)
        let count = cache.builtTurnCount
        #expect(RunGrouper.group(frame("Third"), cache: &cache) == first)
        #expect(cache.builtTurnCount == count)
    }

    @Test("the cache gives the same result as no cache")
    func sameAsWithoutCache() {
        var cache = RunGrouper.Cache()
        _ = RunGrouper.group(frame("Th"), cache: &cache)
        #expect(RunGrouper.group(frame("Thi"), cache: &cache) == group(frame("Thi")))
    }

    @Test("a search landing in the last turn extends its citations and leaves earlier turns alone")
    func searchLandsLater() {
        var cache = RunGrouper.Cache()
        let before = turns(RunGrouper.group(Self.history, cache: &cache))
        let after = turns(
            RunGrouper.group(
                Self.history + [
                    toolResult("t3", "u3", callId: "call-t3", name: "web_search", details: sourcesCD),
                    text("a3", "u3", "cited"),
                ], cache: &cache))
        #expect(Array(after.prefix(2)) == before)
        #expect(after[2].citations.count == 4)
    }

    @Test("an earlier turn changing updates the citations of later, untouched turns")
    func earlierTurnChanges() {
        var cache = RunGrouper.Cache()
        let noSearch: [ChatMessage] = [user("u1"), text("a1", "u1", "one"), user("u2"), text("a2", "u2", "two")]
        _ = RunGrouper.group(noSearch, cache: &cache)
        let withSearch: [ChatMessage] = [
            user("u1"),
            toolResult("t1", "u1", callId: "c", name: "web_search", details: sourcesAB),
            text("a1", "u1", "one"), user("u2"), text("a2", "u2", "two"),
        ]
        let later = turns(RunGrouper.group(withSearch, cache: &cache))
        #expect(later[1].citations.map(\.rank) == [1, 2])
        #expect(later == turns(group(withSearch)))
    }

    @Test("the cache forgets runs that are no longer in the chat")
    func forgets() {
        var cache = RunGrouper.Cache()
        _ = RunGrouper.group(frame("Th"), cache: &cache)
        _ = RunGrouper.group([user("x1")], cache: &cache)
        #expect(cache.cachedTurnCount == 0)
    }
}

@Suite("RunGrouper: fix round 1")
struct RunGrouperFixRoundTests {
    @Test("a leading block of run-less messages is one run keyed by its first message")
    func leadingRunlessBlock() throws {
        let segments = group([
            assistant("a1", runId: nil, blocks: toolCall("c1", "grep"), stopReason: "toolUse"),
            toolResult("t1", nil, callId: "c1", name: "grep"),
            text("a2", nil, "done"),
        ])
        #expect(labels(segments) == ["a1"])
        let turn = try #require(turns(segments).first)
        #expect(turn.messageIds == ["a1", "t1", "a2"])
        #expect(turn.pendingToolCalls.isEmpty)
        #expect(turn.body == "done")
    }

    @Test("out-of-range and non-finite numbers never trap")
    func outOfRangeNumbers() throws {
        let big = try #require(
            turns(
                group([
                    user("u"),
                    toolResult(
                        "t1", "u", callId: "c1", name: "web_search",
                        details: #"[{"rank":1e20,"link":"https://x","title":"x"},{"rank":-1e20,"link":"https://y","title":"y"},{"rank":3,"link":"https://z","title":"z"}]"#),
                    assistant("a1", runId: "u", blocks: #"{"type":"text","text":"x"}"#, extra: #","durationMs":1e20"#),
                ])
            ).first)
        #expect(big.sources.map(\.rank) == [3])
        #expect(big.durationMs == nil)

        var raw = text("a2", "v", "y").raw
        raw["durationMs"] = .number(.nan)
        raw["timestamp"] = .number(.infinity)
        let nan = try #require(
            turns(group([user("v"), ChatMessage(id: "a2", role: "assistant", raw: raw)])).first)
        #expect(nan.durationMs == nil)
        #expect(CitationSource(.object(["rank": .number(.infinity), "link": .string("l")])) == nil)
        #expect(CitationSource(.object(["rank": .number(.nan), "link": .string("l")])) == nil)
    }

    @Test("an empty or {} error text is no text, so the view says the tool failed")
    func emptyErrorText() throws {
        let turn = try #require(
            turns(
                group([
                    user("u"),
                    toolResult("t1", "u", callId: "c1", name: "grep", content: #"[{"type":"text","text":" {} "}]"#, isError: true),
                    toolResult("t2", "u", callId: "c2", name: "grep", content: #"[{"type":"text","text":"  "}]"#, isError: true),
                ])
            ).first)
        #expect(toolSteps(turn).map(\.errorText) == [nil, nil])
    }

    @Test("a CRLF thinking block's title is its first line")
    func crlfTitle() {
        #expect(RunGrouper.thinkingTitle("\r\n\r\nFirst line\r\nsecond") == "First line")
    }

    @Test("public initialisers build a fixture without JSON")
    func publicInitialisers() {
        let source = CitationSource(rank: 1, link: "https://a", title: "A")
        let step = AssistantTurn.ToolCallStep(id: "c1", name: "web_search", argumentSummary: "q", results: [source])
        let turn = AssistantTurn(
            runId: "r",
            steps: [.thinking(.init(text: "**T**", title: "T")), .toolCall(step)],
            body: "Hi 【1-source】",
            toolCards: [ToolCard(id: "t", toolName: "terminal", kind: .terminal, payload: .object([:]))],
            pendingToolCalls: [PendingToolCall(id: "c2", name: "grep")],
            sources: [source])
        #expect(turn.id == "run:r")
        #expect(turn.citation(forMarker: 1) == source)
        #expect(turn.hasContent)
        #expect(step.status == .succeeded)
        #expect(ItineraryScale(days: 1, stops: 2).stops == 2)
        #expect(Segment.assistantTurn(turn).id == "run:r")
        #expect(!AssistantTurn(runId: "e").hasContent)
    }

    @Test("messages of one run split by another run get unique, stable segment ids")
    func nonAdjacentSameRun() {
        let messages = [user("u1"), text("a", "X", "first"), user("u2"), text("b", "X", "second")]
        var cache = RunGrouper.Cache()
        let first = RunGrouper.group(messages, cache: &cache)
        let ids = first.map(\.id)
        #expect(Set(ids).count == ids.count)
        #expect(ids == ["u1", "run:X", "u2", "run:X#2"])
        let built = cache.builtTurnCount
        let second = RunGrouper.group(messages, cache: &cache)
        #expect(second == first)
        #expect(cache.builtTurnCount == built)
        #expect(second == group(messages))
    }

    @Test("an edit to an earlier run's message with the same id rebuilds that run")
    func earlierEditRebuilds() {
        var cache = RunGrouper.Cache()
        _ = RunGrouper.group([user("u1"), text("a1", "u1", "one"), user("u2"), text("a2", "u2", "two")], cache: &cache)
        let after = turns(
            RunGrouper.group([user("u1"), text("a1", "u1", "ONE"), user("u2"), text("a2", "u2", "two")], cache: &cache))
        #expect(after[0].body == "ONE")
        #expect(after[1].body == "two")
    }

    @Test("parallel calls answered in reverse order both succeed")
    func parallelReverse() throws {
        let turn = try #require(
            turns(
                group([
                    user("u"),
                    assistant("a1", runId: "u", blocks: toolCall("k1", "grep") + "," + toolCall("k2", "grep"), stopReason: "toolUse"),
                    toolResult("t2", "u", callId: "k2", name: "grep"),
                    toolResult("t1", "u", callId: "k1", name: "grep"),
                ])
            ).first)
        #expect(toolSteps(turn).map(\.status) == [.succeeded, .succeeded])
        #expect(turn.pendingToolCalls.isEmpty)
    }

    @Test("a tool-call id reused in a later step settles each step in turn")
    func reusedCallId() throws {
        let partial = try #require(
            turns(
                group([
                    user("u"),
                    assistant("a1", runId: "u", blocks: toolCall("call_0", "grep"), stopReason: "toolUse"),
                    toolResult("t1", "u", callId: "call_0", name: "grep"),
                    assistant("a2", runId: "u", blocks: toolCall("call_0", "read_file"), stopReason: "toolUse"),
                ])
            ).first)
        #expect(toolSteps(partial).map(\.status) == [.succeeded, .pending])
        #expect(partial.pendingToolCalls == [PendingToolCall(id: "call_0", name: "read_file")])

        let done = try #require(
            turns(
                group([
                    user("u"),
                    assistant("a1", runId: "u", blocks: toolCall("call_0", "grep"), stopReason: "toolUse"),
                    toolResult("t1", "u", callId: "call_0", name: "grep"),
                    assistant("a2", runId: "u", blocks: toolCall("call_0", "read_file"), stopReason: "toolUse"),
                    toolResult("t2", "u", callId: "call_0", name: "read_file", content: #"[{"type":"text","text":"ENOENT"}]"#, isError: true),
                ])
            ).first)
        #expect(toolSteps(done).map(\.status) == [.succeeded, .failed])
        #expect(done.pendingToolCalls.isEmpty)
    }

    @Test("a web_search that fails while its call is pending fails the step and adds no sources")
    func failedSearch() throws {
        let turn = try #require(
            turns(
                group([
                    user("u"),
                    assistant("a1", runId: "u", blocks: toolCall("c1", "web_search", #"{"query":"q"}"#), stopReason: "toolUse"),
                    toolResult("t1", "u", callId: "c1", name: "web_search", details: sourcesAB, isError: true),
                ])
            ).first)
        #expect(toolSteps(turn).map(\.status) == [.failed])
        #expect(turn.sources.isEmpty)
        #expect(turn.citations.isEmpty)
    }

    @Test("a done frame of freshly decoded but equal messages rebuilds nothing")
    func doneReplacement() {
        func transcript() -> [ChatMessage] {
            [
                user("u1"), toolResult("t1", "u1", callId: "c", name: "web_search", details: sourcesAB),
                text("a1", "u1", "one 【1-source】"), user("u2"), text("a2", "u2", "two"),
            ]
        }
        var cache = RunGrouper.Cache()
        let before = turns(RunGrouper.group(transcript(), cache: &cache))
        let built = cache.builtTurnCount
        let after = turns(RunGrouper.group(transcript(), cache: &cache))
        #expect(after == before)
        #expect(cache.builtTurnCount == built)
    }
}
