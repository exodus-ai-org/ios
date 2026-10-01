// Sources/HealthFeature/Data/SleepAnalyzer.swift
import Foundation

/// One night of sleep: the minutes in each stage, and when it began and ended.
public struct SleepNight: Sendable, Equatable {
    public var asleepMin: Int
    public var deepMin: Int
    public var coreMin: Int
    public var remMin: Int
    public var awakeMin: Int
    public var bedtime: Date
    public var wake: Date
    /// The chosen source's samples, clipped to the window and in order (the hero's track and the hypnogram).
    public var stages: [SleepSample]
}

/// Turns sleep samples into the night that ended on a day. "Last night" runs from 18:00 the day before to 12:00 on
/// the day. When a Watch and an iPhone both recorded the night, only one source is read — the one with the most staged
/// minutes (core, deep, REM), else the one with the most sleep — so overlapping minutes are not counted twice.
public enum SleepAnalyzer {
    public static func window(endingOn day: Date, calendar: Calendar) -> DateInterval {
        let start = calendar.startOfDay(for: day)
        let from = calendar.date(byAdding: .hour, value: -6, to: start)!
        let to = calendar.date(byAdding: .hour, value: 12, to: start)!
        return DateInterval(start: from, end: to)
    }

    public static func night(from samples: [SleepSample], endingOn day: Date, calendar: Calendar) -> SleepNight? {
        let window = window(endingOn: day, calendar: calendar)
        let clipped: [SleepSample] = samples.compactMap { sample in
            let start = max(sample.start, window.start)
            let end = min(sample.end, window.end)
            guard end > start else { return nil }
            return SleepSample(start: start, end: end, stage: sample.stage, source: sample.source)
        }
        let bySource = Dictionary(grouping: clipped, by: \.source)
        func minutes(_ list: [SleepSample], _ include: (SleepStage) -> Bool) -> Int {
            Int(list.filter { include($0.stage) }.reduce(0) { $0 + $1.end.timeIntervalSince($1.start) } / 60)
        }
        let staged: (SleepStage) -> Bool = { $0 == .core || $0 == .deep || $0 == .rem }
        guard
            let chosen = bySource.values.max(by: { a, b in
                let (sa, sb) = (minutes(a, staged), minutes(b, staged))
                return sa != sb ? sa < sb : minutes(a, \.isAsleep) < minutes(b, \.isAsleep)
            })
        else { return nil }
        let asleep = chosen.filter(\.stage.isAsleep)
        guard let bedtime = asleep.map(\.start).min(), let wake = asleep.map(\.end).max() else { return nil }
        return SleepNight(
            asleepMin: minutes(chosen, \.isAsleep),
            deepMin: minutes(chosen) { $0 == .deep },
            coreMin: minutes(chosen) { $0 == .core || $0 == .unspecified },
            remMin: minutes(chosen) { $0 == .rem },
            awakeMin: minutes(chosen) { $0 == .awake },
            bedtime: bedtime,
            wake: wake,
            stages: chosen.sorted { $0.start < $1.start })
    }
}
