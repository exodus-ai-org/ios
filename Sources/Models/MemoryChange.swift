import Foundation

/// A memory entry's fields at one moment (`MemorySnapshot`, packages/shared/src/types/memory.ts).
public struct MemorySnapshot: JSONValueDecodable {
    /// Raw, so a section this app does not know still decodes.
    public let section: String
    public let key: String
    public let summary: String
    public let details: [String]
    public let isActive: Bool

    public init(section: String, key: String, summary: String, details: [String], isActive: Bool = true) {
        self.section = section
        self.key = key
        self.summary = summary
        self.details = details
        self.isActive = isActive
    }

    public init?(json: JSONValue) {
        guard let fields = JSONFields(json), let key = fields.string("key") else { return nil }
        self.init(
            section: fields.string("section") ?? MemorySection.topic.rawValue, key: key,
            summary: fields.string("summary") ?? "", details: fields.strings("details"),
            isActive: fields.bool("isActive") ?? true)
    }

    /// An entry as it reads now, in the shape a change's `after` is compared with (the desktop's `snapshotOf`).
    public init(entry: MemoryEntry) {
        self.init(
            section: entry.section, key: entry.key, summary: entry.summary, details: entry.details,
            isActive: entry.isActive)
    }
}

extension MemorySnapshot: Encodable {
    private enum CodingKeys: String, CodingKey { case section, key, summary, details, isActive }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(section, forKey: .section)
        try container.encode(key, forKey: .key)
        try container.encode(summary, forKey: .summary)
        try container.encode(details, forKey: .details)
        try container.encode(isActive, forKey: .isActive)
    }
}

/// One create / update / delete `update_memory` applied: `before` is nil for a create, `after` for a delete.
public struct MemoryChange: JSONValueDecodable, Identifiable {
    public enum Operation: String, Sendable {
        case create, update, delete
    }

    public let op: Operation
    public let id: String
    public let before: MemorySnapshot?
    public let after: MemorySnapshot?

    /// The entry's title as the change left it (or as it was, for a delete).
    public var key: String { after?.key ?? before?.key ?? "" }

    public init?(json: JSONValue) {
        guard let fields = JSONFields(json), let op = fields.string("op").flatMap(Operation.init(rawValue:)),
            let id = fields.nonEmpty("id")
        else { return nil }
        self.op = op
        self.id = id
        before = fields.decoded("before")
        after = fields.decoded("after")
    }

    public init(op: Operation, id: String, before: MemorySnapshot?, after: MemorySnapshot?) {
        self.op = op
        self.id = id
        self.before = before
        self.after = after
    }
}

extension MemoryChange: Encodable {
    private enum CodingKeys: String, CodingKey { case op, id, before, after }

    // `before`/`after` are sent as an explicit null: the undo route requires the key (`z.null()`).
    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(op.rawValue, forKey: .op)
        try container.encode(id, forKey: .id)
        try container.encode(before, forKey: .before)
        try container.encode(after, forKey: .after)
    }
}

/// The body of `POST /api/v1/memory/undo`: a run's changes, as `update_memory` reported them.
public struct MemoryUndoBody: Encodable, Sendable {
    public let changes: [MemoryChange]

    public init(changes: [MemoryChange]) {
        self.changes = changes
    }
}

/// What `POST /api/v1/memory/undo` did: the ids it reverted, and those edited since and kept.
public struct MemoryUndoResult: Decodable, Equatable, Sendable {
    public let undone: [String]
    public let skipped: [String]

    public init(undone: [String], skipped: [String]) {
        self.undone = undone
        self.skipped = skipped
    }
}

/// update_memory's details `{changes}`.
public struct MemoryUpdateResult: JSONValueDecodable {
    public let changes: [MemoryChange]

    public init?(json: JSONValue) {
        guard let fields = JSONFields(json), fields.array("changes") != nil else { return nil }
        changes = fields.list("changes")
    }
}

/// A memory entry as a run used it, with its own copy of the title and section: the SSE `memories_used` event and
/// `GET /api/v1/memory/usage`.
public struct UsedMemory: JSONValueDecodable, Identifiable {
    public let id: String
    public let key: String
    public let section: String

    public init(id: String, key: String, section: String) {
        self.id = id
        self.key = key
        self.section = section
    }

    public init?(json: JSONValue) {
        guard let fields = JSONFields(json), let id = fields.nonEmpty("id") else { return nil }
        self.init(
            id: id, key: fields.string("key") ?? "", section: fields.string("section") ?? MemorySection.topic.rawValue)
    }
}
