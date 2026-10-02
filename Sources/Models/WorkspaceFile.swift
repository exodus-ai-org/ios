import Foundation

/// A file the chat's tools wrote into its workspace, as `GET /api/v1/workspace/:chatId/file?path=…` serves it (exodus
/// `routes/workspace.ts`): text only, at most 1 MB; a larger or binary file is refused with 413 / 415.
public struct WorkspaceFile: Decodable, Equatable, Sendable {
    public enum Kind: String, Decodable, Sendable {
        case markdown
        case text

        public init(from decoder: Decoder) throws {
            // Anything the phone does not know yet is shown as plain text.
            self = Kind(rawValue: try decoder.singleValueContainer().decode(String.self)) ?? .text
        }
    }

    /// The real path on the computer.
    public let path: String
    public let name: String
    public let size: Int
    /// Milliseconds since the epoch.
    public let modifiedAt: Double?
    public let kind: Kind
    public let content: String

    public init(path: String, name: String, size: Int, modifiedAt: Double? = nil, kind: Kind, content: String) {
        self.path = path
        self.name = name
        self.size = size
        self.modifiedAt = modifiedAt
        self.kind = kind
        self.content = content
    }
}
