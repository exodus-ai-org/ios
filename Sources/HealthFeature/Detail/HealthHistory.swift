// Sources/HealthFeature/Detail/HealthHistory.swift
import Foundation
import Models

struct DayPoint: Identifiable, Equatable {
    let day: Date
    let value: Double
    var id: Date { day }
}

/// What a detail page draws. Each category fills only its own fields.
struct HealthHistoryData: Equatable {
    var nights: [DayPoint] = []
    var lastNight: SleepNight?
    var hourlySteps: [DayPoint] = []
    var dailySteps: [DayPoint] = []
    var hrv: [DayPoint] = []
    var restingHr: [DayPoint] = []
    var respRate: [DayPoint] = []
    var weights: [DayPoint] = []
    var moods: [MoodSample] = []
    var workouts: [WorkoutSample] = []
    var waterCups = 0
}

struct HealthHistoryLoader {
    let source: any HealthDataSource
    let calendar: Calendar

    func load(_ category: HealthCategory, now: Date) async throws -> HealthHistoryData {
        let today = calendar.startOfDay(for: now)
        let tomorrow = calendar.date(byAdding: .day, value: 1, to: today)!
        let monthAgo = calendar.date(byAdding: .day, value: -29, to: today)!
        let weekAgo = calendar.date(byAdding: .day, value: -6, to: today)!
        func points(_ values: [DayValue]) -> [DayPoint] { values.map { DayPoint(day: $0.day, value: $0.value) } }
        var data = HealthHistoryData()
        switch category {
        case .sleep:
            let from = SleepAnalyzer.window(endingOn: monthAgo, calendar: calendar).start
            let samples = try await source.sleepSamples(from: from, to: now)
            data.lastNight = SleepAnalyzer.night(from: samples, endingOn: today, calendar: calendar)
            data.nights = (0..<30).reversed().compactMap { offset in
                let day = calendar.date(byAdding: .day, value: -offset, to: today)!
                return SleepAnalyzer.night(from: samples, endingOn: day, calendar: calendar)
                    .map { DayPoint(day: day, value: Double($0.asleepMin) / 60) }
            }
        case .activity:
            data.hourlySteps = points(try await source.hourlySums(.steps, on: today))
            data.dailySteps = points(try await source.dailySums(.steps, from: weekAgo, to: tomorrow))
            data.workouts = try await source.workouts(from: weekAgo, to: tomorrow)
        case .recovery:
            data.hrv = points(try await source.dailyAverages(.hrv, from: monthAgo, to: tomorrow))
            data.restingHr = points(try await source.dailyAverages(.restingHr, from: monthAgo, to: tomorrow))
            data.respRate = points(try await source.dailyAverages(.respRate, from: monthAgo, to: tomorrow))
        case .body:
            data.weights = points(try await source.dailyAverages(.weightKg, from: monthAgo, to: tomorrow))
            data.moods = try await source.moods(from: weekAgo, to: tomorrow)
            let water = try await source.dailySums(.waterMl, from: today, to: tomorrow).reduce(0) { $0 + $1.value }
            data.waterCups = Int(water / 250)
        }
        return data
    }
}

/// A detail page's question carries the category's last seven days instead of today's snapshot.
struct HealthHistory: Encodable, Equatable {
    struct Day: Encodable, Equatable {
        let date: String
        let values: [String: Double]
    }

    let category: String
    let days: [Day]

    static func lastWeek(_ c: HealthCategory, from data: HealthHistoryData, calendar: Calendar, now: Date) -> HealthHistory {
        let format = DateFormatter()
        format.locale = Locale(identifier: "en_US_POSIX")
        format.calendar = calendar
        format.timeZone = calendar.timeZone
        format.dateFormat = "yyyy-MM-dd"
        let today = calendar.startOfDay(for: now)
        let week = (0..<7).reversed().map { calendar.date(byAdding: .day, value: -$0, to: today)! }
        func value(_ series: [DayPoint], _ day: Date) -> Double? { series.first { calendar.isDate($0.day, inSameDayAs: day) }?.value }
        let days = week.map { day -> Day in
            var values: [String: Double] = [:]
            switch c {
            case .sleep: values["asleepHours"] = value(data.nights, day)
            case .activity: values["steps"] = value(data.dailySteps, day)
            case .recovery:
                values["hrvMs"] = value(data.hrv, day)
                values["restingHr"] = value(data.restingHr, day)
            case .body: values["weightKg"] = value(data.weights, day)
            }
            return Day(date: format.string(from: day), values: values)
        }
        return HealthHistory(category: c.rawValue, days: days)
    }
}
