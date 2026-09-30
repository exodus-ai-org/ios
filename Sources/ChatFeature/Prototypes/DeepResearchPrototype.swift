#if DEBUG
import Foundation
import Models
import NetworkingKit
import Synchronization
import SwiftUI

/// The deep research card is real now: this group draws `DeepResearchCard` from `ToolCard`s built the way the
/// transcript builds them, reading desktop-shaped job rows and progress messages from a stand-in computer. "Live" walks
/// through a whole job, a step per poll. `-CardPrototypesResearchReport` opens the finished report at launch.
struct ProtoDeepResearchSection: View {
    @State private var jobs = Self.makeStore()
    @State private var report: DeepResearchReport?

    /// `-CardPrototypesResearchEndings`: the stalled and failed states first, for screenshots.
    private static let endsFirst = ProcessInfo.processInfo.arguments.contains("-CardPrototypesResearchEndings")
    private static let opensReport = ProcessInfo.processInfo.arguments.contains("-CardPrototypesResearchReport")
    /// `-CardPrototypesResearchSources`: the report opens at its sources, source 3 marked.
    private static let opensSources = ProcessInfo.processInfo.arguments.contains("-CardPrototypesResearchSources")

    var body: some View {
        VStack(alignment: .leading, spacing: 28) {
            UserBubble(text: ProtoFixtures.researchSubject)
            if Self.endsFirst { endings }
            ProtoInReply(state: "Live: a step per poll, then the report") { Self.cards("k0", details: #"{"id":"dr_live"}"#) }
            ProtoInReply(state: "Running: searching") { Self.cards("k1", details: #"{"id":"dr_run"}"#) }
            ProtoInReply(state: "Running: writing the report") { Self.cards("k2", details: #"{"id":"dr_write"}"#) }
            ProtoInReply(
                state: "Done: the report's opening, tap to read it all",
                answer: "The report is ready — the short version: filter, re-allocate, price."
            ) {
                Self.cards("k3", details: #"{"id":"dr_done"}"#)
            }
            if !Self.endsFirst { endings }
        }
        .environment(\.deepResearchJobs, jobs)
        .task {
            guard Self.opensReport || Self.opensSources else { return }
            await jobs.follow("dr_done")
            if case .done(let done) = jobs.entry("dr_done").state { report = done }
        }
        .sheet(item: $report) { DeepResearchReportView(report: $0, startAt: Self.opensSources ? 3 : nil) }
    }

    @ViewBuilder
    private var endings: some View {
        ProtoInReply(state: "Stalled: still 'streaming', nothing new for 15 min") {
            Self.cards("k4", details: #"{"id":"dr_stall"}"#)
        }
        ProtoInReply(state: "Failed: jobStatus 'failed' with its errorMessage") {
            Self.cards("k5", details: #"{"id":"dr_failed"}"#)
        }
        ProtoInReply(state: "Failed: no errorMessage stored") { Self.cards("k9", details: #"{"id":"dr_failed_bare"}"#) }
        ProtoInReply(state: "Gone: deleted on the computer (404)") { Self.cards("k6", details: #"{"id":"dr_gone"}"#) }
        ProtoInReply(state: "Refused: the tool answered {error}") {
            Self.cards("k7", details: #"{"error":"Brave API key is not configured"}"#)
        }
        ProtoInReply(state: "Tool error") { Self.cards("k8", details: "null", isError: true) }
    }

    private static func makeStore() -> DeepResearchStore {
        let live = Mutex(0)
        let rows: [String: (row: String, messages: String)] = [
            "dr_run": (ProtoFixtures.researchRow("dr_run", status: "streaming"), ProtoFixtures.researchMessages(searched: 2)),
            "dr_write": (
                ProtoFixtures.researchRow("dr_write", status: "streaming"), ProtoFixtures.researchMessages(searched: 4, writing: true)
            ),
            "dr_done": (
                ProtoFixtures.researchRow(
                    "dr_done", status: "archived", report: ProtoFixtures.researchReport, sources: ProtoFixtures.researchSources),
                "[]"
            ),
            "dr_failed": (
                ProtoFixtures.researchRow(
                    "dr_failed", status: "failed",
                    errorMessage: "APICallError: Rate limit reached for requests. Please try again in 20s."),
                "[]"
            ),
            "dr_failed_bare": (ProtoFixtures.researchRow("dr_failed_bare", status: "failed"), "[]"),
        ]
        let store = DeepResearchStore(
            fetcher: .init(
                result: { id in
                    try await Task.sleep(for: .milliseconds(300))
                    if id == "dr_live" {
                        let step = live.withLock { step in
                            defer { step += 1 }
                            return step
                        }
                        let row =
                            if step >= 6 {
                                ProtoFixtures.researchRow(
                                    id, status: "archived", report: ProtoFixtures.researchReport,
                                    sources: ProtoFixtures.researchSources)
                            } else {
                                ProtoFixtures.researchRow(id, status: "streaming")
                            }
                        return Data(row.utf8)
                    }
                    guard let row = rows[id] else {
                        throw HTTPError(statusCode: 404, code: "DEEP_RESEARCH_NOT_FOUND", message: "")
                    }
                    return Data(row.row.utf8)
                },
                messages: { id in
                    if id == "dr_live" {
                        let step = live.withLock { $0 }
                        return Data(ProtoFixtures.researchMessages(searched: min(step, 4), writing: step >= 5).utf8)
                    }
                    return Data((rows[id]?.messages ?? "[]").utf8)
                }),
            interval: .seconds(2), now: { try! Date.ISO8601FormatStyle().parse("2026-09-24T09:10:00Z") })
        let stalled =
            (try? JSONDecoder().decode([DeepResearchMessage].self, from: Data(ProtoFixtures.researchMessages(searched: 1).utf8)))
            ?? []
        store.entry("dr_stall").state = .stalled(DeepResearchProgress(events: stalled, startedAt: nil))
        return store
    }

    private static func cards(_ id: String, details: String, isError: Bool = false) -> some View {
        let text: String
        if isError {
            text = "Failed to start the research: the database is locked"
        } else {
            text = "{}"
        }
        let messages = [
            message(#"{"id":"u","runId":"u","role":"user","content":"research","timestamp":1}"#),
            message(
                #"{"id":"a-\#(id)","runId":"u","role":"assistant","content":[{"type":"toolCall","id":"\#(id)","name":"deep_research","arguments":{"subject":"\#(ProtoFixtures.researchSubject)"}}],"stopReason":"toolUse","timestamp":2}"#
            ),
            message(
                #"{"id":"t-\#(id)","runId":"u","role":"toolResult","toolCallId":"\#(id)","toolName":"deep_research","content":[{"type":"text","text":"\#(text)"}],"details":\#(details),"isError":\#(isError),"timestamp":3}"#
            ),
        ]
        var cache = RunGrouper.Cache()
        let cards = RunGrouper.group(messages, cache: &cache).flatMap { segment -> [ToolCard] in
            if case .assistantTurn(let turn) = segment { turn.toolCards } else { [] }
        }
        return VStack(alignment: .leading) {
            ForEach(cards, id: \.renderKey) { ToolCardView(card: $0) }
        }
    }

    private static func message(_ json: String) -> ChatMessage {
        try! JSONDecoder().decode(ChatMessage.self, from: Data(json.utf8))
    }
}

extension DeepResearchReport: Identifiable {
    var id: String { markdown }
}
#endif
