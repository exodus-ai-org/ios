import Foundation
import Models
import Testing

@testable import ChatFeature

@Suite("A question's pictures")
struct UserImagesTests {
    private func message(_ content: String) -> ChatMessage {
        try! JSONDecoder().decode(
            ChatMessage.self, from: Data(#"{"id":"u1","role":"user","content":\#(content)}"#.utf8))
    }

    @Test("the image blocks of a user message, in order, as data URLs; text and a plain string have none")
    func dataURLs() {
        let mixed = message(
            #"[{"type":"text","text":"which?"},{"type":"image","mimeType":"image/png","data":"data:image/png;base64,AAA"},{"type":"image","mimeType":"image/jpeg","data":"BBB"}]"#)
        #expect(UserImages.dataURLs(of: mixed) == ["data:image/png;base64,AAA", "data:image/jpeg;base64,BBB"])
        #expect(UserImages.dataURLs(of: message(#""just text""#)).isEmpty)
    }

    @Test("a picture is decoded from its data URL")
    func decodes() async throws {
        let url = MessageGalleryFixtures.picture(.systemTeal, width: 40, height: 20)
        let image = try #require(await ComputerUseFrameStore.decodeScreenshot(url, maxPixelWidth: UserImages.maxPixelWidth))
        #expect(image.size.width * image.scale == 40)
    }
}
