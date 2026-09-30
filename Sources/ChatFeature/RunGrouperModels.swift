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

    /// A piece of the answer: the model's text, or the card of a tool it called.
    public enum Block: Equatable, Sendable, Identifiable {
        case text(TextBlock)
        case card(ToolCard)

        /// A card is known by its call, so a running card becomes its result in place; a text by its place among the
        /// texts, so the one that streams stays the same view while it grows.
        public var id: String {
            switch self {
            case .text(let text): text.id
            case .card(let card): card.renderKey
            }
        }

        /// A hand-built turn's layout: its cards, then its text.
        static func laidOut(cards: [ToolCard], text: String) -> [Block] {
            numbered(cards.map(Block.card) + (text.isEmpty ? [] : [.text(TextBlock(id: "", text: text))]))
        }

        /// Text joins the text before it: what no card stands between is one block. The texts are numbered in order.
        static func numbered(_ blocks: [Block]) -> [Block] {
            var out: [Block] = []
            var texts = 0
            for block in blocks {
                guard case .text(let next) = block else {
                    out.append(block)
                    continue
                }
                if case .text(let last)? = out.last {
                    out[out.count - 1] = .text(TextBlock(id: last.id, text: last.text + TextBlock.separator + next.text))
                } else {
                    out.append(.text(TextBlock(id: "text:\(texts)", text: next.text)))
                    texts += 1
                }
            }
            return out
        }
    }

    public struct TextBlock: Equatable, Sendable, Identifiable {
        static let separator = "\n\n"

        public let id: String
        public let text: String
    }

    public let runId: String
    public let messageIds: [String]
    public let steps: [Step]
    /// The answer in the order the model produced it: text, a card where its call was made, text.
    public let blocks: [Block]
    /// Every text block joined: what Copy, read-aloud and the Sources sheet take as the answer.
    public let body: String
    /// The blocks' cards, in their order.
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
    /// The run's place in a regenerate group, from its user message; nil for an ordinary run.
    public internal(set) var attempt: TurnAttempt?

    /// A turn from its body and its cards, for fixtures: the cards first, then the text.
    public init(
        runId: String, messageIds: [String] = [], steps: [Step] = [], body: String = "", toolCards: [ToolCard] = [],
        pendingToolCalls: [PendingToolCall] = [], sources: [CitationSource] = [], citations: [CitationSource]? = nil,
        durationMs: Int? = nil, timestampMs: Double? = nil, error: String? = nil, hasContent: Bool? = nil,
        occurrence: Int = 1, foot: RunFoot = RunFoot()
    ) {
        self.init(
            runId: runId, messageIds: messageIds, steps: steps, blocks: Block.laidOut(cards: toolCards, text: body),
            pendingToolCalls: pendingToolCalls, sources: sources, citations: citations, durationMs: durationMs,
            timestampMs: timestampMs, error: error, hasContent: hasContent, occurrence: occurrence, foot: foot)
    }

    /// `body` and `toolCards` are read off `blocks`, here and nowhere else.
    public init(
        runId: String, messageIds: [String] = [], steps: [Step] = [], blocks: [Block],
        pendingToolCalls: [PendingToolCall] = [], sources: [CitationSource] = [], citations: [CitationSource]? = nil,
        durationMs: Int? = nil, timestampMs: Double? = nil, error: String? = nil, hasContent: Bool? = nil,
        occurrence: Int = 1, foot: RunFoot = RunFoot()
    ) {
        let blocks = Block.numbered(blocks)
        let body = blocks.compactMap { if case .text(let text) = $0 { text.text } else { nil } }
            .joined(separator: TextBlock.separator)
        let toolCards = blocks.compactMap { if case .card(let card) = $0 { card } else { nil } }
        self.runId = runId
        self.messageIds = messageIds
        self.steps = steps
        self.blocks = blocks
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
