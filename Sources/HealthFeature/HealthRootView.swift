import Models
import NetworkingKit
import SwiftUI
import WidgetKitShared

/// The Health workspace: onboarding the first time, then the daily report. Owns the home model; reloads when the app
/// comes back to the foreground (the health store is only readable while unlocked).
public struct HealthRootView: View {
    @State private var model: HealthHomeModel
    let onAsk: (String) -> Void
    let onGlanceChange: (HealthGlance?) -> Void
    /// A question from a widget for the ask box, and how to say it was put there, so a later visit starts empty.
    let initialAsk: String?
    let onInitialAskUsed: () -> Void
    @Environment(\.scenePhase) private var scenePhase
    @State private var confirmClear = false
    /// Bumped when the archive was cleared: the success tap.
    @State private var cleared = 0

    public init(
        apiClient: APIClient, onGlanceChange: @escaping (HealthGlance?) -> Void = { _ in },
        initialAsk: String? = nil, onInitialAskUsed: @escaping () -> Void = {},
        onAsk: @escaping (String) -> Void = { _ in }
    ) {
        let source = HealthKitSource()
        _model = State(
            initialValue: HealthHomeModel(
                source: source, summaries: LiveHealthSummaryService(apiClient: apiClient),
                memory: LiveMemoryWriter(apiClient: apiClient), cache: .standard(), preferences: HealthPreferences(),
                periodReports: LivePeriodReportService(apiClient: apiClient),
                locale: Bundle.main.preferredLocalizations.first ?? "en"))
        self.onAsk = onAsk
        self.onGlanceChange = onGlanceChange
        self.initialAsk = initialAsk
        self.onInitialAskUsed = onInitialAskUsed
    }

    init(model: HealthHomeModel, onAsk: @escaping (String) -> Void) {
        _model = State(initialValue: model)
        self.onAsk = onAsk
        self.onGlanceChange = { _ in }
        self.initialAsk = nil
        self.onInitialAskUsed = {}
    }

    #if DEBUG
    /// The workspace on a model made elsewhere (preview data), for the app's `-HealthGallery`.
    public static func gallery(model: HealthHomeModel) -> HealthRootView { HealthRootView(model: model, onAsk: { _ in }) }
    #endif

    public var body: some View {
        Group {
            if model.needsOnboarding {
                HealthOnboardingView(model: model)
            } else {
                HealthHomeView(model: model, initialAsk: initialAsk, onAsk: onAsk)
                    // Used once the ask box has it — not during onboarding, where there is no box yet.
                    .onChange(of: initialAsk, initial: true) { if initialAsk != nil { onInitialAskUsed() } }
            }
        }
        .task { await open() }
        .onChange(of: scenePhase) { if scenePhase == .active { Task { await open() } } }
        .onChange(of: settledGlance, initial: true) { _, glance in
            if let glance { onGlanceChange(glance) }
        }
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Menu {
                    // Consent can be taken back here; onboarding is where it is first asked.
                    if !model.needsOnboarding {
                        Toggle(isOn: notesBinding) {
                            Label(Self.notesText, systemImage: "text.bubble")
                        }
                        Button(role: .destructive) {
                            confirmClear = true
                        } label: {
                            Label(Self.clearArchiveText, systemImage: "trash")
                        }
                    }
                    #if DEBUG
                    Button {
                        Task {
                            try? await HealthKitSource().writeSampleData(now: Date())
                            await model.load(force: true)
                        }
                    } label: { Label { Text(verbatim: "Write sample health data") } icon: { Image(systemName: "ladybug") } }
                    #endif
                } label: {
                    Label(Self.menuText, systemImage: "ellipsis")
                }
                .accessibilityIdentifier("healthMenu")
            }
        }
        .alert(Text(Self.clearTitleText), isPresented: $confirmClear) {
            Button(role: .destructive) {
                if model.clearArchive() { cleared += 1 }
            } label: {
                Text(Self.clearArchiveText)
            }
            Button("common:action.cancel", role: .cancel) {}
        } message: {
            Text(Self.clearMessageText)
        }
        .sensoryFeedback(.success, trigger: cleared)
    }

    /// An open of Health: the day and its note, then the period reports that are due.
    private func open() async {
        await model.load()
        await model.writeDueReports()
    }

    /// The glance once the report has settled. Before the first read and while a note is written nothing is known
    /// yet: passing that on would blank the widgets' health every time Health opens, until the report is back.
    private var settledGlance: HealthGlance?? {
        switch model.report {
        case .writing: nil
        case .idle where model.day == nil: nil
        default: .some(model.widgetGlance)
        }
    }

    private var notesBinding: Binding<Bool> {
        Binding(
            get: { model.hasConsent },
            set: { on in
                if on { Task { await model.grantConsent() } } else { model.revokeConsent() }
            })
    }

    private static let notesText = LocalizedStringResource(
        "ios:health.settings.notes", defaultValue: "Write daily notes",
        comment: "Health menu toggle: send the day's summary to the AI provider for a written note.")
    private static let menuText = LocalizedStringResource(
        "ios:health.settings.menu", defaultValue: "Health options", comment: "Health toolbar menu, VoiceOver label.")
    private static let clearArchiveText = LocalizedStringResource(
        "ios:health.archive.clear", defaultValue: "Clear archive",
        comment: "Health menu, and its confirmation's button: delete every daily note kept on this iPhone.")
    private static let clearTitleText = LocalizedStringResource(
        "ios:health.archive.confirmTitle", defaultValue: "Clear the archive?",
        comment: "Confirmation title before deleting every kept daily note.")
    private static let clearMessageText = LocalizedStringResource(
        "ios:health.archive.confirmMessage",
        defaultValue: "This deletes every daily note and report kept on this iPhone. Today's note and your health data stay.",
        comment: "Confirmation message before deleting every kept daily note and period report.")
}
