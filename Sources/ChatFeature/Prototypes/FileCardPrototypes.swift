#if DEBUG
import Models
import SwiftUI

// MARK: - Shared pieces

struct ProtoErrorBody: View {
    let message: String

    var body: some View {
        Text(verbatim: message)
            .font(.caption.monospaced())
            .foregroundStyle(.red)
            .textSelection(.enabled)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .dynamicTypeSize(...DynamicTypeSize.xxLarge)
    }
}

// MARK: - The section

/// The file cards are real now: this group draws `ReadFileCard` / `WriteFileCard` / `EditFileCard` from `ToolCard`s
/// built the way the transcript builds them, in their states.
struct ProtoFileCardsSection: View {
    private static func card(
        _ tool: String, arguments: JSONValue? = nil, details: JSONValue? = nil, error: String? = nil
    ) -> ToolCardView {
        ToolCardView(
            card: ToolCard(
                id: tool, toolName: tool, kind: .generic, payload: details, arguments: arguments,
                isError: error != nil, errorText: error))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 28) {
            UserBubble(text: "Read the README, then bump the retry policy to 5 attempts with backoff.")

            ProtoInReply(state: "read_file · done, short", header: "Worked for 4 sec") {
                Self.card(
                    "read_file", arguments: .object(["path": .string("/Users/me/Code/exodus/README.md")]),
                    details: ProtoFixtures.readmeShort)
            }
            ProtoInReply(state: "read_file · 300 lines, preview expands in place") {
                Self.card("read_file", details: ProtoFixtures.longFile)
            }
            ProtoInReply(state: "read_file · error") {
                Self.card(
                    "read_file", arguments: .object(["path": .string("/Users/me/notes.md")]),
                    error: "Failed to read file \"/Users/me/notes.md\": ENOENT: no such file or directory, open '/Users/me/notes.md'")
            }

            ProtoInReply(
                state: "write_file · done", header: "Worked for 2 sec",
                answer: "I saved the plan to trip-plan.md in this chat's workspace."
            ) {
                Self.card("write_file", arguments: ProtoFixtures.writeArguments, details: ProtoFixtures.writeDetails)
            }
            ProtoInReply(state: "write_file · append") {
                Self.card("write_file", arguments: ProtoFixtures.appendArguments, details: ProtoFixtures.appendDetails)
            }
            ProtoInReply(state: "write_file · error") {
                Self.card(
                    "write_file",
                    arguments: .object([
                        "path": .string("/etc/hosts"), "content": .string("127.0.0.1 exodus.local"), "append": .bool(true),
                    ]),
                    error: "Failed to write file \"/etc/hosts\": EACCES: permission denied, open '/etc/hosts'")
            }

            ProtoInReply(state: "edit_file · one edit in the run: open") {
                Self.card("edit_file", arguments: ProtoFixtures.editArguments, details: ProtoFixtures.editDetails)
            }
            ProtoInReply(state: "edit_file · run of 3+ edits: collapsed") {
                Self.card("edit_file", arguments: ProtoFixtures.replaceAllArguments, details: ProtoFixtures.replaceAllDetails)
                    .environment(\.editDiffsStartOpen, false)
            }
            ProtoInReply(state: "edit_file · replace_all, open") {
                Self.card("edit_file", arguments: ProtoFixtures.replaceAllArguments, details: ProtoFixtures.replaceAllDetails)
            }
            ProtoInReply(state: "edit_file · error") {
                Self.card(
                    "edit_file", arguments: ProtoFixtures.editArguments,
                    error: "old_string appears 3 times in the file. Provide more surrounding context to make it unique, or set replace_all=true.")
            }
        }
        // View reads the file from a stand-in computer: the workspace's files load (the trip plan as Markdown), a file
        // outside the workspace is refused as the route refuses it. `-CardPrototypesFileSheet trip-plan` opens that card's sheet at launch.
        .environment(\.workspaceFileLoader, Self.files)
    }

    private static let files = WorkspaceFileLoader { path in
        try await Task.sleep(for: .milliseconds(400))
        guard path.contains("/.exodus/workspace/") else {
            throw HTTPError(statusCode: 403, code: "OUTSIDE_WORKSPACE", message: "The file is not in this chat's workspace.")
        }
        var content = "# Kyoto, 3 days"
        if case .object(let fields) = ProtoFixtures.writeArguments, let text = fields["content"]?.stringValue {
            content = text
        }
        return WorkspaceFile(
            path: path, name: FileCardRules.fileName(path), size: content.utf8.count, kind: .markdown, content: content)
    }
}
#endif
