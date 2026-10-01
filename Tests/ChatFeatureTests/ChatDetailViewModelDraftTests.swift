import Foundation
import NetworkingKit
import Testing

@testable import ChatFeature

@MainActor
@Suite("ChatDetailViewModel.applyDraft: a widget's prompt waits in the composer")
struct ChatDetailViewModelDraftTests {
    /// Nothing here talks to the computer: a draft is the composer's alone.
    private func makeModel() -> ChatDetailViewModel {
        let suite = "ChatDetailViewModelDraftTests"
        let defaults = UserDefaults(suiteName: suite)!
        defaults.removePersistentDomain(forName: suite)
        let config = ServerConfigStore(userDefaults: defaults)
        let session = URLSession(configuration: .ephemeral)
        return ChatDetailViewModel(
            chatId: "c1", apiClient: APIClient(session: session, serverConfig: config),
            streamManager: ChatStreamManager(sseClient: SSEClient(session: session)), serverConfig: config)
    }

    @Test("a draft fills the composer once and is not sent")
    func draft() async throws {
        let model = makeModel()
        model.applyDraft("Plan my day")
        model.applyDraft("Something else")
        #expect(model.composerText == "Plan my day")
        #expect(model.composerFocusRequest == 1)
        #expect(model.messages.isEmpty)
        #expect(!model.isTurnInFlight)
    }
}
