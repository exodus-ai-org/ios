import Foundation
import Models
import NetworkingKit
import Observation

/// The one way Settings pages read and write the computer's `settings` row. Every write re-reads the row first and
/// posts only the columns it changes, with `id` and `lastBackupAt` echoed from that fresh read: the server replaces
/// a column whole and nulls `lastBackupAt` unless it is sent back, and the desktop may have saved since the page
/// loaded (last write wins per column, as on the desktop).
@MainActor
@Observable
public final class SettingsStore {
    /// The row as last read from the server.
    public private(set) var snapshot: SettingsSnapshot?

    private let apiClient: APIClient
    private static let path = "/api/v1/settings"

    public init(apiClient: APIClient) {
        self.apiClient = apiClient
    }

    /// Where the pages built on this store report their own warnings.
    public var reporter: LogReporter? { apiClient.reporter }

    @discardableResult
    public func load() async throws -> SettingsSnapshot {
        let fresh: SettingsSnapshot = try await apiClient.get(Self.path)
        snapshot = fresh
        return fresh
    }

    /// `load()`, failing with `SettingsStoreError.unreadableColumn` when one of `columns` is stored in a shape this
    /// app cannot read: a page shows that instead of an empty form it would then save over the real value.
    @discardableResult
    public func load(requiring columns: [String]) async throws -> SettingsSnapshot {
        let fresh = try await load()
        try Self.requireReadable(columns, in: fresh)
        return fresh
    }

    /// Writes `value` as the whole of `column`.
    public func patch<Value>(_ column: SettingsColumn<Value>, value: Value) async throws {
        try await patch([column.assigning(value)])
    }

    /// Writes several whole columns in one request, so they change together.
    public func patch(_ columns: [SettingsColumnValue]) async throws {
        let fresh = try await load()
        try await write(columns, over: fresh)
    }

    /// Read-modify-write of one column: `modify` edits the column as it is on the server now (or its empty value
    /// when the row has none), and the result is written back. Returns what was written.
    @discardableResult
    public func update<Value>(_ column: SettingsColumn<Value>, _ modify: (inout Value) -> Void) async throws -> Value {
        let fresh = try await load()
        var value = fresh[keyPath: column.keyPath] ?? column.emptyValue
        modify(&value)
        try await write([column.assigning(value)], over: fresh)
        return value
    }

    /// Read-modify-write of several columns in one request: `build` sees the row as the server holds it now and
    /// returns the columns to write. Returns the row as written.
    @discardableResult
    public func update(_ build: (SettingsSnapshot) throws -> [SettingsColumnValue]) async throws -> SettingsSnapshot {
        let fresh = try await load()
        let columns = try build(fresh)
        return try await write(columns, over: fresh)
    }

    @discardableResult
    private func write(_ columns: [SettingsColumnValue], over fresh: SettingsSnapshot) async throws -> SettingsSnapshot {
        try Self.requireReadable(columns.map(\.name), in: fresh)
        let body = SettingsWriteBody(
            id: fresh.id, lastBackupAt: fresh.lastBackupAt, columns: columns.map { ($0.name, $0.value) })
        try await apiClient.post(Self.path, body: body)
        var written = fresh
        for column in columns { column.apply(&written) }
        // A key typed here is sent once and then held only as the computer would show it.
        written.providers = written.providers?.maskingKeys()
        snapshot = written
        return written
    }

    private static func requireReadable(_ columns: [String], in snapshot: SettingsSnapshot) throws {
        if let name = columns.first(where: snapshot.unreadableColumns.contains) {
            throw SettingsStoreError.unreadableColumn(name)
        }
    }
}

public enum SettingsStoreError: LocalizedError, Equatable {
    /// The column is in the row but not in a shape this app reads; writing it would replace the real value.
    case unreadableColumn(String)

    public var errorDescription: String? {
        switch self {
        case .unreadableColumn:
            String(
                localized: "ios:settings.error.unreadableColumn",
                defaultValue:
                    "These settings are stored on your computer in a form this app can't read, so they were left unchanged. Edit them on your computer.",
                comment: "Error on a Settings page whose stored settings the phone cannot decode; nothing is written.")
        }
    }
}
