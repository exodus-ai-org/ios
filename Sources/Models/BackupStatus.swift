import Foundation

/// `GET /api/v1/backup/status`: whether the computer's daily backup is on, and when the last backup was made.
public struct BackupStatus: Decodable, Equatable, Sendable {
    public var autoBackup: Bool
    /// ISO 8601.
    public var lastBackupAt: String?

    public init(autoBackup: Bool = true, lastBackupAt: String? = nil) {
        self.autoBackup = autoBackup
        self.lastBackupAt = lastBackupAt
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: AnyCodingKey.self)
        autoBackup = c.lenient(Bool.self, forKey: "autoBackup") ?? true
        lastBackupAt = c.lenient(String.self, forKey: "lastBackupAt")
    }

    public var lastBackupDate: Date? { lastBackupAt.flatMap(BackupInfo.date(from:)) }
}

/// One file of `GET /api/v1/backup/list`, newest first.
public struct BackupInfo: Decodable, Equatable, Identifiable, Sendable {
    public var name: String
    public var size: Int
    public var createdAt: String

    public var id: String { name }

    public init(name: String, size: Int, createdAt: String) {
        self.name = name
        self.size = size
        self.createdAt = createdAt
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: AnyCodingKey.self)
        name = try c.decode(String.self, forKey: "name")
        size = Int(c.lenient(Double.self, forKey: "size") ?? 0)
        createdAt = c.lenient(String.self, forKey: "createdAt") ?? ""
    }

    /// Reads `toISOString()` output, with or without fractional seconds.
    public static func date(from iso: String) -> Date? {
        (try? Date.ISO8601FormatStyle(includingFractionalSeconds: true).parse(iso))
            ?? (try? Date.ISO8601FormatStyle().parse(iso))
    }
}
