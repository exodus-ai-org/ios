import Foundation
import Testing

@testable import Models

@Suite("Built-in tool names")
struct ToolNamesTests {
    private static let fixture = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
        .deletingLastPathComponent().appending(path: "SettingsFeatureTests/Fixtures/desktop-tools.json")

    @Test("the list is the desktop's TOOL_NAMES, as the SettingsFeature fixture pins it")
    func matchesToolNames() throws {
        struct Fixture: Decodable { let toolNames: [String] }
        let desktop = try JSONDecoder().decode(Fixture.self, from: Data(contentsOf: Self.fixture))
        #expect(ToolNames.builtIn.count == Set(ToolNames.builtIn).count)
        #expect(Set(ToolNames.builtIn) == Set(desktop.toolNames))
    }

    @Test("rows of the retired rag tool are known, not reported as an unknown tool")
    func retiredNamesAreKnown() {
        #expect(ToolNames.known == Set(ToolNames.builtIn).union(["rag"]))
    }
}
