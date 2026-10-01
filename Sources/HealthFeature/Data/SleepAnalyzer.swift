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
/// minutes (core, deep, REM), else the one with the most sleep, else the first by name. Within that source, overlapping
/// samples are swept onto one timeline so each minute counts once, the deepest stage winning.
public enum SleepAnalyzer {
    /// 18:00 the day before to 12:00 on the day, on the calendar's wall clock (a DST night is 23 or 25 hours long).
    public static func window(endingOn day: Date, calendar: Calendar) -> DateInterval {
        let start = calendar.startOfDay(for: day)
        let yesterday = calendar.date(byAdding: .day, value: -1, to: start)!
        let from = calendar.date(bySettingHour: 18, minute: 0, second: 0, of: yesterday)!
        let to = calendar.date(bySettingHour: 12, minute: 0, second: 0, of: start)!
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
        let bySource = Dictionary(grouping: clipped, by: \.source).map { (source: $0.key, segments: sweep($0.value)) }
        func minutes(_ list: [SleepSample], _ include: (SleepStage) -> Bool) -> Int {
            Int(list.filter { include($0.stage) }.reduce(0) { $0 + $1.end.timeIntervalSince($1.start) } / 60)
        }
        let staged: (SleepStage) -> Bool = { $0 == .core || $0 == .deep || $0 == .rem }
        guard
            let chosen = bySource.max(by: { a, b in
                let (sa, sb) = (minutes(a.segments, staged), minutes(b.segments, staged))
                if sa != sb { return sa < sb }
                let (ta, tb) = (minutes(a.segments, \.isAsleep), minutes(b.segments, \.isAsleep))
                return ta != tb ? ta < tb : a.source > b.source
            })?.segments
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
            stages: chosen)
    }

    /// Lays one source's samples on a single timeline: each instant takes the deepest stage covering it, so an
    /// `unspecified` block under staged samples, or awake inside a sleep block, is not counted twice.
    private static func sweep(_ samples: [SleepSample]) -> [SleepSample] {
        func rank(_ stage: SleepStage) -> Int {
            switch stage {
            case .deep: 4
            case .rem: 3
            case .core: 2
            case .unspecified: 1
            case .awake: 0
            }
        }
        let edges = Set(samples.flatMap { [$0.start, $0.end] }).sorted()
        var result: [SleepSample] = []
        for (from, to) in zip(edges, edges.dropFirst()) {
            let covering = samples.filter { $0.start <= from && $0.end >= to }
            guard let top = covering.max(by: { rank($0.stage) < rank($1.stage) }) else { continue }
            if let last = result.last, last.stage == top.stage, last.end == from {
                result[result.count - 1].end = to
            } else {
                result.append(SleepSample(start: from, end: to, stage: top.stage, source: top.source))
            }
        }
        return result
    }
}
