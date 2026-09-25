import Models
import SwiftUI

/// Settings → Memory: the desktop's `memory.tsx` — Memory and Context management switches, then the stored entries
/// grouped You / Topics / People with the disabled ones last. Tapping an entry edits it; swipe to disable or delete.
struct MemorySettingsPage: View {
    @Bindable var viewModel: MemorySettingsViewModel
    @State private var editing: MemoryEntry?
    @State private var isAdding = false

    var body: some View {
        ScrollViewReader { proxy in
            form
                .task {
                    if viewModel.pendingWrites == 0 { await viewModel.load() }
                    #if DEBUG
                    applyGalleryScene(proxy)
                    #endif
                }
        }
    }

    private var form: some View {
        Form {
            memorySection
            contextSection
            SettingsErrorSection(message: viewModel.errorMessage)
            if !isSheetOpen { MemoryFailureSection(failure: viewModel.failure) }
            entriesSections
        }
        .refreshable { await viewModel.refresh() }
        .overlay {
            if viewModel.isLoadingSettings && !viewModel.hasLoadedSettings { ProgressView() }
        }
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button {
                    viewModel.failure = nil
                    isAdding = true
                } label: {
                    Label("common:action.add", systemImage: "plus")
                }
                .disabled(viewModel.listState != .loaded)
            }
        }
        .sheet(isPresented: $isAdding) {
            MemoryEditorSheet(viewModel: viewModel, entry: nil)
        }
        .sheet(item: $editing) { entry in
            MemoryEditorSheet(viewModel: viewModel, entry: entry)
        }
        .alert(
            Text(verbatim: MemoryDeleteConfirmation.title(for: viewModel.pendingDeletion)),
            isPresented: deletionBinding(when: !isSheetOpen)
        ) {
            MemoryDeleteConfirmation.actions(viewModel)
        } message: {
            Text("ios:settings.memory.deleteMessage")
        }
    }

    private var isSheetOpen: Bool { isAdding || editing != nil }

    private static let listStateID = "memory.listState"
    private static let freshTailID = "memory.freshTail"

    private func deletionBinding(when active: Bool) -> Binding<Bool> {
        Binding(
            get: { active && viewModel.pendingDeletion != nil },
            set: { _ in })
    }

    /// iOS Settings' layout: each control is a one-line row and its explanation is the fine print under its own
    /// section, so a long description never squeezes a switch or a stepper.
    @ViewBuilder
    private var memorySection: some View {
        Section {
            Toggle(
                "settings:memory.settings.autoCapture.label",
                isOn: Binding(get: { viewModel.autoCapture }, set: { viewModel.setAutoCapture($0) }))
        } header: {
            Text("settings:memory.settings.sections.memory")
        } footer: {
            Text("settings:memory.settings.autoCapture.description")
        }
        .disabled(!viewModel.hasLoadedSettings)
        Section {
            Toggle(
                "settings:memory.settings.useInChat.label",
                isOn: Binding(get: { viewModel.useInChat }, set: { viewModel.setUseInChat($0) }))
        } footer: {
            VStack(alignment: .leading, spacing: 6) {
                Text("settings:memory.settings.useInChat.description")
                Text("ios:settings.memory.appliesToComputer")
            }
        }
        .disabled(!viewModel.hasLoadedSettings)
    }

    @ViewBuilder
    private var contextSection: some View {
        Section {
            Toggle(
                "settings:memory.settings.lcmEnabled.label",
                isOn: Binding(get: { viewModel.lcmEnabled }, set: { viewModel.setLcmEnabled($0) }))
        } header: {
            Text("settings:memory.settings.sections.context")
        } footer: {
            Text("settings:memory.settings.lcmEnabled.description")
        }
        .disabled(!viewModel.hasLoadedSettings)
        if viewModel.lcmEnabled {
            Section {
                StepperRow(
                    title: Text("settings:memory.settings.contextWindowPercent.label"),
                    value: Text(Double(viewModel.contextWindowPercent) / 100, format: .percent),
                    number: Binding(
                        get: { viewModel.contextWindowPercent }, set: { viewModel.setContextWindowPercent($0) }),
                    range: MemorySettingsViewModel.percentRange, step: 5)
            } footer: {
                Text("settings:memory.settings.contextWindowPercent.description")
            }
            .disabled(!viewModel.hasLoadedSettings)
            Section {
                StepperRow(
                    title: Text("settings:memory.settings.freshTailSize.label"),
                    value: Text(viewModel.freshTailSize, format: .number),
                    number: Binding(get: { viewModel.freshTailSize }, set: { viewModel.setFreshTailSize($0) }),
                    range: MemorySettingsViewModel.freshTailRange, step: 1)
            } footer: {
                Text("settings:memory.settings.freshTailSize.description")
            }
            .id(Self.freshTailID)
            .disabled(!viewModel.hasLoadedSettings)
        }
    }

    @ViewBuilder
    private var entriesSections: some View {
        switch viewModel.listState {
        case .idle, .loading:
            Section {
                ProgressView().frame(maxWidth: .infinity)
            } header: {
                Text("settings:memory.settings.storedMemoriesHeading")
            }
        case .failed(let message):
            Section {
                VStack(alignment: .leading, spacing: 4) {
                    Text("settings:memory.settings.loadFailedTitle").font(.headline)
                    Text(verbatim: message).foregroundStyle(.secondary)
                }
                Button("common:action.retry") { Task { await viewModel.loadList() } }
                    .id(Self.listStateID)
            } header: {
                Text("settings:memory.settings.storedMemoriesHeading")
            }
        case .loaded where viewModel.entries.isEmpty:
            Section {
                ContentUnavailableView {
                    Label("settings:memory.settings.emptyTitle", systemImage: "brain")
                } description: {
                    Text("ios:settings.memory.emptyHint")
                }
                .id(Self.listStateID)
            } header: {
                Text("settings:memory.settings.storedMemoriesHeading")
            }
        case .loaded:
            ForEach(viewModel.activeGroups, id: \.section) { group in
                Section {
                    ForEach(group.entries) { row(for: $0) }
                } header: {
                    MemorySectionTitle(section: group.section)
                }
            }
            let disabled = viewModel.disabledEntries
            if !disabled.isEmpty {
                Section {
                    ForEach(disabled) { row(for: $0) }
                } header: {
                    Text(
                        verbatim: String(
                            localized: "settings:memory.settings.disabledHeading",
                            defaultValue: "Disabled · \(String(disabled.count))",
                            comment: "Header of the disabled memory entries, with their count."))
                }
            }
        }
    }

    private func row(for entry: MemoryEntry) -> some View {
        Button {
            viewModel.failure = nil
            editing = entry
        } label: {
            MemoryRow(entry: entry)
        }
        .foregroundStyle(.primary)
        .disabled(viewModel.isWriting)
        // Not `role: .destructive`: that animates the row away before the confirm alert has been answered.
        .swipeActions(edge: .trailing, allowsFullSwipe: false) {
            Button("common:action.delete", systemImage: "trash") {
                viewModel.requestDelete(entry)
            }
            .tint(.red)
            if entry.isActive {
                Button("settings:memory.disableLabel", systemImage: "eye.slash") {
                    Task { await viewModel.setActive(entry, false) }
                }
            } else {
                Button("settings:memory.restoreLabel", systemImage: "eye") {
                    Task { await viewModel.setActive(entry, true) }
                }
            }
        }
    }

    #if DEBUG
    private func applyGalleryScene(_ proxy: ScrollViewProxy) {
        let scene = SettingsGalleryLaunch.memoryScene
        if scene == "context" {
            Task {
                try? await Task.sleep(for: .milliseconds(400))
                proxy.scrollTo(Self.freshTailID, anchor: .bottom)
            }
        }
        if scene == "list" || scene == "empty" || scene == "error" {
            let target = viewModel.entries.last?.id ?? Self.listStateID
            Task {
                try? await Task.sleep(for: .milliseconds(400))
                proxy.scrollTo(target, anchor: .bottom)
            }
        }
        guard let entry = viewModel.entries.first(where: \.isActive) else { return }
        switch scene {
        case "edit": editing = entry
        case "add": isAdding = true
        case "delete": viewModel.requestDelete(entry)
        default: break
        }
    }
    #endif
}

/// Title and value on one line with the stepper trailing, as in iOS Settings; at an accessibility size the stepper
/// moves under them so neither is squeezed.
private struct StepperRow: View {
    let title: Text
    let value: Text
    @Binding var number: Int
    let range: ClosedRange<Int>
    let step: Int
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    var body: some View {
        if dynamicTypeSize.isAccessibilitySize {
            VStack(alignment: .leading, spacing: 8) {
                title.accessibilityHidden(true)
                HStack {
                    value.monospacedDigit().foregroundStyle(.secondary).accessibilityHidden(true)
                    Spacer(minLength: 8)
                    Stepper(value: $number, in: range, step: step) { reading }
                        .labelsHidden()
                }
            }
        } else {
            Stepper(value: $number, in: range, step: step) { reading }
        }
    }

    private var reading: some View {
        HStack(alignment: .firstTextBaseline) {
            title
            Spacer(minLength: 8)
            value.monospacedDigit().foregroundStyle(.secondary)
        }
    }
}

private struct MemoryRow: View {
    let entry: MemoryEntry

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(verbatim: entry.key)
                .fontWeight(.medium)
                .foregroundStyle(entry.isActive ? .primary : .secondary)
            if entry.summary.isEmpty {
                Text("settings:memory.row.noSummaryYet").italic().foregroundStyle(.secondary)
            } else {
                Text(verbatim: entry.summary).foregroundStyle(.secondary).lineLimit(2)
            }
        }
        .font(.subheadline)
        .frame(maxWidth: .infinity, alignment: .leading)
        .contentShape(.rect)
    }
}

struct MemorySectionTitle: View {
    let section: MemorySection

    var body: some View {
        switch section {
        case .profile: Text("settings:memory.sectionGroups.profile")
        case .topic: Text("settings:memory.sectionGroups.topic")
        case .person: Text("settings:memory.sectionGroups.person")
        }
    }
}

/// A failed entry operation under the desktop's title for it (its toast title), with the server's message.
struct MemoryFailureSection: View {
    let failure: MemorySettingsViewModel.Failure?

    var body: some View {
        if let failure {
            Section {
                VStack(alignment: .leading, spacing: 4) {
                    switch failure {
                    case .load(let message):
                        Text("settings:memory.settings.loadFailedTitle").font(.headline)
                        Text(verbatim: message)
                    case .create(let message):
                        Text("settings:memory.settings.toast.createFailedTitle").font(.headline)
                        Text(verbatim: message)
                    case .save(let message):
                        Text("settings:memory.detail.toast.notSavedTitle").font(.headline)
                        Text(verbatim: message)
                    case .delete(let message):
                        Text("settings:memory.detail.toast.deleteFailedTitle").font(.headline)
                        Text(verbatim: message)
                    case .titleRequired:
                        Text("ios:settings.memory.titleRequired")
                    }
                }
                .foregroundStyle(.red)
            }
        }
    }
}

enum MemoryDeleteConfirmation {
    static func title(for entry: MemoryEntry?) -> String {
        String(
            localized: "ios:settings.memory.deleteTitle", defaultValue: "Delete “\(entry?.key ?? "")”?",
            comment: "Title of the confirmation before a memory entry is deleted. %@ is the entry's title.")
    }

    @ViewBuilder
    static func actions(
        _ viewModel: MemorySettingsViewModel, onDeleted: @escaping @MainActor () -> Void = {}
    ) -> some View {
        // An alert closes only through its buttons: Delete takes the entry, Cancel clears it.
        Button("common:action.delete", role: .destructive) {
            guard let deletion = viewModel.confirmDelete() else { return }
            Task {
                if await deletion.value { onDeleted() }
            }
        }
        Button("common:action.cancel", role: .cancel) { viewModel.cancelDelete() }
    }
}

/// Adds an entry (`entry == nil`) or edits one: title, summary and details one per line, as the desktop's detail
/// view. A new entry also picks its section (the desktop creates every new one under Topics).
struct MemoryEditorSheet: View {
    let viewModel: MemorySettingsViewModel
    let entry: MemoryEntry?
    @State private var draft: MemoryDraft
    @Environment(\.dismiss) private var dismiss

    init(viewModel: MemorySettingsViewModel, entry: MemoryEntry?) {
        self.viewModel = viewModel
        self.entry = entry
        _draft = State(initialValue: entry.map(MemoryDraft.init(entry:)) ?? MemoryDraft())
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField(
                        "settings:memory.detail.titlePlaceholder", text: $draft.key,
                        prompt: Text("settings:memory.detail.titlePlaceholder"))
                        .font(.headline)
                    if entry == nil {
                        Picker("ios:settings.memory.sectionPicker", selection: $draft.section) {
                            ForEach(MemorySection.allCases, id: \.self) { section in
                                MemorySectionTitle(section: section).tag(section)
                            }
                        }
                    }
                }

                Section {
                    TextField(
                        "settings:memory.detail.summaryLabel", text: $draft.summary,
                        prompt: Text("settings:memory.detail.summaryPlaceholder"), axis: .vertical)
                        .lineLimit(1...4)
                } header: {
                    Text("settings:memory.detail.summaryLabel")
                }

                Section {
                    TextField(
                        "settings:memory.detail.detailsLabel", text: $draft.detailsText,
                        prompt: Text("settings:memory.detail.detailsPlaceholder"), axis: .vertical)
                        .lineLimit(4...14)
                } header: {
                    Text("settings:memory.detail.detailsLabel")
                }

                MemoryFailureSection(failure: viewModel.failure)

                if let entry {
                    Section {
                        if entry.isActive {
                            Button("settings:memory.disableLabel") { setActive(entry, false) }
                        } else {
                            Button("settings:memory.restoreLabel") { setActive(entry, true) }
                        }
                        Button("common:action.delete", role: .destructive) { viewModel.requestDelete(entry) }
                    }
                }
            }
            .disabled(viewModel.isWriting)
            .navigationTitle(title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("common:action.cancel", role: .cancel) {
                        viewModel.failure = nil
                        dismiss()
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("common:action.save") { save() }
                        .disabled(draft.key.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                            || viewModel.isWriting)
                }
            }
            .alert(
                Text(verbatim: MemoryDeleteConfirmation.title(for: viewModel.pendingDeletion)),
                isPresented: Binding(get: { viewModel.pendingDeletion != nil }, set: { _ in })
            ) {
                MemoryDeleteConfirmation.actions(viewModel) { dismiss() }
            } message: {
                Text("ios:settings.memory.deleteMessage")
            }
        }
        .interactiveDismissDisabled(draft != initialDraft)
    }

    private var title: Text {
        if entry == nil {
            Text("ios:settings.memory.newTitle")
        } else {
            Text("ios:settings.memory.editTitle")
        }
    }

    private var initialDraft: MemoryDraft { entry.map(MemoryDraft.init(entry:)) ?? MemoryDraft() }

    private func save() {
        Task {
            let saved = if let entry { await viewModel.save(draft, for: entry) } else { await viewModel.create(draft) }
            if saved { dismiss() }
        }
    }

    private func setActive(_ entry: MemoryEntry, _ active: Bool) {
        Task {
            if await viewModel.setActive(entry, active) { dismiss() }
        }
    }
}
