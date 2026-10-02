// Sources/HealthFeature/Trends/DayRecordStore.swift
import Foundation

/// Day records by day, so paging the calendar back and forth reads Apple Health once per day it shows. Today is never
/// kept: it is still going on.
@MainActor
final class DayRecordStore {
    private let builder: SnapshotBuilder
    private let calendar: Calendar
    private let now: @Sendable () -> Date
    private var kept: [Date: DayRecord] = [:]

    init(builder: SnapshotBuilder, calendar: Calendar, now: @escaping @Sendable () -> Date) {
        self.builder = builder
        self.calendar = calendar
        self.now = now
    }

    /// The records of the days `first` through `last` that have begun, by day; days to come have none. What is not
    /// kept yet (and today) is read in one go.
    func records(from first: Date, through last: Date) async throws -> [Date: DayRecord] {
        let today = calendar.startOfDay(for: now())
        let days = builder.days(from: first, through: min(calendar.startOfDay(for: last), today))
        let missing = days.filter { $0 == today || kept[$0] == nil }
        var out: [Date: DayRecord] = [:]
        if let from = missing.first, let to = missing.last {
            for record in try await builder.records(from: from, through: to, now: now()) {
                out[record.day] = record
                if record.day < today { kept[record.day] = record }
            }
        }
        for day in days where out[day] == nil { out[day] = kept[day] }
        return out
    }

    /// A whole day, built as the home builds today: what the day sheet sends with a question.
    func snapshot(for day: Date, locale: String) async throws -> HealthDay {
        try await builder.snapshot(for: day, now: now(), locale: locale)
    }
}
