import Foundation
import Models

/// The words the timeline and the tool cards show, kept out of the views so they can be tested.
enum ToolPresentation {
    // MARK: Tool names

    /// A built-in's user-facing name; an MCP or unknown tool keeps its own name.
    static func displayName(_ name: String) -> String {
        switch name {
        case "computer_use":
            String(localized: "ios:chat.message.tool.computerUse", defaultValue: "Computer Use", comment: "Tool name in a reply's steps.")
        case "deep_research":
            String(localized: "ios:chat.message.tool.deepResearch", defaultValue: "Deep Research", comment: "Tool name in a reply's steps.")
        case "create_artifact":
            String(localized: "ios:chat.message.tool.createArtifact", defaultValue: "Create Artifact", comment: "Tool name in a reply's steps.")
        case "image_generation":
            String(localized: "ios:chat.message.tool.imageGeneration", defaultValue: "Image Generation", comment: "Tool name in a reply's steps.")
        case "find_files":
            String(localized: "ios:chat.message.tool.findFiles", defaultValue: "Find Files", comment: "Tool name in a reply's steps.")
        case "edit_file":
            String(localized: "ios:chat.message.tool.editFile", defaultValue: "Edit File", comment: "Tool name in a reply's steps.")
        case "lcm_grep":
            String(localized: "ios:chat.message.tool.lcmGrep", defaultValue: "Search History", comment: "Tool name in a reply's steps: searches earlier parts of the conversation.")
        case "grep":
            String(localized: "ios:chat.message.tool.grep", defaultValue: "Grep", comment: "Tool name in a reply's steps: searches file contents.")
        case "lcm_describe":
            String(localized: "ios:chat.message.tool.lcmDescribe", defaultValue: "Describe History", comment: "Tool name in a reply's steps: summarises an earlier part of the conversation.")
        case "search_knowledge_base", "rag":
            String(localized: "ios:chat.message.tool.searchKnowledgeBase", defaultValue: "Search Knowledge Base", comment: "Tool name in a reply's steps.")
        case "map_itinerary":
            String(localized: "ios:chat.message.tool.mapItinerary", defaultValue: "Map Itinerary", comment: "Tool name in a reply's steps.")
        case "web_search":
            String(localized: "ios:chat.message.tool.webSearch", defaultValue: "Web Search", comment: "Tool name in a reply's steps.")
        case "lcm_expand":
            String(localized: "ios:chat.message.tool.lcmExpand", defaultValue: "Expand History", comment: "Tool name in a reply's steps: reopens an earlier part of the conversation.")
        case "weather":
            String(localized: "ios:chat.message.tool.weather", defaultValue: "Weather", comment: "Tool name in a reply's steps.")
        case "list_directory":
            String(localized: "ios:chat.message.tool.listDirectory", defaultValue: "List Directory", comment: "Tool name in a reply's steps.")
        case "terminal":
            String(localized: "ios:chat.message.tool.terminal", defaultValue: "Terminal", comment: "Tool name in a reply's steps.")
        case "read_file":
            String(localized: "ios:chat.message.tool.readFile", defaultValue: "Read File", comment: "Tool name in a reply's steps.")
        case "web_fetch":
            String(localized: "ios:chat.message.tool.webFetch", defaultValue: "Web Fetch", comment: "Tool name in a reply's steps: opens a web page.")
        case "write_file":
            String(localized: "ios:chat.message.tool.writeFile", defaultValue: "Write File", comment: "Tool name in a reply's steps.")
        case "update_memory":
            String(localized: "settings:tools.registry.updateMemory.label", defaultValue: "Update Memory", comment: "Tool name in a reply's steps.")
        case "list_mcp_tools":
            String(localized: "ios:chat.message.tool.listMcpTools", defaultValue: "List MCP Tools", comment: "Tool name in a reply's steps. MCP is the Model Context Protocol.")
        case "call_mcp_tool":
            String(localized: "ios:chat.message.tool.callMcpTool", defaultValue: "Call MCP Tool", comment: "Tool name in a reply's steps. MCP is the Model Context Protocol.")
        case "":
            String(localized: "ios:chat.message.tool.fallback", defaultValue: "Tool", comment: "Name shown for a tool whose name is unknown.")
        default:
            name
        }
    }

    /// Every tool name `displayName` knows. A name outside it is a tool this app has not caught up with.
    static var knownToolNames: Set<String> { ToolNames.known }

    /// What a card should report about how it rendered: an unknown tool, or a card drawn generically because its
    /// payload could not be read. Names and kinds only, never the payload.
    typealias RenderIssue = (message: String, attributes: [String: String])

    static func renderIssue(for card: ToolCard) -> RenderIssue? {
        let tool = String(card.toolName.prefix(64))
        if !knownToolNames.contains(card.toolName) {
            return ("Unknown tool name: \(tool)", ["tool": tool])
        }
        if ToolCardRegistry.hasCard(for: card.toolName), !ToolCardRegistry.canDraw(card) {
            return ("Unreadable \(tool) card shown as the generic card", ["tool": tool, "kind": "\(card.kind)"])
        }
        // No card of its own yet, but its result has a shape; one without it is reported like an unreadable card.
        if card.toolName == "create_artifact", card.kind != .artifact, !card.isError {
            return ("Unreadable \(tool) card shown as the generic card", ["tool": tool, "kind": "\(card.kind)"])
        }
        return nil
    }

    static func systemImage(for name: String) -> String {
        switch name {
        case "web_search", "web_fetch": "globe"
        case "terminal": "terminal"
        case "read_file", "write_file", "edit_file", "find_files", "list_directory", "grep": "doc.text.magnifyingglass"
        case "weather": "cloud.sun"
        case "map_itinerary": "map"
        case "update_memory": "brain"
        default: "wrench.and.screwdriver"
        }
    }

    // MARK: Timeline

    enum Header: Equatable {
        case live(String)
        case finished(thought: Bool, seconds: Int?)
    }

    /// The desktop drops a duration under a second: message timestamps mark a stream's start, not its end.
    static func wholeSeconds(_ durationMs: Int?) -> Int? {
        guard let durationMs, durationMs >= 1000 else { return nil }
        return Int((Double(durationMs) / 1000).rounded())
    }

    static func hasFailedTool(_ turn: AssistantTurn) -> Bool {
        turn.steps.contains { if case .toolCall(let call) = $0 { call.isError } else { false } }
    }

    static func header(for turn: AssistantTurn, isLive: Bool) -> Header {
        if isLive {
            guard let last = turn.steps.last else {
                return .live(turn.hasThinking ? thinkingPlaceholder : workingPlaceholder)
            }
            return .live(title(of: last))
        }
        return .finished(thought: turn.hasThinking, seconds: wholeSeconds(turn.durationMs))
    }

    static func headerText(_ header: Header) -> String {
        switch header {
        case .live(let title):
            return title
        case .finished(let thought, nil):
            return thought
                ? String(localized: "ios:chat.message.timeline.thought", defaultValue: "Thought", comment: "Collapsed header of a finished reply's steps when it reasoned; its duration is unknown.")
                : String(localized: "ios:chat.message.timeline.worked", defaultValue: "Worked", comment: "Collapsed header of a finished reply's steps when it only used tools; its duration is unknown.")
        case .finished(let thought, let seconds?):
            let duration = Duration.seconds(seconds).formatted(.units(allowed: [.minutes, .seconds], width: .abbreviated))
            return thought
                ? String(localized: "ios:chat.message.timeline.thoughtFor", defaultValue: "Thought for \(duration)", comment: "Collapsed header of a finished reply's steps. %@ is a duration such as 12 sec.")
                : String(localized: "ios:chat.message.timeline.workedFor", defaultValue: "Worked for \(duration)", comment: "Collapsed header of a finished reply's steps when it only used tools. %@ is a duration such as 12 sec.")
        }
    }

    static var thinkingPlaceholder: String {
        String(localized: "ios:chat.message.timeline.thinking", defaultValue: "Thinking…", comment: "Header of a reply's steps while the model reasons and nothing has streamed yet.")
    }

    static var workingPlaceholder: String {
        String(localized: "ios:chat.message.timeline.working", defaultValue: "Working…", comment: "Header of a reply's steps while the model works and nothing has streamed yet.")
    }

    /// One line per step: the collapsed header while live, and the step's row when expanded.
    static func title(of step: AssistantTurn.Step) -> String {
        switch step {
        case .thinking(let thinking):
            return thinking.title ?? String(localized: "ios:chat.message.timeline.thinkingStep", defaultValue: "Thinking", comment: "Title of a reasoning step that has no title of its own.")
        case .toolCall(let call):
            if call.isError { return call.errorText ?? failedText(call.name) }
            if !call.results.isEmpty { return resultCountText(call.resultCount) }
            return callText(call)
        }
    }

    static func callText(_ call: AssistantTurn.ToolCallStep) -> String {
        let name = displayName(call.name)
        let argument = call.argumentSummary ?? call.itinerary.map(itineraryText)
        guard let argument else { return name }
        return String(localized: "ios:chat.message.timeline.toolWithArgument", defaultValue: "\(name): \(argument)", comment: "A tool step: the tool's name, then what it was called with (a query, a URL or a path).")
    }

    static func failedText(_ name: String) -> String {
        let tool = displayName(name)
        return String(localized: "ios:chat.message.timeline.toolFailed", defaultValue: "\(tool) failed", comment: "A tool step that failed without a message. %@ is the tool's name.")
    }

    static func resultCountText(_ count: Int) -> String {
        count == 1
            ? String(localized: "ios:chat.message.timeline.oneResult", defaultValue: "1 result", comment: "A web search step that found one result.")
            : String(localized: "ios:chat.message.timeline.resultCount", defaultValue: "\(count) results", comment: "A web search step. %lld is how many results it found (never 1).")
    }

    static func moreSitesText(_ count: Int) -> String {
        String(localized: "ios:chat.message.timeline.moreSites", defaultValue: "+\(count) more", comment: "The last pill under a web search step: how many more sites it found than the pills show. It opens the list of sources.")
    }

    /// "3 days, 12 stops": the desktop's phrase, each count in its own plural form.
    static func itineraryText(_ scale: ItineraryScale) -> String {
        // The catalog's plural picks the form; the branches only give the hostless tests (no catalog) the right English.
        let days =
            scale.days == 1
            ? String(localized: "chat:toolPreview.mapItineraryDayCount", defaultValue: "\(scale.days) day", comment: "A map itinerary's length in days (plural).")
            : String(localized: "chat:toolPreview.mapItineraryDayCount", defaultValue: "\(scale.days) days", comment: "A map itinerary's length in days (plural).")
        let stops =
            scale.stops == 1
            ? String(localized: "chat:toolPreview.mapItineraryStopCount", defaultValue: "\(scale.stops) stop", comment: "A map itinerary's number of places to visit (plural).")
            : String(localized: "chat:toolPreview.mapItineraryStopCount", defaultValue: "\(scale.stops) stops", comment: "A map itinerary's number of places to visit (plural).")
        return String(
            localized: "chat:toolPreview.mapItinerarySummary", defaultValue: "\(days), \(stops)",
            comment: "A map itinerary's scale: its days, then its stops, each already a phrase.")
    }

    static func host(of source: CitationSource) -> String? {
        let candidates = [source.siteName, source.hostname, URL(string: source.link)?.host()]
        return candidates.compactMap { $0 }.first { !$0.isEmpty }
    }

    // MARK: Cards

    typealias TerminalOutput = TerminalResult

    static func terminalOutput(_ payload: JSONValue?) -> TerminalOutput? { payload.flatMap(TerminalResult.init(json:)) }

    static func exitText(_ code: String) -> String {
        String(localized: "ios:chat.message.terminal.exitCode", defaultValue: "exit \(code)", comment: "A terminal command's exit status. %@ is the code, such as 0 or 127.")
    }

    static func hasPayload(_ payload: JSONValue?) -> Bool {
        switch payload {
        case nil, .null?: false
        case .string(let text)?: !text.isEmpty
        default: true
        }
    }

    /// A string payload is shown as it came; anything else as sorted, indented JSON; cut after `maxLines` lines.
    static func prettyPayload(_ payload: JSONValue?, maxLines: Int = .max) -> String {
        let text: String
        switch payload {
        case nil, .null?: return ""
        case .string(let string)?: text = string
        case let value?:
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
            guard let data = try? encoder.encode(value), let encoded = String(data: data, encoding: .utf8) else { return "" }
            text = encoded
        }
        var lines = text.split(separator: "\n", omittingEmptySubsequences: false)
        guard lines.count > maxLines else { return text }
        lines = Array(lines.prefix(maxLines))
        return lines.joined(separator: "\n") + "\n\u{2026}"
    }

    /// Whether the terminal card has more to show than its collapsed height: many lines, or long ones that wrap.
    static func terminalOutputIsLong(_ output: TerminalOutput, collapsedLines: Int) -> Bool {
        let text = output.stdout + "\n" + output.stderr
        return text.split(separator: "\n", omittingEmptySubsequences: false).count > collapsedLines
            || text.count > collapsedLines * 60 || output.command.count > 120
    }
}
