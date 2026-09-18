import Models
import NetworkingKit
import SwiftUI

public struct ChatListView: View {
    @State private var viewModel: ChatListViewModel
    private let onSelectChat: (String) -> Void
    private let onNewChat: (String) -> Void

    public init(apiClient: APIClient, onSelectChat: @escaping (String) -> Void, onNewChat: @escaping (String) -> Void) {
        _viewModel = State(initialValue: ChatListViewModel(apiClient: apiClient))
        self.onSelectChat = onSelectChat
        self.onNewChat = onNewChat
    }

    public var body: some View {
        List {
            ForEach(viewModel.chats) { chat in
                Button {
                    onSelectChat(chat.id)
                } label: {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(chat.title).font(.body)
                        Text(ChatListViewModel.relativeTime(forCreatedAt: chat.createdAt))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
            .onDelete { offsets in
                for index in offsets {
                    let chat = viewModel.chats[index]
                    Task { await viewModel.delete(chat) }
                }
            }
        }
        .overlay {
            if viewModel.chats.isEmpty {
                if viewModel.isLoading {
                    ProgressView()
                } else if viewModel.loadFailed {
                    ContentUnavailableView {
                        Label("Can't load chats", systemImage: "wifi.exclamationmark")
                    } description: {
                        Text("Pull down or tap Retry to try again.")
                    } actions: {
                        Button("Retry") { Task { await viewModel.load() } }
                    }
                } else {
                    ContentUnavailableView("No chats yet", systemImage: "message")
                }
            }
        }
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button {
                    onNewChat(UUID().uuidString.lowercased())
                } label: {
                    Label("New Chat", systemImage: "square.and.pencil")
                }
            }
        }
        .task { await viewModel.load() }
        .refreshable { await viewModel.load() }
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
}
