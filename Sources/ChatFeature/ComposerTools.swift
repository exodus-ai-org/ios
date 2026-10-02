import Foundation
import Models
import NetworkingKit
import Observation

/// The composer's `+` choices for the whole app session, as the desktop's atoms keep them: a reasoning effort and Deep
/// Research, which exclude each other (`useAdvancedToolToggle`), and what the menu needs to know — the efforts the
/// current model supports and the tools the computer's MCP servers offer. One instance, made by the app shell and
/// handed to each chat screen; a turn reads `turnOptions` when it starts.
@MainActor
@Observable
public final class ComposerTools {
    public private(set) var reasoningEffort: ReasoningEffort = .off
    public private(set) var deepResearch = false
    /// What the Reasoning submenu offers, `off` first. Empty — the entry hidden — for a model that does not reason, or
    /// before the computer's settings have been read once.
    public private(set) var reasoningLevels: [ReasoningEffort] = []
    /// The connected servers' tools, by server, for the read-only sheet.
    public private(set) var mcpGroups: [McpToolsResponse.Group] = []

    /// Counts the user's own changes (not a refresh's fallback to off), so a haptic fires only for them.
    public private(set) var userChangeCount = 0

    public init() {}

    public var mcpToolCount: Int { mcpGroups.reduce(0) { $0 + $1.tools.count } }

    /// Something is on: the `+` is tinted and pills show.
    public var isActive: Bool { deepResearch || reasoningEffort != .off }

    public var turnOptions: TurnOptions { TurnOptions(deepResearch: deepResearch, reasoningEffort: reasoningEffort) }

    /// A level the model offers (or off). One other than off turns Deep Research off.
    public func setEffort(_ level: ReasoningEffort) {
        guard level == .off || reasoningLevels.contains(level) else { return }
        reasoningEffort = level
        userChangeCount += 1
        if level != .off { deepResearch = false }
    }

    /// Turning Deep Research on sets the effort off.
    public func setDeepResearch(_ on: Bool) {
        deepResearch = on
        userChangeCount += 1
        if on { reasoningEffort = .off }
    }

    /// The levels of the model now selected (`modelSnapshot.reasoningLevels`). A chosen level it lacks falls back to off.
    public func adopt(reasoningLevels supported: [String]) {
        reasoningLevels = Self.levels(supported)
        if !reasoningLevels.contains(reasoningEffort) { reasoningEffort = .off }
    }

    /// The connected servers' tools; a server with none is left out.
    public func adopt(mcpTools: McpToolsResponse) {
        mcpGroups = mcpTools.tools.filter { !$0.tools.isEmpty }
    }

    /// Off first, then the known levels the model lists, in the desktop's order; none when it lists no level but off.
    static func levels(_ supported: [String]) -> [ReasoningEffort] {
        let levels = ReasoningEffort.allCases.filter { $0 != .off && supported.contains($0.rawValue) }
        return levels.isEmpty ? [] : [.off] + levels
    }

    /// Reads the current model's levels and the MCP tools again. A read that fails keeps what was known: an entry is
    /// hidden only while nothing is.
    public func refresh(from source: ComposerToolsSource) async {
        async let levels = try? source.reasoningLevels()
        async let tools = try? source.mcpTools()
        if let levels = await levels { adopt(reasoningLevels: levels) }
        if let tools = await tools { adopt(mcpTools: tools) }
    }
}

/// Where `ComposerTools` reads from: the computer, or a test's stand-in.
public struct ComposerToolsSource: Sendable {
    public var reasoningLevels: @Sendable () async throws -> [String]
    public var mcpTools: @Sendable () async throws -> McpToolsResponse

    public init(
        reasoningLevels: @escaping @Sendable () async throws -> [String],
        mcpTools: @escaping @Sendable () async throws -> McpToolsResponse
    ) {
        self.reasoningLevels = reasoningLevels
        self.mcpTools = mcpTools
    }
}

extension ComposerToolsSource {
    /// `GET /api/v1/settings` (the selected model's snapshot, the desktop's `useAvailableEffortLevels`) and
    /// `GET /api/v1/mcp/tools`, through the paired session.
    public init(apiClient: APIClient) {
        self.init(
            reasoningLevels: {
                let settings: SettingsSnapshot = try await apiClient.get("/api/v1/settings")
                return settings.providerConfig?.modelSnapshot?.reasoningLevels ?? []
            },
            mcpTools: { try await apiClient.get("/api/v1/mcp/tools") })
    }
}
