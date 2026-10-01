import Foundation
import Testing

@testable import WidgetKitShared

@Suite("WidgetSnapshot and its store")
struct WidgetSnapshotTests {
    private let now = Date(timeIntervalSince1970: 1_790_000_000)

    private func store() throws -> SnapshotStore {
        let dir = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString, directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return SnapshotStore(directory: dir)
    }

    private let glance = HealthGlance(
        day: "2026-10-01", sleepMinutes: 352, steps: 1251, stepGoal: 8000, headline: "Take it easy",
        suggestion: "Why do I feel tired today?", mood: .sleepy)

    @Test("a snapshot written is the snapshot read")
    func roundTrip() throws {
        let store = try store()
        let snapshot = WidgetSnapshot.empty
            .updating(recents: [RecentChat(id: "a", title: "Swift 6", updatedAt: now)], at: now)
            .updating(health: glance, at: now)
        try store.save(snapshot)
        #expect(store.load() == snapshot)
    }

    @Test("no file, a half-written file or a newer version reads as empty")
    func tolerant() throws {
        let store = try store()
        #expect(store.load() == .empty)
        try Data("{\"version\":1,\"updatedAt\":".utf8).write(to: store.fileURL)
        #expect(store.load() == .empty)
        try Data("{\"version\":99,\"updatedAt\":0,\"recentChats\":[]}".utf8).write(to: store.fileURL)
        #expect(store.load() == .empty)
    }

    @Test("recents keep the newest three; health can be set and taken away; clearing forgets both")
    func updates() {
        let chats = (0..<5).map { RecentChat(id: "\($0)", title: "t\($0)", updatedAt: now.addingTimeInterval(Double($0))) }
        let snapshot = WidgetSnapshot.empty.updating(recents: chats, at: now).updating(health: glance, at: now)
        #expect(snapshot.recentChats.map(\.id) == ["4", "3", "2"])
        #expect(snapshot.updating(health: nil, at: now).health == nil)
        let cleared = snapshot.cleared(at: now)
        #expect(cleared.recentChats.isEmpty && cleared.health == nil)
    }

    @Test("recents of the same moment keep one order: newest first, then by id")
    func tieBreak() {
        let chats = [
            RecentChat(id: "c", title: "C", updatedAt: now), RecentChat(id: "a", title: "A", updatedAt: now),
            RecentChat(id: "b", title: "B", updatedAt: now), RecentChat(id: "d", title: "D", updatedAt: now.addingTimeInterval(1)),
        ]
        let ids = WidgetSnapshot.empty.updating(recents: chats, at: now).recentChats.map(\.id)
        #expect(ids == ["d", "a", "b"])
        #expect(WidgetSnapshot.empty.updating(recents: chats.reversed(), at: now).recentChats.map(\.id) == ids)
    }

    @Test("a chat listed twice is one recent: its newest entry")
    func duplicates() {
        let chats = [
            RecentChat(id: "a", title: "Old", updatedAt: now), RecentChat(id: "b", title: "B", updatedAt: now),
            RecentChat(id: "a", title: "New", updatedAt: now.addingTimeInterval(5)),
        ]
        let recents = WidgetSnapshot.empty.updating(recents: chats, at: now).recentChats
        #expect(recents.map(\.id) == ["a", "b"])
        #expect(recents.first?.title == "New")
    }

    @Test("a title is trimmed and an empty one is skipped")
    func titles() {
        let chats = [
            RecentChat(id: "a", title: "  Plan  ", updatedAt: now), RecentChat(id: "b", title: " ", updatedAt: now),
        ]
        #expect(WidgetSnapshot.empty.updating(recents: chats, at: now).recentChats.map(\.title) == ["Plan"])
    }
}
