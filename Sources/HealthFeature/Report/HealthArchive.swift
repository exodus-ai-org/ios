// Sources/HealthFeature/Report/HealthArchive.swift
import Foundation
import Models

/// A day's note as it was written: the note, the numbers it was written from, and when.
public struct ArchivedDay: Codable, Equatable, Sendable {
    public var snapshot: HealthSnapshot
    public var summary: HealthSummary
    public var generatedAt: Date

    public init(snapshot: HealthSnapshot, summary: HealthSummary, generatedAt: Date) {
        self.snapshot = snapshot
        self.summary = summary
        self.generatedAt = generatedAt
    }

    public init(_ report: CachedReport) {
        self.init(snapshot: report.snapshot, summary: report.summary, generatedAt: report.generatedAt)
    }
}

/// Every daily note, one file per day (`archive/2026/10/01.json`), so a past day can be read again as it was. On
/// this phone only: complete file protection, and the folder and each file excluded from backups (App Review allows
/// no health data in iCloud). A note written again the same day replaces that day's file. A later phase files its
/// period reports under `archive/reports/`, so clearing the archive clears them too.
public struct HealthArchive: Sendable {
    public let directory: URL

    public init(directory: URL) { self.directory = directory }

    /// "2026-10-01" → `2026/10/01.json`; anything that is not a wire day has no file.
    func fileURL(day: String) -> URL? {
        let parts = day.split(separator: "-", omittingEmptySubsequences: false)
        guard parts.count == 3, parts.map(\.count) == [4, 2, 2],
            parts.allSatisfy({ $0.allSatisfy { $0.isASCII && $0.isNumber } })
        else { return nil }
        return directory.appending(path: "\(parts[0])/\(parts[1])/\(parts[2]).json")
    }

    public func write(_ entry: ArchivedDay) throws {
        guard let url = fileURL(day: entry.snapshot.date) else { throw CocoaError(.fileWriteInvalidFileName) }
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Self.excludeFromBackup(directory)
        try HealthWire.encoder().encode(entry).write(to: url, options: [.atomic, .completeFileProtection])
        try Self.excludeFromBackup(url)
    }

    /// The note kept for a day; nil when there is none, or its file can't be read — a corrupt file is no note.
    public func read(day: String) -> ArchivedDay? {
        guard let url = fileURL(day: day), let data = try? Data(contentsOf: url),
            let entry = try? JSONDecoder().decode(ArchivedDay.self, from: data), entry.snapshot.date == day
        else { return nil }
        return entry
    }

    /// Deletes every kept note (and every report). Nothing kept is fine.
    public func clear() throws {
        guard FileManager.default.fileExists(atPath: directory.path(percentEncoded: false)) else { return }
        try FileManager.default.removeItem(at: directory)
    }

    private static func excludeFromBackup(_ url: URL) throws {
        var url = url
        var values = URLResourceValues()
        values.isExcludedFromBackup = true
        try url.setResourceValues(values)
    }
}
