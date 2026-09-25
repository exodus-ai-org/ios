import Foundation
import MarkdownKit
import Models
import NetworkingKit
import Synchronization
import SwiftUI
import Testing
import UIKit

@testable import ChatFeature

// Desktop shapes (src/main/lib/ai/calling-tools/deep-research.ts, server/routes/deep-research.ts): the tool returns
// `{id, toolCallId}` at once and the job runs on; `/result/:id` is the `deep_research` row (`jobStatus` streaming →
// archived), `/messages/:id` its progress notifications.

private func decode(_ json: String) -> ChatMessage {
    try! JSONDecoder().decode(ChatMessage.self, from: Data(json.utf8))
}

private func user(_ id: String) -> ChatMessage {
    decode(#"{"id":"\#(id)","runId":"\#(id)","role":"user","content":"q","timestamp":1}"#)
}

private func call(_ id: String, _ run: String, _ callId: String, subject: String = "Car traffic") -> ChatMessage {
    decode(
        #"{"id":"\#(id)","runId":"\#(run)","role":"assistant","content":[{"type":"toolCall","id":"\#(callId)","name":"deep_research","arguments":{"subject":"\#(subject)"}}],"stopReason":"toolUse","timestamp":2}"#
    )
}

private func result(_ id: String, _ run: String, _ callId: String, details: String) -> ChatMessage {
    decode(
        #"{"id":"\#(id)","runId":"\#(run)","role":"toolResult","toolCallId":"\#(callId)","toolName":"deep_research","content":[{"type":"text","text":"{}"}],"details":\#(details),"isError":false,"timestamp":3}"#
    )
}

private func failedCall(_ id: String, _ run: String, _ callId: String, text: String) -> ChatMessage {
    decode(
        #"{"id":"\#(id)","runId":"\#(run)","role":"toolResult","toolCallId":"\#(callId)","toolName":"deep_research","content":[{"type":"text","text":"\#(text)"}],"details":null,"isError":true,"timestamp":3}"#
    )
}

private func answer(_ id: String, _ run: String, _ text: String) -> ChatMessage {
    decode(
        #"{"id":"\#(id)","runId":"\#(run)","role":"assistant","content":[{"type":"text","text":"\#(text)"}],"stopReason":"stop","timestamp":4}"#
    )
}

private func cards(_ messages: [ChatMessage]) -> [ToolCard] {
    var cache = RunGrouper.Cache()
    return RunGrouper.group(messages, cache: &cache).flatMap { segment -> [ToolCard] in
        if case .assistantTurn(let turn) = segment { turn.toolCards } else { [] }
    }
}

private func iso(_ text: String) -> Date { try! Date.ISO8601FormatStyle(includingFractionalSeconds: true).parse(text) }

private func job(_ status: String, report: String? = nil, sources: String = "[]", start: String = "2026-09-24T09:00:00.000Z")
    -> String
{
    let reportJSON = report.map { String(data: try! JSONEncoder().encode($0), encoding: .utf8)! } ?? "null"
    return #"{"id":"dr_1","toolCallId":"k1","title":"Car traffic","jobStatus":"\#(status)","finalReport":\#(reportJSON),"webSources":\#(sources),"startTime":"\#(start)","endTime":"2026-09-24T09:12:00.000Z"}"#
}

private func message(_ id: String, _ data: String, at: String = "2026-09-24T09:01:00.000Z") -> String {
    #"{"id":"\#(id)","deepResearchId":"dr_1","message":{"jsonrpc":"2.0","method":"message/deep-research","params":{"data":\#(data)}},"createdAt":"\#(at)"}"#
}

private func messageRow(_ id: String, _ data: String, at: String = "2026-09-24T09:01:00.000Z") -> DeepResearchMessage {
    DeepResearchMessage(json: try! JSONDecoder().decode(JSONValue.self, from: Data(message(id, data, at: at).utf8)))!
}

private let sources =
    #"[{"rank":1,"link":"https://a.example/1","title":"Superblocks","snippet":"s","hostname":"a.example"},{"rank":2,"link":"https://b.example/2","title":"Ghent","snippet":"","hostname":"b.example"},{"rank":3,"link":"https://c.example/3","title":"Paris","snippet":"","hostname":"c.example"}]"#

private let sampleReport =
    "# Car traffic\n\n## Summary\n\nGhent cut trips 【2-source】.\n\n## What worked\n\n- Filters\n- Buses\n\n## What did not\n\nNothing."

private let progressMessages =
    "["
    + [
        message("m0", #"{"type":0}"#, at: "2026-09-24T09:00:01.000Z"),
        message(
            "m1",
            #"{"type":1,"query":"Car traffic","searchQueries":[{"query":"Ghent plan","researchGoal":"Modal shift"},{"query":"Paris","researchGoal":"Trips"}]}"#,
            at: "2026-09-24T09:00:05.000Z"),
        message(
            "m2", #"{"type":2,"query":"Ghent plan","webSearchResults":[{"rank":1,"link":"https://b.example/2","title":"G"}]}"#,
            at: "2026-09-24T09:00:09.000Z"),
    ].joined(separator: ",") + "]"

/// A stand-in computer: what the result and messages routes answer, and how often each was asked.
private final class FakeComputer: Sendable {
    struct Answer: Sendable {
        var job: String?
        var status = 200
        var messages = "[]"
        var fails = false
    }

    private let state: Mutex<(answers: [Answer], results: Int, messages: Int, reports: Int)>

    init(_ answers: [Answer]) { state = Mutex((answers, 0, 0, 0)) }

    var resultCount: Int { state.withLock { $0.results } }
    var messageCount: Int { state.withLock { $0.messages } }
    var reportCount: Int { state.withLock { $0.reports } }

    /// The next answer; the last one repeats.
    private func current(counting: Bool) -> Answer {
        state.withLock { state in
            let index = min(state.results, state.answers.count - 1)
            if counting { state.results += 1 }
            return state.answers[index]
        }
    }

    var fetcher: DeepResearchStore.Fetcher {
        DeepResearchStore.Fetcher(
            result: { [self] _ in
                let answer = current(counting: true)
                if answer.fails { throw URLError(.timedOut) }
                if answer.status != 200 { throw HTTPError(statusCode: answer.status, code: "NOT_FOUND", message: "gone") }
                return Data((answer.job ?? "").utf8)
            },
            messages: { [self] _ in
                let answer = state.withLock { state -> Answer in
                    state.messages += 1
                    return state.answers[min(max(state.results - 1, 0), state.answers.count - 1)]
                }
                return Data(answer.messages.utf8)
            },
            reportUnreadable: { [self] in state.withLock { $0.reports += 1 } })
    }
}

@MainActor
private func store(_ computer: FakeComputer, now: Date = iso("2026-09-24T09:01:00.000Z")) -> DeepResearchStore {
    DeepResearchStore(
        fetcher: computer.fetcher, interval: .milliseconds(5), maximumInterval: .milliseconds(20), stallAfter: 15 * 60,
        now: { now })
}

// MARK: - The card's model

@Suite("Deep research: the card's model, built with the turn")
struct DeepResearchModelTests {
    @Test("{id} names the job with the call's subject; {error} is a refusal; a failed call keeps its message")
    func phases() throws {
        let started = cards([user("u"), call("a", "u", "k1"), result("t", "u", "k1", details: #"{"id":"dr_1","toolCallId":"k1"}"#)])
        #expect(started.first?.content.deepResearch == DeepResearchCardModel(subject: "Car traffic", phase: .job(id: "dr_1")))
        let refused = cards([user("u"), call("a", "u", "k2"), result("t", "u", "k2", details: #"{"error":"No key"}"#)])
        #expect(refused.first?.content.deepResearch?.phase == .refused("No key"))
        let failed = cards([user("u"), call("a", "u", "k3"), failedCall("t", "u", "k3", text: "boom")])
        #expect(failed.first?.content.deepResearch == DeepResearchCardModel(subject: "Car traffic", phase: .failed("boom")))
        #expect([started, refused, failed].allSatisfy { $0.allSatisfy(ToolCardRegistry.canDraw) })
    }

    @Test("a running call has no card yet (its step shows it); the result arrives at once")
    func pending() {
        #expect(cards([user("u"), call("a", "u", "k1")]).isEmpty)
    }

    @Test("details that are no deep_research shape fall back to the generic card and are reported without the payload")
    @MainActor
    func undecodable() throws {
        let card = try #require(cards([user("u"), call("a", "u", "k1"), result("t", "u", "k1", details: #"{"secret":"s3cr3t"}"#)]).first)
        #expect(card.content == .undecodable)
        guard case .generic(let issue) = ToolCardRegistry.resolve(card) else {
            Issue.record("drew a card from bad details")
            return
        }
        let reported = try #require(issue)
        #expect(reported.message == "Unreadable deep_research card shown as the generic card")
        #expect(!"\(reported)".contains("s3cr3t"))
    }
}

// MARK: - Progress and report

@Suite("Deep research: progress and the report")
struct DeepResearchProgressTests {
    @Test("the step follows the last message; searches, distinct sources and learnings are counted; goals kept")
    func progress() {
        let events = [
            messageRow("0", #"{"type":0}"#, at: "2026-09-24T09:00:01.000Z"),
            messageRow(
                "1",
                #"{"type":1,"query":"T","searchQueries":[{"query":"q1","researchGoal":"g1"},{"query":"q2","researchGoal":"g2"},{"query":"q3","researchGoal":"g3"},{"query":"q4","researchGoal":"g4"}]}"#,
                at: "2026-09-24T09:00:02.000Z"),
            messageRow("2", #"{"type":2,"query":"q1","webSearchResults":[{"rank":1,"link":"https://a"},{"rank":2,"link":"https://b"}]}"#),
            messageRow("3", #"{"type":3,"learnings":[{"learning":"x"},{"learning":"y"}]}"#),
            messageRow("4", #"{"type":2,"query":"q2","webSearchResults":[{"rank":1,"link":"https://b"},{"rank":2,"link":"https://c"}]}"#),
            messageRow("5", #"{"type":7}"#),
            messageRow("6", #"{"type":2,"query":"q3","webSearchResults":[]}"#),
            messageRow("7", #"{"type":2,"query":"new","webSearchResults":[]}"#, at: "2026-09-24T09:05:00.000Z"),
        ]
        let progress = DeepResearchProgress(events: events, startedAt: iso("2026-09-24T09:00:00.000Z"))
        #expect(progress.step == .searched("new"))
        #expect(progress.searches.map(\.query) == ["q1", "q2", "q3", "new"])
        #expect(progress.recent.map(\.query) == ["q2", "q3", "new"])
        #expect(progress.recent.map(\.goal) == ["g2", "g3", ""])
        #expect(progress.sources == 3)
        #expect(progress.learnings == 2)
        #expect(progress.lastActivity == iso("2026-09-24T09:05:00.000Z"))
        #expect(DeepResearchProgress(events: Array(events.prefix(4)), startedAt: nil).step == .planning)
        #expect(DeepResearchProgress(events: Array(events.prefix(2)), startedAt: nil).step == .searching)
        #expect(DeepResearchProgress(events: events + [messageRow("8", #"{"type":4}"#)], startedAt: nil).step == .writing)
        let fresh = DeepResearchProgress(events: [], startedAt: iso("2026-09-24T09:00:00.000Z"))
        #expect(fresh.step == .starting)
        #expect(fresh.lastActivity == iso("2026-09-24T09:00:00.000Z"))
    }

    @Test("the report: the preview drops its # title and keeps three blocks; sources split cited / more; chips by rank")
    func report() throws {
        let row = try #require(DeepResearchJob(json: try JSONDecoder().decode(JSONValue.self, from: Data(job("archived", report: sampleReport, sources: sources).utf8))))
        let parsed = DeepResearchReport(job: row, report: sampleReport)
        #expect(parsed.document.blocks.count == 7)
        #expect(parsed.preview.blocks.count == DeepResearchReport.previewBlockCount)
        guard case .heading(level: 2, _)? = parsed.preview.blocks.first?.kind else {
            Issue.record("the preview starts with the title")
            return
        }
        #expect(parsed.cited.map(\.rank) == [2])
        #expect(parsed.more.map(\.rank) == [1, 3])
        #expect(parsed.citations.map(\.number) == [1, 2, 3])
        #expect(parsed.citations[1].host == "b.example")
        #expect(parsed.duration == 720)
        #expect(DeepResearchText.completed(parsed).contains("sources: 3"))
        let untitled = DeepResearchReport(job: row, report: "Just a line.")
        #expect(untitled.preview.blocks.count == 1)
        #expect(untitled.cited.isEmpty && untitled.more.count == 3)
    }

    @Test("copy: the desktop's step lines, the counts")
    func copy() {
        #expect(DeepResearchText.step(.searched("Ghent")) == "Searched for \"Ghent\"")
        #expect(DeepResearchText.step(.writing) == "Start writing final report...")
        #expect(DeepResearchText.step(.starting) == "Start deep researching...")
        #expect(DeepResearchText.sources(4) == "Sources: 4")
        #expect(DeepResearchText.unknownStatus("paused").contains("paused"))
    }
}

// MARK: - The store

@MainActor
// A regression that keeps polling a settled job would hang, not fail: the limit turns that into a failure.
@Suite("Deep research: reading the job from the computer", .serialized, .timeLimit(.minutes(1)))
struct DeepResearchStoreTests {
    @Test("a streaming job is polled with its messages until it is archived; then nothing more is asked")
    func pollsUntilDone() async {
        let computer = FakeComputer([
            .init(job: job("streaming"), messages: progressMessages),
            .init(job: job("streaming"), messages: progressMessages),
            .init(job: job("archived", report: sampleReport, sources: sources)),
        ])
        let jobs = store(computer)
        await jobs.follow("dr_1")
        guard case .done(let done) = jobs.entry("dr_1").state else {
            Issue.record("not done: \(jobs.entry("dr_1").state)")
            return
        }
        #expect(done.cited.map(\.rank) == [2])
        #expect(computer.resultCount == 3)
        #expect(computer.messageCount == 2)
        await jobs.follow("dr_1")
        #expect(computer.resultCount == 3)
    }

    @Test("404 is a job gone from the computer; failed, terminated and unknown statuses settle without polling")
    func settled() async {
        for (answer, expected) in [
            (FakeComputer.Answer(job: nil, status: 404), DeepResearchJobState.missing),
            (.init(job: job("failed")), .failed(terminated: false)),
            (.init(job: job("terminated")), .failed(terminated: true)),
            (.init(job: job("paused")), .unknownStatus("paused")),
            (.init(job: job("archived")), .finishedWithoutReport),
        ] {
            let computer = FakeComputer([answer])
            let jobs = store(computer)
            await jobs.follow("dr_1")
            #expect(jobs.entry("dr_1").state == expected)
            #expect(computer.resultCount == 1)
            #expect(computer.messageCount == 0)
        }
    }

    @Test("no answer to the first read: unreachable, no more polling; Retry starts again")
    func unreachable() async {
        let computer = FakeComputer([.init(fails: true), .init(job: job("archived", report: sampleReport))])
        let jobs = store(computer)
        await jobs.follow("dr_1")
        #expect(jobs.entry("dr_1").state == .unreachable)
        #expect(computer.resultCount == 1)
        jobs.retry("dr_1")
        #expect(jobs.entry("dr_1").state == .loading)
        #expect(jobs.entry("dr_1").attempt == 1)
        await jobs.follow("dr_1")
        guard case .done = jobs.entry("dr_1").state else {
            Issue.record("retry did not recover")
            return
        }
    }

    @Test("a failure mid-run keeps the progress shown and backs off, then carries on")
    func failureMidRun() async {
        let computer = FakeComputer([
            .init(job: job("streaming"), messages: progressMessages), .init(fails: true), .init(fails: true),
            .init(job: job("archived", report: sampleReport)),
        ])
        let jobs = store(computer)
        await jobs.follow("dr_1")
        guard case .done = jobs.entry("dr_1").state else {
            Issue.record("did not carry on")
            return
        }
        #expect(computer.resultCount == 4)
    }

    @Test("a streaming job with nothing new for a long time is stalled, and is not polled on")
    func stalled() async {
        let computer = FakeComputer([.init(job: job("streaming"), messages: progressMessages)])
        let jobs = store(computer, now: iso("2026-09-24T09:16:00.000Z"))
        await jobs.follow("dr_1")
        guard case .stalled(let progress) = jobs.entry("dr_1").state else {
            Issue.record("not stalled")
            return
        }
        #expect(progress.step == .searched("Ghent plan"))
        #expect(computer.resultCount == 1)
    }

    @Test("an id that is no plain id never reaches a URL; an answer that is no job is reported once, without it")
    func unreadable() async {
        let computer = FakeComputer([.init(job: #"{"secret":"x"}"#)])
        let jobs = store(computer)
        await jobs.follow("../chat/c1")
        #expect(jobs.entry("../chat/c1").state == .unreadable)
        #expect(computer.resultCount == 0)
        #expect(DeepResearchStore.isAcceptableId("0b6f1f7e-2c1d-4a53-9a55-1f0c3e0e9a11"))
        #expect(!DeepResearchStore.isAcceptableId(""))
        #expect(!DeepResearchStore.isAcceptableId("a/b"))
        #expect(!DeepResearchStore.isAcceptableId("a?b"))
        #expect(!DeepResearchStore.isAcceptableId("ü"))
        await jobs.follow("dr_1")
        #expect(jobs.entry("dr_1").state == .unreadable)
        #expect(computer.reportCount == 1)
    }

    @Test("two cards of one job share one poller; when the first goes away the second carries on")
    func onePollerPerJob() async throws {
        final class Counts: Sendable {
            let state = Mutex((inFlight: 0, most: 0, total: 0))
            var total: Int { state.withLock { $0.total } }
            var most: Int { state.withLock { $0.most } }
        }
        let counts = Counts()
        let fetcher = DeepResearchStore.Fetcher(
            result: { _ in
                counts.state.withLock {
                    $0.inFlight += 1
                    $0.most = max($0.most, $0.inFlight)
                    $0.total += 1
                }
                try? await Task.sleep(for: .milliseconds(10))
                counts.state.withLock { $0.inFlight -= 1 }
                return Data(job("streaming").utf8)
            },
            messages: { _ in Data(progressMessages.utf8) })
        let now = iso("2026-09-24T09:01:00.000Z")
        let jobs = DeepResearchStore(
            fetcher: fetcher, interval: .milliseconds(5), maximumInterval: .milliseconds(20), now: { now })
        let first = Task { await jobs.follow("dr_1") }
        let second = Task { await jobs.follow("dr_1") }
        for _ in 0..<400 where counts.total < 6 { try await Task.sleep(for: .milliseconds(5)) }
        #expect(counts.total >= 6)
        #expect(counts.most == 1, "two pollers read the same job at once")
        first.cancel()
        await first.value
        let before = counts.total
        for _ in 0..<400 where counts.total < before + 3 { try await Task.sleep(for: .milliseconds(5)) }
        #expect(counts.total >= before + 3, "the second card did not take over")
        #expect(counts.most == 1)
        second.cancel()
        await second.value
        let after = counts.total
        try await Task.sleep(for: .milliseconds(80))
        #expect(counts.total == after, "polling outlived both cards")
    }

    @Test("cancelling the card's task stops polling: nothing is asked afterwards")
    func cancellation() async throws {
        let computer = FakeComputer([.init(job: job("streaming"), messages: progressMessages)])
        let jobs = store(computer)
        let task = Task { await jobs.follow("dr_1") }
        for _ in 0..<200 where computer.resultCount < 3 { try await Task.sleep(for: .milliseconds(5)) }
        task.cancel()
        await task.value
        let asked = computer.resultCount
        try await Task.sleep(for: .milliseconds(80))
        #expect(computer.resultCount == asked)
        guard case .running = jobs.entry("dr_1").state else {
            Issue.record("lost the progress")
            return
        }
    }
}

// MARK: - Over the network

private final class DRMockURLProtocol: URLProtocol, @unchecked Sendable {
    nonisolated(unsafe) static var handler: (@Sendable (URLRequest) -> (Int, Data))?
    nonisolated(unsafe) static var paths: [String] = []

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        guard let handler = Self.handler else {
            client?.urlProtocol(self, didFailWithError: URLError(.badServerResponse))
            return
        }
        Self.paths.append(request.url?.path ?? "")
        let (status, data) = handler(request)
        let response = HTTPURLResponse(
            url: request.url!, statusCode: status, httpVersion: "HTTP/1.1", headerFields: ["Content-Type": "application/json"])!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: data)
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {}
}

@MainActor
@Suite("Deep research: over the network", .serialized)
struct DeepResearchNetworkTests {
    @Test("the paired client reads the desktop's routes: the row, then its messages; a 404 is a missing job")
    func routes() async throws {
        let suite = #function
        let defaults = UserDefaults(suiteName: suite)!
        defaults.removePersistentDomain(forName: suite)
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [DRMockURLProtocol.self]
        let api = APIClient(session: URLSession(configuration: configuration), serverConfig: ServerConfigStore(userDefaults: defaults))
        DRMockURLProtocol.paths = []
        let rows = [job("streaming"), job("archived", report: sampleReport, sources: sources)]
        let calls = Mutex(0)
        DRMockURLProtocol.handler = { request in
            if request.url?.path.contains("/messages/") == true { return (200, Data(progressMessages.utf8)) }
            let index = calls.withLock { count in
                defer { count += 1 }
                return count
            }
            return (200, Data(rows[min(index, 1)].utf8))
        }
        let jobs = DeepResearchStore(
            fetcher: .init(apiClient: api), interval: .milliseconds(5), now: { iso("2026-09-24T09:01:00.000Z") })
        await jobs.follow("dr_1")
        #expect(
            DRMockURLProtocol.paths == [
                "/api/v1/deep-research/result/dr_1", "/api/v1/deep-research/messages/dr_1", "/api/v1/deep-research/result/dr_1",
            ])
        guard case .done = jobs.entry("dr_1").state else {
            Issue.record("not done")
            return
        }
        DRMockURLProtocol.handler = { _ in
            (404, Data(#"{"error":{"code":"DEEP_RESEARCH_NOT_FOUND","message":"Not found"}}"#.utf8))
        }
        await jobs.follow("dr_2")
        #expect(jobs.entry("dr_2").state == .missing)
        DRMockURLProtocol.handler = nil
    }
}

// MARK: - Drawn

private final class Reports: @unchecked Sendable {
    private let lock = NSLock()
    private var stored: [String] = []
    var entries: [String] { lock.withLock { stored } }
    func append(_ entry: String) { lock.withLock { stored.append(entry) } }
}

@MainActor
@Suite("Deep research: drawn in a window", .serialized)
struct DeepResearchHostedTests {
    @Test("running, done, stalled, gone, refused and failed cards draw their own card; the report view draws; no reports")
    func hosted() async throws {
        let reports = Reports()
        let diagnostics = RenderDiagnostics { scope, message, _ in reports.append("\(scope): \(message)") }
        let computer = FakeComputer([.init(job: job("streaming"), messages: progressMessages)])
        let jobs = store(computer)
        let row = try #require(DeepResearchJob(json: try JSONDecoder().decode(JSONValue.self, from: Data(job("archived", report: sampleReport, sources: sources).utf8))))
        let done = DeepResearchReport(job: row, report: sampleReport)
        jobs.entry("dr_done").state = .done(done)
        jobs.entry("dr_stalled").state = .stalled(DeepResearchProgress(events: [], startedAt: nil))
        jobs.entry("dr_gone").state = .missing
        let all =
            ["dr_1", "dr_done", "dr_stalled", "dr_gone"].enumerated().flatMap { index, id in
                cards([user("u"), call("a", "u", "k\(index)"), result("t", "u", "k\(index)", details: #"{"id":"\#(id)"}"#)])
            }
            + cards([user("u"), call("a", "u", "k8"), result("t", "u", "k8", details: #"{"error":"No key"}"#)])
            + cards([user("u"), call("a", "u", "k9"), failedCall("t", "u", "k9", text: "boom")])
        #expect(all.count == 6)
        #expect(all.allSatisfy(ToolCardRegistry.canDraw))
        let root = VStack {
            ForEach(all, id: \.renderKey) { ToolCardView(card: $0) }
            DeepResearchReportView(report: done)
        }
        .environment(\.renderDiagnostics, diagnostics)
        .environment(\.deepResearchJobs, jobs)
        .environment(\.scenePhase, .active)
        let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 390, height: 2400))
        let host = UIHostingController(rootView: AnyView(root))
        window.rootViewController = host
        window.makeKeyAndVisible()
        for _ in 0..<50 where jobs.entry("dr_1").state.progress == nil {
            window.layoutIfNeeded()
            try await Task.sleep(for: .milliseconds(10))
        }
        window.layoutIfNeeded()
        #expect(jobs.entry("dr_1").state.progress?.searches.count == 1)
        #expect(reports.entries.isEmpty)
        #expect(computer.resultCount >= 1)
        host.rootView = AnyView(EmptyView())
        window.layoutIfNeeded()
        try await Task.sleep(for: .milliseconds(50))
        let asked = computer.resultCount
        try await Task.sleep(for: .milliseconds(100))
        #expect(computer.resultCount == asked, "polling outlived the card")
        #expect(jobs.entry("dr_done").state == .done(done))
        window.isHidden = true
    }
}

// MARK: - Render guard

@MainActor
@Suite("Deep research: a settled research turn stays put while a later turn streams")
struct DeepResearchRenderTests {
    @Test("a later turn's frames rebuild only that turn; the settled research turn and its view compare equal")
    func settledStays() throws {
        let settled = [
            user("u1"), call("a1", "u1", "k1"), result("t1", "u1", "k1", details: #"{"id":"dr_1","toolCallId":"k1"}"#),
            answer("b1", "u1", "Started the research."), user("u2"),
        ]
        var cache = RunGrouper.Cache()
        let first = RunGrouper.group(settled + [answer("b2", "u2", "P")], cache: &cache)
        let built = cache.builtTurnCount
        var previous = first
        for frame in 1...5 {
            let next = RunGrouper.group(settled + [answer("b2", "u2", String(repeating: "P", count: frame + 1))], cache: &cache)
            #expect(next.first { $0.id == "run:u1" } == previous.first { $0.id == "run:u1" })
            previous = next
        }
        #expect(cache.builtTurnCount == built + 5)
        guard case .assistantTurn(let before)? = first.first(where: { $0.id == "run:u1" }),
            case .assistantTurn(let after)? = previous.first(where: { $0.id == "run:u1" })
        else {
            Issue.record("no settled turn")
            return
        }
        #expect(before.toolCards.first?.content.deepResearch?.phase == .job(id: "dr_1"))
        let lhs = AssistantTurnView(turn: before, isStreaming: false, error: nil, regenerate: {})
        let rhs = AssistantTurnView(turn: after, isStreaming: false, error: nil, regenerate: { print("new") })
        #expect(lhs == rhs)
    }
}
