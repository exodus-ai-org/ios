import Foundation

/// The rules a widget entry is drawn by, apart from drawing: the greeting's period, which health may be shown, and
/// when entries fall.
public enum WidgetPresentation {
    public enum Period: Sendable { case morning, afternoon, evening }

    public static func period(at date: Date, calendar: Calendar) -> Period {
        switch calendar.component(.hour, from: date) {
        case 5..<12: .morning
        case 12..<18: .afternoon
        default: .evening
        }
    }

    public static func clockHour(at date: Date, calendar: Calendar) -> Double {
        let parts = calendar.dateComponents([.hour, .minute], from: date)
        return Double(parts.hour ?? 0) + Double(parts.minute ?? 0) / 60
    }

    public static func dayString(_ date: Date, calendar: Calendar) -> String {
        let parts = calendar.dateComponents([.year, .month, .day], from: date)
        return String(format: "%04d-%02d-%02d", parts.year ?? 0, parts.month ?? 0, parts.day ?? 0)
    }

    /// The glance, on its own day only: never yesterday's numbers as today's.
    public static func health(of snapshot: WidgetSnapshot, at date: Date, calendar: Calendar) -> HealthGlance? {
        guard let health = snapshot.health, health.day == dayString(date, calendar: calendar) else { return nil }
        return health
    }

    /// Now, then each of the next eleven hours on the hour: the sky moves with the clock.
    public static func entryDates(from now: Date, calendar: Calendar) -> [Date] {
        guard let hour = calendar.dateInterval(of: .hour, for: now)?.start else { return [now] }
        return [now] + (1..<12).compactMap { calendar.date(byAdding: .hour, value: $0, to: hour) }
    }
}
