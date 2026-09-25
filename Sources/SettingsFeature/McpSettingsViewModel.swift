import Foundation
import Models
import NetworkingKit
import Observation

/// Settings → MCP Servers: the servers registered on the computer, each with its tool count and the desktop's
/// on/off switch. The switch sends only `{isActive}` (`PUT /api/v1/mcp/:id` is a partial update), so no command,
/// URL, env or header ever reaches or leaves the phone. Adding and editing servers stays on the computer.
@MainActor
@Observable
public final class McpSettingsViewModel {
    public private(set) var servers: [McpServer] = []
    /// Tools of the connected servers, by server name.
    public private(set) var toolsByServer: [String: [McpTool]] = [:]
    public private(set) var listState: SettingsListState = .idle
    /// A failed switch.
    public var errorMessage: String?
    /// A reload that failed while the list stays on screen.
    public private(set) var refreshError: String?
    public private(set) var pending: Set<String> = []

    private let apiClient: APIClient
    private static let path = "/api/v1/mcp"

    public init(apiClient: APIClient) {
        self.apiClient = apiClient
    }

    public func tools(for server: McpServer) -> [McpTool] { toolsByServer[server.name] ?? [] }

    public func load() async {
        if servers.isEmpty { listState = .loading }
        async let serversRequest: [McpServer] = apiClient.get(Self.path)
        async let toolsRequest: McpToolsResponse = apiClient.get("\(Self.path)/tools")
        do {
            servers = try await serversRequest
            listState = .loaded
            refreshError = nil
        } catch {
            if servers.isEmpty {
                listState = .failed(error.localizedDescription)
            } else {
                refreshError = error.localizedDescription
            }
        }
        // The desktop's route answers an empty list when a server cannot be reached; a failure here only hides counts.
        if let tools = try? await toolsRequest { toolsByServer = tools.byServer }
    }

    /// Flips the switch at once, writes it, then re-reads servers and tools (a server switched on connects and
    /// lists its tools); a failed write puts the switch back.
    @discardableResult
    public func setActive(_ id: String, _ active: Bool) -> Task<Void, Never>? {
        guard let index = servers.firstIndex(where: { $0.id == id }), servers[index].isActive != active,
            !pending.contains(id)
        else { return nil }
        servers[index].isActive = active
        errorMessage = nil
        pending.insert(id)
        return Task {
            defer { pending.remove(id) }
            do {
                try await apiClient.put("\(Self.path)/\(id)", body: ActiveFlagBody(isActive: active))
            } catch {
                if let index = servers.firstIndex(where: { $0.id == id }) { servers[index].isActive = !active }
                let message = error.localizedDescription
                await load()
                errorMessage = message
                return
            }
            await load()
        }
    }
}
