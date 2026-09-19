/// One row of `GET /api/v1/chat/search`: a message database row plus its chat's `title`. Only the
/// columns the app uses are decoded; every other column of the row is ignored. `searchText` is the
/// indexable text of a user or assistant message (text blocks only), and may be null.
public struct ChatSearchHit: Decodable, Equatable, Sendable, Identifiable {
    public var id: String
    public var chatId: String
    public var role: String?
    public var searchText: String?
    public var title: String
    public var createdAt: String?

    public init(
        id: String, chatId: String, role: String? = nil, searchText: String? = nil, title: String,
        createdAt: String? = nil
    ) {
        self.id = id
        self.chatId = chatId
        self.role = role
        self.searchText = searchText
        self.title = title
        self.createdAt = createdAt
    }

    private enum CodingKeys: String, CodingKey {
        case id, chatId, role, searchText, title, createdAt
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(String.self, forKey: .id)
        chatId = try container.decode(String.self, forKey: .chatId)
        title = try container.decode(String.self, forKey: .title)
        role = try container.decodeIfPresent(String.self, forKey: .role)
        searchText = try container.decodeIfPresent(String.self, forKey: .searchText)
        createdAt = try container.decodeIfPresent(String.self, forKey: .createdAt)
    }
}
