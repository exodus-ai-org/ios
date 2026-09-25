import Foundation

/// One entry of `GET /api/v1/skills/installed` (the desktop's `InstalledSkill`).
public struct InstalledSkill: Decodable, Equatable, Identifiable, Sendable {
    public let slug: String
    public var displayName: String
    public var version: String
    public var isActive: Bool
    /// Milliseconds since 1970, as the lockfile stores it.
    public var installedAt: Double?
    public var registryId: String?
    /// Absent on entries from before skills.sh: the desktop labels those "Legacy".
    public var source: String?

    public var id: String { slug }
    public var isLegacy: Bool { source == nil }
    public var installedDate: Date? { installedAt.map { Date(timeIntervalSince1970: $0 / 1000) } }

    public init(
        slug: String, displayName: String? = nil, version: String = "", isActive: Bool = true,
        installedAt: Double? = nil, registryId: String? = nil, source: String? = "skills.sh"
    ) {
        self.slug = slug
        self.displayName = displayName ?? slug
        self.version = version
        self.isActive = isActive
        self.installedAt = installedAt
        self.registryId = registryId
        self.source = source
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: AnyCodingKey.self)
        slug = try c.decode(String.self, forKey: "slug")
        displayName = c.lenient(String.self, forKey: "displayName") ?? slug
        version = c.lenient(String.self, forKey: "version") ?? ""
        isActive = c.lenient(Bool.self, forKey: "isActive") ?? false
        installedAt = c.lenient(Double.self, forKey: "installedAt")
        registryId = c.lenient(String.self, forKey: "registryId")
        source = c.lenient(String.self, forKey: "source")
    }
}

/// One row of `GET /api/v1/mcp`. The row also carries the server's command, URL, env and headers, which can hold
/// secrets: they are deliberately not decoded.
public struct McpServer: Decodable, Equatable, Identifiable, Sendable {
    public let id: String
    public var name: String
    public var description: String
    /// `stdio`, `sse` or `streamable-http`.
    public var transportType: String
    /// The desktop reads `null` as off.
    public var isActive: Bool

    public var isRemote: Bool { transportType != "stdio" }

    public init(id: String, name: String, description: String = "", transportType: String = "stdio", isActive: Bool) {
        self.id = id
        self.name = name
        self.description = description
        self.transportType = transportType
        self.isActive = isActive
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: AnyCodingKey.self)
        id = try c.decode(String.self, forKey: "id")
        name = c.lenient(String.self, forKey: "name") ?? ""
        description = c.lenient(String.self, forKey: "description") ?? ""
        transportType = c.lenient(String.self, forKey: "transportType") ?? "stdio"
        isActive = c.lenient(Bool.self, forKey: "isActive") ?? false
    }
}

/// `GET /api/v1/mcp/tools`: the tools of each connected (active) server, keyed by server name.
public struct McpToolsResponse: Decodable, Equatable, Sendable {
    public struct Group: Decodable, Equatable, Sendable {
        public var mcpServerName: String
        public var tools: [McpTool]
    }

    public var tools: [Group]

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: AnyCodingKey.self)
        tools = c.lenient([Group].self, forKey: "tools") ?? []
    }

    public var byServer: [String: [McpTool]] {
        Dictionary(tools.map { ($0.mcpServerName, $0.tools) }, uniquingKeysWith: { $0 + $1 })
    }
}

public struct McpTool: Decodable, Equatable, Sendable, Identifiable {
    public var name: String
    public var description: String

    public var id: String { name }

    public init(name: String, description: String = "") {
        self.name = name
        self.description = description
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: AnyCodingKey.self)
        name = c.lenient(String.self, forKey: "name") ?? ""
        description = c.lenient(String.self, forKey: "description") ?? ""
    }
}

/// `{isActive}`: the whole body of `PATCH /api/v1/skills/:slug/toggle` and of the desktop's MCP switch,
/// `PUT /api/v1/mcp/:id` (a partial update; the server sets only the fields sent).
public struct ActiveFlagBody: Encodable, Equatable, Sendable {
    public let isActive: Bool

    public init(isActive: Bool) { self.isActive = isActive }
}
