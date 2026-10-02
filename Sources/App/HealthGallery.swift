#if DEBUG
import HealthFeature
import Models
import SwiftUI

/// DEBUG-only visual check of Health: `-HealthGallery <state>` opens the workspace on preview data with the report in
/// `<state>` (`ready` default, `writing`, `offline`, `needsModel`, `failed`, `consent`, `onboarding`), or opens the
/// calendar over it: `calendar-week`, `calendar-month`, `calendar-quarter`, `calendar-year`, and `day-note` /
/// `day-empty` (the month with yesterday's sheet up, which has a kept note, or the sheet of three days ago, which has
/// none). Add `-HealthGalleryAnchor center|bottom` to open the home scrolled down, for a screenshot of the note below
/// the hero.
enum HealthGalleryLaunch {
    static var isEnabled: Bool { ProcessInfo.processInfo.arguments.contains("-HealthGallery") }

    static var state: String {
        let args = ProcessInfo.processInfo.arguments
        guard let i = args.firstIndex(of: "-HealthGallery"), i + 1 < args.count, !args[i + 1].hasPrefix("-") else {
            return "ready"
        }
        return args[i + 1]
    }

    static var anchor: UnitPoint? {
        let args = ProcessInfo.processInfo.arguments
        guard let i = args.firstIndex(of: "-HealthGalleryAnchor"), i + 1 < args.count else { return nil }
        switch args[i + 1] {
        case "center": return .center
        case "bottom": return .bottom
        default: return nil
        }
    }
}

struct HealthGalleryView: View {
    /// Made once: the model mirrors the preferences when it is created, so they are set first.
    @State private var model = Self.makeModel()
    @State private var path = NavigationPath(Self.routes())

    var body: some View {
        NavigationStack(path: $path) { HealthRootView.gallery(model: model) }
            .defaultScrollAnchor(HealthGalleryLaunch.anchor)
    }

    private static func routes() -> [TrendsRoute] {
        let now = Date()
        let cal = Calendar.current
        switch HealthGalleryLaunch.state {
        case "calendar-week": return [TrendsRoute(scope: .week, anchor: now)]
        case "calendar-month": return [TrendsRoute(scope: .month, anchor: now)]
        case "calendar-quarter": return [TrendsRoute(scope: .quarter, anchor: now)]
        case "calendar-year": return [TrendsRoute(scope: .year, anchor: now)]
        case "day-note":
            return [TrendsRoute(scope: .month, anchor: now, presentedDay: cal.date(byAdding: .day, value: -1, to: now))]
        case "day-empty":
            return [TrendsRoute(scope: .month, anchor: now, presentedDay: cal.date(byAdding: .day, value: -3, to: now))]
        default: return []
        }
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
        let cache = ReportCache(directory: FileManager.default.temporaryDirectory.appending(path: UUID().uuidString))
        // Yesterday has a kept note; the days before it have none.
        if let yesterday = Calendar.current.date(byAdding: .day, value: -1, to: Date()) {
            try? cache.archive.writePreview(day: yesterday)
        }
        return HealthHomeModel(
            source: HealthPreviewSource(), summaries: PreviewSummaryService(report: report),
            memory: PreviewMemoryWriter(), cache: cache, preferences: prefs,
            locale: Bundle.main.preferredLocalizations.first ?? "en")
    }
}
#endif
