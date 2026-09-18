public struct ChatSummary: Codable, Equatable, Sendable, Identifiable {
    public var id: String
    public var title: String
    public var createdAt: String
    public var favorite: Bool?
    public var projectId: String?

    public init(id: String, title: String, createdAt: String, favorite: Bool? = nil, projectId: String? = nil) {
        self.id = id
        self.title = title
        self.createdAt = createdAt
        self.favorite = favorite
        self.projectId = projectId
    }
}
