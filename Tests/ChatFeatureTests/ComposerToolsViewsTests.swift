import AVFoundation
import Foundation
import Models
import Testing

@testable import ChatFeature

@MainActor
@Suite("The composer's + views")
struct ComposerToolsViewsTests {
    @Test("Take Photo opens the camera when allowed, lets the system ask the first time, and explains once refused")
    func cameraAccess() {
        #expect(CameraAccess.decision(for: .authorized) == .open)
        #expect(CameraAccess.decision(for: .notDetermined) == .ask)
        #expect(CameraAccess.decision(for: .denied) == .explain)
        #expect(CameraAccess.decision(for: .restricted) == .explain)
    }

    @Test("no pill while nothing is on")
    func noPills() {
        #expect(ComposerToolPills.pills(for: ComposerTools()).isEmpty)
    }

    @Test("a reasoning level shows its pill, and its ✕ turns reasoning off")
    func reasoningPill() {
        let tools = ComposerTools()
        tools.adopt(reasoningLevels: ["off", "high"])
        tools.setEffort(.high)
        #expect(ComposerToolPills.pills(for: tools) == [.reasoning(.high)])
        ComposerToolPills.turnOff(.reasoning(.high), in: tools)
        #expect(tools.reasoningEffort == .off)
        #expect(ComposerToolPills.pills(for: tools).isEmpty)
    }

    @Test("Deep Research shows its pill, and its ✕ turns it off")
    func deepResearchPill() {
        let tools = ComposerTools()
        tools.setDeepResearch(true)
        #expect(ComposerToolPills.pills(for: tools) == [.deepResearch])
        ComposerToolPills.turnOff(.deepResearch, in: tools)
        #expect(!tools.deepResearch)
    }

    @Test("a tool's description is its own, or a line saying it has none")
    func toolDescription() {
        #expect(McpToolsSheet.description(of: McpTool(name: "read_file", description: "Reads **a file**.")) == "Reads **a file**.")
        #expect(McpToolsSheet.description(of: McpTool(name: "get_me")) == "No description for get_me.")
        #expect(McpToolsSheet.description(of: McpTool(name: "ping", description: "  \n")) == "No description for ping.")
    }
}
