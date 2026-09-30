import Models
import SwiftUI

/// The run's foot, drawn from `RunFoot` only: `media` under the answer (search images and videos); the line saying
/// which memories the run read and the strip of what it changed, over the action row (`TurnFoot`).
struct RunFootView: View {
    enum Section {
        case media, usedMemories, memoryChanges
    }

    let foot: RunFoot
    let section: Section
    var runId = ""
    /// Whether the run still streams.
    var isStreaming = false
    @Environment(\.memoryFoot) private var memoryFoot

    var body: some View {
        switch section {
        case .media:
            if !foot.gallery.isEmpty {
                SearchMediaSection(gallery: foot.gallery)
            }
        case .usedMemories:
            if let memoryFoot {
                UsedMemoriesLine(run: memoryFoot.run(runId), store: memoryFoot)
            }
        case .memoryChanges:
            if let memoryFoot, let changes = RunMemoryChanges(foot.memoryUpdates) {
                MemoryChangeStrip(
                    runId: runId, changes: changes, active: isStreaming, run: memoryFoot.run(runId), store: memoryFoot
                )
                .padding(.top, TurnFootMetrics.blockGap)
                .padding(.bottom, TurnFootMetrics.cardBottom)
            }
        }
    }
}
