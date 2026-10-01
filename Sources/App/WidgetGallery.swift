#if DEBUG
import SwiftUI
import WidgetKit
import WidgetKitShared
import WidgetUI

/// DEBUG-only visual check of the widgets: `-WidgetGallery` draws every widget on a fixture snapshot — small and
/// medium at 07:00, 12:00, 18:30 and 23:00 over their sky, the accented Home Screen, the Lock Screen pair and the
/// empty state. `-WidgetGallery <part>` shows one part only, sized for a screenshot: `day` (07:00, 12:00), `night`
/// (18:30, 23:00), `other` (accented, Lock Screen) or `empty`.
enum WidgetGalleryLaunch {
    static var isEnabled: Bool { ProcessInfo.processInfo.arguments.contains("-WidgetGallery") }

    static var part: String? {
        let args = ProcessInfo.processInfo.arguments
        guard let i = args.firstIndex(of: "-WidgetGallery"), i + 1 < args.count, !args[i + 1].hasPrefix("-") else {
            return nil
        }
        return args[i + 1]
    }
}

struct WidgetGalleryView: View {
    private let calendar = Calendar.current
    private let snapshot = Self.fixture(now: .now, calendar: .current)

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                if shows("day") {
                    hour(7, 0)
                    hour(12, 0)
                }
                if shows("night") {
                    hour(18, 30)
                    hour(23, 0)
                }
                if shows("other") {
                    accented
                    lockScreen
                }
                if shows("empty") { empty }
            }
            .padding(13)
        }
        .background(Color(uiColor: .secondarySystemBackground))
    }

    private func shows(_ part: String) -> Bool { WidgetGalleryLaunch.part.map { $0 == part } ?? true }

    private func at(_ hour: Int, _ minute: Int) -> Date {
        calendar.date(bySettingHour: hour, minute: minute, second: 0, of: .now) ?? .now
    }

    private func hour(_ hour: Int, _ minute: Int) -> some View {
        let date = at(hour, minute)
        return section(String(format: "%02d:%02d", hour, minute)) {
            home(AskSmallView(snapshot: snapshot, date: date, calendar: calendar), width: 170, date: date)
            home(AskMediumView(snapshot: snapshot, date: date, calendar: calendar), width: 364, date: date)
        }
    }

    /// A tinted or clear Home Screen: no sky, Ody's outline. The system tints the content itself, which the app
    /// cannot do, so the night's white ink stands in for the tint.
    private var accented: some View {
        let date = at(23, 0)
        return section("Accented") {
            HStack(alignment: .top, spacing: 10) {
                AskSmallView(snapshot: snapshot, date: date, calendar: calendar).padding(14)
                    .frame(width: 170, height: 170).background(Color(white: 0.25), in: .rect(cornerRadius: 22))
                AskSmallView(snapshot: .empty, date: date, calendar: calendar).padding(14)
                    .frame(width: 170, height: 170).background(Color(white: 0.25), in: .rect(cornerRadius: 22))
            }
            .environment(\.colorScheme, .dark)
            .environment(\.widgetRenderingMode, .accented)
        }
    }

    private var lockScreen: some View {
        let date = at(12, 0)
        // Outside WidgetKit `AccessoryWidgetBackground` draws nothing, so the circle is drawn here.
        return section("Lock Screen") {
            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 12) {
                    AskCircularView().frame(width: 76, height: 76).background(.white.opacity(0.12), in: .circle)
                    TodayRectangularView(snapshot: snapshot, date: date, calendar: calendar).rectangularBounds
                }
                TodayRectangularView(snapshot: .empty, date: date, calendar: calendar).rectangularBounds
            }
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .foregroundStyle(.white)
            .environment(\.colorScheme, .dark)
            .environment(\.widgetRenderingMode, .vibrant)
            .background(LinearGradient(colors: [.indigo, .black], startPoint: .top, endPoint: .bottom), in: .rect(cornerRadius: 22))
        }
    }

    private var empty: some View {
        let date = at(18, 30)
        return section("Empty") {
            home(AskSmallView(snapshot: .empty, date: date, calendar: calendar), width: 170, date: date)
            home(AskMediumView(snapshot: .empty, date: date, calendar: calendar), width: 364, date: date)
        }
    }

    private func home(_ widget: some View, width: CGFloat, date: Date) -> some View {
        widget.padding(14).frame(width: width, height: 170)
            .background { WidgetSky(date: date, calendar: calendar) }
            .clipShape(.rect(cornerRadius: 22))
            .environment(\.widgetRenderingMode, .fullColor)
    }

    private func section(_ title: String, @ViewBuilder content: () -> some View) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(verbatim: title).font(.caption.weight(.semibold)).foregroundStyle(.secondary)
            content()
        }
    }

    /// Three recents and today's glance, as the app would write them.
    private static func fixture(now: Date, calendar: Calendar) -> WidgetSnapshot {
        WidgetSnapshot(
            updatedAt: now,
            recentChats: [
                RecentChat(id: "1", title: "Swift 6 concurrency migration", updatedAt: now.addingTimeInterval(-5 * 60)),
                RecentChat(id: "2", title: "Weekend in Hangzhou", updatedAt: now.addingTimeInterval(-3 * 3600)),
                RecentChat(id: "3", title: "Reading notes", updatedAt: now.addingTimeInterval(-26 * 3600))
            ],
            health: HealthGlance(
                day: WidgetPresentation.dayString(now, calendar: calendar), sleepMinutes: 352, steps: 1251,
                stepGoal: 8000, headline: "Take it easy", suggestion: "Why do I feel tired today?", mood: .sleepy))
    }
}

extension View {
    /// The rectangular Lock Screen widget's size, its edge shown so a clipped line can be told.
    fileprivate var rectangularBounds: some View {
        frame(width: 172, height: 76).background(.white.opacity(0.12), in: .rect(cornerRadius: 12))
    }
}
#endif
