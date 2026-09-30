import Foundation

// A deep_research job as the desktop keeps it (src/main/lib/db/schema.ts `deep_research` / `deep_research_message`,
// packages/shared/src/types/deep-research.ts), read from `GET /api/v1/deep-research/result/:id` and `/messages/:id`.

/// One web page the research read: a `WebSearchResult`, numbered by `rank` as the report's `【N-source】` markers are.
public struct DeepResearchSource: JSONValueDecodable {
    public let rank: Int
    public let link: String
    public let title: String
    public let snippet: String
    public let siteName: String?
    public let hostname: String?
    public let age: String?

    public init?(json: JSONValue) {
        guard let fields = JSONFields(json), let rank = fields.int("rank"), let link = fields.nonEmpty("link") else {
            return nil
        }
        self.rank = rank
        self.link = link
        title = fields.string("title") ?? ""
        snippet = fields.string("snippet") ?? ""
        siteName = fields.nonEmpty("siteName")
        hostname = fields.nonEmpty("hostname")
        age = fields.nonEmpty("age")
    }
}

/// The job's row. `jobStatus` is `streaming` until the report is written, then `archived`, or `failed` with
/// `errorMessage` when a step threw (desktops before that fix leave such a job `streaming`); `terminated` is in the
/// schema though nothing writes it yet.
public struct DeepResearchJob: JSONValueDecodable {
    public enum Status: Equatable, Sendable {
        case streaming, archived, failed, terminated
        case other(String)

        init(_ raw: String) {
            switch raw {
            case "streaming": self = .streaming
            case "archived": self = .archived
            case "failed": self = .failed
            case "terminated": self = .terminated
            default: self = .other(raw)
            }
        }
    }

    public let id: String
    public let title: String?
    public let status: Status
    public let finalReport: String?
    public let webSources: [DeepResearchSource]
    public let startTime: Date?
    public let endTime: Date?
    /// Why a `failed` job failed: a short, secret-scrubbed summary.
    public let errorMessage: String?

    public init?(json: JSONValue) {
        guard let fields = JSONFields(json), let id = fields.nonEmpty("id"), let status = fields.nonEmpty("jobStatus")
        else { return nil }
        self.id = id
        title = fields.nonEmpty("title")
        self.status = Status(status)
        finalReport = fields.nonEmpty("finalReport")
        webSources = fields.list("webSources")
        startTime = fields.string("startTime").flatMap(DeepResearchDate.parse)
        endTime = fields.string("endTime").flatMap(DeepResearchDate.parse)
        errorMessage = fields.nonEmpty("errorMessage")
    }
}

/// A search the research planned, with what it was meant to find out.
public struct DeepResearchQuery: JSONValueDecodable {
    public let query: String
    public let researchGoal: String

    public init?(json: JSONValue) {
        guard let fields = JSONFields(json), let query = fields.nonEmpty("query") else { return nil }
        self.query = query
        researchGoal = fields.string("researchGoal") ?? ""
    }
}

/// One progress payload (`ReportProgressPayload`, its `type` the `DeepResearchProgress` enum's number).
public enum DeepResearchEvent: Equatable, Sendable {
    case started
    case queries(topic: String, queries: [DeepResearchQuery], deeper: Bool)
    case searched(query: String, results: [DeepResearchSource])
    case learned([String])
    case writing
    case completed(query: String)
    case failed(error: String)
    case unknown

    init(_ fields: JSONFields) {
        switch fields.int("type") {
        case 0: self = .started
        case 1:
            self = .queries(
                topic: fields.string("query") ?? "", queries: fields.list("searchQueries"),
                deeper: fields.bool("deeper") ?? false)
        case 2: self = .searched(query: fields.string("query") ?? "", results: fields.list("webSearchResults"))
        case 3:
            self = .learned((fields.array("learnings") ?? []).compactMap { JSONFields($0)?.nonEmpty("learning") })
        case 4: self = .writing
        case 5: self = .completed(query: fields.string("query") ?? "")
        case 6: self = .failed(error: fields.string("error") ?? "")
        default: self = .unknown
        }
    }
}

/// A saved progress message: `{id, deepResearchId, message: {jsonrpc, method, params: {data}}, createdAt}`.
public struct DeepResearchMessage: JSONValueDecodable {
    public let id: String
    public let createdAt: Date?
    public let event: DeepResearchEvent

    public init(id: String, createdAt: Date?, event: DeepResearchEvent) {
        self.id = id
        self.createdAt = createdAt
        self.event = event
    }

    public init?(json: JSONValue) {
        guard let fields = JSONFields(json), let id = fields.nonEmpty("id"),
            let data = JSONFields(JSONFields(JSONFields(fields.raw["message"])?.raw["params"])?.raw["data"])
        else { return nil }
        self.id = id
        createdAt = fields.string("createdAt").flatMap(DeepResearchDate.parse)
        event = DeepResearchEvent(data)
    }
}

enum DeepResearchDate {
    static func parse(_ iso: String) -> Date? {
        (try? Date.ISO8601FormatStyle(includingFractionalSeconds: true).parse(iso))
            ?? (try? Date.ISO8601FormatStyle().parse(iso))
    }
}
