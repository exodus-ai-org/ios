import SwiftUI
import UIKit

extension EnvironmentValues {
    /// Whether an edit_file card starts with its diff open; the turn sets it from how many edits its run made.
    @Entry var editDiffsStartOpen = true
}

// MARK: - read_file

struct ReadFileCard: View {
    let model: ReadFileCardModel
    @State private var expanded = false
    @State private var showsFile = false

    private static let previewLines = 10

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            FileCardHeader(toolName: "read_file", systemImage: "doc.text", path: model.path, copyText: copyText) {
                switch model.state {
                case .read(let preview, let size): FileCardSummary(text: FileCardText.readSummary(preview, size: size))
                case .binary(let size): FileCardSummary(text: size.map(FileCardText.bytes) ?? "")
                case .failed: FileCardFailedIcon()
                }
            }
            Divider()
            switch model.state {
            case .read(let preview, _): content(preview)
            case .binary: FileCardNote(text: Text("ios:chat.card.file.binary"))
            case .failed(let message): FileCardError(message: message ?? ToolPresentation.failedText("read_file"))
            }
        }
        .modifier(CardSurface())
    }

    private var copyText: String? {
        if case .read(let preview, _) = model.state, !preview.isEmpty { preview.text } else { nil }
    }

    @ViewBuilder
    private func content(_ preview: FilePreview) -> some View {
        if preview.isEmpty {
            FileCardNote(text: Text("ios:chat.card.file.empty"))
        } else {
            // A few more lines than the preview are shown whole: a fold that hides two lines saves nothing.
            let isLong = preview.totalLines > Self.previewLines + 4
            let shown = expanded || !isLong ? preview.lines.count : Self.previewLines
            CodeLines(lines: Array(preview.lines.prefix(shown)))
                .mask {
                    if isLong && !expanded {
                        LinearGradient(
                            stops: [.init(color: .black, location: 0.7), .init(color: .clear, location: 1)],
                            startPoint: .top, endPoint: .bottom)
                    } else {
                        Color.black
                    }
                }
            if expanded && preview.linesPastCap > 0 {
                Divider()
                Button {
                    showsFile = true
                } label: {
                    Label("ios:chat.card.file.openWholeFile", systemImage: "arrow.up.left.and.arrow.down.right")
                        .font(.caption.weight(.medium))
                        .frame(maxWidth: .infinity, minHeight: 44)
                        .contentShape(.rect)
                }
                .buttonStyle(.plain)
                .foregroundStyle(.tint)
                .sheet(isPresented: $showsFile) { FileSheet(path: model.path, text: preview.text) }
            }
            if isLong {
                Divider()
                ExpandRow(isExpanded: $expanded, collapsedTitle: FileCardText.showAllLines(preview.totalLines))
            }
        }
    }
}

// MARK: - write_file

struct WriteFileCard: View {
    let model: WriteFileCardModel
    @State private var expanded = false

    private static let previewLines = 6

    var body: some View {
        let appended = if case .written(_, true) = model.state { true } else { false }
        VStack(alignment: .leading, spacing: 0) {
            FileCardHeader(
                toolName: "write_file", systemImage: appended ? "text.append" : "square.and.pencil",  // l10n:ignore: SF Symbol names
                path: model.path, copyText: model.preview?.text
            ) {
                switch model.state {
                case .written(let bytes, let appended):
                    FileCardSummary(text: FileCardText.writeSummary(bytes: bytes, appended: appended))
                case .failed: FileCardFailedIcon()
                }
            }
            switch model.state {
            case .failed(let message):
                Divider()
                FileCardError(message: message ?? ToolPresentation.failedText("write_file"))
            case .written:
                if let preview = model.preview { content(preview) }
            }
        }
        .modifier(CardSurface())
    }

    @ViewBuilder
    private func content(_ preview: FilePreview) -> some View {
        Divider()
        if preview.isEmpty {
            FileCardNote(text: Text("ios:chat.card.file.empty"))
        } else {
            CodeLines(lines: expanded ? preview.lines : Array(preview.lines.prefix(Self.previewLines)))
            if preview.totalLines > Self.previewLines {
                Divider()
                ExpandRow(isExpanded: $expanded, collapsedTitle: FileCardText.showAllLines(preview.totalLines))
            }
        }
    }
}

// MARK: - edit_file

struct EditFileCard: View {
    let model: EditFileCardModel
    @State private var openState: Bool?
    @State private var showsAllRows = false
    @Environment(\.editDiffsStartOpen) private var startsOpen
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    /// Rows drawn before "Show all": a whole-file rewrite would otherwise lay out every line at once.
    private static let rowCap = 120

    private var isOpen: Bool { openState ?? (!model.isFailed && startsOpen) }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            if case .failed(let message) = model.state {
                Divider()
                FileCardError(message: message ?? ToolPresentation.failedText("edit_file"))
            }
            if isOpen, let diff = model.diff {
                Divider()
                diffBody(diff)
                if let summary = model.replacementSummary {
                    Divider()
                    Text(verbatim: FileCardText.replacements(summary.count, before: summary.before, after: summary.after))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 7)
                }
            }
        }
        .modifier(CardSurface())
    }

    @ViewBuilder
    private var header: some View {
        if let diff = model.diff {
            Button {
                withAnimation(reduceMotion ? nil : .snappy(duration: 0.2)) { openState = !isOpen }
            } label: {
                headerBand(diff)
                    .contentShape(.rect)
            }
            .buttonStyle(.plain)
            .accessibilityValue(isOpen ? Text("ios:chat.message.timeline.expanded") : Text("ios:chat.message.timeline.collapsed"))
        } else {
            headerBand(nil)
        }
    }

    private func headerBand(_ diff: LineDiff.Result?) -> some View {
        FileCardHeader(toolName: "edit_file", systemImage: "pencil.line", path: model.path, copyText: nil) {
            HStack(spacing: 6) {
                if model.isFailed {
                    FileCardFailedIcon()
                } else if let diff {
                    DiffStat(added: diff.added, removed: diff.removed)
                }
                if diff != nil {
                    Image(systemName: "chevron.right")
                        .imageScale(.small)
                        .foregroundStyle(.tertiary)
                        .rotationEffect(.degrees(isOpen ? 90 : 0))
                        .accessibilityHidden(true)
                }
            }
        }
    }

    @ViewBuilder
    private func diffBody(_ diff: LineDiff.Result) -> some View {
        switch diff {
        case .tooLarge(let oldLines, let newLines):
            FileCardNote(text: Text(verbatim: FileCardText.diffTooLarge(oldLines: oldLines, newLines: newLines)))
        case .lines(let items, _, _):
            let shown = showsAllRows ? items : Array(items.prefix(Self.rowCap))
            DiffLines(items: shown)
            if items.count > Self.rowCap {
                Divider()
                ExpandRow(isExpanded: $showsAllRows, collapsedTitle: FileCardText.showAllLines(items.count))
            }
        }
    }
}

struct DiffStat: View {
    let added: Int
    let removed: Int

    var body: some View {
        HStack(spacing: 6) {
            Text(verbatim: "+\(added)").foregroundStyle(.green)
            Text(verbatim: "−\(removed)").foregroundStyle(.red)
        }
        .font(.caption.monospacedDigit().weight(.medium))
        .fixedSize()
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(verbatim: FileCardText.diffStat(added: added, removed: removed)))
    }
}

/// A unified diff: a sign column, then the line, green for added and red for removed.
struct DiffLines: View {
    let items: [LineDiff.Item]

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            ForEach(Array(items.enumerated()), id: \.offset) { _, item in
                switch item {
                case .row(let row): line(row)
                case .gap(let count):
                    Text(verbatim: FileCardText.unchangedLines(count))
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, 28)
                        .padding(.vertical, 3)
                        .background(Color(.quaternarySystemFill))
                }
            }
        }
        .font(.caption.monospaced())
        .textSelection(.enabled)
        .padding(.vertical, 6)
        // Code does not reflow gracefully: past xxLarge a line wraps every word.
        .dynamicTypeSize(...DynamicTypeSize.xxLarge)
    }

    private func line(_ row: LineDiff.Row) -> some View {
        let (sign, tint): (String, Color?) =
            switch row.kind {
            case .context: (" ", nil)
            case .removed: ("−", .red)
            case .added: ("+", .green)
            }
        return HStack(alignment: .firstTextBaseline, spacing: 8) {
            Text(verbatim: sign)
                .foregroundStyle(tint ?? .secondary)
                .frame(width: 10)
            Text(verbatim: row.text.isEmpty ? " " : row.text)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 1)
        .background((tint ?? .clear).opacity(0.14))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(verbatim: FileCardText.accessibilityLine(row)))
    }
}

// MARK: - Shared pieces

/// The band every file card opens with: the tool's icon, the file's name over its folder, and a trailing summary.
/// Long-press copies the file's text, when the card has it.
struct FileCardHeader<Trailing: View>: View {
    let toolName: String
    let systemImage: String
    let path: String
    let copyText: String?
    @ViewBuilder var trailing: Trailing

    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    var body: some View {
        // At accessibility sizes the summary drops under the title instead of squeezing it to "…".
        let layout =
            dynamicTypeSize.isAccessibilitySize
            ? AnyLayout(VStackLayout(alignment: .leading, spacing: 6)) : AnyLayout(HStackLayout(alignment: .center, spacing: 8))
        let name = FileCardRules.fileName(path)
        let folder = FileCardRules.directory(path)
        layout {
            HStack(alignment: .center, spacing: 8) {
                Image(systemName: systemImage)
                    .foregroundStyle(.tint)
                    .frame(minWidth: 20)
                    .accessibilityLabel(Text(verbatim: ToolPresentation.displayName(toolName)))
                VStack(alignment: .leading, spacing: 1) {
                    Text(verbatim: name.isEmpty ? ToolPresentation.displayName(toolName) : name)
                        .font(.subheadline.weight(.medium))
                        .lineLimit(dynamicTypeSize.isAccessibilitySize ? 3 : 1)
                        .truncationMode(.middle)
                    if !folder.isEmpty {
                        Text(verbatim: folder)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(dynamicTypeSize.isAccessibilitySize ? 3 : 1)
                            .truncationMode(.head)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            trailing
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 9)
        .background(Color(.tertiarySystemFill))
        .accessibilityElement(children: .combine)
        .contextMenu {
            if let copyText {
                Button("chat:messageAction.copy", systemImage: "doc.on.doc") { UIPasteboard.general.string = copyText }
            }
        }
    }
}

struct FileCardSummary: View {
    let text: String

    var body: some View {
        Text(verbatim: text)
            .font(.caption)
            .foregroundStyle(.secondary)
            .fixedSize()
    }
}

struct FileCardFailedIcon: View {
    var body: some View {
        Image(systemName: "xmark.circle.fill")
            .foregroundStyle(.red)
            .accessibilityHidden(true)
    }
}

struct FileCardError: View {
    let message: String
    /// Inside a card's box; 0 under a card that has no box (the image frame), so it lines up with the frame's edge.
    var horizontalInset: CGFloat = 12

    var body: some View {
        Label {
            Text(verbatim: message)
        } icon: {
            Image(systemName: "exclamationmark.circle")
        }
        .font(.caption.monospaced())
        .foregroundStyle(.red)
        .textSelection(.enabled)
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, horizontalInset)
        .padding(.vertical, 8)
        .dynamicTypeSize(...DynamicTypeSize.xxLarge)
    }
}

struct FileCardNote: View {
    let text: Text

    var body: some View {
        text
            .font(.caption)
            .italic()
            .foregroundStyle(.secondary)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
    }
}

/// Monospaced lines with a line-number gutter; long lines wrap rather than scroll sideways.
struct CodeLines: View {
    let lines: [String]

    var body: some View {
        VStack(alignment: .leading, spacing: 1) {
            ForEach(Array(lines.enumerated()), id: \.offset) { index, line in
                HStack(alignment: .firstTextBaseline, spacing: 10) {
                    Text(verbatim: "\(index + 1)")
                        .foregroundStyle(.tertiary)
                        .frame(minWidth: 22, alignment: .trailing)
                        .accessibilityHidden(true)
                    Text(verbatim: line.isEmpty ? " " : line)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
        }
        .font(.caption.monospaced())
        .textSelection(.enabled)
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        // Code does not reflow gracefully: past xxLarge a line wraps every word.
        .dynamicTypeSize(...DynamicTypeSize.xxLarge)
    }
}

/// A full-width "Show all" / "Show less" row, the terminal card's pattern.
struct ExpandRow: View {
    @Binding var isExpanded: Bool
    let collapsedTitle: String
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        Button {
            withAnimation(reduceMotion ? nil : .snappy(duration: 0.2)) { isExpanded.toggle() }
        } label: {
            Group {
                if isExpanded {
                    Label("ios:chat.message.terminal.showLess", systemImage: "chevron.up")
                } else {
                    Label {
                        Text(verbatim: collapsedTitle)
                    } icon: {
                        Image(systemName: "chevron.down")
                    }
                }
            }
            .font(.caption.weight(.medium))
            .frame(maxWidth: .infinity, minHeight: 44)
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .foregroundStyle(.tint)
    }
}

/// The whole file, in a sheet: what a preview past its inline cap leads to.
struct FileSheet: View {
    let path: String
    let text: String
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollView {
                CodeLines(lines: LineDiff.lines(of: text).map { LineDiff.clip($0, to: 2_000) })
            }
            .navigationTitle(Text(verbatim: FileCardRules.fileName(path)))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("common:action.close", role: .close) { dismiss() }
                }
                ToolbarItem(placement: .primaryAction) {
                    ShareLink(item: text)
                }
            }
        }
    }
}

// MARK: - Copy

enum FileCardText {
    static func bytes(_ count: Int) -> String { count.formatted(.byteCount(style: .file)) }

    static func lineCount(_ count: Int) -> String {
        count == 1
            ? String(localized: "ios:chat.card.file.oneLine", defaultValue: "1 line", comment: "A file card's header: the file has one line.")
            : String(localized: "ios:chat.card.file.lineCount", defaultValue: "\(count) lines", comment: "A file card's header. %lld is how many lines the file has (never 1).")
    }

    static func readSummary(_ preview: FilePreview, size: Int?) -> String {
        let lines = lineCount(preview.totalLines)
        guard let size else { return lines }
        let bytes = bytes(size)
        return String(localized: "ios:chat.card.file.linesAndSize", defaultValue: "\(lines) · \(bytes)", comment: "A read file card's header: its line count, then its size, e.g. “12 lines · 612 bytes”.")
    }

    static func writeSummary(bytes count: Int?, appended: Bool) -> String {
        guard let count else {
            return appended
                ? String(localized: "ios:chat.card.file.appendedNoSize", defaultValue: "Appended", comment: "A write file card's header when text was added to the end of a file of unknown size.")
                : String(localized: "ios:chat.card.file.wroteNoSize", defaultValue: "Written", comment: "A write file card's header when the file was saved and its size is unknown.")
        }
        let size = bytes(count)
        return appended
            ? String(localized: "ios:chat.card.file.appended", defaultValue: "Appended \(size)", comment: "A write file card's header: text added to the end of a file. %@ is its size, e.g. “96 bytes”.")
            : String(localized: "ios:chat.card.file.wrote", defaultValue: "Wrote \(size)", comment: "A write file card's header: the file was saved. %@ is its size, e.g. “284 bytes”.")
    }

    static func showAllLines(_ count: Int) -> String {
        String(localized: "ios:chat.card.file.showAllLines", defaultValue: "Show all \(count) lines", comment: "Button that expands a file card. %lld is how many lines (always more than 10).")
    }

    static func diffStat(added: Int, removed: Int) -> String {
        String(localized: "ios:chat.card.file.diffStat", defaultValue: "\(added) lines added, \(removed) removed", comment: "VoiceOver label of an edit card's +N −M counts. The first number is lines added, the second lines removed.")
    }

    static func unchangedLines(_ count: Int) -> String {
        String(localized: "ios:chat.card.file.unchangedLines", defaultValue: "\(count) unchanged lines", comment: "A fold in a diff standing for lines the edit did not touch. %lld is how many (always 2 or more).")
    }

    static func replacements(_ count: Int, before: Int?, after: Int?) -> String {
        guard let before, let after else {
            return String(localized: "ios:chat.card.file.replacementsOnly", defaultValue: "Replaced \(count) occurrences", comment: "Under an edit card's diff: the same change was made in several places. %lld is how many (2 or more, or 1 when “replace all” was asked).")
        }
        return String(localized: "ios:chat.card.file.replacements", defaultValue: "Replaced \(count) occurrences · \(before) → \(after) lines", comment: "Under an edit card's diff: how many places changed, then the file's line count before → after.")
    }

    static func diffTooLarge(oldLines: Int, newLines: Int) -> String {
        String(localized: "ios:chat.card.file.diffTooLarge", defaultValue: "Too large to compare here: \(oldLines) lines replaced with \(newLines).", comment: "An edit card whose change is too big to diff on the phone. The first number is lines removed, the second lines put in their place.")
    }

    static func accessibilityLine(_ row: LineDiff.Row) -> String {
        switch row.kind {
        case .context: row.text
        case .added: String(localized: "ios:chat.card.file.addedLine", defaultValue: "Added: \(row.text)", comment: "VoiceOver label of an added line in a diff. %@ is the line.")
        case .removed: String(localized: "ios:chat.card.file.removedLine", defaultValue: "Removed: \(row.text)", comment: "VoiceOver label of a removed line in a diff. %@ is the line.")
        }
    }
}
