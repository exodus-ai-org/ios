import Foundation
import Models
import Testing

@testable import ChatFeature

private func turn(_ json: String) throws -> AssistantTurn {
    var cache = RunGrouper.Cache()
    let messages = try JSONDecoder().decode([ChatMessage].self, from: Data(json.utf8))
    guard case .assistantTurn(let turn)? = RunGrouper.group(messages, cache: &cache).last else {
        throw CocoaError(.coderValueNotFound)
    }
    return turn
}

private func run(_ assistantAndTools: String) -> String {
    #"[{"id":"u1","runId":"u1","role":"user","content":"q"},"# + assistantAndTools + "]"
}

private func json(_ text: String) throws -> JSONValue {
    try JSONDecoder().decode(JSONValue.self, from: Data(text.utf8))
}

@Suite("ToolPresentation: names")
struct ToolDisplayNameTests {
    @Test(
        "built-ins get their user-facing name",
        arguments: [
            ("web_search", "Web Search"), ("terminal", "Terminal"), ("read_file", "Read File"),
            ("call_mcp_tool", "Call MCP Tool"), ("lcm_grep", "Search History"), ("map_itinerary", "Map Itinerary"),
        ])
    func builtIns(name: String, expected: String) {
        #expect(ToolPresentation.displayName(name) == expected)
    }

    @Test("an MCP or unknown tool keeps its own name; an empty one is \"Tool\"")
    func others() {
        #expect(ToolPresentation.displayName("drawio_create") == "drawio_create")
        #expect(ToolPresentation.displayName("") == "Tool")
    }

    @Test("every built-in of the desktop's TOOL_NAMES has a name of its own")
    func everyBuiltIn() {
        let names = [
            "computer_use", "deep_research", "create_artifact", "image_generation", "find_files", "edit_file", "lcm_grep",
            "grep", "lcm_describe", "search_knowledge_base", "map_itinerary", "web_search", "lcm_expand", "weather",
            "list_directory", "terminal", "read_file", "web_fetch", "write_file", "list_mcp_tools", "call_mcp_tool",
        ]
        for name in names where name != "grep" && name != "weather" && name != "terminal" {
            #expect(ToolPresentation.displayName(name) != name, "\(name)")
        }
        #expect(Set(names.map(ToolPresentation.displayName)).count == names.count)
    }
}

@Suite("ToolPresentation: timeline header")
struct TimelineHeaderTests {
    @Test("whole seconds, rounded half up; under a second or unknown has no duration")
    func seconds() {
        #expect(ToolPresentation.wholeSeconds(nil) == nil)
        #expect(ToolPresentation.wholeSeconds(999) == nil)
        #expect(ToolPresentation.wholeSeconds(1000) == 1)
        #expect(ToolPresentation.wholeSeconds(1499) == 1)
        #expect(ToolPresentation.wholeSeconds(1500) == 2)
        #expect(ToolPresentation.wholeSeconds(12_400) == 12)
        #expect(ToolPresentation.wholeSeconds(90_000) == 90)
    }

    @Test("finished: Thought when it reasoned, Worked when it only used tools, with the duration when known")
    func finished() throws {
        let thought = try turn(run(#"{"id":"a1","runId":"u1","role":"assistant","content":[{"type":"thinking","thinking":"hm"},{"type":"text","text":"x"}],"durationMs":12400}"#))
        #expect(ToolPresentation.header(for: thought, isLive: false) == .finished(thought: true, seconds: 12))
        #expect(ToolPresentation.headerText(.finished(thought: true, seconds: 12)).hasPrefix("Thought for "))
        #expect(ToolPresentation.headerText(.finished(thought: true, seconds: 12)).contains("12"))
        #expect(ToolPresentation.headerText(.finished(thought: false, seconds: 3)).hasPrefix("Worked for "))
        #expect(ToolPresentation.headerText(.finished(thought: true, seconds: nil)) == "Thought")
        #expect(ToolPresentation.headerText(.finished(thought: false, seconds: nil)) == "Worked")
    }

    @Test("live: the latest step's title")
    func live() throws {
        let thinking = try turn(run(#"{"id":"a1","runId":"u1","role":"assistant","content":[{"type":"thinking","thinking":"**Weighing options** now"}]}"#))
        #expect(ToolPresentation.header(for: thinking, isLive: true) == .live("Weighing options"))
        let searching = try turn(run(#"{"id":"a1","runId":"u1","role":"assistant","content":[{"type":"thinking","thinking":"x"},{"type":"toolCall","id":"k1","name":"web_search","arguments":{"query":"swift 6"}}]}"#))
        #expect(ToolPresentation.header(for: searching, isLive: true) == .live("Web Search: swift 6"))
        let found = try turn(run(#"""
            {"id":"a1","runId":"u1","role":"assistant","content":[{"type":"toolCall","id":"k1","name":"web_search","arguments":{"query":"q"}}]},
            {"id":"t1","runId":"u1","role":"toolResult","toolCallId":"k1","toolName":"web_search","content":[],"details":[{"rank":1,"link":"https://a.com","title":"A"},{"rank":2,"link":"https://b.com","title":"B"}],"isError":false}
            """#))
        #expect(ToolPresentation.header(for: found, isLive: true) == .live("2 results"))
    }

    @Test("step titles: failed tools, one result, terminal and itinerary")
    func stepTitles() throws {
        let failed = try turn(run(#"""
            {"id":"a1","runId":"u1","role":"assistant","content":[{"type":"toolCall","id":"k1","name":"read_file","arguments":{"path":"/x"}}]},
            {"id":"t1","runId":"u1","role":"toolResult","toolCallId":"k1","toolName":"read_file","content":[{"type":"text","text":"ENOENT"}],"isError":true}
            """#))
        #expect(ToolPresentation.title(of: try #require(failed.steps.last)) == "ENOENT")
        #expect(ToolPresentation.failedText("read_file") == "Read File failed")
        #expect(ToolPresentation.resultCountText(1) == "1 result")
        #expect(ToolPresentation.resultCountText(0) == "0 results")
        let terminal = try turn(run(#"{"id":"a1","runId":"u1","role":"assistant","content":[{"type":"toolCall","id":"k1","name":"terminal","arguments":{"command":"ls -la"}}]}"#))
        guard case .toolCall(let call)? = terminal.steps.last else { throw CocoaError(.coderValueNotFound) }
        #expect(ToolPresentation.callText(call) == "Terminal")
        #expect(call.codeArgument == "ls -la")
        #expect(ToolPresentation.itineraryText(ItineraryScale(days: 3, stops: 12)) == "3 days, 12 stops")
        #expect(ToolPresentation.itineraryText(ItineraryScale(days: 1, stops: 1)) == "1 day, 1 stop")
    }

    @Test("a thinking step without a title of its own reads Thinking; no steps yet reads Thinking… or Working…")
    func placeholders() throws {
        let blank = try turn(run(#"{"id":"a1","runId":"u1","role":"assistant","content":[{"type":"toolCall","id":"k1","name":"grep","arguments":{}}]}"#))
        #expect(ToolPresentation.header(for: blank, isLive: true) == .live("Grep"))
        #expect(ToolPresentation.thinkingPlaceholder == "Thinking…")
        #expect(ToolPresentation.workingPlaceholder == "Working…")
    }
}

@Suite("ToolPresentation: cards")
struct ToolCardPresentationTests {
    @Test("terminal payload: command, cwd, numeric or named exit code, output")
    func terminal() throws {
        let ok = try #require(ToolPresentation.terminalOutput(json(#"{"command":"ls","cwd":"/tmp","exitCode":0,"stdout":"a\nb","stderr":""}"#)))
        #expect(ok == .init(command: "ls", cwd: "/tmp", exitCode: "0", stdout: "a\nb", stderr: ""))
        #expect(ok.succeeded)
        let failed = try #require(ToolPresentation.terminalOutput(json(#"{"command":"x","exitCode":127,"stderr":"not found"}"#)))
        #expect(failed.exitCode == "127")
        #expect(!failed.succeeded)
        #expect(failed.cwd == nil)
        let signal = try #require(ToolPresentation.terminalOutput(json(#"{"command":"sleep 9","exitCode":"ETIMEDOUT"}"#)))
        #expect(signal.exitCode == "ETIMEDOUT")
        #expect(ToolPresentation.exitText("0") == "exit 0")
    }

    @Test("terminal payload given as a JSON string still parses; anything without a command does not")
    func terminalFallbacks() throws {
        #expect(ToolPresentation.terminalOutput(.string(#"{"command":"pwd","exitCode":0}"#))?.command == "pwd")
        #expect(ToolPresentation.terminalOutput(.string("plain text")) == nil)
        #expect(ToolPresentation.terminalOutput(try json(#"{"stdout":"x"}"#)) == nil)
        #expect(ToolPresentation.terminalOutput(nil) == nil)
    }

    @Test("generic payload: strings as they are, JSON sorted and indented, nothing for null")
    func pretty() throws {
        #expect(ToolPresentation.prettyPayload(nil) == "")
        #expect(ToolPresentation.prettyPayload(.null) == "")
        #expect(ToolPresentation.prettyPayload(.string("raw")) == "raw")
        let text = ToolPresentation.prettyPayload(try json(#"{"b":1,"a":"https://x.com/y"}"#))
        #expect(text == "{\n  \"a\" : \"https://x.com/y\",\n  \"b\" : 1\n}")
    }
}
