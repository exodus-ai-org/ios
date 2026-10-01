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
    /// Each night by the day it ended on, for the week's attachment (stages and waking).
    var nightsByDay: [Date: SleepNight] = [:]
    var lastNight: SleepNight?
    var hourlySteps: [DayPoint] = []
    var dailySteps: [DayPoint] = []
    var dailyExercise: [DayPoint] = []
    var hrv: [DayPoint] = []
    var restingHr: [DayPoint] = []
    var respRate: [DayPoint] = []
    var weights: [DayPoint] = []
    var moods: [MoodSample] = []
    var workouts: [WorkoutSample] = []
    var dailyWaterMl: [DayPoint] = []
    /// Today's cups.
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
            for offset in (0..<30).reversed() {
                let day = calendar.date(byAdding: .day, value: -offset, to: today)!
                guard let night = SleepAnalyzer.night(from: samples, endingOn: day, calendar: calendar) else { continue }
                data.nights.append(DayPoint(day: day, value: Double(night.asleepMin) / 60))
                data.nightsByDay[day] = night
            }
        case .activity:
            data.hourlySteps = points(try await source.hourlySums(.steps, on: today))
            data.dailySteps = points(try await source.dailySums(.steps, from: weekAgo, to: tomorrow))
            data.dailyExercise = points(try await source.dailySums(.exerciseMin, from: weekAgo, to: tomorrow))
            data.workouts = try await source.workouts(from: weekAgo, to: tomorrow)
        case .recovery:
            data.hrv = points(try await source.dailyAverages(.hrv, from: monthAgo, to: tomorrow))
            data.restingHr = points(try await source.dailyAverages(.restingHr, from: monthAgo, to: tomorrow))
            data.respRate = points(try await source.dailyAverages(.respRate, from: monthAgo, to: tomorrow))
        case .body:
            data.weights = points(try await source.dailyAverages(.weightKg, from: monthAgo, to: tomorrow))
            data.moods = try await source.moods(from: weekAgo, to: tomorrow)
            data.dailyWaterMl = points(try await source.dailySums(.waterMl, from: weekAgo, to: tomorrow))
            let water = data.dailyWaterMl.filter { $0.day >= today }.reduce(0) { $0 + $1.value }
            data.waterCups = Int(water / 250)
        }
        return data
    }
}

/// A detail page's question carries the category's last seven days instead of today's snapshot: enough of each day
/// for the page's own suggested questions (how deep, when you woke, how much water, how you felt).
struct HealthHistory: Encodable, Equatable {
    struct Day: Encodable, Equatable {
        let date: String
        let values: [String: Double]
        /// Sleep: when the night ended, "HH:mm".
        var wake: String?
        /// Body: the day's last logged mood.
        var mood: MoodLabel?
    }

    let category: String
    let days: [Day]

    static func lastWeek(_ c: HealthCategory, from data: HealthHistoryData, calendar: Calendar, now: Date) -> HealthHistory {
        let format = WireDate(timeZone: calendar.timeZone)
        let today = calendar.startOfDay(for: now)
        let week = (0..<7).reversed().map { calendar.date(byAdding: .day, value: -$0, to: today)! }
        func value(_ series: [DayPoint], _ day: Date) -> Double? { series.first { calendar.isDate($0.day, inSameDayAs: day) }?.value }
        let days = week.map { day -> Day in
            var values: [String: Double] = [:]
            var wake: String?
            var mood: MoodLabel?
            switch c {
            case .sleep:
                values["asleepHours"] = value(data.nights, day)
                if let night = data.nightsByDay[day] {
                    values["deepMin"] = Double(night.deepMin)
                    values["remMin"] = Double(night.remMin)
                    values["awakeMin"] = Double(night.awakeMin)
                    wake = format.clock(night.wake)
                }
            case .activity:
                values["steps"] = value(data.dailySteps, day)
                values["exerciseMin"] = value(data.dailyExercise, day)
            case .recovery:
                values["hrvMs"] = value(data.hrv, day)
                values["restingHr"] = value(data.restingHr, day)
                values["respRate"] = value(data.respRate, day)
            case .body:
                values["weightKg"] = value(data.weights, day)
                values["waterCups"] = value(data.dailyWaterMl, day).map { ($0 / 250).rounded(.down) }
                mood = data.moods.filter { calendar.isDate($0.date, inSameDayAs: day) }.max { $0.date < $1.date }?.label
            }
            return Day(date: format.day(day), values: values, wake: wake, mood: mood)
        }
        return HealthHistory(category: c.rawValue, days: days)
    }
}
