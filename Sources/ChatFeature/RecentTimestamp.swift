import Foundation

/// The compact time shown at the trailing edge of a Recents row, the way Mail and Messages format
/// a conversation list: today shows the time, the last few days a weekday, anything older a short
/// date. `now` and `calendar` are parameters so a test can pin them; the view always calls with the
/// defaults.
enum RecentTimestamp {
    static func format(
        _ iso8601: String, now: Date = .now, calendar: Calendar = .current, locale: Locale = .current
    ) -> String? {
        guard let date = parseDate(iso8601) else { return nil }
        return format(date, now: now, calendar: calendar, locale: locale)
    }

    static func format(
        _ date: Date, now: Date = .now, calendar: Calendar = .current, locale: Locale = .current
    ) -> String {
        if calendar.isDate(date, inSameDayAs: now) {
            return date.formatted(dateStyle(time: .shortened, calendar: calendar, locale: locale))
        }
        let today = calendar.startOfDay(for: now)
        let day = calendar.startOfDay(for: date)
        if let daysAgo = calendar.dateComponents([.day], from: day, to: today).day,
            daysAgo > 0, daysAgo < 6
        {
            // `DateStyle` has no weekday-only case, so this one is built up from an empty style
            // instead of the `date:`/`time:` initializer the other two branches use.
            return date.formatted(
                Date.FormatStyle(locale: locale, calendar: calendar, timeZone: calendar.timeZone)
                    .weekday(.abbreviated))
        }
        // Also where a clock-skewed `createdAt` in the future lands: neither "today" nor a small,
        // positive "days ago", so it falls through to a plain date rather than a wrong weekday.
        return date.formatted(dateStyle(date: .numeric, calendar: calendar, locale: locale))
    }

    /// `Date.FormatStyle`'s own `timeZone` defaults to the system zone regardless of what
    /// `calendar` says, so every style is built with the same zone `isDate(_:inSameDayAs:)`/`startOfDay`
    /// already used above — otherwise the boundary decision and the rendered string could
    /// disagree near a day's edge, or (a test pinning a zone other than the system's) not agree
    /// at all.
    private static func dateStyle(
        date: Date.FormatStyle.DateStyle = .omitted, time: Date.FormatStyle.TimeStyle = .omitted,
        calendar: Calendar, locale: Locale
    ) -> Date.FormatStyle {
        Date.FormatStyle(
            date: date, time: time, locale: locale, calendar: calendar, timeZone: calendar.timeZone)
    }

    private static func parseDate(_ iso8601: String) -> Date? {
        let withFraction = ISO8601DateFormatter()
        withFraction.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = withFraction.date(from: iso8601) { return date }
        let plain = ISO8601DateFormatter()
        plain.formatOptions = [.withInternetDateTime]
        return plain.date(from: iso8601)
    }
}
