import Foundation
import Models
import Testing

@testable import ChatFeature

@Suite("Tool card diagnostics")
struct ToolCardDiagnosticsTests {
    @Test("every known tool has its own display name, so the known set matches displayName")
    func knownNamesMatchDisplayNames() {
        for name in ToolPresentation.knownToolNames {
            #expect(ToolPresentation.displayName(name) != name, "\(name) has no display name")
        }
    }

    @Test("a row of the retired rag tool is known: no card, and not reported as an unknown tool")
    func ragIsKnown() {
        let card = ToolCard(id: "t1", toolName: "rag", kind: .generic, payload: .string("private"))
        #expect(ToolPresentation.renderIssue(for: card) == nil)
        #expect(ToolPresentation.displayName("rag") == ToolPresentation.displayName("search_knowledge_base"))
    }

    @Test("an unknown tool name is reported by name")
    func unknownToolReported() throws {
        let card = ToolCard(id: "t1", toolName: "summon_llama", kind: .generic, payload: .string("private"))
        let issue = try #require(ToolPresentation.renderIssue(for: card))
        #expect(issue.message == "Unknown tool name: summon_llama")
        #expect(issue.attributes == ["tool": "summon_llama"])
    }

    @Test("update_memory is a known tool with its own name and icon; an unreadable result is reported, without it")
    func updateMemoryIsKnown() throws {
        let card = ToolCard(id: "t1", toolName: "update_memory", kind: .generic, payload: .string("private"))
        let issue = try #require(ToolPresentation.renderIssue(for: card))
        #expect(issue.attributes == ["tool": "update_memory", "kind": "generic"])
        #expect(!issue.message.contains("private"))
        #expect(ToolPresentation.displayName("update_memory") == "Update Memory")
        #expect(ToolPresentation.systemImage(for: "update_memory") == "brain")
    }

    @Test("a terminal card whose payload cannot be read reports the generic fallback, without the payload")
    func terminalFallbackReported() throws {
        let card = ToolCard(
            id: "t1", toolName: "terminal", kind: .terminal, payload: .object(["stdout": .string("secret output")]))
        let issue = try #require(ToolPresentation.renderIssue(for: card))
        #expect(issue.attributes == ["tool": "terminal", "kind": "terminal"])
        #expect(!issue.message.contains("secret"))
    }

    @Test("a readable card of a known tool reports nothing")
    func readableCardIsQuiet() {
        let terminal = ToolCard(
            id: "t1", toolName: "terminal", kind: .terminal, payload: .object(["command": .string("ls")]))
        #expect(ToolPresentation.renderIssue(for: terminal) == nil)
        let weather = ToolCard(
            id: "t2", toolName: "weather", kind: .weather,
            payload: .object(["location": .string("Shanghai"), "current": .object(["tempC": .string("22")])]))
        #expect(ToolPresentation.renderIssue(for: weather) == nil)
        #expect(ToolPresentation.renderIssue(for: ToolCard(
                    id: "t3", toolName: "deep_research", kind: .deepResearch, payload: .object(["id": .string("d1")])))
                == nil)
    }
}
