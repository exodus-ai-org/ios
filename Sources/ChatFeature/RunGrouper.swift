import Foundation
import Models

public enum RunGrouper {
    public struct Cache: Sendable {
        fileprivate struct Entry: Sendable {
            let messages: [ChatMessage]
            let priorCitations: [CitationSource]
            let turn: AssistantTurn
        }

        fileprivate var entries: [String: Entry] = [:]
        public fileprivate(set) var builtTurnCount = 0
        public var cachedTurnCount: Int { entries.count }

        public init() {}
    }

    public static func group(_ messages: [ChatMessage], cache: inout Cache) -> [Segment] {
        var segments: [Segment] = []
        var seen: [String: Cache.Entry] = [:]
        var buffer: [ChatMessage] = []
        var bufferRun = ""
        var currentRun: String?
        var citations: [CitationSource] = []
        var occurrences: [String: Int] = [:]

        func flush() {
            guard !buffer.isEmpty else { return }
            let occurrence = occurrences[bufferRun, default: 0] + 1
            occurrences[bufferRun] = occurrence
            let key = AssistantTurn.key(runId: bufferRun, occurrence: occurrence)
            var turn: AssistantTurn
            if let entry = cache.entries[key], entry.messages == buffer {
                turn = entry.turn
                if entry.priorCitations != citations { turn.citations = citations + turn.sources }
            } else {
                turn = buildTurn(runId: bufferRun, messages: buffer)
                cache.builtTurnCount += 1
                turn.occurrence = occurrence
                turn.citations = turn.sources.isEmpty ? citations : citations + turn.sources
            }
            seen[key] = Cache.Entry(messages: buffer, priorCitations: citations, turn: turn)
            citations = turn.citations
            if turn.hasContent { segments.append(.assistantTurn(turn)) }
            buffer = []
        }

        for message in messages {
            if message.role == "user" {
                flush()
                currentRun = message.runId ?? message.id
                segments.append(.user(message))
            } else {
                let run = message.runId ?? currentRun ?? message.id
                if currentRun == nil && message.runId == nil { currentRun = message.id }
                if !buffer.isEmpty && run != bufferRun { flush() }
                bufferRun = run
                buffer.append(message)
            }
        }
        flush()
        cache.entries = seen
        return segments
    }

    static func buildTurn(runId: String, messages: [ChatMessage]) -> AssistantTurn {
        var steps: [AssistantTurn.Step] = []
        var texts: [String] = []
        var pending: [PendingToolCall] = []
        var cards: [ToolCard] = []
        var sources: [CitationSource] = []
        var timestamp: Double?
        var callArguments: [String: JSONValue] = [:]
        var memoryUpdates: [MemoryUpdate] = []

        func settleMemoryUpdate(_ update: MemoryUpdate) {
            if let index = memoryUpdates.firstIndex(where: { $0.id == update.id && $0.status == .pending }) {
                memoryUpdates[index] = update
            } else {
                memoryUpdates.append(update)
            }
        }

        func pendingStepIndex(_ callId: String?) -> Int? {
            steps.firstIndex {
                if case .toolCall(let step) = $0 { step.id == callId && step.isPending } else { false }
            }
        }

        func settle(_ message: ChatMessage, _ update: (inout AssistantTurn.ToolCallStep) -> Void) {
            if let index = pendingStepIndex(message.toolCallId), case .toolCall(var step) = steps[index] {
                update(&step)
                steps[index] = .toolCall(step)
            } else {
                var step = AssistantTurn.ToolCallStep(
                    id: message.toolCallId ?? message.id, name: message.toolName ?? "", argumentSummary: nil,
                    codeArgument: nil, itinerary: nil, status: .succeeded, errorText: nil, results: [])
                update(&step)
                steps.append(.toolCall(step))
            }
        }

        for message in messages {
            switch message.role {
            case "assistant":
                timestamp = message.timestampMs
                let ran = message.stopReason != "aborted" && message.stopReason != "error"
                for block in message.contentBlocks {
                    switch block {
                    case .thinking(let text) where !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty:
                        steps.append(.thinking(.init(text: text, title: thinkingTitle(text))))
                    case .toolCall(let id, let name, let arguments):
                        steps.append(.toolCall(toolCallStep(id: id, name: name, arguments: arguments)))
                        pending.append(PendingToolCall(id: id, name: name))
                        callArguments[id] = .object(arguments)
                        if name == "update_memory", ran { memoryUpdates.append(MemoryUpdate(id: id, status: .pending)) }
                    case .text(let text) where !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty:
                        texts.append(text)
                    default:
                        break
                    }
                }
            case "toolResult":
                let hadStep = pendingStepIndex(message.toolCallId) != nil
                if let index = pending.firstIndex(where: { $0.id == message.toolCallId }) { pending.remove(at: index) }
                let name = message.toolName ?? ""
                if message.isError {
                    let errorText = message.contentBlocks.lazy.compactMap { if case .text(let t) = $0 { t } else { nil } }
                        .first.flatMap { text -> String? in
                            let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
                            return trimmed.isEmpty || trimmed == "{}" ? nil : text
                        }
                    settle(message) {
                        $0.status = .failed
                        $0.errorText = errorText
                    }
                    if name == "update_memory" {
                        settleMemoryUpdate(
                            MemoryUpdate(id: message.toolCallId ?? message.id, status: .failed, errorText: errorText))
                    }
                    if ToolCardRegistry.drawsFailures(for: name) {
                        cards.append(
                            ToolCard(
                                id: message.id, toolCallId: message.toolCallId, toolName: name, kind: .generic,
                                arguments: message.toolCallId.flatMap { callArguments[$0] }, isError: true,
                                errorText: errorText))
                    }
                    continue
                }
                let details = message.details
                if name == "web_search", case .array(let items)? = details, !items.isEmpty {
                    let results = items.compactMap(CitationSource.init)
                    sources += results
                    settle(message) {
                        $0.status = .succeeded
                        $0.results = results
                    }
                    continue
                }
                if hadStep { settle(message) { $0.status = .succeeded } }
                let output = payload(of: message)
                if name == "update_memory" {
                    let result = output.flatMap(MemoryUpdateResult.init(json:))
                    settleMemoryUpdate(MemoryUpdate(id: message.toolCallId ?? message.id, status: .succeeded, result: result))
                }
                if name == "web_fetch", let details, let source = CitationSource(details) {
                    sources.append(source)
                } else {
                    if let kind = cardKind(name, output) {
                        cards.append(
                            ToolCard(
                                id: message.id, toolCallId: message.toolCallId, toolName: name, kind: kind,
                                payload: output, arguments: message.toolCallId.flatMap { callArguments[$0] },
                                resultImage: name == "computer_use"
                                    ? ComputerUseCardModel.resultImage(message.contentBlocks) : nil))
                    }
                }
            default:
                break
            }
        }

        for call in pending where ToolCardRegistry.drawsPending(for: call.name) {
            cards.append(
                ToolCard(
                    id: "pending:\(call.id)", toolCallId: call.id, toolName: call.name, kind: .generic,
                    arguments: callArguments[call.id], isPending: true))
        }

        cards = imageCardsLast(cards, steps: steps)
        let body = texts.joined(separator: "\n\n")
        let lastAssistant = messages.last { $0.role == "assistant" }
        let error = lastAssistant?.stopReason == "error" ? (lastAssistant?.errorMessage ?? "") : nil
        let hasToolResult = messages.contains { $0.role == "toolResult" }
        return AssistantTurn(
            runId: runId, messageIds: messages.map(\.id), steps: steps, body: body, toolCards: cards,
            pendingToolCalls: pending, sources: sources, citations: sources,
            durationMs: duration(of: messages), timestampMs: timestamp, error: error,
            hasContent: !steps.isEmpty || !body.isEmpty || !pending.isEmpty || hasToolResult || error != nil,
            foot: foot(memoryUpdates: memoryUpdates, sources: sources))
    }

    /// The desktop draws the image-generation cards after every other card, in call order; a running one keeps the
    /// slot its result lands in.
    private static func imageCardsLast(_ cards: [ToolCard], steps: [AssistantTurn.Step]) -> [ToolCard] {
        let images = cards.enumerated().filter { $0.element.toolName == "image_generation" }
        guard !images.isEmpty else { return cards }
        var order: [String: Int] = [:]
        for case .toolCall(let step) in steps where order[step.id] == nil { order[step.id] = order.count }
        let sorted = images.sorted {
            let lhs = $0.element.toolCallId.flatMap { order[$0] } ?? Int.max
            let rhs = $1.element.toolCallId.flatMap { order[$0] } ?? Int.max
            return lhs != rhs ? lhs < rhs : $0.offset < $1.offset
        }
        return cards.filter { $0.toolName != "image_generation" } + sorted.map(\.element)
    }

    private static func foot(memoryUpdates: [MemoryUpdate], sources: [CitationSource]) -> RunFoot {
        let media = sources.flatMap { $0.media.compactMap(WebSearchMedia.init(json:)) }
        var foot = RunFoot(memoryUpdates: memoryUpdates, searchMedia: media)
        if !media.isEmpty { foot.gallery = SearchGallery(media: media) }
        return foot
    }

    static func thinkingTitle(_ text: String) -> String? {
        if let match = text.firstMatch(of: #/\*\*(.+?)\*\*/#) { return String(match.1) }
        return text.split(whereSeparator: \.isNewline).first.map { String($0.prefix(60)) }
    }

    private static func toolCallStep(id: String, name: String, arguments: [String: JSONValue])
        -> AssistantTurn.ToolCallStep
    {
        func pick(_ key: String) -> String? {
            guard let value = arguments[key]?.stringValue, !value.isEmpty else { return nil }
            return value
        }
        var summary: String?
        var code: String?
        var itinerary: ItineraryScale?
        switch name {
        case "terminal": code = pick("command")
        case "web_search": summary = pick("query")
        case "web_fetch": summary = pick("url")
        case "read_file", "write_file", "edit_file": summary = pick("path") ?? pick("filePath")
        case "weather": summary = pick("location")
        case "map_itinerary":
            let days: [JSONValue] = if case .array(let days)? = arguments["days"] { days } else { [] }
            let stops = days.reduce(0) { total, day in
                guard case .object(let object) = day, case .array(let places)? = object["places"] else { return total }
                return total + places.count
            }
            itinerary = ItineraryScale(days: days.count, stops: stops)
        default: break
        }
        return AssistantTurn.ToolCallStep(
            id: id, name: name, argumentSummary: summary, codeArgument: code, itinerary: itinerary,
            status: .pending, errorText: nil, results: [])
    }

    private static func cardKind(_ name: String, _ payload: JSONValue?) -> ToolCard.Kind? {
        let type: String? = if case .object(let object)? = payload { object["type"]?.stringValue } else { nil }
        switch name {
        case "terminal": return .terminal
        case "weather": return .weather
        case "deep_research": return .deepResearch
        case "computer_use": return .computerUse
        // An unreadable result still shows (the generic card) and is reported, like every other card's.
        case "map_itinerary": return type == "mapItinerary" ? .mapItinerary : .generic
        // Its result is the memory strip at the run's foot; only one that cannot be read gets the generic card.
        case "update_memory": return payload.flatMap(MemoryUpdateResult.init(json:)) == nil ? .generic : nil
        case "create_artifact": return type == "artifact" ? .artifact : .generic
        // A built-in gets a card only once it has one of its own in the registry.
        default: return ToolNames.known.contains(name) && !ToolCardRegistry.hasCard(for: name) ? nil : .generic
        }
    }

    // Built-ins put their payload in `details`; MCP tools wrap it as text blocks, like the desktop's CallingTools.
    static func payload(of message: ChatMessage) -> JSONValue? {
        func parseTextBlocks(_ blocks: JSONValue?) -> JSONValue? {
            guard case .array(let items)? = blocks else { return nil }
            let text = items.lazy.compactMap { item -> String? in
                guard case .object(let object) = item, object["type"]?.stringValue == "text" else { return nil }
                return object["text"]?.stringValue
            }.first
            guard let text else { return nil }
            guard let parsed = try? JSONDecoder().decode(JSONValue.self, from: Data(text.utf8)) else {
                return .string(text)
            }
            if case .object(let object) = parsed, object["content"] != nil, let details = object["details"] {
                return details
            }
            return parsed
        }
        if let details = message.details {
            if case .object(let object) = details, case .array? = object["content"], object["type"] == nil {
                return parseTextBlocks(object["content"])
            }
            return details
        }
        return parseTextBlocks(message.raw["content"])
    }

    private static func duration(of messages: [ChatMessage]) -> Int? {
        if let stamped = messages.last(where: { $0.role == "assistant" && $0.durationMs != nil })?.durationMs {
            return Int(exactly: stamped.rounded())
        }
        guard let first = messages.first?.timestampMs, let last = messages.last?.timestampMs, first != 0, last != 0
        else { return nil }
        return Int(exactly: (last - first).rounded())
    }
}
