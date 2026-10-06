// Sources/HealthFeature/Report/PeriodReportStore.swift
import Foundation
import Models

/// The period reports kept on this phone, one file per period (`archive/reports/2026-W40.json`, `2026-09.json`,
/// `2026-Q3.json`, `2026.json`), inside the archive so Clear archive deletes them with the notes. Same protection as
/// the notes: complete file protection, never backed up. A corrupt file is no report.
public struct PeriodReportStore: Sendable {
    public let directory: URL

    public init(directory: URL) { self.directory = directory }

    /// Only a report name has a file — never a path.
    func fileURL(id: String) -> URL? {
        guard id.wholeMatch(of: /\d{4}(?:-W\d{2}|-\d{2}|-Q[1-4])?/) != nil else { return nil }
        return directory.appending(path: "\(id).json")
    }

    public func write(_ report: PeriodReport, id: String) throws {
        guard let url = fileURL(id: id) else { throw CocoaError(.fileWriteInvalidFileName) }
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try Self.excludeFromBackup(directory.deletingLastPathComponent())
        try Self.excludeFromBackup(directory)
        try HealthWire.encoder().encode(report).write(to: url, options: [.atomic, .completeFileProtection])
        try Self.excludeFromBackup(url)
    }

    public func read(id: String) -> PeriodReport? {
        guard let url = fileURL(id: id), let data = try? Data(contentsOf: url) else { return nil }
        return try? JSONDecoder().decode(PeriodReport.self, from: data)
    }

    private static func excludeFromBackup(_ url: URL) throws {
        var url = url
        var values = URLResourceValues()
        values.isExcludedFromBackup = true
        try url.setResourceValues(values)
    }
}

extension HealthArchive {
    /// The period reports, in `archive/reports/`.
    public var reports: PeriodReportStore {
        PeriodReportStore(directory: directory.appending(path: "reports", directoryHint: .isDirectory))
    }
}
