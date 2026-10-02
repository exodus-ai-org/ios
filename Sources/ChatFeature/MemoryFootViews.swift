import Models
import SwiftUI

/// The foot of a run that changed memory through `update_memory` (the desktop's `MemoryChangeStrip`): "Updating
/// memory…" while the call is out, then what it changed with Undo, opening in place to each change. Drawn from the
/// run's own messages and its own `RunMemoryFoot`; the memory list is read only to tell a settled run whose changes
/// were undone or edited since.
struct MemoryChangeStrip: View {
    let runId: String
    let changes: RunMemoryChanges
    /// Whether the run still streams.
    let active: Bool
    let run: RunMemoryFoot
    let store: MemoryFootStore
    /// Opened to its changes at first (the prototypes page).
    var startsOpen = false
    @State private var opened: Bool?
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    private var open: Bool { opened ?? startsOpen }
    private var stopped: Bool { changes.running && !active }

    var body: some View {
        let display = MemoryStripRules.display(
            changes, active: active, undo: run.undo, live: run.live, entries: needsList ? store.entries : nil)
        Group {
            if let display {
                strip(display)
            }
        }
        .onChange(of: changes.running && active, initial: true) { _, running in
            if running { run.live = true }
        }
        .task(id: stopped) {
            // Stop cut the call off: the client never sees its end, but it may have finished on the computer.
            guard stopped, !run.rereadAfterStop else { return }
            run.rereadAfterStop = true
            await store.refreshEntries()
        }
        .task(id: needsList) {
            if needsList { await store.loadEntriesIfNeeded() }
        }
    }

    /// Only a settled run this client did not see change memory, and not undone here, compares with the list.
    private var needsList: Bool {
        !run.live && run.undo == .idle && !changes.changes.isEmpty && !(changes.running && active)
    }

    @ViewBuilder
    private func strip(_ display: MemoryStripDisplay) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            switch display {
            case .running:
                row(icon: AnyView(ProgressView().controlSize(.mini))) {
                    Text(verbatim: MemoryStripRules.updatingText)
                        .frame(maxWidth: .infinity, minHeight: 32, alignment: .leading)
                }
                .accessibilityElement(children: .combine)
            case .failed:
                row(icon: AnyView(Image(systemName: "exclamationmark.triangle"))) {
                    Text(verbatim: MemoryStripRules.failedText)
                        .frame(maxWidth: .infinity, minHeight: 32, alignment: .leading)
                }
                .accessibilityElement(children: .combine)
            case .changes(let label, let warning, let undoable):
                changesStrip(label: label, warning: warning, undoable: undoable)
            }
        }
        .font(.footnote)
        .foregroundStyle(display == .failed ? AnyShapeStyle(.red) : AnyShapeStyle(.secondary))
        .padding(.horizontal, 12)
        .padding(.vertical, 4)
        .background(
            display == .failed ? AnyShapeStyle(Color.red.opacity(0.08)) : AnyShapeStyle(.fill.quaternary),
            in: .rect(cornerRadius: 12))
    }

    private func row<Content: View>(icon: AnyView, @ViewBuilder content: () -> Content) -> some View {
        HStack(spacing: 8) {
            icon.frame(minWidth: 16).accessibilityHidden(true)
            content()
        }
    }

    @ViewBuilder
    private func changesStrip(label: MemoryStripDisplay.Label, warning: Bool, undoable: Bool) -> some View {
        let text = MemoryStripRules.text(label)
        let toggle = Button {
            withAnimation(reduceMotion ? nil : .snappy(duration: 0.2)) { opened = !open }
        } label: {
            HStack(spacing: 4) {
                Text(verbatim: text).lineLimit(dynamicTypeSize.isAccessibilitySize ? nil : 2)
                Image(systemName: "chevron.down")
                    .imageScale(.small)
                    .rotationEffect(.degrees(open ? 180 : 0))
                    .accessibilityHidden(true)
            }
            .frame(maxWidth: .infinity, minHeight: 32, alignment: .leading)
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(Text(verbatim: text))
        .accessibilityValue(open ? Text("ios:chat.message.timeline.expanded") : Text("ios:chat.message.timeline.collapsed"))

        let icon = AnyView(Image(systemName: warning ? "exclamationmark.triangle" : "checkmark")) // l10n:ignore: SF Symbol names
        if dynamicTypeSize.isAccessibilitySize {
            VStack(alignment: .leading, spacing: 4) {
                row(icon: icon) { toggle }
                if undoable { undoButton }
            }
        } else {
            row(icon: icon) {
                toggle
                if undoable { undoButton }
            }
        }
        if run.undoFailed {
            Text("chat:memoryStrip.undoFailed")
                .font(.caption)
                .foregroundStyle(.red)
                .padding(.leading, 24)
                .padding(.bottom, 4)
        }
        if open {
            VStack(alignment: .leading, spacing: 10) {
                // One entry can change twice in a run: the offset keeps the rows apart.
                ForEach(Array(changes.changes.enumerated()), id: \.offset) { _, change in
                    MemoryChangeRow(change: change)
                }
            }
            .padding(.leading, 24)
            .padding(.top, 4)
            .padding(.bottom, 6)
            .transition(.opacity)
        }
    }

    private var undoButton: some View {
        Button {
            Task { await store.undo(runId: runId, changes: changes.changes) }
        } label: {
            Text("chat:memoryStrip.undo").fontWeight(.medium)
        }
        .buttonStyle(.bordered)
        .buttonBorderShape(.capsule)
        .controlSize(.small)
        .disabled(run.undoing)
    }
}

/// One change: a create or a delete as the entry read, an update as what differs, before → after.
struct MemoryChangeRow: View {
    let change: MemoryChange

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack(spacing: 6) {
                Text(verbatim: change.key).fontWeight(.medium).foregroundStyle(.primary)
                switch change.op {
                case .create: badge(Text("chat:memoryStrip.new"))
                case .delete: badge(Text("chat:memoryStrip.deleted"))
                case .update: EmptyView()
                }
            }
            .accessibilityElement(children: .combine)
            switch change.op {
            case .create:
                if let after = change.after { MemorySnapshotLines(snapshot: after, removed: false) }
            case .delete:
                if let before = change.before { MemorySnapshotLines(snapshot: before, removed: true) }
            case .update:
                if let before = change.before, let after = change.after { diff(before, after) }
            }
        }
    }

    private func badge(_ text: Text) -> some View {
        text
            .font(.caption2)
            .padding(.horizontal, 6)
            .padding(.vertical, 1)
            .overlay(Capsule().strokeBorder(Color(.separator)))
    }

    @ViewBuilder
    private func diff(_ before: MemorySnapshot, _ after: MemorySnapshot) -> some View {
        if before.key != after.key { fieldChange(before.key, after.key) }
        if before.summary != after.summary { fieldChange(before.summary, after.summary) }
        ForEach(before.details.filter { !after.details.contains($0) }, id: \.self) { detail in
            Text(verbatim: "− \(detail)")
                .strikethrough()
                .foregroundStyle(.tertiary)
                .accessibilityLabel(Text(verbatim: MemoryChangeText.removed(detail)))
        }
        ForEach(after.details.filter { !before.details.contains($0) }, id: \.self) { detail in
            Text(verbatim: "+ \(detail)")
                .foregroundStyle(.primary)
                .accessibilityLabel(Text(verbatim: MemoryChangeText.added(detail)))
        }
    }

    private func fieldChange(_ before: String, _ after: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(verbatim: before).strikethrough().foregroundStyle(.tertiary)
            HStack(alignment: .firstTextBaseline, spacing: 4) {
                Image(systemName: "arrow.turn.down.right").imageScale(.small)
                Text(verbatim: after).foregroundStyle(.primary)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(verbatim: MemoryChangeText.changed(from: before, to: after)))
    }
}

/// An entry's summary and bullets; a deleted one struck through.
struct MemorySnapshotLines: View {
    let snapshot: MemorySnapshot
    let removed: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            if !snapshot.summary.isEmpty { Text(verbatim: snapshot.summary) }
            ForEach(snapshot.details, id: \.self) { Text(verbatim: "• \($0)") }
        }
        .strikethrough(removed)
        .opacity(removed ? 0.7 : 1)
        .accessibilityElement(children: .combine)
    }
}

/// What VoiceOver says for a struck-through or added line, which it would otherwise read like any other.
enum MemoryChangeText {
    static func changed(from before: String, to after: String) -> String {
        String(
            localized: "ios:chat.card.memory.changed", defaultValue: "Was \(before). Now \(after)",
            comment: "VoiceOver, one field of a memory entry a reply changed. The first %@ is the old text, the second the new.")
    }

    static func removed(_ detail: String) -> String {
        String(
            localized: "ios:chat.card.memory.removed", defaultValue: "Removed: \(detail)",
            comment: "VoiceOver, a bullet a reply removed from a memory entry. %@ is the bullet.")
    }

    static func added(_ detail: String) -> String {
        String(
            localized: "ios:chat.card.memory.added", defaultValue: "Added: \(detail)",
            comment: "VoiceOver, a bullet a reply added to a memory entry. %@ is the bullet.")
    }
}

/// "Used 2 memories · Work setup and Classical Music" at the foot of a run (the desktop's `UsedMemories`), opening a
/// sheet with each entry as it reads now. Reads only its own run's `used`, so another run streaming or getting its own
/// line does not reach it.
struct UsedMemoriesLine: View {
    let run: RunMemoryFoot
    let store: MemoryFootStore
    @State private var open = false
    /// What the sheet asked for, done once it has gone: the composer cannot take focus under a sheet.
    @State private var pending: UsedMemoriesSheet.Action?
    /// Taps on an entry's "Wrong?": a light tap answers each, as the sheet goes.
    @State private var fixes = 0
    @Environment(\.openMemorySettings) private var openMemorySettings
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    var body: some View {
        if !run.used.isEmpty {
            let label = UsedMemoriesText.label(run.used)
            Button {
                pending = nil
                open = true
            } label: {
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    Image(systemName: "brain").accessibilityHidden(true)
                    Text(verbatim: label).lineLimit(dynamicTypeSize.isAccessibilitySize ? 3 : 1)
                }
                .font(.footnote)
                .foregroundStyle(.secondary)
                // The line takes the room of its text; its target reaches beyond it.
                .footRowTarget()
            }
            .buttonStyle(.plain)
            .padding(.top, TurnFootMetrics.rowTop)
            .padding(.bottom, TurnFootMetrics.rowBottom)
            .accessibilityLabel(Text(verbatim: label))
            .accessibilityAddTraits(.isButton)
            .sheet(isPresented: $open, onDismiss: perform) {
                UsedMemoriesSheet(used: run.used, store: store, opensSettings: openMemorySettings != nil) { action in
                    if case .wrong = action { fixes += 1 }
                    pending = action
                    open = false
                }
            }
            .sensoryFeedback(.impact(weight: .light), trigger: fixes)
        }
    }

    private func perform() {
        guard let action = pending else { return }
        pending = nil
        switch action {
        case .wrong(let key): store.onWrong(UsedMemoriesText.prefill(key: key))
        case .openSettings: openMemorySettings?()
        }
    }
}

/// The entries behind the logged ones, as they read now: a deleted entry keeps its logged title, greyed. Fixing a
/// wrong one is the sheet's point: each entry carries a tinted "Wrong?" beside its title, and the foot says in a
/// sentence what it does; Settings is the secondary way, a link under that.
struct UsedMemoriesSheet: View {
    enum Action: Equatable {
        case wrong(key: String)
        case openSettings
    }

    let used: [UsedMemory]
    let store: MemoryFootStore
    let opensSettings: Bool
    let act: (Action) -> Void
    @Environment(\.dismiss) private var dismiss
    /// The chat's: a screenshot of the sheet is "Memories used · <chat>".
    @Environment(\.screenTitle) private var enclosingTitle

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    Text("chat:usedMemories.intro")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                    ForEach(used) { memory in
                        UsedMemoryRow(memory: memory, entries: store.entries) { act(.wrong(key: $0)) }
                    }
                    VStack(alignment: .leading, spacing: 2) {
                        Text("ios:chat.usedMemories.fixHint")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                        if opensSettings {
                            Button {
                                act(.openSettings)
                            } label: {
                                Text("chat:usedMemories.openSettings").frame(minHeight: 32)
                            }
                            .font(.footnote.weight(.medium))
                            .buttonStyle(.borderless)
                        }
                    }
                    .padding(.top, 4)
                }
                .padding(16)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .navigationTitle(Text("ios:chat.card.usedMemories.title"))
            .navigationBarTitleDisplayMode(.inline)
            .screenTitle(
                ScreenTitles.join(
                    String(
                        localized: "ios:chat.card.usedMemories.title", defaultValue: "Memories used",
                        comment: "Title of the sheet listing the memory entries a reply read."),
                    enclosingTitle))
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("common:action.close", role: .close) { dismiss() }
                }
            }
        }
        .presentationDetents([.medium, .large])
        .task { await store.refreshEntries() }
    }
}

/// What one row of the sheet shows: the entry's title as it reads now, its current text, and whether it can still be
/// fixed — a deleted entry cannot.
struct UsedMemoryRowState {
    let key: String
    let current: MemoryEntry?
    let deleted: Bool
    var offersFix: Bool { !deleted }

    /// `entries` is nil until the list is read: until then an entry is shown as logged, neither deleted nor current.
    init(memory: UsedMemory, entries: [MemoryEntry]?) {
        current = entries?.first { $0.id == memory.id }
        deleted = entries != nil && current == nil
        key = current?.key ?? memory.key
    }
}

struct UsedMemoryRow: View {
    let memory: UsedMemory
    /// Nil until the list is read: until then an entry is shown as logged, neither deleted nor current.
    let entries: [MemoryEntry]?
    let onWrong: (String) -> Void
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    var body: some View {
        let state = UsedMemoryRowState(memory: memory, entries: entries)
        VStack(alignment: .leading, spacing: 4) {
            // At accessibility sizes the button goes under the title rather than squeezing it.
            let layout = dynamicTypeSize.isAccessibilitySize
                ? AnyLayout(VStackLayout(alignment: .leading, spacing: 6))
                : AnyLayout(HStackLayout(alignment: .center, spacing: 8))
            layout {
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    Text(verbatim: state.key).font(.subheadline.weight(.semibold))
                    if state.deleted {
                        Text("chat:usedMemories.deleted").font(.caption).foregroundStyle(.secondary)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .accessibilityElement(children: .combine)
                if state.offersFix { wrongButton(state.key) }
            }
            if let current = state.current {
                VStack(alignment: .leading, spacing: 2) {
                    if !current.summary.isEmpty { Text(verbatim: current.summary) }
                    ForEach(current.details, id: \.self) { Text(verbatim: "• \($0)") }
                }
                .font(.footnote)
                .foregroundStyle(.secondary)
                .accessibilityElement(children: .combine)
            }
        }
        .opacity(state.deleted ? 0.5 : 1)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    /// A capsule in the tone (`.tint`, which the app sets to the tone's ink): the one thing to do with an entry.
    private func wrongButton(_ key: String) -> some View {
        Button {
            onWrong(key)
        } label: {
            Label("chat:usedMemories.wrong", systemImage: "pencil")
                .font(.footnote.weight(.semibold))
        }
        .buttonStyle(.bordered)
        .buttonBorderShape(.capsule)
        .controlSize(.small)
        .fixedSize()
    }
}
