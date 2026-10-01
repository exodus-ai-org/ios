import Foundation

/// `create_artifact`'s result (exodus `calling-tools/create-artifact.ts`): a single-file React component the desktop
/// renders in its artifact sandbox, with the chat and id it is saved under there.
public struct ArtifactResult: JSONValueDecodable {
    public let artifactId: String
    public let chatId: String?
    public let title: String
    /// Empty when the row came without it; the desktop's copy on disk (`GET /api/v1/artifacts/:chatId/:id`) has it.
    public let code: String

    public init(artifactId: String, chatId: String?, title: String, code: String) {
        self.artifactId = artifactId
        self.chatId = chatId
        self.title = title
        self.code = code
    }

    public init?(json: JSONValue) {
        guard let fields = JSONFields(json), fields.string("type") == "artifact",
            let artifactId = fields.nonEmpty("artifactId")
        else { return nil }
        self.init(
            artifactId: artifactId, chatId: fields.nonEmpty("chatId"), title: fields.string("title") ?? "",
            code: fields.string("code") ?? "")
    }
}
