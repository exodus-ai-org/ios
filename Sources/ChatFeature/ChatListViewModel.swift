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

    private let apiClient: APIClient

    public init(apiClient: APIClient) {
        self.apiClient = apiClient
    }

    public func load() async {
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }
        do {
            chats = try await apiClient.get("/api/history")
            loadFailed = false
        } catch {
            // SwiftUI cancels a view's `.task` when the view goes away; that is not a failure.
            guard !Self.isCancellation(error) else { return }
            loadFailed = true
            errorMessage = error.localizedDescription
        }
    }

    public func delete(_ chat: ChatSummary) async {
        do {
            try await apiClient.delete("/api/chat/\(chat.id)")
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
