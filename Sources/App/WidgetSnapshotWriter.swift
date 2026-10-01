import Foundation
import Models
import WidgetKit
import WidgetKitShared

/// Keeps the widgets' snapshot in step with the app: recents from the chat list, today's glance from Health, nothing
/// once the computer goes. Reloads the widgets only when what they draw changed.
@MainActor
final class WidgetSnapshotWriter {
    private let store: SnapshotStore?
    private let reload: () -> Void
    private let now: () -> Date
    private var current: WidgetSnapshot

    init(
        store: SnapshotStore? = .appGroup(), reload: @escaping () -> Void = { WidgetCenter.shared.reloadAllTimelines() },
        now: @escaping () -> Date = Date.init
    ) {
        self.store = store
        self.reload = reload
        self.now = now
        self.current = store?.load() ?? .empty
    }

    func recentsChanged(_ chats: [ChatSummary]) {
        let recents = WidgetSnapshotRules.recents(from: chats.map { ($0.id, $0.title, $0.createdAt) })
        write(current.updating(recents: recents, at: now()))
    }

    func healthChanged(_ glance: HealthGlance?) { write(current.updating(health: glance, at: now())) }

    func computerChanged() { write(current.cleared(at: now())) }

    private func write(_ next: WidgetSnapshot) {
        // `updatedAt` always moves; what the widgets draw is the rest.
        guard next.recentChats != current.recentChats || next.health != current.health else { return }
        do {
            try store?.save(next)
        } catch {
            // The widgets keep the last good snapshot; the next change tries again.
            return
        }
        current = next
        reload()
    }
}
