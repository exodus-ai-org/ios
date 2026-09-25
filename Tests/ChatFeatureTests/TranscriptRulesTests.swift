import Foundation
import Models
import Testing

@testable import ChatFeature

private func rows(_ json: String) -> [ChatMessage] {
    try! JSONDecoder().decode([ChatMessage].self, from: Data(json.utf8))
}

private func segments(_ json: String) -> [Segment] {
    var cache = RunGrouper.Cache()
    return RunGrouper.group(rows(json), cache: &cache)
}

private func lastTurn(_ segments: [Segment]) -> AssistantTurn? {
    if case .assistantTurn(let turn)? = segments.last { turn } else { nil }
}

private let userOnly = #"[{"id":"u1","runId":"u1","role":"user","content":"hi"}]"#
private let thinkingOnly = #"""
    [{"id":"u1","runId":"u1","role":"user","content":"hi"},
     {"id":"a1","runId":"u1","role":"assistant","content":[{"type":"thinking","thinking":"**Plan** it"}]}]
    """#
private let answered = #"""
    [{"id":"u1","runId":"u1","role":"user","content":"hi"},
     {"id":"a1","runId":"u1","role":"assistant","content":[{"type":"text","text":"Hello"}],"durationMs":1500}]
    """#
private let answerThenPendingTool = #"""
    [{"id":"u1","runId":"u1","role":"user","content":"hi"},
     {"id":"a1","runId":"u1","role":"assistant","content":[{"type":"text","text":"Let me check."},{"type":"toolCall","id":"k1","name":"terminal","arguments":{"command":"ls"}}]}]
    """#
private let answerThenToolResult = #"""
    [{"id":"u1","runId":"u1","role":"user","content":"hi"},
     {"id":"a1","runId":"u1","role":"assistant","content":[{"type":"text","text":"Let me check."},{"type":"toolCall","id":"k1","name":"grep","arguments":{}}]},
     {"id":"t1","runId":"u1","role":"toolResult","toolCallId":"k1","toolName":"grep","content":[{"type":"text","text":"ok"}],"isError":false}]
    """#
private let answerThenThinkingAfterTool = #"""
    [{"id":"u1","runId":"u1","role":"user","content":"hi"},
     {"id":"a1","runId":"u1","role":"assistant","content":[{"type":"text","text":"Let me check."},{"type":"toolCall","id":"k1","name":"grep","arguments":{}}]},
     {"id":"t1","runId":"u1","role":"toolResult","toolCallId":"k1","toolName":"grep","content":[{"type":"text","text":"ok"}],"isError":false},
     {"id":"a2","runId":"u1","role":"assistant","content":[{"type":"thinking","thinking":"Reading the matches"}]}]
    """#
private let answerThenTextAfterTool = #"""
    [{"id":"u1","runId":"u1","role":"user","content":"hi"},
     {"id":"a1","runId":"u1","role":"assistant","content":[{"type":"text","text":"Let me check."},{"type":"toolCall","id":"k1","name":"grep","arguments":{}}]},
     {"id":"t1","runId":"u1","role":"toolResult","toolCallId":"k1","toolName":"grep","content":[{"type":"text","text":"ok"}],"isError":false},
     {"id":"a2","runId":"u1","role":"assistant","content":[{"type":"text","text":"Found it"}]}]
    """#
private let erroredRun = #"""
    [{"id":"u1","runId":"u1","role":"user","content":"hi"},
     {"id":"a1","runId":"u1","role":"assistant","content":[{"type":"text","text":"Part"}],"stopReason":"error","errorMessage":"429 rate limited"}]
    """#
private let rowErrorNoMessage = #"""
    [{"id":"u1","runId":"u1","role":"user","content":"hi"},
     {"id":"a1","runId":"u1","role":"assistant","content":[],"stopReason":"error"}]
    """#

@Suite("TranscriptRules: streaming signal and dots")
struct TranscriptStreamingTests {
    @Test("only the last segment streams, only while a turn is in flight, and never a user row")
    func streamingTurnId() {
        let turns = segments(answered)
        #expect(TranscriptRules.streamingTurnId(segments: turns, isTurnInFlight: true) == "run:u1")
        #expect(TranscriptRules.streamingTurnId(segments: turns, isTurnInFlight: false) == nil)
        #expect(TranscriptRules.streamingTurnId(segments: segments(userOnly), isTurnInFlight: true) == nil)
        let two = segments(String(answered.dropLast()) + #",{"id":"u2","runId":"u2","role":"user","content":"again"}]"#)
        #expect(TranscriptRules.streamingTurnId(segments: two, isTurnInFlight: true) == nil)
    }

    @Test("dots: while nothing of the reply is on screen, never when idle")
    func dotsBeforeTheReply() {
        let user = rows(userOnly).last
        #expect(TranscriptRules.showsTypingIndicator(segments: segments(userOnly), lastMessage: user, isTurnInFlight: true))
        #expect(TranscriptRules.showsTypingIndicator(segments: [], lastMessage: nil, isTurnInFlight: true))
        #expect(!TranscriptRules.showsTypingIndicator(segments: segments(userOnly), lastMessage: user, isTurnInFlight: false))
    }

    @Test("dots: hidden while the timeline is live (no answer yet, or a tool running), back once the run goes on")
    func dotsAfterTheReplyStarted() {
        func dots(_ json: String) -> Bool {
            TranscriptRules.showsTypingIndicator(segments: segments(json), lastMessage: rows(json).last, isTurnInFlight: true)
        }
        #expect(!dots(thinkingOnly))
        #expect(!dots(answered))
        #expect(!dots(answerThenPendingTool))
        #expect(dots(answerThenToolResult))
        #expect(dots(answerThenThinkingAfterTool))
        #expect(!dots(answerThenTextAfterTool))
    }
}

@Suite("TranscriptRules: timeline visibility")
struct TimelineVisibilityTests {
    @Test("a turn with steps always shows its timeline; a plain answer never does")
    func stepsDecide() throws {
        let thinking = try #require(lastTurn(segments(thinkingOnly)))
        #expect(TranscriptRules.showsTimeline(thinking, isStreaming: false))
        let plain = try #require(lastTurn(segments(answered)))
        #expect(!TranscriptRules.showsTimeline(plain, isStreaming: false))
        #expect(!TranscriptRules.showsTimeline(plain, isStreaming: true))
    }

    @Test("live while streaming before the answer starts, and again while a tool is running")
    func liveUntilTheAnswer() throws {
        let thinking = try #require(lastTurn(segments(thinkingOnly)))
        #expect(TranscriptRules.timelineIsLive(thinking, isStreaming: true))
        #expect(!TranscriptRules.timelineIsLive(thinking, isStreaming: false))
        let pending = try #require(lastTurn(segments(answerThenPendingTool)))
        #expect(TranscriptRules.timelineIsLive(pending, isStreaming: true))
        #expect(!TranscriptRules.timelineIsLive(pending, isStreaming: false))
        let settled = try #require(lastTurn(segments(answerThenToolResult)))
        #expect(!TranscriptRules.timelineIsLive(settled, isStreaming: true))
        #expect(ToolPresentation.header(for: pending, isLive: true) == .live("Terminal"))
    }
}

@Suite("TranscriptRules: scroll key")
struct ScrollKeyTests {
    @Test("the key changes as the last turn's body, steps, cards or dots change, and not otherwise")
    func followsGrowth() {
        let base = TranscriptRules.scrollKey(segments: segments(answered), showsTypingIndicator: false, liveError: nil)
        #expect(base == TranscriptRules.scrollKey(segments: segments(answered), showsTypingIndicator: false, liveError: nil))
        let longer = segments(answered.replacingOccurrences(of: "Hello", with: "Hello there"))
        #expect(base != TranscriptRules.scrollKey(segments: longer, showsTypingIndicator: false, liveError: nil))
        #expect(base != TranscriptRules.scrollKey(segments: segments(answered), showsTypingIndicator: true, liveError: nil))
        let pending = TranscriptRules.scrollKey(segments: segments(answerThenPendingTool), showsTypingIndicator: false, liveError: nil)
        let settled = TranscriptRules.scrollKey(segments: segments(answerThenToolResult), showsTypingIndicator: false, liveError: nil)
        #expect(pending != settled)
        #expect(base != TranscriptRules.scrollKey(segments: segments(answered), showsTypingIndicator: false, liveError: LiveRunError(runId: "u1", message: "x")))
    }
}

@Suite("TranscriptRules: run errors")
struct RunErrorTests {
    @Test("the rows' error shows when nothing live is known; an empty one gets the generic text")
    func rowError() throws {
        let turn = try #require(lastTurn(segments(erroredRun)))
        #expect(TranscriptRules.runError(for: turn, live: nil) == "This reply stopped with an error: 429 rate limited")
        let silent = try #require(lastTurn(segments(rowErrorNoMessage)))
        #expect(TranscriptRules.runError(for: silent, live: nil) == "The response failed.")
        let fine = try #require(lastTurn(segments(answered)))
        #expect(TranscriptRules.runError(for: fine, live: nil) == nil)
    }

    @Test("a live failure of the same run replaces the row's error: one error per run")
    func liveWins() throws {
        let turn = try #require(lastTurn(segments(erroredRun)))
        let live = LiveRunError(runId: "u1", message: "Invalid API key")
        #expect(TranscriptRules.runError(for: turn, live: live) == "This reply stopped with an error: Invalid API key")
        #expect(TranscriptRules.runError(for: turn, live: LiveRunError(runId: "u1", message: " ")) == "The response failed.")
        #expect(TranscriptRules.orphanRunError(segments: segments(erroredRun), live: live) == nil)
        let other = LiveRunError(runId: "u9", message: "x")
        #expect(TranscriptRules.runError(for: turn, live: other) == "This reply stopped with an error: 429 rate limited")
    }

    @Test("a live failure before any step has no turn, so it shows once under the prompt")
    func orphan() {
        let live = LiveRunError(runId: "u1", message: "")
        #expect(TranscriptRules.orphanRunError(segments: segments(userOnly), live: live) == "The response failed.")
        #expect(TranscriptRules.orphanRunError(segments: segments(userOnly), live: nil) == nil)
    }
}

@Suite("TranscriptRules: citations")
struct CitationMappingTests {
    @Test("citations become chips by rank, a later source with the same rank winning, host from siteName first")
    func lastWins() throws {
        let json = #"""
            [{"id":"u1","runId":"u1","role":"user","content":"q"},
             {"id":"a1","runId":"u1","role":"assistant","content":[{"type":"toolCall","id":"k1","name":"web_search","arguments":{"query":"x"}}]},
             {"id":"t1","runId":"u1","role":"toolResult","toolCallId":"k1","toolName":"web_search","content":[],"details":[{"rank":1,"link":"https://www.a.com/x","title":"A"},{"rank":2,"link":"https://b.com","title":"B","siteName":"Bee"}],"isError":false},
             {"id":"a2","runId":"u1","role":"assistant","content":[{"type":"toolCall","id":"k2","name":"web_search","arguments":{"query":"y"}}]},
             {"id":"t2","runId":"u1","role":"toolResult","toolCallId":"k2","toolName":"web_search","content":[],"details":[{"rank":1,"link":"https://c.com","title":"C"}],"isError":false},
             {"id":"a3","runId":"u1","role":"assistant","content":[{"type":"text","text":"x 【1-source】"}]}]
            """#
        let turn = try #require(lastTurn(segments(json)))
        let citations = TranscriptRules.markdownCitations(turn)
        #expect(citations.map(\.number) == [1, 2])
        #expect(citations[0].title == "C")
        #expect(citations[0].host == "c.com")
        #expect(citations[1].host == "Bee")
    }
}

#if DEBUG
@Suite("Message gallery fixtures")
struct MessageGalleryFixtureTests {
    @Test("every gallery run decodes into at least one user row and one turn")
    func fixturesDecode() {
        for run in MessageGalleryFixtures.runs {
            let segments = MessageGalleryFixtures.segments(run.json)
            #expect(segments.count == 2, "\(run.title)")
            #expect(lastTurn(segments) != nil, "\(run.title)")
        }
    }
}
#endif

@Suite("Transcript rules: search media sit in the answer's section")
struct SearchMediaSectionTests {
    @Test("a run with no answer and no error shows no gallery, as on the desktop; an answer or an error does")
    func mediaNeedsBodyOrError() throws {
        let bodyless = AssistantTurn(runId: "r", steps: [.thinking(.init(text: "x"))])
        let answered = AssistantTurn(runId: "r", body: "Done")
        #expect(!TranscriptRules.showsSearchMedia(bodyless, error: nil))
        #expect(TranscriptRules.showsSearchMedia(bodyless, error: "Rate limited"))
        #expect(TranscriptRules.showsSearchMedia(answered, error: nil))
    }
}

@MainActor
@Suite("Chat screen: its objects are built once (m9)")
struct ChatScreenObjectsTests {
    @Test("a LazyBox makes its value on first use only; a fresh box (a discarded init) makes nothing")
    func lazyBox() {
        var made = 0
        let box = LazyBox<Int>()
        #expect(box.isEmpty)
        #expect(box.value { made += 1; return 7 } == 7)
        #expect(box.value { made += 1; return 8 } == 7)
        #expect(made == 1)
        _ = LazyBox<Int>()
        #expect(made == 1)
    }
}
