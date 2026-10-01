#if DEBUG
import HealthFeature
import Models
import SwiftUI

/// DEBUG-only visual check of Health: `-HealthGallery <state>` opens the workspace on preview data with the report in
/// `<state>` (`ready` default, `writing`, `offline`, `needsModel`, `failed`, `consent`, `onboarding`).
enum HealthGalleryLaunch {
    static var isEnabled: Bool { ProcessInfo.processInfo.arguments.contains("-HealthGallery") }

    static var state: String {
        let args = ProcessInfo.processInfo.arguments
        guard let i = args.firstIndex(of: "-HealthGallery"), i + 1 < args.count, !args[i + 1].hasPrefix("-") else {
            return "ready"
        }
        return args[i + 1]
    }
}

struct HealthGalleryView: View {
    /// Made once: the model mirrors the preferences when it is created, so they are set first.
    @State private var model = Self.makeModel()

    var body: some View {
        NavigationStack { HealthRootView.gallery(model: model) }
    }

    private static func makeModel() -> HealthHomeModel {
        let suite = "health-gallery"
        let defaults = UserDefaults(suiteName: suite)!
        defaults.removePersistentDomain(forName: suite)
        let prefs = HealthPreferences(defaults: defaults)
        prefs.hasOnboarded = HealthGalleryLaunch.state != "onboarding"
        prefs.summaryConsent = HealthGalleryLaunch.state != "consent"
        let report: HealthHomeModel.Report =
            switch HealthGalleryLaunch.state {
            case "writing": .writing
            case "offline": .offline
            case "needsModel": .needsModel
            case "failed": .failed
            default: .ready(PreviewSummaryService.sample)
            }
        return HealthHomeModel(
            source: HealthPreviewSource(), summaries: PreviewSummaryService(report: report),
            memory: PreviewMemoryWriter(),
            cache: ReportCache(directory: FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)),
            preferences: prefs, locale: Bundle.main.preferredLocalizations.first ?? "en")
    }
}
#endif
