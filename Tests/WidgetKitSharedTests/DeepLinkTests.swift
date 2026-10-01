import Foundation
import Testing

@testable import WidgetKitShared

@Suite("DeepLink: the widgets' exodus:// links")
struct DeepLinkTests {
    @Test("every link reads back as itself", arguments: [
        DeepLink.newChat(prompt: nil), .newChat(prompt: "Plan my day"), .chat(id: "3f2a-9c"), .health(ask: nil),
        .health(ask: "Why do I feel tired today?"),
        .newChat(prompt: "a & b #c ?d = e / 100% 今天睡得怎么样？ 😴 \n second line"), .newChat(prompt: "1+1=2 %26"),
        .health(ask: "1+1=2 %26"), .chat(id: "new_chat-2"),
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

    @Test("a prompt of exactly 500 characters is a link")
    func longestPrompt() {
        let prompt = String(repeating: "睡", count: DeepLink.maxPrompt)
        #expect(DeepLink(url: DeepLink.newChat(prompt: prompt).url) == .newChat(prompt: prompt))
        #expect(DeepLink(url: DeepLink.health(ask: prompt).url) == .health(ask: prompt))
    }

    /// The id goes into `/api/v1/chat/<id>/…`: a dot segment or a slash would reach another endpoint.
    @Test("a chat id is 1–64 letters, digits, `-` or `_`", arguments: [
        "exodus://chat/..", "exodus://chat/.", "exodus://chat/a%2Fb", "exodus://chat/a%2F..", "exodus://chat/%20",
        "exodus://chat/a.b", "exodus://chat/a%3Fb", "exodus://chat/%C3%BC",
        "exodus://chat/" + String(repeating: "a", count: 65),
    ])
    func rejectsIds(string: String) throws {
        #expect(DeepLink(url: try #require(URL(string: string))) == nil)
    }

    @Test("ids at the edges")
    func acceptsIds() throws {
        let longest = String(repeating: "a", count: 64)
        #expect(DeepLink(url: try #require(URL(string: "exodus://chat/" + longest))) == .chat(id: longest))
        #expect(DeepLink(url: try #require(URL(string: "exodus://chat/0b6f1f7e-2c1d-4a53-9a55-1f0c3e0e9a11")))
            == .chat(id: "0b6f1f7e-2c1d-4a53-9a55-1f0c3e0e9a11"))
        // `new` is the new-chat link, never a chat called "new".
        #expect(DeepLink(url: try #require(URL(string: "exodus://chat/new"))) == .newChat(prompt: nil))
        #expect(!DeepLink.isAcceptableChatId(""))
        #expect(!DeepLink.isAcceptableChatId("a/b"))
        #expect(!DeepLink.isAcceptableChatId(".."))
    }
}
