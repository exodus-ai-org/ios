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
                .onChange(of: viewModel.messages.last?.displayText) {
                    scrollToBottom(proxy, animated: false)
                }
            }

            Divider()

            HStack {
                TextField("Message", text: $viewModel.composerText, axis: .vertical)
                    .textFieldStyle(.roundedBorder)
                Button {
                    Task { await viewModel.sendMessage() }
                } label: {
                    Image(systemName: "arrow.up.circle.fill").font(.title2)
                }
                .disabled(!viewModel.canSend)
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

    private func scrollToBottom(_ proxy: ScrollViewProxy, animated: Bool) {
        guard let lastId = viewModel.messages.last?.id else { return }
        if animated {
            withAnimation { proxy.scrollTo(lastId, anchor: .bottom) }
        } else {
            proxy.scrollTo(lastId, anchor: .bottom)
        }
    }
}
