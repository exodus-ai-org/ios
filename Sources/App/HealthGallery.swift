#if DEBUG
import HealthFeature
import Models
import SwiftUI

/// DEBUG-only visual check of Health: `-HealthGallery <state>` opens the workspace on preview data with the report in
/// `<state>` (`ready` default, `writing`, `offline`, `needsModel`, `failed`, `consent`, `onboarding`), or opens the
/// calendar over it, on last month: `calendar-week`, `calendar-month`, `calendar-quarter`, `calendar-year`, and
/// `day-note` / `day-empty` (the month with the sheet of its 16th up, which has a kept note, or of its 12th, which has
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

    /// The calendar opens on last month, which preview data fills with coloured days: its 15th and the days around.
    private static func reference(_ offset: Int = 0) -> Date {
        let cal = Calendar.current
        let thisMonth = cal.dateInterval(of: .month, for: Date())?.start ?? Date()
        let mid = cal.date(byAdding: .month, value: -1, to: thisMonth).flatMap { cal.date(byAdding: .day, value: 14, to: $0) } ?? Date()
        return cal.date(byAdding: .day, value: offset, to: mid) ?? mid
    }

    private static func routes() -> [TrendsRoute] {
        let anchor = reference()
        switch HealthGalleryLaunch.state {
        case "calendar-week": return [TrendsRoute(scope: .week, anchor: anchor)]
        case "calendar-month": return [TrendsRoute(scope: .month, anchor: anchor)]
        case "calendar-quarter": return [TrendsRoute(scope: .quarter, anchor: anchor)]
        case "calendar-year": return [TrendsRoute(scope: .year, anchor: anchor)]
        case "day-note": return [TrendsRoute(scope: .month, anchor: anchor, presentedDay: reference(1))]
        case "day-empty": return [TrendsRoute(scope: .month, anchor: anchor, presentedDay: reference(-3))]
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
        // Yesterday and the day-note state's day have a kept note; the other days have none.
        if let yesterday = Calendar.current.date(byAdding: .day, value: -1, to: Date()) {
            try? cache.archive.writePreview(day: yesterday)
        }
        try? cache.archive.writePreview(day: reference(1))
        return HealthHomeModel(
            source: HealthPreviewSource(), summaries: PreviewSummaryService(report: report),
            memory: PreviewMemoryWriter(), cache: cache, preferences: prefs,
            locale: Bundle.main.preferredLocalizations.first ?? "en")
    }
}
#endif
