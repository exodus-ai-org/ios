import Foundation
import MarkdownKit
import Models
import NetworkingKit
import Observation
import SwiftUI

extension EnvironmentValues {
    /// Where a deep_research card reads its job; the chat screen gives one bound to its paired session.
    @Entry var deepResearchJobs: DeepResearchStore?
}

/// A `deep_research` call: the subject, and the job its result names (`{id, toolCallId}`), or why there is none.
struct DeepResearchCardModel: Equatable, Sendable {
    enum Phase: Equatable, Sendable {
        case job(id: String)
        /// The tool answered `{error}` (it could not start the job).
        case refused(String)
        /// The call itself failed; the tool's message, if any.
        case failed(String?)
    }

    let subject: String
    let phase: Phase

    init(subject: String, phase: Phase) {
        self.subject = subject
        self.phase = phase
    }

    init(_ call: DecodedCall<DeepResearchArguments, DeepResearchResult>) {
        subject = call.arguments?.subject ?? ""
        switch call.result {
        case .started(let id): phase = .job(id: id)
        case .failed(let message): phase = .refused(message)
        }
    }
}

/// Where a running job stands, summarised from its progress messages the way the desktop's Activity panel lists them.
struct DeepResearchProgress: Equatable, Sendable {
    enum Step: Equatable, Sendable {
        case starting, searching, searched(String), planning, writing, completed
    }

    struct Search: Equatable, Sendable, Identifiable {
        let id: Int
        let query: String
        let goal: String
    }

    static let recentLimit = 3

    private(set) var step: Step = .starting
    /// Every search run so far, in order.
    private(set) var searches: [Search] = []
    /// Distinct pages found (the desktop's final `webSources` is keyed by link too).
    private(set) var sources = 0
    private(set) var learnings = 0
    /// The newest message's time, else the job's start: what a stall is measured from.
    private(set) var lastActivity: Date?

    var recent: [Search] { Array(searches.suffix(Self.recentLimit)) }

    init(events: [DeepResearchMessage], startedAt: Date?) {
        var goals: [String: String] = [:]
        var links = Set<String>()
        lastActivity = startedAt
        for message in events {
            if let at = message.createdAt { lastActivity = max(lastActivity ?? at, at) }
            switch message.event {
            case .started:
                step = .starting
            case .queries(_, let queries, _):
                for query in queries where goals[query.query] == nil { goals[query.query] = query.researchGoal }
                step = .searching
            case .searched(let query, let results):
                searches.append(Search(id: searches.count, query: query, goal: goals[query] ?? ""))
                links.formUnion(results.map(\.link))
                step = .searched(query)
            case .learned(let items):
                learnings += items.count
                step = .planning
            case .writing:
                step = .writing
            case .completed:
                step = .completed
            case .unknown:
                break
            }
        }
        sources = links.count
    }
}

/// A finished job's report, parsed once off the main actor: the whole document, the few blocks the card previews
/// (its `# title` dropped — the card already names the research), and its sources split as the desktop's panel splits
/// them: the ones the report cites, then the rest.
struct DeepResearchReport: Equatable, Sendable {
    static let previewBlockCount = 3

    let markdown: String
    let document: MarkdownParseResult
    let preview: MarkdownParseResult
    let citations: [MarkdownCitation]
    let cited: [CitationSource]
    let more: [CitationSource]
    let sourceCount: Int
    let duration: TimeInterval?

    init(job: DeepResearchJob, report: String) {
        markdown = report
        let document = MarkdownParser.parse(report, source: 0)
        self.document = document
        var body = document.blocks
        if case .heading(level: 1, _)? = body.first?.kind { body.removeFirst() }
        preview = MarkdownParseResult(blocks: Array(body.prefix(Self.previewBlockCount)), citations: document.citations)
        let sources = job.webSources.map {
            CitationSource(
                rank: $0.rank, link: $0.link, title: $0.title, snippet: $0.snippet, siteName: $0.siteName,
                hostname: $0.hostname, age: $0.age)
        }
        var byRank: [Int: CitationSource] = [:]
        for source in sources where byRank[source.rank] == nil { byRank[source.rank] = source }
        citations = byRank.keys.sorted().compactMap { rank in
            byRank[rank].map { MarkdownCitation(number: rank, title: $0.title, host: ToolPresentation.host(of: $0)) }
        }
        let citedRanks = Set(document.citations)
        cited = sources.filter { citedRanks.contains($0.rank) }
        more = sources.filter { !citedRanks.contains($0.rank) }
        sourceCount = sources.count
        duration = job.startTime.flatMap { start in job.endTime.map { max(0, $0.timeIntervalSince(start)) } }
    }
}

/// What the card knows about its job.
enum DeepResearchJobState: Equatable, Sendable {
    case loading
    case running(DeepResearchProgress)
    /// Still `streaming`, but nothing new for a long time: the desktop never marks a job that died (an error, a quit)
    /// as failed, so this is how such a job looks.
    case stalled(DeepResearchProgress)
    case done(DeepResearchReport)
    case finishedWithoutReport
    case failed(terminated: Bool)
    /// A `jobStatus` this app does not know.
    case unknownStatus(String)
    /// The answer was no job row, or the id is not one this app will put in a path.
    case unreadable
    /// 404: the job is gone from the computer.
    case missing
    /// The first read never got an answer.
    case unreachable

    /// Still worth asking the computer again on its own.
    var isPolling: Bool {
        switch self {
        case .loading, .running: true
        default: false
        }
    }

    var progress: DeepResearchProgress? {
        switch self {
        case .running(let progress), .stalled(let progress): progress
        default: nil
        }
    }
}

/// One job's state, observed by the card that shows it (and only that card).
@MainActor
@Observable
final class DeepResearchJobEntry {
    var state: DeepResearchJobState = .loading
    /// Bumped by a retry, so the card's polling task starts again.
    var attempt = 0
}

/// Reads jobs from the computer while their cards are on screen: the row every few seconds while it streams (its
/// progress messages with it), once when it is settled. A card's own `.task` drives `follow`, so polling ends when the
/// card scrolls away, the chat closes or the app leaves the foreground — no timer outlives it. Decoding, summarising
/// and parsing the report happen off the main actor.
@MainActor
final class DeepResearchStore {
    struct Fetcher: Sendable {
        let result: @Sendable (String) async throws -> Data
        let messages: @Sendable (String) async throws -> Data
        /// Told when the computer answers with something that is not a job row. Never given the payload.
        let reportUnreadable: @Sendable () -> Void

        init(
            result: @escaping @Sendable (String) async throws -> Data,
            messages: @escaping @Sendable (String) async throws -> Data,
            reportUnreadable: @escaping @Sendable () -> Void = {}
        ) {
            self.result = result
            self.messages = messages
            self.reportUnreadable = reportUnreadable
        }

        init(apiClient: APIClient) {
            let reporter = apiClient.reporter
            self.init(
                result: { try await apiClient.data("/api/v1/deep-research/result/\($0)") },
                messages: { try await apiClient.data("/api/v1/deep-research/messages/\($0)") },
                reportUnreadable: {
                    reporter?.report(.error, scope: "chat.deepResearch", message: "Unreadable deep research job")
                })
        }
    }

    enum Outcome: Equatable, Sendable {
        case state(DeepResearchJobState)
        case failure
        case cancelled
    }

    private let fetcher: Fetcher
    private let interval: Duration
    private let maximumInterval: Duration
    private let stallAfter: TimeInterval
    private let now: @Sendable () -> Date
    private var entries: [String: DeepResearchJobEntry] = [:]
    /// The jobs a `follow` is polling right now: one poller per job, however many cards show it.
    private var polling: Set<String> = []

    init(
        fetcher: Fetcher, interval: Duration = .seconds(3), maximumInterval: Duration = .seconds(30),
        stallAfter: TimeInterval = 15 * 60, now: @escaping @Sendable () -> Date = { Date() }
    ) {
        self.fetcher = fetcher
        self.interval = interval
        self.maximumInterval = maximumInterval
        self.stallAfter = stallAfter
        self.now = now
    }

    convenience init(apiClient: APIClient) {
        self.init(fetcher: Fetcher(apiClient: apiClient))
    }

    func entry(_ id: String) -> DeepResearchJobEntry {
        if let entry = entries[id] { return entry }
        let entry = DeepResearchJobEntry()
        entries[id] = entry
        return entry
    }

    /// Asks again after a stall or an unanswered first read.
    func retry(_ id: String) {
        let entry = entry(id)
        entry.state = .loading
        entry.attempt += 1
    }

    /// Reads the job until it settles, stalls or the calling task is cancelled.
    func follow(_ id: String) async {
        let entry = entry(id)
        guard Self.isAcceptableId(id) else {
            entry.state = .unreadable
            return
        }
        // A second card of the same job (or a retry racing the old task's exit) waits, and takes over if the poller
        // goes away while the job still runs.
        while polling.contains(id) {
            guard entry.state.isPolling else { return }
            do { try await Task.sleep(for: min(interval, .milliseconds(250))) } catch { return }
        }
        polling.insert(id)
        defer { polling.remove(id) }
        var delay = interval
        while entry.state.isPolling, !Task.isCancelled {
            let outcome = await Self.load(id, fetcher: fetcher, now: now(), stallAfter: stallAfter)
            switch outcome {
            case .cancelled:
                return
            case .state(let state):
                entry.state = state
                delay = interval
            case .failure:
                if entry.state == .loading {
                    entry.state = .unreachable
                    return
                }
                delay = min(delay * 2, maximumInterval)
            }
            guard entry.state.isPolling else { return }
            do { try await Task.sleep(for: delay) } catch { return }
        }
    }

    /// A job id goes into a URL path: only the characters of a UUID-like id, never `/` or `..`.
    nonisolated static func isAcceptableId(_ id: String) -> Bool {
        (1...64).contains(id.count)
            && id.unicodeScalars.allSatisfy { ($0.isASCII && CharacterSet.alphanumerics.contains($0)) || $0 == "-" || $0 == "_" }
    }

    @concurrent
    nonisolated static func load(_ id: String, fetcher: Fetcher, now: Date, stallAfter: TimeInterval) async -> Outcome {
        do {
            let data = try await fetcher.result(id)
            guard let value = try? JSONDecoder().decode(JSONValue.self, from: data), let job = DeepResearchJob(json: value)
            else {
                fetcher.reportUnreadable()
                return .state(.unreadable)
            }
            switch job.status {
            case .archived:
                guard let report = job.finalReport else { return .state(.finishedWithoutReport) }
                try Task.checkCancellation()
                return .state(.done(DeepResearchReport(job: job, report: report)))
            case .failed:
                return .state(.failed(terminated: false))
            case .terminated:
                return .state(.failed(terminated: true))
            case .other(let status):
                return .state(.unknownStatus(status))
            case .streaming:
                let raw = try await fetcher.messages(id)
                let events: [DeepResearchMessage] =
                    ((try? JSONDecoder().decode([JSONValue].self, from: raw)) ?? []).compactMap(DeepResearchMessage.init(json:))
                let progress = DeepResearchProgress(events: events, startedAt: job.startTime)
                if let last = progress.lastActivity, now.timeIntervalSince(last) > stallAfter {
                    return .state(.stalled(progress))
                }
                return .state(.running(progress))
            }
        } catch {
            if error is CancellationError || (error as? URLError)?.code == .cancelled { return .cancelled }
            if let http = error as? HTTPError, http.statusCode == 404 { return .state(.missing) }
            return .failure
        }
    }
}

/// The card's words, for views and tests alike.
enum DeepResearchText {
    static func step(_ step: DeepResearchProgress.Step) -> String {
        switch step {
        case .starting:
            String(
                localized: "deepResearch:messages.start.title", defaultValue: "Start deep researching...",
                comment: "Deep research card: the job has just started.")
        case .searching:
            String(
                localized: "ios:chat.card.research.searching", defaultValue: "Searching the web…",
                comment: "Deep research card: the current step, while a web search runs.")
        case .searched(let query):
            String(
                localized: "deepResearch:messages.searchedFor", defaultValue: "Searched for \"\(query)\"",
                comment: "Deep research card: the current step. %@ is the search query.")
        case .planning:
            String(
                localized: "ios:chat.card.research.planning", defaultValue: "Planning the next searches…",
                comment: "Deep research card: the current step, after learning from results.")
        case .writing:
            String(
                localized: "deepResearch:messages.writingReport.title", defaultValue: "Start writing final report...",
                comment: "Deep research card: the report is being written.")
        case .completed:
            String(
                localized: "deepResearch:messages.complete.title", defaultValue: "Completed deep research",
                comment: "Deep research card: the research is done.")
        }
    }

    static func completed(_ report: DeepResearchReport) -> String {
        guard let duration = report.duration else { return sources(report.sourceCount) }
        let text = Duration.seconds(max(duration, 1)).formatted(
            .units(allowed: [.hours, .minutes, .seconds], width: .abbreviated, maximumUnitCount: 2))
        return String(
            localized: "ios:chat.card.research.completed", defaultValue: "Completed in \(text) · sources: \(report.sourceCount)",
            comment: "Deep research card header, when the report is ready. %1$@ is how long it took, %2$lld the number of sources.")
    }

    static func sources(_ count: Int) -> String {
        String(
            localized: "ios:chat.card.research.sourceCount", defaultValue: "Sources: \(count)",
            comment: "Deep research card: how many distinct web pages were found.")
    }

    static func learnings(_ count: Int) -> String {
        String(
            localized: "ios:chat.card.research.learningCount", defaultValue: "Learnings: \(count)",
            comment: "Deep research card: how many findings were extracted so far.")
    }

    static func searches(_ count: Int) -> String {
        String(
            localized: "ios:chat.card.research.searchCount", defaultValue: "Searches: \(count)",
            comment: "Deep research card: how many web searches have run so far.")
    }

    static func unknownStatus(_ status: String) -> String {
        String(
            localized: "ios:chat.card.research.unknownStatus",
            defaultValue: "This research is in a state this app doesn't know: \(status).",
            comment: "Deep research card: the computer reported a job status this app version does not know. %@ is it.")
    }

    static var failed: String {
        String(
            localized: "ios:chat.card.research.failed", defaultValue: "The research failed on the computer.",
            comment: "Deep research card: the job failed.")
    }

    static var terminated: String {
        String(
            localized: "ios:chat.card.research.terminated", defaultValue: "The research was stopped on the computer.",
            comment: "Deep research card: the job was stopped.")
    }
}
