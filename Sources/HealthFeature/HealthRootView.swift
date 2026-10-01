import Models
import NetworkingKit
import SwiftUI

enum HealthFeatureInfo {
    static let name = "Health"
}

/// The Health workspace: onboarding the first time, then the daily report. Owns the home model; reloads when the app
/// comes back to the foreground (the health store is only readable while unlocked).
public struct HealthRootView: View {
    @State private var model: HealthHomeModel
    let onAsk: (String) -> Void
    @Environment(\.scenePhase) private var scenePhase

    public init(apiClient: APIClient, onAsk: @escaping (String) -> Void = { _ in }) {
        let source = HealthKitSource()
        _model = State(
            initialValue: HealthHomeModel(
                source: source, summaries: LiveHealthSummaryService(apiClient: apiClient),
                memory: LiveMemoryWriter(apiClient: apiClient), cache: .standard(), preferences: HealthPreferences(),
                locale: Bundle.main.preferredLocalizations.first ?? "en"))
        self.onAsk = onAsk
    }

    init(model: HealthHomeModel, onAsk: @escaping (String) -> Void) {
        _model = State(initialValue: model)
        self.onAsk = onAsk
    }

    public var body: some View {
        Group {
            if !model.preferences.hasOnboarded || model.day?.snapshot.odyState == .permission {
                HealthOnboardingView(model: model)
            } else {
                HealthHomeView(model: model, onAsk: onAsk)
            }
        }
        .task { await model.load() }
        .onChange(of: scenePhase) { if scenePhase == .active { Task { await model.load() } } }
        #if DEBUG
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Menu {
                    Button {
                        Task {
                            try? await HealthKitSource().writeSampleData(now: Date())
                            await model.load(force: true)
                        }
                    } label: { Text(verbatim: "Write sample health data") }
                } label: { Image(systemName: "ladybug") }
            }
        }
        #endif
    }
}
