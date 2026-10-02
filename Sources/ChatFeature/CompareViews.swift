import Models
import SwiftUI

/// The words of a regenerate comparison, for views and tests alike.
enum CompareText {
    static func answer(_ position: Int) -> String {
        String(
            localized: "ios:chat.compare.answerTab", defaultValue: "Answer \(String(position))",
            comment: "Label over one of two answers to the same question being compared. %@ is 1 or 2.")
    }

    static var useThis: String {
        String(
            localized: "ios:chat.compare.useThis", defaultValue: "Use this one",
            comment: "Button under a compared answer: keep this answer and fold the other.")
    }

    static var useThisHint: String {
        String(
            localized: "ios:chat.compare.useThisHint", defaultValue: "Keeps this answer and folds the other one away.",
            comment: "VoiceOver hint of the Use this one button.")
    }

    static var useInstead: String {
        String(
            localized: "ios:chat.compare.useInstead", defaultValue: "Use this instead",
            comment: "Button in the sheet showing the other version of an answer: swap it in for the chosen one.")
    }

    static var chosen: String {
        String(
            localized: "ios:chat.compare.chosen", defaultValue: "Chosen",
            comment: "Spoken by VoiceOver once an answer has been picked from a comparison.")
    }

    /// The catalog picks the plural form; the branch only gives the hostless tests (no catalog) the right English.
    static func otherVersions(_ count: Int) -> String {
        if count == 1 {
            return String(
                localized: "ios:chat.compare.otherVersion", defaultValue: "\(count) other version",
                comment: "Quiet link under a chosen answer that opens the answer it was compared with (plural).")
        }
        return String(
            localized: "ios:chat.compare.otherVersion", defaultValue: "\(count) other versions",
            comment: "Quiet link under a chosen answer that opens the answer it was compared with (plural).")
    }

    static var locked: String {
        String(
            localized: "ios:chat.compare.locked",
            defaultValue: "The conversation has moved on, so this answer can no longer be swapped.",
            comment: "Alert after Use this instead was refused: a later message exists.")
    }

    static var missing: String {
        String(
            localized: "ios:chat.compare.missing", defaultValue: "That answer is no longer in this chat.",
            comment: "Alert after choosing an answer the computer no longer has.")
    }
}

/// Over a compared answer: which one it is, and the button that keeps it.
struct CompareHeader: View {
    let position: Int
    let canChoose: Bool
    let choose: () -> Void
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    var body: some View {
        let layout =
            dynamicTypeSize.isAccessibilitySize
            ? AnyLayout(VStackLayout(alignment: .leading, spacing: 8)) : AnyLayout(HStackLayout(alignment: .center, spacing: 8))
        layout {
            Text(verbatim: CompareText.answer(position))
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.secondary)
                .accessibilityAddTraits(.isHeader)
                .frame(maxWidth: dynamicTypeSize.isAccessibilitySize ? nil : .infinity, alignment: .leading)
            Button(action: choose) {
                Text(verbatim: CompareText.useThis)
                    .font(.subheadline.weight(.medium))
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .background(.fill.tertiary, in: .capsule)
                    .frame(minHeight: 44)
                    .contentShape(.rect)
            }
            .buttonStyle(.plain)
            .foregroundStyle(.tint)
            .disabled(!canChoose)
            .accessibilityHint(Text(verbatim: CompareText.useThisHint))
        }
    }
}

/// Under a chosen answer: the quiet way to the answer it was compared with.
struct OtherVersionLink: View {
    let count: Int
    let open: () -> Void

    var body: some View {
        Button(action: open) {
            Label {
                Text(verbatim: CompareText.otherVersions(count))
            } icon: {
                Image(systemName: "square.on.square")
            }
            .font(.footnote)
            .foregroundStyle(.secondary)
            .footRowTarget()
        }
        .buttonStyle(.plain)
    }
}

/// A folded answer, read-only, with Use this instead while the swap is still allowed.
struct OtherVersion: Identifiable, Equatable {
    let turn: AssistantTurn
    let canSwap: Bool

    var id: String { turn.runId }
}

struct OtherVersionSheet: View {
    let version: OtherVersion
    let useInstead: () -> Void
    @State private var sources: SourcesSheetModel?
    @Environment(\.dismiss) private var dismiss
    @Environment(\.accentGlyph) private var accentGlyph
    @Environment(\.screenTitle) private var enclosingTitle

    var body: some View {
        NavigationStack {
            ScrollView {
                AssistantTurnView(
                    turn: version.turn, isStreaming: false,
                    error: TranscriptRules.runError(for: version.turn, live: nil),
                    showSources: { _, marker in sources = SourcesSheetModel(turn: version.turn, marker: marker) }
                )
                .padding()
            }
            .navigationTitle(Text(verbatim: CompareText.otherVersions(1)))
            .navigationBarTitleDisplayMode(.inline)
            .screenTitle(ScreenTitles.join(CompareText.otherVersions(1), enclosingTitle))
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("common:action.close", role: .close) { dismiss() }
                }
            }
            .safeAreaBar(edge: .bottom) {
                if version.canSwap {
                    Button {
                        useInstead()
                        dismiss()
                    } label: {
                        Text(verbatim: CompareText.useInstead)
                            .font(.body.weight(.semibold))
                            .foregroundStyle(accentGlyph)
                            .frame(maxWidth: .infinity, minHeight: 44)
                    }
                    .buttonStyle(.glassProminent)
                    .toneFill()
                    .padding(.horizontal)
                    .padding(.bottom, 8)
                }
            }
        }
        .sheet(item: $sources) { SourcesSheet(model: $0) }
        .presentationDragIndicator(.visible)
    }
}
