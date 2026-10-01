import Foundation
import Models
import Testing
import WidgetKitShared

// The app target ships as `Exodus`, so that — not `App` — is the module name to import.
@testable import Exodus

@MainActor
@Suite("WidgetSnapshotWriter")
struct WidgetSnapshotWriterTests {
    private let dir = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString, directoryHint: .isDirectory)

    @Test("the widgets reload only when what they draw changed, and unpairing empties them")
    func writer() throws {
        var reloads = 0
        let writer = WidgetSnapshotWriter(store: SnapshotStore(directory: dir), reload: { reloads += 1 })
        let chats = [ChatSummary(id: "a", title: "Plan", createdAt: "2026-10-01T10:00:00Z")]
        writer.recentsChanged(chats)
        writer.recentsChanged(chats)
        #expect(reloads == 1)
        writer.computerChanged()
        #expect(reloads == 2)
        #expect(SnapshotStore(directory: dir).load().recentChats.isEmpty)
    }

    @Test("a glance is written next to the recents, and its going away is a change too")
    func health() throws {
        var reloads = 0
        let writer = WidgetSnapshotWriter(store: SnapshotStore(directory: dir), reload: { reloads += 1 })
        let glance = HealthGlance(
            day: "2026-10-01", sleepMinutes: 352, steps: 1251, stepGoal: 8000, headline: "Take it easy",
            suggestion: nil, mood: .sleepy)
        writer.healthChanged(glance)
        writer.healthChanged(glance)
        #expect(reloads == 1)
        #expect(SnapshotStore(directory: dir).load().health == glance)
        writer.healthChanged(nil)
        #expect(reloads == 2)
        #expect(SnapshotStore(directory: dir).load().health == nil)
    }

    @Test("a new writer starts from what is on disk, so a relaunch with the same chats reloads nothing")
    func resumes() throws {
        var reloads = 0
        let chats = [ChatSummary(id: "a", title: "Plan", createdAt: "2026-10-01T10:00:00Z")]
        WidgetSnapshotWriter(store: SnapshotStore(directory: dir), reload: {}).recentsChanged(chats)
        let relaunched = WidgetSnapshotWriter(store: SnapshotStore(directory: dir), reload: { reloads += 1 })
        relaunched.recentsChanged(chats)
        #expect(reloads == 0)
    }
}
