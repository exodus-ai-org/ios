import Foundation
import Models
import NetworkingKit
import Observation

/// Settings → Backups: the Backups section of the desktop's Data Controls, without its switch — the last backup,
/// the stored backups, and Back Up Now (`POST /api/v1/backup/now`). The server records `lastBackupAt` itself; this
/// page never writes settings. Export, import and delete stay on the computer.
@MainActor
@Observable
public final class BackupSettingsViewModel {
    public enum Phase: Equatable, Sendable {
        case idle, running, succeeded
        case failed(String)
    }

    public private(set) var status: BackupStatus?
    public private(set) var backups: [BackupInfo] = []
    public private(set) var loadState: SettingsListState = .idle
    public private(set) var phase: Phase = .idle
    /// A reload that failed while the last status stays on screen.
    public private(set) var refreshError: String?

    private let apiClient: APIClient
    private static let path = "/api/v1/backup"

    public init(apiClient: APIClient) {
        self.apiClient = apiClient
    }

    public var isRunning: Bool { phase == .running }

    public func load() async {
        if status == nil { loadState = .loading }
        async let statusRequest: BackupStatus = apiClient.get("\(Self.path)/status")
        async let listRequest: [BackupInfo] = apiClient.get("\(Self.path)/list")
        do {
            let (fresh, list) = try await (statusRequest, listRequest)
            status = fresh
            backups = list
            loadState = .loaded
            refreshError = nil
        } catch {
            if status == nil {
                loadState = .failed(error.localizedDescription)
            } else {
                refreshError = error.localizedDescription
            }
        }
    }

    /// Makes a backup on the computer, then re-reads the status and list whatever the outcome: a request that
    /// timed out may still have finished there.
    @discardableResult
    public func backUpNow() -> Task<Void, Never>? {
        guard phase != .running else { return nil }
        phase = .running
        return Task {
            var outcome = Phase.succeeded
            do {
                // A dump of the whole database can outlast the default wait; the POST is never re-sent elsewhere.
                try await apiClient.post("\(Self.path)/now", body: EmptyBody(), timeout: 300)
            } catch {
                outcome = .failed(error.localizedDescription)
            }
            await load()
            phase = outcome
        }
    }

    private struct EmptyBody: Encodable {}
}
