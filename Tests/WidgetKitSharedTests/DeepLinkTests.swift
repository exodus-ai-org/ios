import Foundation
import Testing

@testable import WidgetKitShared

@Suite("DeepLink: the widgets' exodus:// links")
struct DeepLinkTests {
    @Test("every link reads back as itself", arguments: [
        DeepLink.newChat(prompt: nil), .newChat(prompt: "Plan my day"), .chat(id: "3f2a-9c"), .health(ask: nil),
        .health(ask: "Why do I feel tired today?"),
        .newChat(prompt: "a & b #c ?d = e / 100% 今天睡得怎么样？ 😴 \n second line"),
    ])
    func roundTrip(link: DeepLink) throws {
        #expect(DeepLink(url: link.url) == link)
    }

    @Test("the links are the documented ones")
    func shapes() {
        #expect(DeepLink.newChat(prompt: nil).url.absoluteString == "exodus://chat/new")
        #expect(DeepLink.chat(id: "abc").url.absoluteString == "exodus://chat/abc")
        #expect(DeepLink.health(ask: nil).url.absoluteString == "exodus://health")
    }

    @Test("anything else is not a link", arguments: [
        "https://chat/new", "exodus://", "exodus://chat", "exodus://chat/", "exodus://settings",
        "exodus://chat/a/b", "exodus://health/x",
    ])
    func rejects(string: String) throws {
        #expect(DeepLink(url: try #require(URL(string: string))) == nil)
    }

    @Test("an empty prompt is no prompt; one over 500 characters is not a link")
    func prompts() throws {
        #expect(DeepLink(url: try #require(URL(string: "exodus://chat/new?prompt="))) == .newChat(prompt: nil))
        let long = DeepLink.newChat(prompt: String(repeating: "a", count: 501)).url
        #expect(DeepLink(url: long) == nil)
    }
}
