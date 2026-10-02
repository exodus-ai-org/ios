import Foundation
import MarkdownKit
import Models
import NetworkingKit
import SwiftUI
import UIKit

extension EnvironmentValues {
    /// Reads this chat's workspace files from the computer; nil where there is no chat (the card then has no View).
    @Entry var workspaceFileLoader: WorkspaceFileLoader?
}

/// A file the chat's tools wrote, read from the computer through the paired session (device token, pinned TLS):
/// `GET /api/v1/workspace/:chatId/file?path=…` (exodus `routes/workspace.ts`). The computer confines the path to this
/// chat's workspace and sends text only, at most 1 MB.
final class WorkspaceFileLoader: Sendable {
    typealias Fetch = @Sendable (_ path: String) async throws -> WorkspaceFile

    private let fetch: Fetch

    init(fetch: @escaping Fetch) {
        self.fetch = fetch
    }

    convenience init(apiClient: APIClient, chatId: String) {
        let id = chatId.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed.subtracting(["/"])) ?? chatId
        self.init { path in
            try await apiClient.get("/api/v1/workspace/\(id)/file", query: [URLQueryItem(name: "path", value: path)])
        }
    }

    func load(_ path: String) async throws -> WorkspaceFile { try await fetch(path) }
}

/// What the View sheet shows: the file, or why it cannot.
@MainActor
@Observable
final class WorkspaceFileSheetModel {
    /// Why the file is not shown, from what the computer answered.
    enum Fallback: Equatable, Sendable {
        /// No answer, the computer locked or erring, or a computer too old to serve files: worth trying again.
        case unreachable
        case tooLarge
        case notText
        case notFound
        case outsideWorkspace

        static func from(_ error: Error) -> Fallback {
            guard let http = error as? HTTPError else { return .unreachable }
            switch http.statusCode {
            case 413: return .tooLarge
            case 415: return .notText
            // A 404 without the route's own code is a computer that has no such route yet.
            case 404: return http.code == "FILE_NOT_FOUND" ? .notFound : .unreachable
            case 400, 403: return .outsideWorkspace
            default: return .unreachable
            }
        }

        var canRetry: Bool { self == .unreachable }

        var message: String {
            switch self {
            case .unreachable:
                String(localized: "ios:chat.card.file.sheet.unreachable", defaultValue: "Couldn’t get this file from your computer. Make sure Exodus is running there, then try again.", comment: "The file viewer, when the computer did not send the file.")
            case .tooLarge:
                String(localized: "ios:chat.card.file.sheet.tooLarge", defaultValue: "This file is too large to show on your phone. Open it on your computer.", comment: "The file viewer, when the file is over the size the phone is sent (1 MB).")
            case .notText:
                String(localized: "ios:chat.card.file.sheet.notText", defaultValue: "This file isn’t text, so it can’t be shown here. Open it on your computer.", comment: "The file viewer, when the file is binary (an image, a PDF…).")
            case .notFound:
                String(localized: "ios:chat.card.file.sheet.notFound", defaultValue: "This file is no longer on your computer. It may have been moved or deleted.", comment: "The file viewer, when the file the card names is gone.")
            case .outsideWorkspace:
                String(localized: "ios:chat.card.file.sheet.outside", defaultValue: "Only files in this chat’s workspace can be shown here.", comment: "The file viewer, when the file was written outside the chat's workspace folder on the computer.")
            }
        }
    }

    enum State: Equatable {
        case loading
        case loaded(WorkspaceFile)
        case failed(Fallback)
    }

    let path: String
    private(set) var state: State = .loading
    /// The Markdown, parsed off the main actor once the file arrives; nil for plain text.
    private(set) var markdown: MarkdownParseResult?
    private let loader: WorkspaceFileLoader

    init(path: String, loader: WorkspaceFileLoader) {
        self.path = path
        self.loader = loader
    }

    /// The file's name for the title: the computer's once it answers, the card's path before.
    var fileName: String {
        if case .loaded(let file) = state, !file.name.isEmpty { return file.name }
        return FileCardRules.fileName(path)
    }

    /// The text that Copy and Share take, once there is one.
    var text: String? {
        if case .loaded(let file) = state { file.content } else { nil }
    }

    func load() async {
        state = .loading
        markdown = nil
        do {
            let file = try await loader.load(path)
            if file.kind == .markdown { markdown = await Self.parse(file.content) }
            state = .loaded(file)
        } catch is CancellationError {
            return
        } catch {
            state = .failed(.from(error))
        }
    }

    @concurrent
    private static func parse(_ text: String) async -> MarkdownParseResult {
        MarkdownParser.parse(text, source: 0)
    }

    /// "<file name> · <chat title>", what a screenshot of the sheet is called.
    static func screenTitle(fileName: String, chatTitle: String?) -> String {
        ScreenTitles.join(fileName, chatTitle)
    }
}

/// The file as it is on the computer now, read-only: Markdown drawn by MarkdownKit, anything else monospaced. Both
/// select; Copy and Share take the whole text.
struct WorkspaceFileSheet: View {
    @State private var model: WorkspaceFileSheetModel
    @Environment(\.dismiss) private var dismiss
    @Environment(\.screenTitle) private var enclosingTitle

    init(path: String, loader: WorkspaceFileLoader) {
        _model = State(initialValue: WorkspaceFileSheetModel(path: path, loader: loader))
    }

    var body: some View {
        NavigationStack {
            content
                .navigationTitle(Text(verbatim: model.fileName))
                .navigationBarTitleDisplayMode(.inline)
                .screenTitle(WorkspaceFileSheetModel.screenTitle(fileName: model.fileName, chatTitle: enclosingTitle))
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("common:action.close", role: .close) { dismiss() }
                    }
                    if let text = model.text {
                        ToolbarItemGroup(placement: .primaryAction) {
                            Button("chat:messageAction.copy", systemImage: "doc.on.doc") {
                                UIPasteboard.general.string = text
                            }
                            ShareLink(item: text)
                        }
                    }
                }
        }
        .task { await model.load() }
    }

    @ViewBuilder
    private var content: some View {
        switch model.state {
        case .loading:
            ProgressView()
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        case .loaded(let file):
            ScrollView {
                if let markdown = model.markdown {
                    MarkdownDocumentView(parsed: markdown)
                        .padding()
                } else if file.content.isEmpty {
                    FileCardNote(text: Text("ios:chat.card.file.empty"))
                } else {
                    CodeLines(lines: LineDiff.lines(of: file.content).map { LineDiff.clip($0, to: 2_000) })
                }
            }
        case .failed(let fallback):
            ContentUnavailableView {
                Label("ios:chat.card.file.sheet.unavailableTitle", systemImage: "doc.questionmark")
            } description: {
                Text(verbatim: fallback.message)
            } actions: {
                if fallback.canRetry {
                    Button("common:action.retry") { Task { await model.load() } }
                        .buttonStyle(.bordered)
                }
            }
        }
    }
}

/// The card's View row: opens the file as the computer has it now. Only drawn where the chat gave a loader.
struct WorkspaceFileViewRow: View {
    let path: String
    @Environment(\.workspaceFileLoader) private var loader
    @State private var showsFile = false

    var body: some View {
        if let loader, !path.isEmpty {
            Divider()
            Button {
                showsFile = true
            } label: {
                Label("ios:chat.card.file.view", systemImage: "doc.text.magnifyingglass")
                    .font(.caption.weight(.medium))
                    .frame(maxWidth: .infinity, minHeight: 44)
                    .contentShape(.rect)
            }
            .buttonStyle(.plain)
            .foregroundStyle(.tint)
            .sheet(isPresented: $showsFile) { WorkspaceFileSheet(path: path, loader: loader) }
            .onAppear {
                if WorkspaceFileViewRow.opensOnLaunch(path) { showsFile = true }
            }
        }
    }

    #if DEBUG
    /// `-CardPrototypesFileSheet <path fragment>`: the gallery opens the View sheet of the first card whose path holds
    /// the fragment at launch, for screenshots.
    @MainActor private static var launchArgumentUsed = false
    @MainActor private static func opensOnLaunch(_ path: String) -> Bool {
        let arguments = ProcessInfo.processInfo.arguments
        guard !launchArgumentUsed, let index = arguments.firstIndex(of: "-CardPrototypesFileSheet"),
            index + 1 < arguments.count, path.contains(arguments[index + 1])
        else { return false }
        launchArgumentUsed = true
        return true
    }
    #else
    private static func opensOnLaunch(_ path: String) -> Bool { false }
    #endif
}
