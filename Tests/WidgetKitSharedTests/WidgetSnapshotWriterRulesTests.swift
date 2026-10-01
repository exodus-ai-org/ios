import Foundation
import Testing

@testable import WidgetKitShared

@Suite("WidgetSnapshotRules: the chat list as recents")
struct WidgetSnapshotWriterRulesTests {
    @Test("dates are read as the server writes them; one it cannot read sorts last")
    func recents() {
        let recents = WidgetSnapshotRules.recents(from: [
            ("a", "Old", "2026-09-01T10:00:00.000Z"), ("b", "New", "2026-10-01T10:00:00Z"), ("c", "Odd", "yesterday"),
        ])
        let snapshot = WidgetSnapshot.empty.updating(recents: recents, at: Date())
        #expect(snapshot.recentChats.map(\.id) == ["b", "a", "c"])
    }
}
