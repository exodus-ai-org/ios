import Foundation
import Models
import Testing

@testable import ChatFeature

private func segments(_ json: String) -> [Segment] {
    let messages = try! JSONDecoder().decode([ChatMessage].self, from: Data(json.utf8))
    var cache = RunGrouper.Cache()
    return RunGrouper.group(messages, cache: &cache)
}

private func turn(_ json: String) -> AssistantTurn {
    guard case .assistantTurn(let turn)? = segments(json).last else { fatalError("no turn in fixture") }
    return turn
}

private let answered = #"""
    [{"id":"u1","runId":"u1","role":"user","content":"hi"},
     {"id":"a1","runId":"u1","role":"assistant","content":[{"type":"text","text":"Hello **there**"}],"timestamp":1700000000000}]
    """#
private let searched = #"""
    [{"id":"u1","runId":"u1","role":"user","content":"news"},
     {"id":"a1","runId":"u1","role":"assistant","content":[{"type":"toolCall","id":"k1","name":"web_search","arguments":{"query":"news"}}],"stopReason":"toolUse"},
     {"id":"t1","runId":"u1","role":"toolResult","toolCallId":"k1","toolName":"web_search","content":[{"type":"text","text":"ok"}],"details":[{"rank":1,"link":"https://a.example/1","title":"One"},{"rank":2,"link":"https://b.example/2","title":"Two"}],"isError":false},
     {"id":"a2","runId":"u1","role":"assistant","content":[{"type":"text","text":"Found two 【1-source】"}],"stopReason":"stop","timestamp":1700000005000}]
    """#
private let toolsOnly = #"""
    [{"id":"u1","runId":"u1","role":"user","content":"ls"},
     {"id":"a1","runId":"u1","role":"assistant","content":[{"type":"toolCall","id":"k1","name":"terminal","arguments":{"command":"ls"}}],"stopReason":"toolUse"},
     {"id":"t1","runId":"u1","role":"toolResult","toolCallId":"k1","toolName":"terminal","content":[{"type":"text","text":"{}"}],"details":{"command":"ls","exitCode":0,"stdout":"a","stderr":""},"isError":false}]
    """#

@Suite("TurnActions: the action bar")
struct ActionBarRulesTests {
    @Test("a finished answer gets copy, the time and no sources when it searched nothing")
    func plainAnswer() {
        let bar = TurnActions.bar(for: turn(answered), isStreaming: false, canRegenerate: false)
        #expect(bar == TurnActionBar(copyText: "Hello **there**", showsRegenerate: false, sourceCount: 0, timestampMs: 1_700_000_000_000))
        #expect(bar?.showsSources == false)
    }

    @Test("Sources shows with the turn's own count, and only when there is one")
    func sourcesCount() {
        let bar = TurnActions.bar(for: turn(searched), isStreaming: false, canRegenerate: false)
        #expect(bar?.sourceCount == 2)
        #expect(bar?.showsSources == true)
        #expect(TurnActions.bar(for: turn(answered), isStreaming: false, canRegenerate: false)?.showsSources == false)
    }

    @Test("Regenerate follows what the view model says about this turn")
    func regenerateFollowsTheFlag() {
        #expect(TurnActions.bar(for: turn(answered), isStreaming: false, canRegenerate: true)?.showsRegenerate == true)
        #expect(TurnActions.bar(for: turn(answered), isStreaming: false, canRegenerate: false)?.showsRegenerate == false)
    }

    @Test("no bar while the turn streams, whatever else is true")
    func noBarWhileStreaming() {
        #expect(TurnActions.bar(for: turn(searched), isStreaming: true, canRegenerate: true) == nil)
    }

    @Test("no bar without answer text: a run of tool cards, or a body of whitespace")
    func noBarWithoutAnAnswer() {
        #expect(TurnActions.bar(for: turn(toolsOnly), isStreaming: false, canRegenerate: true) == nil)
        #expect(TurnActions.bar(for: AssistantTurn(runId: "r", body: " \n "), isStreaming: false, canRegenerate: true) == nil)
        #expect(TurnActions.bar(for: AssistantTurn(runId: "r", body: ""), isStreaming: false, canRegenerate: true) == nil)
    }

    @Test("copy takes the whole markdown body, joined across the run's text blocks, markers and all")
    func copyText() {
        let twoBlocks = #"""
            [{"id":"u1","runId":"u1","role":"user","content":"hi"},
             {"id":"a1","runId":"u1","role":"assistant","content":[{"type":"text","text":"First."},{"type":"toolCall","id":"k1","name":"grep","arguments":{}}],"stopReason":"toolUse"},
             {"id":"t1","runId":"u1","role":"toolResult","toolCallId":"k1","toolName":"grep","content":[],"isError":false},
             {"id":"a2","runId":"u1","role":"assistant","content":[{"type":"text","text":"Second 【1-source】."}],"stopReason":"stop"}]
            """#
        let bar = TurnActions.bar(for: turn(twoBlocks), isStreaming: false, canRegenerate: false)
        #expect(bar?.copyText == "First.\n\nSecond \u{3010}1-source\u{3011}.")
        #expect(bar?.copyText == turn(twoBlocks).body)
    }

    @Test("the time reads from the last assistant message, and nothing for a missing, zero or broken timestamp")
    func timeText() {
        #expect(TurnActions.bar(for: turn(searched), isStreaming: false, canRegenerate: false)?.timestampMs == 1_700_000_005_000)
        #expect(TurnActions.timeText(nil) == nil)
        #expect(TurnActions.timeText(0) == nil)
        #expect(TurnActions.timeText(-5) == nil)
        #expect(TurnActions.timeText(.nan) == nil)
        #expect(TurnActions.timeText(.infinity) == nil)
        #expect(TurnActions.timeText(1_700_000_000_000)?.isEmpty == false)
    }

    @Test("the time is the Recents list's format: exactly the short time today, a weekday this week, a date before")
    func timeFormat() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        let locale = Locale(identifier: "en_US")
        let now = Date(timeIntervalSince1970: 1_790_078_400)  // 2026-09-22 12:00 UTC, a Tuesday
        func text(_ secondsBefore: TimeInterval) -> String? {
            TurnActions.timeText(
                (now.timeIntervalSince1970 - secondsBefore) * 1000, now: now, calendar: calendar, locale: locale)
        }
        #expect(text(2 * 3600 + 45 * 60) == "9:15\u{202F}AM")
        #expect(text(24 * 3600) == "Mon")
        #expect(TurnActions.timeText(1_700_000_000_000, now: now, calendar: calendar, locale: locale) == "11/14/2023")
    }
}

@Suite("TurnActions: which turn may regenerate")
struct RegenerableTurnTests {
    private let two = #"""
        [{"id":"u1","runId":"u1","role":"user","content":"one"},
         {"id":"a1","runId":"u1","role":"assistant","content":[{"type":"text","text":"A1"}],"stopReason":"stop"},
         {"id":"u2","runId":"u2","role":"user","content":"two"},
         {"id":"a2","runId":"u2","role":"assistant","content":[{"type":"text","text":"A2"}],"stopReason":"stop"}]
        """#

    @Test("only the last answer, once history is known and nothing is in flight")
    func lastAnswerOnly() {
        let all = segments(two)
        #expect(TurnActions.regenerableTurnId(segments: all, hasLoadedHistory: true, isTurnInFlight: false) == "run:u2")
        #expect(TurnActions.regenerableTurnId(segments: all, hasLoadedHistory: true, isTurnInFlight: true) == nil)
        #expect(TurnActions.regenerableTurnId(segments: all, hasLoadedHistory: false, isTurnInFlight: false) == nil)
    }

    @Test("nothing when the transcript ends with a question nobody answered, or is empty")
    func noAnswerNoRegenerate() {
        let unanswered = segments(#"[{"id":"u1","runId":"u1","role":"user","content":"hi"}]"#)
        #expect(TurnActions.regenerableTurnId(segments: unanswered, hasLoadedHistory: true, isTurnInFlight: false) == nil)
        #expect(TurnActions.regenerableTurnId(segments: [], hasLoadedHistory: true, isTurnInFlight: false) == nil)
    }

    @Test("nothing to ask again without a user message, or with one that has no text or image")
    func needsAResendableQuestion() {
        let assistantOnly = segments(#"[{"id":"a1","runId":"r","role":"assistant","content":[{"type":"text","text":"Hi"}],"stopReason":"stop"}]"#)
        #expect(TurnActions.regenerableTurnId(segments: assistantOnly, hasLoadedHistory: true, isTurnInFlight: false) == nil)
        let emptyQuestion = segments(#"""
            [{"id":"u1","runId":"u1","role":"user","content":"   "},
             {"id":"a1","runId":"u1","role":"assistant","content":[{"type":"text","text":"Hi"}],"stopReason":"stop"}]
            """#)
        #expect(TurnActions.resendableUserMessage(in: emptyQuestion) == nil)
        #expect(TurnActions.regenerableTurnId(segments: emptyQuestion, hasLoadedHistory: true, isTurnInFlight: false) == nil)
    }

    @Test("the question is the transcript's last user message, an image-only one included")
    func lastQuestion() {
        #expect(TurnActions.resendableUserMessage(in: segments(two))?.id == "u2")
        let imageOnly = segments(#"""
            [{"id":"u1","runId":"u1","role":"user","content":[{"type":"image","data":"data:image/png;base64,AAAA","mimeType":"image/png"}]},
             {"id":"a1","runId":"u1","role":"assistant","content":[{"type":"text","text":"A picture."}],"stopReason":"stop"}]
            """#)
        #expect(TurnActions.resendableUserMessage(in: imageOnly)?.id == "u1")
    }
}
