import Foundation

/// The desktop's `memory_section` enum, in the order its Memory page groups entries.
public enum MemorySection: String, CaseIterable, Codable, Sendable {
    case profile, topic, person
}

/// One row of `GET /api/v1/memory` (the desktop's `MemoryItem`): a topic or person with a one-line summary and
/// bullet details. Only what the phone shows or edits is decoded.
public struct MemoryEntry: Decodable, Equatable, Identifiable, Sendable {
    public let id: String
    /// Raw, so an entry in a section this app does not know still decodes.
    public var section: String
    public var key: String
    public var summary: String
    public var details: [String]
    /// The desktop treats only an explicit `false` as disabled.
    public var isActive: Bool
    public var updatedAt: String?

    public init(
        id: String, section: String, key: String, summary: String = "", details: [String] = [],
        isActive: Bool = true, updatedAt: String? = nil
    ) {
        self.id = id
        self.section = section
        self.key = key
        self.summary = summary
        self.details = details
        self.isActive = isActive
        self.updatedAt = updatedAt
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: AnyCodingKey.self)
        id = try c.decode(String.self, forKey: "id")
        section = c.lenient(String.self, forKey: "section") ?? MemorySection.topic.rawValue
        key = c.lenient(String.self, forKey: "key") ?? ""
        summary = c.lenient(String.self, forKey: "summary") ?? ""
        details = c.lenient([String].self, forKey: "details") ?? []
        isActive = c.lenient(Bool.self, forKey: "isActive") ?? true
        updatedAt = c.lenient(String.self, forKey: "updatedAt")
    }
}

/// The body of `POST /api/v1/memory` as the desktop's Memory page sends it (`source: "explicit"`).
public struct MemoryCreateBody: Encodable, Equatable, Sendable {
    public let section: String
    public let key: String
    public let summary: String
    public let details: [String]
    public let source = "explicit"

    public init(section: String, key: String, summary: String, details: [String]) {
        self.section = section
        self.key = key
        self.summary = summary
        self.details = details
    }

    private enum CodingKeys: String, CodingKey { case section, key, summary, details, source }
}

/// The body of `PATCH /api/v1/memory/:id`: only the fields being changed; the server sets exactly those.
public struct MemoryPatchBody: Encodable, Equatable, Sendable {
    public var key: String?
    public var summary: String?
    public var details: [String]?
    public var isActive: Bool?

    public init(key: String? = nil, summary: String? = nil, details: [String]? = nil, isActive: Bool? = nil) {
        self.key = key
        self.summary = summary
        self.details = details
        self.isActive = isActive
    }

    public var isEmpty: Bool { key == nil && summary == nil && details == nil && isActive == nil }
}
