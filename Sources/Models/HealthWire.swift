import Foundation

/// The Health workspace's wire types: the day's aggregated snapshot the phone sends to `/api/v1/health/summary` and
/// the report that comes back. The desktop's `packages/shared/src/types/health.ts`, held to the same JSON.

/// Which Ody the day calls for. The first two are about the app, the rest about the body.
public enum OdyMood: String, Codable, CaseIterable, Equatable, Sendable {
    case permission, noData, tired, recovering, active, rested, calm, happy
}

/// Recovery relative to the user's own 30-day baseline — never a medical judgement.
public enum RecoveryLevel: String, Codable, Equatable, Sendable {
    case good, fair, low
}

/// HealthKit's State of Mind valence, as a label.
public enum MoodLabel: String, Codable, Equatable, Sendable {
    case veryUnpleasant, unpleasant, slightlyUnpleasant, neutral, slightlyPleasant, pleasant, veryPleasant

    public var isPleasant: Bool { self == .slightlyPleasant || self == .pleasant || self == .veryPleasant }
}

public struct HealthSnapshot: Codable, Equatable, Sendable {
    public var date: String
    public var localTime: String
    public var locale: String
    public var sleep: Sleep?
    public var activity: Activity?
    public var recovery: Recovery?
    public var body: Body?
    public var odyState: OdyMood

    public init(
        date: String, localTime: String, locale: String, sleep: Sleep?, activity: Activity?, recovery: Recovery?,
        body: Body?, odyState: OdyMood
    ) {
        self.date = date
        self.localTime = localTime
        self.locale = locale
        self.sleep = sleep
        self.activity = activity
        self.recovery = recovery
        self.body = body
        self.odyState = odyState
    }

    public struct Sleep: Codable, Equatable, Sendable {
        public var asleepMin: Int
        public var baselineMin: Int?
        public var deepMin: Int
        public var coreMin: Int
        public var remMin: Int
        public var awakeMin: Int
        public var bedtime: String
        public var wake: String

        public init(
            asleepMin: Int, baselineMin: Int?, deepMin: Int, coreMin: Int, remMin: Int, awakeMin: Int,
            bedtime: String, wake: String
        ) {
            self.asleepMin = asleepMin
            self.baselineMin = baselineMin
            self.deepMin = deepMin
            self.coreMin = coreMin
            self.remMin = remMin
            self.awakeMin = awakeMin
            self.bedtime = bedtime
            self.wake = wake
        }
    }

    public struct Activity: Codable, Equatable, Sendable {
        public var steps: Int
        public var stepGoal: Int
        public var activeKcal: Int
        public var kcalGoal: Int?
        public var exerciseMin: Int
        public var standHours: Int
        public var workouts: [Workout]

        public init(
            steps: Int, stepGoal: Int, activeKcal: Int, kcalGoal: Int?, exerciseMin: Int, standHours: Int,
            workouts: [Workout]
        ) {
            self.steps = steps
            self.stepGoal = stepGoal
            self.activeKcal = activeKcal
            self.kcalGoal = kcalGoal
            self.exerciseMin = exerciseMin
            self.standHours = standHours
            self.workouts = workouts
        }

        public var reachedGoal: Bool { steps >= stepGoal }
    }

    public struct Workout: Codable, Equatable, Sendable {
        public var type: String
        public var minutes: Int
        public var kcal: Int?

        public init(type: String, minutes: Int, kcal: Int?) {
            self.type = type
            self.minutes = minutes
            self.kcal = kcal
        }
    }

    public struct Recovery: Codable, Equatable, Sendable {
        public var level: RecoveryLevel?
        public var hrvMs: Double?
        public var hrvBaselineMs: Double?
        public var restingHr: Double?
        public var restingHrBaseline: Double?
        public var respRate: Double?

        public init(
            level: RecoveryLevel?, hrvMs: Double?, hrvBaselineMs: Double?, restingHr: Double?,
            restingHrBaseline: Double?, respRate: Double?
        ) {
            self.level = level
            self.hrvMs = hrvMs
            self.hrvBaselineMs = hrvBaselineMs
            self.restingHr = restingHr
            self.restingHrBaseline = restingHrBaseline
            self.respRate = respRate
        }
    }

    public struct Body: Codable, Equatable, Sendable {
        public var waterCups: Int
        public var weightKg: Double?
        public var weightTrend30d: Double?
        public var mood: MoodLabel?

        public init(waterCups: Int, weightKg: Double?, weightTrend30d: Double?, mood: MoodLabel?) {
            self.waterCups = waterCups
            self.weightKg = weightKg
            self.weightTrend30d = weightTrend30d
            self.mood = mood
        }
    }
}

public struct HealthSummary: Codable, Equatable, Sendable {
    public var headline: String
    /// The headline's key phrase, an exact substring of it, coloured as `headlineCategory`.
    public var headlineHighlight: String?
    public var headlineCategory: String?
    /// The note as short stories, most important first. Nil in reports from desktops (and caches) that predate them,
    /// which show `summary` instead.
    public var insights: [Insight]?
    /// One everyday habit to try today.
    public var nudge: String?
    /// The note as Markdown; the desktop still fills it in for phones that don't read `insights`.
    public var summary: String
    public var categories: Categories
    public var memorySuggestion: MemorySuggestion?

    public init(
        headline: String, summary: String, categories: Categories, memorySuggestion: MemorySuggestion?,
        headlineHighlight: String? = nil, headlineCategory: String? = nil, insights: [Insight]? = nil,
        nudge: String? = nil
    ) {
        self.headline = headline
        self.headlineHighlight = headlineHighlight
        self.headlineCategory = headlineCategory
        self.insights = insights
        self.nudge = nudge
        self.summary = summary
        self.categories = categories
        self.memorySuggestion = memorySuggestion
    }

    /// One sentence about one category. `category` stays a string so a category this app doesn't know yet costs
    /// that one insight, not the whole report.
    public struct Insight: Codable, Equatable, Sendable {
        public var category: String
        public var text: String
        /// Exact substrings of `text`, coloured in the category's colour.
        public var highlights: [String]
        public var stat: Stat?

        public init(category: String, text: String, highlights: [String] = [], stat: Stat? = nil) {
            self.category = category
            self.text = text
            self.highlights = highlights
            self.stat = stat
        }

        public init(from decoder: any Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            category = try c.decode(String.self, forKey: .category)
            text = try c.decode(String.self, forKey: .text)
            highlights = try c.decodeIfPresent([String].self, forKey: .highlights) ?? []
            stat = try c.decodeIfPresent(Stat.self, forKey: .stat)
        }
    }

    /// The insight's one number, shown big: "6:12" "hours", "usual 7:05".
    public struct Stat: Codable, Equatable, Sendable {
        public var value: String
        public var unit: String
        public var caption: String?

        public init(value: String, unit: String, caption: String? = nil) {
            self.value = value
            self.unit = unit
            self.caption = caption
        }
    }

    public struct Categories: Codable, Equatable, Sendable {
        public var sleep: String?
        public var activity: String?
        public var recovery: String?
        public var body: String?

        public init(sleep: String?, activity: String?, recovery: String?, body: String?) {
            self.sleep = sleep
            self.activity = activity
            self.recovery = recovery
            self.body = body
        }
    }

    /// Posted as-is to `/api/v1/memory` when the user taps Remember.
    public struct MemorySuggestion: Codable, Equatable, Sendable {
        public var section: String
        public var key: String
        public var summary: String

        public init(section: String, key: String, summary: String) {
            self.section = section
            self.key = key
            self.summary = summary
        }
    }
}

public enum HealthWire {
    /// Sorted keys, so a snapshot always reads the same (cache comparisons, the block sent to Chat).
    public static func encoder() -> JSONEncoder {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        return encoder
    }
}
