import Foundation
import Testing

@testable import WidgetKitShared

@MainActor
@Suite("PendingLink: a link waits behind the gates")
struct PendingLinkTests {
    @Test("the latest valid link is kept until taken, once; an invalid one changes nothing")
    func waits() throws {
        let pending = PendingLink()
        pending.offer(try #require(URL(string: "exodus://chat/new")))
        pending.offer(try #require(URL(string: "exodus://health")))
        pending.offer(try #require(URL(string: "exodus://nowhere")))
        #expect(pending.take() == .health(ask: nil))
        #expect(pending.take() == nil)
    }
}
