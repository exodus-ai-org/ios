import Foundation
import Models
import Testing

@testable import ChatFeature

private let mcpJSON = #"""
    {"tools":[{"mcpServerName":"files","tools":[{"name":"read_file","description":"Reads a file."},{"name":"write_file","description":""}]},
              {"mcpServerName":"github","tools":[{"name":"search_issues","description":"Searches issues."}]},
              {"mcpServerName":"idle","tools":[]}]}
    """#

/// A computer that answers with `levels` and `tools` (JSON), or fails where one is nil.
private func source(levels: [String]?, tools: String?) -> ComposerToolsSource {
    ComposerToolsSource(
        reasoningLevels: {
            guard let levels else { throw URLError(.cannotConnectToHost) }
            return levels
        },
        mcpTools: {
            guard let tools else { throw URLError(.cannotConnectToHost) }
            return try JSONDecoder().decode(McpToolsResponse.self, from: Data(tools.utf8))
        })
}

@MainActor
@Suite("The composer's + choices")
struct ComposerToolsTests {
    private func tools(levels: [String] = ["off", "low", "medium", "high", "xhigh", "max"]) -> ComposerTools {
        let tools = ComposerTools()
        tools.adopt(reasoningLevels: levels)
        return tools
    }

    @Test("nothing is on at first")
    func startsOff() {
        let tools = ComposerTools()
        #expect(tools.reasoningEffort == .off && !tools.deepResearch && !tools.isActive)
        #expect(tools.turnOptions == TurnOptions())
        #expect(tools.reasoningLevels.isEmpty && tools.mcpToolCount == 0)
    }

    @Test("turning Deep Research on sets the effort off")
    func deepResearchTurnsTheEffortOff() {
        let tools = tools()
        tools.setEffort(.high)
        tools.setDeepResearch(true)
        #expect(tools.reasoningEffort == .off)
        #expect(tools.turnOptions == TurnOptions(deepResearch: true))
        #expect(tools.isActive)
    }

    @Test("picking a level other than off turns Deep Research off")
    func aLevelTurnsDeepResearchOff() {
        let tools = tools()
        tools.setDeepResearch(true)
        tools.setEffort(.low)
        #expect(!tools.deepResearch)
        #expect(tools.turnOptions == TurnOptions(reasoningEffort: .low))
    }

    @Test("picking off leaves Deep Research on")
    func offKeepsDeepResearch() {
        let tools = tools()
        tools.setDeepResearch(true)
        tools.setEffort(.off)
        #expect(tools.deepResearch)
    }

    @Test("the levels are off first, then the model's in the desktop's order; unknown names are ignored")
    func levelsInOrder() {
        #expect(ComposerTools.levels(["high", "off", "low", "bogus"]) == [.off, .low, .high])
        #expect(ComposerTools.levels(["medium"]) == [.off, .medium])
    }

    @Test("a model that does not reason hides the entry")
    func noReasoning() {
        #expect(ComposerTools.levels([]) == [])
        #expect(ComposerTools.levels(["off"]) == [])
    }

    @Test("a level the new model lacks falls back to off; one it has is kept")
    func fallback() {
        let tools = tools()
        tools.setEffort(.max)
        tools.adopt(reasoningLevels: ["off", "low", "high"])
        #expect(tools.reasoningEffort == .off)
        tools.setEffort(.high)
        tools.adopt(reasoningLevels: ["off", "high"])
        #expect(tools.reasoningEffort == .high)
        tools.adopt(reasoningLevels: [])
        #expect(tools.reasoningEffort == .off)
    }

    @Test("a level the model does not offer cannot be picked")
    func unsupportedLevel() {
        let tools = tools(levels: ["off", "low"])
        tools.setEffort(.max)
        #expect(tools.reasoningEffort == .off)
    }

    @Test("a refresh reads the model's levels and the connected servers' tools")
    func refresh() async {
        let tools = ComposerTools()
        await tools.refresh(from: source(levels: ["off", "medium"], tools: mcpJSON))
        #expect(tools.reasoningLevels == [.off, .medium])
        #expect(tools.mcpToolCount == 3)
        #expect(tools.mcpGroups.map(\.mcpServerName) == ["files", "github"])
    }

    @Test("a refresh to a model without the chosen level turns it off")
    func aRefreshToAModelWithoutTheLevelTurnsItOff() async {
        let tools = ComposerTools()
        await tools.refresh(from: source(levels: ["off", "low", "high"], tools: mcpJSON))
        tools.setEffort(.high)
        await tools.refresh(from: source(levels: ["off", "low"], tools: mcpJSON))
        #expect(tools.reasoningEffort == .off)
        #expect(tools.turnOptions.wireReasoningEffort == nil)
    }

    @Test("a failed refresh keeps what was known")
    func aFailedRefreshKeepsWhatWasKnown() async {
        let tools = ComposerTools()
        await tools.refresh(from: source(levels: ["off", "high"], tools: mcpJSON))
        tools.setEffort(.high)
        await tools.refresh(from: source(levels: nil, tools: nil))
        #expect(tools.reasoningLevels == [.off, .high])
        #expect(tools.reasoningEffort == .high)
        #expect(tools.mcpToolCount == 3)
    }

    @Test("a computer never reached hides Reasoning and MCP Tools, and Deep Research still works")
    func neverReached() async {
        let tools = ComposerTools()
        await tools.refresh(from: source(levels: nil, tools: nil))
        #expect(tools.reasoningLevels.isEmpty && tools.mcpToolCount == 0)
        tools.setDeepResearch(true)
        #expect(tools.turnOptions.advancedTools == ["Deep Research"])
    }

    @Test("only a user's change counts, not a refresh that drops the level")
    func userChangeCount() async {
        let tools = ComposerTools()
        await tools.refresh(from: source(levels: ["off", "low", "high"], tools: mcpJSON))
        #expect(tools.userChangeCount == 0)
        tools.setEffort(.high)
        #expect(tools.userChangeCount == 1)
        tools.setDeepResearch(true)
        #expect(tools.userChangeCount == 2)
        tools.setDeepResearch(false)
        tools.setEffort(.high)
        let before = tools.userChangeCount
        await tools.refresh(from: source(levels: ["off", "low"], tools: mcpJSON))
        #expect(tools.reasoningEffort == .off)
        #expect(tools.userChangeCount == before)
        tools.setEffort(.max)
        #expect(tools.userChangeCount == before)
    }
}
