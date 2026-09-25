import Foundation
import Models
import Testing

@testable import ChatFeature

private func segments(_ json: String) -> [Segment] {
    let messages = try! JSONDecoder().decode([ChatMessage].self, from: Data(json.utf8))
    var cache = RunGrouper.Cache()
    return RunGrouper.group(messages, cache: &cache)
}

private func turns(_ segments: [Segment]) -> [AssistantTurn] {
    segments.compactMap { if case .assistantTurn(let turn) = $0 { turn } else { nil } }
}

private func json(_ text: String) throws -> JSONValue {
    try JSONDecoder().decode(JSONValue.self, from: Data(text.utf8))
}

private let splitRun = #"""
    [{"id":"u1","runId":"X","role":"user","content":"one"},
     {"id":"a","runId":"X","role":"assistant","content":[{"type":"text","text":"first"}]},
     {"id":"u2","runId":"Y","role":"user","content":"two"},
     {"id":"b","runId":"X","role":"assistant","content":[{"type":"text","text":"second"}]}]
    """#

@Suite("Fix round: live errors on split runs")
struct SplitRunLiveErrorTests {
    @Test("a run split into two turns shows its live error once, on the last of them")
    func lastOccurrenceOnly() throws {
        let all = segments(splitRun)
        #expect(all.map(\.id) == ["u1", "run:X", "u2", "run:X#2"])
        let live = LiveRunError(runId: "X", message: "boom")
        let target = TranscriptRules.liveErrorTurnId(segments: all, live: live)
        #expect(target == "run:X#2")
        let shown = turns(all).filter { turn in
            TranscriptRules.runError(for: turn, live: turn.id == target ? live : nil) != nil
        }
        #expect(shown.map(\.id) == ["run:X#2"])
        #expect(TranscriptRules.liveErrorTurnId(segments: all, live: nil) == nil)
        #expect(TranscriptRules.liveErrorTurnId(segments: all, live: LiveRunError(runId: "Z", message: "")) == nil)
    }
}

@Suite("Fix round: scroll key")
struct ScrollKeyThinkingTests {
    @Test("a thinking step that grows moves the key, so the transcript follows it")
    func thinkingGrowth() {
        func key(_ thinking: String) -> TranscriptRules.ScrollKey {
            let turn = AssistantTurn(runId: "r", steps: [.thinking(.init(text: thinking))])
            return TranscriptRules.scrollKey(segments: [.assistantTurn(turn)], showsTypingIndicator: false, liveError: nil)
        }
        #expect(key("Weighing") != key("Weighing the options"))
        #expect(key("Weighing") == key("Weighing"))
    }
}

@Suite("Fix round: tool presentation")
struct ToolPresentationFixRoundTests {
    @Test("an exit code outside Int's range, or not whole, is dropped rather than trapping")
    func exitCodeRange() throws {
        #expect(ToolPresentation.terminalOutput(try json(#"{"command":"x","exitCode":1e20}"#))?.exitCode == nil)
        #expect(ToolPresentation.terminalOutput(try json(#"{"command":"x","exitCode":-1e300}"#))?.exitCode == nil)
        #expect(ToolPresentation.terminalOutput(try json(#"{"command":"x","exitCode":1.5}"#))?.exitCode == nil)
        #expect(ToolPresentation.terminalOutput(try json(#"{"command":"x","exitCode":-2}"#))?.exitCode == "-2")
    }

    @Test("the generic card's payload is cut after its line cap, with an ellipsis; a short one is whole")
    func payloadCap() {
        let long = JSONValue.string((1...10).map(String.init).joined(separator: "\n"))
        #expect(ToolPresentation.prettyPayload(long, maxLines: 3) == "1\n2\n3\n\u{2026}")
        #expect(ToolPresentation.prettyPayload(long, maxLines: 10) == (1...10).map(String.init).joined(separator: "\n"))
        #expect(ToolPresentation.hasPayload(nil) == false)
        #expect(ToolPresentation.hasPayload(.null) == false)
        #expect(ToolPresentation.hasPayload(.string("")) == false)
        #expect(ToolPresentation.hasPayload(.object([:])))
    }

    @Test("a terminal card offers Show full output only when there is more than its collapsed height")
    func terminalLength() {
        func output(_ stdout: String, command: String = "ls") -> ToolPresentation.TerminalOutput {
            .init(command: command, cwd: nil, exitCode: "0", stdout: stdout, stderr: "")
        }
        #expect(!ToolPresentation.terminalOutputIsLong(output("a\nb"), collapsedLines: 12))
        #expect(ToolPresentation.terminalOutputIsLong(output((1...20).map(String.init).joined(separator: "\n")), collapsedLines: 12))
        #expect(ToolPresentation.terminalOutputIsLong(output(String(repeating: "x", count: 2000)), collapsedLines: 12))
    }

    @Test("a turn with a failed tool is marked in its header; one without is not")
    func failedToolHeader() {
        let failed = AssistantTurn(
            runId: "r", steps: [.toolCall(.init(id: "k", name: "read_file", status: .failed, errorText: "ENOENT"))])
        let fine = AssistantTurn(runId: "r", steps: [.toolCall(.init(id: "k", name: "read_file"))])
        #expect(ToolPresentation.hasFailedTool(failed))
        #expect(!ToolPresentation.hasFailedTool(fine))
    }
}

@MainActor
@Suite("Fix round: AssistantTurnView equality")
struct AssistantTurnViewEqualityTests {
    private let turn = AssistantTurn(runId: "r", body: "Answer")

    @Test("equal on what it draws; a different turn, streaming flag, error, bar or retry offer is not equal")
    func drawnValues() {
        let base = AssistantTurnView(turn: turn, isStreaming: false, error: nil)
        #expect(base == AssistantTurnView(turn: turn, isStreaming: false, error: nil))
        #expect(base != AssistantTurnView(turn: AssistantTurn(runId: "r", body: "Answer!"), isStreaming: false, error: nil))
        #expect(base != AssistantTurnView(turn: turn, isStreaming: true, error: nil))
        #expect(base != AssistantTurnView(turn: turn, isStreaming: false, error: "boom"))
        #expect(base != AssistantTurnView(turn: turn, isStreaming: false, error: nil, offersRetry: true))
        let bar = TurnActionBar(copyText: "Answer", showsRegenerate: true, sourceCount: 0, timestampMs: nil)
        #expect(base != AssistantTurnView(turn: turn, isStreaming: false, error: nil, actionBar: bar))
    }

    @Test("the closures are left out: new closures on every render keep a settled turn equal")
    func closuresIgnored() {
        let lhs = AssistantTurnView(turn: turn, isStreaming: false, error: nil, regenerate: {}, showSources: { _, _ in })
        let rhs = AssistantTurnView(
            turn: turn, isStreaming: false, error: nil, regenerate: { print("other") }, showSources: { _, _ in print("x") })
        #expect(lhs == rhs)
    }

    @Test("a citation chip opens the Sources sheet of its own turn at the chip's source")
    func chipWiring() {
        var opened: [(String, Int?)] = []
        let tap = AssistantTurnView.citationTap(turnId: "run:r#2") { opened.append(($0, $1)) }
        tap(3)
        #expect(opened.count == 1)
        #expect(opened.first?.0 == "run:r#2")
        #expect(opened.first?.1 == 3)
    }
}

@Suite("Fix round: Regenerate on the error line")
struct RetryOnErrorRulesTests {
    private let failedBeforeAnswering = #"""
        [{"id":"u1","runId":"u1","role":"user","content":"hi"},
         {"id":"a1","runId":"u1","role":"assistant","content":[],"stopReason":"error","errorMessage":"boom"}]
        """#

    @Test("offered only on an error with no action bar, and only where Regenerate may run")
    func rule() {
        let bar = TurnActionBar(copyText: "x", showsRegenerate: true, sourceCount: 0, timestampMs: nil)
        #expect(TurnActions.showsRetryOnError(hasError: true, bar: nil, canRegenerate: true))
        #expect(!TurnActions.showsRetryOnError(hasError: true, bar: bar, canRegenerate: true))
        #expect(!TurnActions.showsRetryOnError(hasError: true, bar: nil, canRegenerate: false))
        #expect(!TurnActions.showsRetryOnError(hasError: false, bar: nil, canRegenerate: true))
    }

    @Test("an errored run with no answer is still the last turn Regenerate belongs to, and has no bar")
    func errorWithoutAnswer() throws {
        let all = segments(failedBeforeAnswering)
        let turn = try #require(turns(all).last)
        #expect(TurnActions.regenerableTurnId(segments: all, hasLoadedHistory: true, isTurnInFlight: false) == turn.id)
        #expect(TurnActions.bar(for: turn, isStreaming: false, canRegenerate: true) == nil)
        #expect(TurnActions.regenerableTurnId(segments: all, hasLoadedHistory: true, isTurnInFlight: true) == nil)
    }

    @Test("a failure before any step: the error under the prompt may retry, never while in flight or without a live error")
    func orphan() {
        let all = segments(#"[{"id":"u1","runId":"u1","role":"user","content":"hi"}]"#)
        let live = LiveRunError(runId: "u1", message: "boom")
        #expect(TurnActions.canRetryOrphan(segments: all, liveError: live, hasLoadedHistory: true, isTurnInFlight: false))
        #expect(!TurnActions.canRetryOrphan(segments: all, liveError: live, hasLoadedHistory: true, isTurnInFlight: true))
        #expect(!TurnActions.canRetryOrphan(segments: all, liveError: nil, hasLoadedHistory: true, isTurnInFlight: false))
        #expect(!TurnActions.canRetryOrphan(segments: all, liveError: live, hasLoadedHistory: false, isTurnInFlight: false))
    }
}

@Suite("Fix round: notice announcement")
struct NoticeAnnouncementTests {
    @Test("VoiceOver hears the banner's title before the server's message")
    func titled() {
        let text = NoticeBanner.announcement(for: .init(level: .warning, message: "Places key expired"))
        #expect(text == "Heads up\nPlaces key expired")
    }
}
