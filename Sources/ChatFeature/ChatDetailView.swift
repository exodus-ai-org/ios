import Models
import NetworkingKit
import SwiftUI

public struct ChatDetailView: View {
    @State private var viewModel: ChatDetailViewModel

    public init(chatId: String, apiClient: APIClient, streamManager: ChatStreamManager, serverConfig: ServerConfigStore) {
        _viewModel = State(
            initialValue: ChatDetailViewModel(
                chatId: chatId, apiClient: apiClient, streamManager: streamManager, serverConfig: serverConfig))
    }

    public var body: some View {
        VStack(spacing: 0) {
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 8) {
                        ForEach(viewModel.messages) { message in
                            MessageRow(
                                message: message,
                                showsTypingIndicator: viewModel.isTurnInFlight && message.id == viewModel.messages.last?.id
                            )
                            .id(message.id)
                        }
                        // Between tapping send and the first assistant message the transcript ends
                        // with the user's message; without this the screen would show nothing.
                        if viewModel.showsPendingRow {
                            AssistantBubble(text: AttributedString("…"))
                                .id(Self.pendingRowID)
                        }
                    }
                    .padding(.horizontal)
                    .padding(.top, 8)
                }
                // Pull down to retry a history load that failed (the composer stays disabled until it succeeds).
                .scrollBounceBehavior(.always)
                .refreshable { await viewModel.loadHistory() }
                .onChange(of: viewModel.messages.count) {
                    scrollToBottom(proxy, animated: true)
                }
                // Follow a reply as it streams in: the count is constant while the last message grows.
                .onChange(of: viewModel.messages.last?.answerText) {
                    scrollToBottom(proxy, animated: false)
                }
                // Sending adds the pending row; reaching it is the point of `isTurnInFlight` flipping.
                .onChange(of: viewModel.isTurnInFlight) {
                    scrollToBottom(proxy, animated: true)
                }
            }

            Divider()

            HStack {
                TextField("Message", text: $viewModel.composerText, axis: .vertical)
                    .textFieldStyle(.roundedBorder)
                if viewModel.isTurnInFlight {
                    // The way out of a turn that will not finish (a half-open connection can otherwise
                    // keep the composer locked for up to an hour).
                    Button {
                        Task { await viewModel.stop() }
                    } label: {
                        Label("Stop", systemImage: "stop.circle.fill")
                            .labelStyle(.iconOnly)
                            .font(.title2)
                    }
                } else {
                    Button {
                        Task { await viewModel.sendMessage() }
                    } label: {
                        Label("Send", systemImage: "arrow.up.circle.fill")
                            .labelStyle(.iconOnly)
                            .font(.title2)
                    }
                    .disabled(!viewModel.canSend)
                }
            }
            .padding()
        }
        .navigationTitle(viewModel.displayTitle)
        .navigationBarTitleDisplayMode(.inline)
        .task { await viewModel.onAppear() }
        .alert(
            "Error",
            isPresented: Binding(
                get: { viewModel.errorMessage != nil },
                set: { if !$0 { viewModel.errorMessage = nil } }
            )
        ) {
            Button("OK") {}
        } message: {
            Text(viewModel.errorMessage ?? "")
        }
    }

    /// Stable id of the pending "…" row, so the scroll view can be pointed at it.
    private static let pendingRowID = "pending"

    private func scrollToBottom(_ proxy: ScrollViewProxy, animated: Bool) {
        let targetId = viewModel.showsPendingRow ? Self.pendingRowID : viewModel.messages.last?.id
        guard let targetId else { return }
        if animated {
            withAnimation { proxy.scrollTo(targetId, anchor: .bottom) }
        } else {
            proxy.scrollTo(targetId, anchor: .bottom)
        }
    }
}
