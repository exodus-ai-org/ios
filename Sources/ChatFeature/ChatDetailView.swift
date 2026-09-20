import Models
import NetworkingKit
import SwiftUI

public struct ChatDetailView: View {
    @State private var viewModel: ChatDetailViewModel
    /// The measured height of the send/stop button. The button is taller than one line of text, so
    /// the field is given it as a minimum height and centres its text in it: with the row bottom-
    /// aligned the two boxes then have the same height at rest and their centres coincide, while a
    /// field grown to several lines still leaves the button sitting on the composer's bottom edge.
    @State private var turnButtonHeight: CGFloat = 0
    /// Stands in for the measurement during the first layout pass, so the composer is not drawn one
    /// line high for a frame and then grown.
    @ScaledMetric(relativeTo: .body) private var estimatedTurnButtonHeight: CGFloat = 32

    public init(
        chatId: String, title: String? = nil, apiClient: APIClient, streamManager: ChatStreamManager,
        serverConfig: ServerConfigStore
    ) {
        _viewModel = State(
            initialValue: ChatDetailViewModel(
                chatId: chatId, title: title, apiClient: apiClient, streamManager: streamManager,
                serverConfig: serverConfig))
    }

    public var body: some View {
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
            .scrollDismissesKeyboard(.interactively)
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
        .overlay {
            if viewModel.showsEmptyState { emptyState }
        }
        .safeAreaBar(edge: .bottom) { composer }
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

    private var emptyState: some View {
        Text("What can I help with?")
            .font(.title2.weight(.semibold))
            .multilineTextAlignment(.center)
            .padding(.horizontal, 32)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .allowsHitTesting(false)
    }

    private var composer: some View {
        HStack(alignment: .bottom, spacing: 8) {
            TextField("Ask Exodus", text: $viewModel.composerText, axis: .vertical)
                .lineLimit(1...5)
                .frame(minHeight: turnButtonHeight > 0 ? turnButtonHeight : estimatedTurnButtonHeight)
                .accessibilityIdentifier("composerField")
            turnButton
                .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { turnButtonHeight = $0 }
        }
        .padding(.leading, 16)
        .padding(.trailing, 6)
        .padding(.vertical, 10)
        .glassEffect(.regular, in: .rect(cornerRadius: 26))
        .padding(.horizontal, 12)
        .padding(.bottom, 4)
    }

    @ViewBuilder
    private var turnButton: some View {
        if viewModel.isTurnInFlight {
            // The way out of a turn that will not finish (a half-open connection can otherwise
            // keep the composer locked for up to an hour).
            Button {
                Task { await viewModel.stop() }
            } label: {
                Label("Stop", systemImage: "stop.fill")
                    .labelStyle(.iconOnly)
            }
            .buttonStyle(.glassProminent)
            .buttonBorderShape(.circle)
            .accessibilityIdentifier("stopButton")
        } else {
            Button {
                Task { await viewModel.sendMessage() }
            } label: {
                Label("Send", systemImage: "arrow.up")
                    .labelStyle(.iconOnly)
            }
            .buttonStyle(.glassProminent)
            .buttonBorderShape(.circle)
            .disabled(!viewModel.canSend)
            .accessibilityIdentifier("sendButton")
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
