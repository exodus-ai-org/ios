import Foundation

/// `GET /api/v1/usage` (the desktop's `routes/usage.ts`): lifetime totals, tokens and cost per UTC day (oldest
/// first), and per model (most expensive first). Cost is in US dollars, as pi-ai reports it.
public struct UsageSummary: Decodable, Equatable, Sendable {
    public struct Day: Decodable, Equatable, Sendable {
        /// `YYYY-MM-DD`.
        public var date: String
        public var cost: Double
        public var tokens: Double

        public init(date: String, cost: Double = 0, tokens: Double) {
            self.date = date
            self.cost = cost
            self.tokens = tokens
        }

        public init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: AnyCodingKey.self)
            date = try c.decode(String.self, forKey: "date")
            cost = c.lenient(Double.self, forKey: "cost") ?? 0
            tokens = c.lenient(Double.self, forKey: "tokens") ?? 0
        }
    }

    public struct ModelUsage: Decodable, Equatable, Sendable, Identifiable {
        public var model: String
        public var provider: String
        public var cost: Double
        public var inputTokens: Double
        public var outputTokens: Double
        public var cacheReadTokens: Double
        public var requests: Int

        public var id: String { model }
        /// What the desktop's Top models list shows: input plus output.
        public var tokens: Double { inputTokens + outputTokens }

        public init(
            model: String, provider: String = "", cost: Double = 0, inputTokens: Double = 0,
            outputTokens: Double = 0, cacheReadTokens: Double = 0, requests: Int = 0
        ) {
            self.model = model
            self.provider = provider
            self.cost = cost
            self.inputTokens = inputTokens
            self.outputTokens = outputTokens
            self.cacheReadTokens = cacheReadTokens
            self.requests = requests
        }

        public init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: AnyCodingKey.self)
            model = c.lenient(String.self, forKey: "model") ?? "unknown"
            provider = c.lenient(String.self, forKey: "provider") ?? ""
            cost = c.lenient(Double.self, forKey: "cost") ?? 0
            inputTokens = c.lenient(Double.self, forKey: "inputTokens") ?? 0
            outputTokens = c.lenient(Double.self, forKey: "outputTokens") ?? 0
            cacheReadTokens = c.lenient(Double.self, forKey: "cacheReadTokens") ?? 0
            requests = Int(c.lenient(Double.self, forKey: "requests") ?? 0)
        }
    }

    public var totalCost: Double
    public var totalTokens: Double
    public var totalRequests: Int
    public var daily: [Day]
    public var models: [ModelUsage]

    public init(
        totalCost: Double = 0, totalTokens: Double = 0, totalRequests: Int = 0, daily: [Day] = [],
        models: [ModelUsage] = []
    ) {
        self.totalCost = totalCost
        self.totalTokens = totalTokens
        self.totalRequests = totalRequests
        self.daily = daily
        self.models = models
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: AnyCodingKey.self)
        totalCost = c.lenient(Double.self, forKey: "totalCost") ?? 0
        totalTokens = c.lenient(Double.self, forKey: "totalTokens") ?? 0
        totalRequests = Int(c.lenient(Double.self, forKey: "totalRequests") ?? 0)
        daily = c.lenient([Day].self, forKey: "daily") ?? []
        models = c.lenient([ModelUsage].self, forKey: "models") ?? []
    }

    /// Nothing has ever been sent to a model.
    public var isEmpty: Bool { totalRequests == 0 && daily.isEmpty && models.isEmpty }
}
