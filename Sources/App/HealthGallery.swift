#if DEBUG
import HealthFeature
import Models
import SwiftUI

/// DEBUG-only visual check of Health: `-HealthGallery <state>` opens the workspace on preview data with the report in
/// `<state>` (`ready` default, `writing`, `offline`, `needsModel`, `failed`, `consent`, `onboarding`), or opens the
/// calendar over it, on last month: `calendar-week`, `calendar-month`, `calendar-quarter`, `calendar-year`, and
/// `day-note` / `day-empty` (the month with the sheet of its 16th up, which has a kept note, or of its 12th, which has
/// none). Period reports: `report-home` (last month's report written just now, so the "report ready" line shows under
/// This week), `report-page` (that report: stories, comparisons, the idea, 21 days with data), `report-card` (the
/// calendar on last month with its report card) and `report-pending` (the calendar on last month with the computer
/// unreachable: "Will be written…"). Add `-HealthGalleryAnchor center|bottom` to open the home scrolled down.
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
    @State private var path = Self.path()

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

    /// Last month: finished, so it has (or waits for) a report.
    private static var lastMonth: Period { Period.containing(reference(), .month, calendar: .current) }

    private static func path() -> NavigationPath {
        let anchor = reference()
        var path = NavigationPath()
        switch HealthGalleryLaunch.state {
        case "calendar-week": path.append(TrendsRoute(scope: .week, anchor: anchor))
        case "calendar-month", "report-card", "report-pending": path.append(TrendsRoute(scope: .month, anchor: anchor))
        case "calendar-quarter": path.append(TrendsRoute(scope: .quarter, anchor: anchor))
        case "calendar-year": path.append(TrendsRoute(scope: .year, anchor: anchor))
        case "day-note": path.append(TrendsRoute(scope: .month, anchor: anchor, presentedDay: reference(1)))
        case "day-empty": path.append(TrendsRoute(scope: .month, anchor: anchor, presentedDay: reference(-3)))
        case "report-page": path.append(PeriodReportRoute(period: lastMonth))
        default: break
        }
        return path
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
        switch HealthGalleryLaunch.state {
        case "report-home", "report-page", "report-card":
            try? cache.archive.reports.writePreview(period: lastMonth, generatedAt: Date())
        default: break
        }
        // Only the pending state asks for reports (and finds the computer unreachable); the others show what is kept.
        let periodReports: (any PeriodReportService)? =
            HealthGalleryLaunch.state == "report-pending" ? PreviewPeriodReportService(offline: true) : nil
        return HealthHomeModel(
            source: HealthPreviewSource(), summaries: PreviewSummaryService(report: report),
            memory: PreviewMemoryWriter(), cache: cache, preferences: prefs, periodReports: periodReports,
            locale: Bundle.main.preferredLocalizations.first ?? "en")
    }
}
#endif
