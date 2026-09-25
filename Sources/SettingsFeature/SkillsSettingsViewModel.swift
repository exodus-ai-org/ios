import Foundation
import Models
import NetworkingKit
import Observation

/// The state of a list read from the computer.
public enum SettingsListState: Equatable, Sendable {
    case idle, loading, loaded
    case failed(String)
}

/// Settings → Installed skills: the desktop's Installed tab — each skill with its switch
/// (`PATCH /api/v1/skills/:slug/toggle {isActive}`). Browsing, installing and uninstalling stay on the computer.
@MainActor
@Observable
public final class SkillsSettingsViewModel {
    public private(set) var skills: [InstalledSkill] = []
    public private(set) var listState: SettingsListState = .idle
    /// A failed switch.
    public var errorMessage: String?
    /// A reload that failed while the list stays on screen.
    public private(set) var refreshError: String?
    public private(set) var pending: Set<String> = []

    private let apiClient: APIClient
    private static let path = "/api/v1/skills"

    public init(apiClient: APIClient) {
        self.apiClient = apiClient
    }

    public func load() async {
        if skills.isEmpty { listState = .loading }
        do {
            skills = try await apiClient.get("\(Self.path)/installed")
            listState = .loaded
            refreshError = nil
        } catch {
            if skills.isEmpty {
                listState = .failed(error.localizedDescription)
            } else {
                refreshError = error.localizedDescription
            }
        }
    }

    /// Flips the switch at once, writes it, then re-reads the list; a failed write puts the switch back.
    @discardableResult
    public func setActive(_ slug: String, _ active: Bool) -> Task<Void, Never>? {
        guard let index = skills.firstIndex(where: { $0.slug == slug }), skills[index].isActive != active,
            !pending.contains(slug)
        else { return nil }
        skills[index].isActive = active
        errorMessage = nil
        pending.insert(slug)
        return Task {
            defer { pending.remove(slug) }
            do {
                try await apiClient.patch("\(Self.path)/\(slug)/toggle", body: ActiveFlagBody(isActive: active))
            } catch {
                if let index = skills.firstIndex(where: { $0.slug == slug }) { skills[index].isActive = !active }
                let message = error.localizedDescription
                await load()
                errorMessage = message
                return
            }
            await load()
        }
    }
}
