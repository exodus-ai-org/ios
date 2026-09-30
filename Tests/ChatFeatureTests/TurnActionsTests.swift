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
    @Test("a finished answer gets copy, and no sources when it searched nothing")
    func plainAnswer() {
        let bar = TurnActions.bar(for: turn(answered), isStreaming: false, canRegenerate: false)
        #expect(bar == TurnActionBar(turnId: "run:u1", copyText: "Hello **there**", showsRegenerate: false, sourceCount: 0))
        #expect(bar?.showsSources == false)
        #expect(bar?.sourceIcons.isEmpty == true)
    }

    @Test("read aloud takes the answer as prose, and is offered when there is something to say")
    func readAloud() {
        let bar = TurnActions.bar(for: turn(searched), isStreaming: false, canRegenerate: false)
        #expect(bar?.speechText == "Found two")
        #expect(bar?.showsReadAloud == true)
        #expect(bar?.turnId == "run:u1")
        let code = TurnActionBar(copyText: "\u{3010}1-source\u{3011}", showsRegenerate: false, sourceCount: 0)
        #expect(code.showsReadAloud == false)
    }

    @Test("Sources draws the icons of its first three sites, each once, in the sources' order: Google's, as the desktop's")
    func sourceIcons() {
        func source(_ rank: Int, _ link: String, icon: String? = nil) -> CitationSource {
            CitationSource(rank: rank, link: link, favicon: icon)
        }
        let icons = TurnActions.sourceIcons([
            source(1, "https://a.example/1", icon: "https://icons.example/a.png"),
            source(2, "https://a.example/2"),
            source(3, "javascript:alert(1)", icon: "https://icons.example/x.png"),
            source(4, "https://b.example/1"),
            source(5, "https://c.example:8443/1"),
            source(6, "https://d.example/1"),
        ])
        #expect(icons.map(\.id) == ["https://a.example", "https://b.example", "https://c.example:8443"])
        #expect(
            icons.map(\.iconURL)
                == ["a.example", "b.example", "c.example"].map { SourceIcon.google(host: $0) })
    }

    @Test("sources that name no site leave the group one default glyph; no sources, no group")
    func noIcons() {
        #expect(TurnActions.sourceIcons([CitationSource(rank: 1, link: "not a link")]) == [SourceAvatar(id: "", iconURL: nil)])
        #expect(TurnActions.sourceIcons([]).isEmpty)
    }

    @Test("the bar carries the icons of the turn's own sources")
    func barIcons() {
        let bar = TurnActions.bar(for: turn(searched), isStreaming: false, canRegenerate: false)
        #expect(bar?.sourceIcons.map(\.id) == ["https://a.example", "https://b.example"])
        #expect(bar?.sourceIcons.map(\.iconURL) == [SourceIcon.google(host: "a.example"), SourceIcon.google(host: "b.example")])
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

    @Test("copy takes the whole markdown body, joined across the run's text blocks; a marker no source answers to is dropped")
    func copyText() {
        let twoBlocks = #"""
            [{"id":"u1","runId":"u1","role":"user","content":"hi"},
             {"id":"a1","runId":"u1","role":"assistant","content":[{"type":"text","text":"First."},{"type":"toolCall","id":"k1","name":"grep","arguments":{}}],"stopReason":"toolUse"},
             {"id":"t1","runId":"u1","role":"toolResult","toolCallId":"k1","toolName":"grep","content":[],"isError":false},
             {"id":"a2","runId":"u1","role":"assistant","content":[{"type":"text","text":"Second 【1-source】."}],"stopReason":"stop"}]
            """#
        let bar = TurnActions.bar(for: turn(twoBlocks), isStreaming: false, canRegenerate: false)
        #expect(turn(twoBlocks).body == "First.\n\nSecond \u{3010}1-source\u{3011}.")
        #expect(bar?.copyText == "First.\n\nSecond .")
    }

    @Test("copy writes references for what the answer cites; read aloud still takes the answer alone")
    func copyTextWithReferences() {
        let bar = TurnActions.bar(for: turn(searched), isStreaming: false, canRegenerate: false)
        #expect(bar?.copyText.contains("\u{3010}") == false)
        #expect(bar?.copyText.contains("[1]") == true)
        #expect(bar?.copyText.contains("\n\n---\n\n## ") == true)
        #expect(bar?.speechText == "Found two")
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
