import Foundation

/// The wire's dates: "yyyy-MM-dd" and "HH:mm" in the calendar's time zone, Gregorian and Western digits whatever the
/// user reads. Format styles are values, so one is made per builder or attachment, not per date.
struct WireDate: Sendable {
    private let dayStyle: Date.ISO8601FormatStyle
    private let clockStyle: Date.VerbatimFormatStyle

    init(timeZone: TimeZone) {
        dayStyle = Date.ISO8601FormatStyle(timeZone: timeZone).year().month().day()
        var gregorian = Calendar(identifier: .gregorian)
        gregorian.timeZone = timeZone
        clockStyle = Date.VerbatimFormatStyle(
            format: "\(hour: .twoDigits(clock: .twentyFourHour, hourCycle: .zeroBased)):\(minute: .twoDigits)",
            locale: Locale(identifier: "en_US_POSIX"), timeZone: timeZone, calendar: gregorian)
    }

    func day(_ date: Date) -> String { dayStyle.format(date) }
    func clock(_ date: Date) -> String { clockStyle.format(date) }
}
