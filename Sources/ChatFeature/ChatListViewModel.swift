import Foundation
import Models
import NetworkingKit
import Observation

@MainActor
@Observable
public final class ChatListViewModel {
    public private(set) var chats: [ChatSummary] = []
    public private(set) var isLoading = false
    /// True when the last load failed — lets the view tell "couldn't load" from "no chats yet".
    public private(set) var loadFailed = false
    public var errorMessage: String?
    /// True once a load has FINISHED, with a result or a failure (a cancelled load does not count).
    /// Before that the empty list is "not known yet", which the view must not present as "No chats yet".
    public private(set) var hasLoaded = false

    /// Whether the view should raise its "Error" alert. When the list is empty because the load
    /// failed, the "Can't load chats" empty state already shows `errorMessage`, so an alert
    /// would only say the same thing again. The alert stays for a failed delete and for a failed
    /// reload while chats are on screen.
    public var showsErrorAlert: Bool { errorMessage != nil && !(chats.isEmpty && loadFailed) }

    private let apiClient: APIClient
    /// Chats whose DELETE succeeded. A load that started before the delete can finish after it
    /// with a list that still contains the chat; filtering here keeps it from coming back.
    private var deletedIDs: Set<String> = []

    public init(apiClient: APIClient) {
        self.apiClient = apiClient
    }

    public func load() async {
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }
        do {
            let loaded: [ChatSummary] = try await apiClient.get("/api/history")
            chats = loaded.filter { !deletedIDs.contains($0.id) }
            loadFailed = false
            hasLoaded = true
        } catch {
            // SwiftUI cancels a view's `.task` when the view goes away; that is not a failure.
            guard !Self.isCancellation(error) else { return }
            loadFailed = true
            hasLoaded = true
            errorMessage = error.localizedDescription
        }
    }

    public func delete(_ chat: ChatSummary) async {
        do {
            try await apiClient.delete("/api/chat/\(chat.id)")
            deletedIDs.insert(chat.id)
            chats.removeAll { $0.id == chat.id }
        } catch {
            guard !Self.isCancellation(error) else { return }
            errorMessage = error.localizedDescription
        }
    }

    /// The server's chat list carries only `createdAt` (the `chat` table has no `updatedAt`),
    /// so a row shows how long ago the chat was created. Accepts ISO-8601 with or without
    /// fractional seconds; anything else is returned unchanged.
    public nonisolated static func relativeTime(
        forCreatedAt iso: String, now: Date = .now, locale: Locale = .current
    ) -> String {
        let withFraction = ISO8601DateFormatter()
        withFraction.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        let plain = ISO8601DateFormatter()
        plain.formatOptions = [.withInternetDateTime]
        guard let date = withFraction.date(from: iso) ?? plain.date(from: iso) else { return iso }
        let formatter = RelativeDateTimeFormatter()
        formatter.locale = locale
        formatter.unitsStyle = .full
        return formatter.localizedString(for: date, relativeTo: now)
    }

    private static func isCancellation(_ error: Error) -> Bool {
        error is CancellationError || (error as? URLError)?.code == .cancelled
    }
}
