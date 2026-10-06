import Foundation
import Models
import NetworkingKit

/// Writes the day's report from its snapshot. The real one asks the computer (`POST /api/v1/health/summary`).
public protocol HealthSummaryService: Sendable {
    func summary(for snapshot: HealthSnapshot) async throws -> HealthSummary
}

public struct LiveHealthSummaryService: HealthSummaryService {
    let apiClient: APIClient

    public init(apiClient: APIClient) { self.apiClient = apiClient }

    public func summary(for snapshot: HealthSnapshot) async throws -> HealthSummary {
        // A memory read and a model call (a slow local model can take a while): give it longer than a plain request.
        try await apiClient.post("/api/v1/health/summary", body: snapshot, timeout: 120)
    }
}

/// Saves a suggestion the user chose to keep, through the memory API every other client uses.
public protocol MemoryWriter: Sendable {
    func remember(_ suggestion: HealthSummary.MemorySuggestion) async throws
}

public struct LiveMemoryWriter: MemoryWriter {
    let apiClient: APIClient

    public init(apiClient: APIClient) { self.apiClient = apiClient }

    public func remember(_ suggestion: HealthSummary.MemorySuggestion) async throws {
        try await apiClient.post("/api/v1/memory", body: suggestion)
    }
}

/// Writes a finished period's report. The real one asks the computer (`POST /api/v1/health/period-report`).
public protocol PeriodReportService: Sendable {
    func report(for request: PeriodReportRequest) async throws -> PeriodReportReply
}

public struct LivePeriodReportService: PeriodReportService {
    let apiClient: APIClient

    public init(apiClient: APIClient) { self.apiClient = apiClient }

    public func report(for request: PeriodReportRequest) async throws -> PeriodReportReply {
        // A memory read and a longer prompt than the day's note: give it longer still.
        try await apiClient.post("/api/v1/health/period-report", body: request, timeout: 180)
    }
}
