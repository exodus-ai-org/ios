import Models
import SwiftUI

/// The run's foot, drawn from `RunFoot` only: `media` under the answer (search images and videos), `memory` under the
/// action bar (the used-memories line, then the memory strip), as on the desktop.
struct RunFootView: View {
    enum Section {
        case media, memory
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
        case .memory:
            if let memoryFoot {
                let run = memoryFoot.run(runId)
                UsedMemoriesLine(run: run, store: memoryFoot)
                if let changes = RunMemoryChanges(foot.memoryUpdates) {
                    MemoryChangeStrip(runId: runId, changes: changes, active: isStreaming, run: run, store: memoryFoot)
                }
            }
        }
    }
}
