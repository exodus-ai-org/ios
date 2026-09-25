import Foundation
import Models

public enum Segment: Equatable, Sendable, Identifiable {
    case user(ChatMessage)
    case assistantTurn(AssistantTurn)

    public var id: String {
        switch self {
        case .user(let message): message.id
        case .assistantTurn(let turn): turn.id
        }
    }
}

public struct AssistantTurn: Equatable, Sendable, Identifiable {
    public enum Step: Equatable, Sendable {
        case thinking(ThinkingStep)
        case toolCall(ToolCallStep)
    }

    public struct ThinkingStep: Equatable, Sendable {
        public let text: String
        public let title: String?

        public init(text: String, title: String? = nil) {
            self.text = text
            self.title = title
        }
    }

    public struct ToolCallStep: Equatable, Sendable {
        public enum Status: Equatable, Sendable {
            case pending, succeeded, failed
        }

        public let id: String
        public let name: String
        public let argumentSummary: String?
        public let codeArgument: String?
        public let itinerary: ItineraryScale?
        public internal(set) var status: Status
        public internal(set) var errorText: String?
        public internal(set) var results: [CitationSource]

        public var isPending: Bool { status == .pending }
        public var isError: Bool { status == .failed }
        public var resultCount: Int { results.count }

        public init(
            id: String, name: String, argumentSummary: String? = nil, codeArgument: String? = nil,
            itinerary: ItineraryScale? = nil, status: Status = .succeeded, errorText: String? = nil,
            results: [CitationSource] = []
        ) {
            self.id = id
            self.name = name
            self.argumentSummary = argumentSummary
            self.codeArgument = codeArgument
            self.itinerary = itinerary
            self.status = status
            self.errorText = errorText
            self.results = results
        }
    }

    public let runId: String
    public let messageIds: [String]
    public let steps: [Step]
    public let body: String
    public let toolCards: [ToolCard]
    public let pendingToolCalls: [PendingToolCall]
    public let sources: [CitationSource]
    public internal(set) var citations: [CitationSource]
    public let durationMs: Int?
    public let timestampMs: Double?
    public let error: String?
    public let hasContent: Bool
    public internal(set) var occurrence: Int
    /// The run foot as the rows give it; the memories the run read are not in the rows (see `MemoryFootStore`).
    public let foot: RunFoot

    public init(
        runId: String, messageIds: [String] = [], steps: [Step] = [], body: String = "", toolCards: [ToolCard] = [],
        pendingToolCalls: [PendingToolCall] = [], sources: [CitationSource] = [], citations: [CitationSource]? = nil,
        durationMs: Int? = nil, timestampMs: Double? = nil, error: String? = nil, hasContent: Bool? = nil,
        occurrence: Int = 1, foot: RunFoot = RunFoot()
    ) {
        self.runId = runId
        self.messageIds = messageIds
        self.steps = steps
        self.body = body
        self.toolCards = toolCards
        self.pendingToolCalls = pendingToolCalls
        self.sources = sources
        self.citations = citations ?? sources
        self.durationMs = durationMs
        self.timestampMs = timestampMs
        self.error = error
        self.hasContent =
            hasContent
            ?? (!steps.isEmpty || !body.isEmpty || !pendingToolCalls.isEmpty || !toolCards.isEmpty || error != nil)
        self.occurrence = occurrence
        self.foot = foot
    }

    // A run split by another run's rows appears twice; the suffix keeps ForEach ids unique.
    public var id: String { Self.key(runId: runId, occurrence: occurrence) }

    static func key(runId: String, occurrence: Int) -> String {
        guard occurrence > 1 else { return "run:\(runId)" }
        return "run:\(runId)#\(occurrence)"
    }
    public var hasBody: Bool { !body.isEmpty }
    public var hasThinking: Bool {
        steps.contains { if case .thinking = $0 { true } else { false } }
    }

    public func citation(forMarker marker: Int) -> CitationSource? {
        citations.last { $0.rank == marker }
    }
}

public struct PendingToolCall: Equatable, Sendable {
    public let id: String
    public let name: String

    public init(id: String, name: String) {
        self.id = id
        self.name = name
    }
}

public struct ItineraryScale: Equatable, Sendable {
    public let days: Int
    public let stops: Int

    public init(days: Int, stops: Int) {
        self.days = days
        self.stops = stops
    }
}

public struct ToolCard: Equatable, Sendable, Identifiable {
    public enum Kind: Equatable, Sendable {
        case terminal, weather, mapItinerary, deepResearch, computerUse, artifact, generic
    }

    public let id: String
    public let toolCallId: String?
    public let toolName: String
    public let kind: Kind
    public let payload: JSONValue?
    /// The call's arguments, when its assistant message is in the same run.
    public let arguments: JSONValue?
    /// A failed call, for a tool whose card shows failures; `errorText` is the tool's own message, if it gave one.
    public let isError: Bool
    public let errorText: String?
    /// A call still running, for a tool whose card has a running state; its result is not in yet.
    public let isPending: Bool
    /// Decoded here, once per card, so no view decodes while it draws.
    let content: ToolCardContent

    public init(
        id: String, toolCallId: String? = nil, toolName: String, kind: Kind, payload: JSONValue? = nil,
        arguments: JSONValue? = nil, isError: Bool = false, errorText: String? = nil, isPending: Bool = false,
        resultImage: String? = nil
    ) {
        self.id = id
        self.toolCallId = toolCallId
        self.toolName = toolName
        self.kind = kind
        self.payload = payload
        self.arguments = arguments
        self.isError = isError
        self.errorText = errorText
        self.isPending = isPending
        content = ToolCardContent(
            toolName: toolName, arguments: arguments, payload: payload, isError: isError, errorText: errorText,
            isPending: isPending, toolCallId: toolCallId, resultImage: resultImage)
    }

    /// The card's place in its turn: the call, so a running card becomes its result in place (the same view, the
    /// image resolving where the placeholder was) rather than being swapped for another.
    public var renderKey: String { toolCallId.map { "call:\($0)" } ?? "row:\(id)" }
}

/// What a run shows under its answer: its memory changes and the media its searches found. Built with the turn; the
/// views only read it.
public struct RunFoot: Equatable, Sendable {
    /// Every `update_memory` call of the run that ran, in order (a call in an aborted or failed message never ran).
    public var memoryUpdates: [MemoryUpdate]
    public var searchMedia: [WebSearchMedia]
    /// `searchMedia` ready to draw: images and videos, de-duplicated, capped, with the hosts that load without a tap.
    var gallery = SearchGallery()

    public init(memoryUpdates: [MemoryUpdate] = [], searchMedia: [WebSearchMedia] = []) {
        self.memoryUpdates = memoryUpdates
        self.searchMedia = searchMedia
    }

    public var isEmpty: Bool { memoryUpdates.isEmpty && searchMedia.isEmpty }
}

public struct MemoryUpdate: Equatable, Sendable, Identifiable {
    public let id: String
    public let status: AssistantTurn.ToolCallStep.Status
    /// Nil while it runs, when it failed, or when its details did not decode.
    public let result: MemoryUpdateResult?
    public let errorText: String?

    public init(
        id: String, status: AssistantTurn.ToolCallStep.Status, result: MemoryUpdateResult? = nil,
        errorText: String? = nil
    ) {
        self.id = id
        self.status = status
        self.result = result
        self.errorText = errorText
    }
}

public struct CitationSource: Equatable, Sendable {
    public let rank: Int
    public let link: String
    public let title: String
    public let snippet: String
    public let siteName: String?
    public let hostname: String?
    public let favicon: String?
    public let thumbnail: String?
    public let age: String?
    public let media: [JSONValue]

    public init(
        rank: Int, link: String, title: String = "", snippet: String = "", siteName: String? = nil,
        hostname: String? = nil, favicon: String? = nil, thumbnail: String? = nil, age: String? = nil,
        media: [JSONValue] = []
    ) {
        self.rank = rank
        self.link = link
        self.title = title
        self.snippet = snippet
        self.siteName = siteName
        self.hostname = hostname
        self.favicon = favicon
        self.thumbnail = thumbnail
        self.age = age
        self.media = media
    }

    init?(_ value: JSONValue) {
        guard case .object(let object) = value, let number = object["rank"]?.numberValue, let rank = Int(exactly: number),
            let link = object["link"]?.stringValue
        else { return nil }
        self.rank = rank
        self.link = link
        title = object["title"]?.stringValue ?? ""
        snippet = object["snippet"]?.stringValue ?? ""
        siteName = object["siteName"]?.stringValue
        hostname = object["hostname"]?.stringValue
        favicon = object["favicon"]?.stringValue
        thumbnail = object["thumbnail"]?.stringValue
        age = object["age"]?.stringValue
        if case .array(let media)? = object["media"] { self.media = media } else { media = [] }
    }
}
