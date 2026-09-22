import Foundation
import Testing

@testable import ChatFeature

@Suite("RecentTimestamp")
struct RecentTimestampTests {
    /// UTC and a fixed locale, so the formatted strings are the same wherever this runs.
    private static let calendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        return calendar
    }()
    private static let locale = Locale(identifier: "en_US_POSIX")

    private func date(_ iso8601: String) -> Date {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter.date(from: iso8601) ?? {
            let plain = ISO8601DateFormatter()
            plain.formatOptions = [.withInternetDateTime]
            return plain.date(from: iso8601)!
        }()
    }

    private func format(_ iso8601: String, now: String) -> String? {
        RecentTimestamp.format(
            iso8601, now: date(now), calendar: Self.calendar, locale: Self.locale)
    }

    /// `en_US_POSIX`'s `.shortened` time style separates the hour from AM/PM with U+202F (narrow
    /// no-break space), not a plain space — matching that, not a visually-identical literal, is
    /// what keeps this comparable at all.
    private func time(_ value: String) -> String {
        value.replacingOccurrences(of: " ", with: "\u{202F}")
    }

    @Test("today shows the time, not a date")
    func today() throws {
        let result = try #require(
            format("2026-09-22T09:15:00.000Z", now: "2026-09-22T18:00:00.000Z"))
        #expect(result == time("9:15 AM"))
    }

    @Test("earlier today, right at midnight, still reads as today")
    func todayAtTheStartOfTheDay() throws {
        let result = try #require(
            format("2026-09-22T00:00:01.000Z", now: "2026-09-22T23:59:00.000Z"))
        #expect(result == time("12:00 AM"))
    }

    @Test("yesterday shows a weekday, not the time or a date")
    func yesterday() throws {
        let result = try #require(
            format("2026-09-21T23:59:00.000Z", now: "2026-09-22T00:30:00.000Z"))
        #expect(result == "Mon")
    }

    @Test("five days ago is still a weekday")
    func fiveDaysAgo() throws {
        let result = try #require(
            format("2026-09-17T12:00:00.000Z", now: "2026-09-22T12:00:00.000Z"))
        #expect(result == "Thu")
    }

    @Test("six days ago is a date, not a weekday")
    func sixDaysAgoIsADate() throws {
        let result = try #require(
            format("2026-09-16T12:00:00.000Z", now: "2026-09-22T12:00:00.000Z"))
        #expect(result == "9/16/2026")
    }

    @Test("a year ago is a plain date")
    func aYearAgo() throws {
        let result = try #require(
            format("2025-01-05T12:00:00.000Z", now: "2026-09-22T12:00:00.000Z"))
        #expect(result == "1/5/2025")
    }

    @Test("a clock-skewed timestamp a few minutes in the future still reads as today")
    func slightlyInTheFuture() throws {
        let result = try #require(
            format("2026-09-22T12:05:00.000Z", now: "2026-09-22T12:00:00.000Z"))
        #expect(result == time("12:05 PM"))
    }

    @Test("a timestamp days in the future falls back to a date, not a wrong weekday")
    func daysInTheFuture() throws {
        let result = try #require(
            format("2026-09-25T12:00:00.000Z", now: "2026-09-22T12:00:00.000Z"))
        #expect(result == "9/25/2026")
    }

    @Test("a createdAt with no fractional seconds parses the same way")
    func noFractionalSeconds() throws {
        let result = try #require(
            format("2026-09-22T09:15:00Z", now: "2026-09-22T18:00:00.000Z"))
        #expect(result == time("9:15 AM"))
    }

    @Test("an unparseable timestamp is nil, not a crash")
    func unparseable() {
        #expect(format("not a date", now: "2026-09-22T12:00:00.000Z") == nil)
    }
}
