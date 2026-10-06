// Tests/HealthFeatureTests/StubPeriodReports.swift
import Foundation

@testable import HealthFeature

/// The computer, for period reports: records what it was asked, can fail, and can hold an answer until released.
actor StubPeriodReports: PeriodReportService {
    var asked: [PeriodReportRequest] = []
    var error: Error?
    var gated = false
    private var held: [CheckedContinuation<Void, Never>] = []

    /// The first day of each period asked about, in order.
    var starts: [String] { asked.map(\.period.start) }

    func fail(_ error: Error?) { self.error = error }
    func hold() { gated = true }

    func release() {
        gated = false
        let waiting = held
        held = []
        waiting.forEach { $0.resume() }
    }

    func report(for request: PeriodReportRequest) async throws -> PeriodReportReply {
        asked.append(request)
        if gated { await withCheckedContinuation { held.append($0) } }
        if let error { throw error }
        return PeriodReportReply(
            headline: "Report \(request.period.start)", insights: [.init(category: "sleep", title: "t")])
    }
}
