import Models
import Testing

@testable import ChatFeature

@Suite("Sidebar: Copy Conversation ID")
struct ConversationIDTests {
    @Test("what is copied is the conversation's id and nothing else: no title, no address, no space around it")
    func copyText() {
        let chat = ChatSummary(
            id: "5b30d978-ebe8-4da6-9e73-02c6fc42b771", title: "Trip to Kyoto", createdAt: "2026-09-29T08:00:00Z")
        #expect(ConversationID.copyText(for: chat) == "5b30d978-ebe8-4da6-9e73-02c6fc42b771")
        let padded = ChatSummary(id: " abc\n", title: "t", createdAt: "")
        #expect(ConversationID.copyText(for: padded) == "abc")
    }
}
