import Models
import SwiftUI

/// The tools whose cards the user hid in Settings › Working cards, for `TranscriptRules.blocks`.
struct HiddenWorkingCards: DynamicProperty {
    @AppStorage(WorkingCard.terminal.defaultsKey) private var terminal = true
    @AppStorage(WorkingCard.fileReads.defaultsKey) private var fileReads = true
    @AppStorage(WorkingCard.fileEdits.defaultsKey) private var fileEdits = true

    var tools: Set<String> {
        WorkingCard.hiddenTools { card in
            switch card {
            case .terminal: terminal
            case .fileReads: fileReads
            case .fileEdits: fileEdits
            }
        }
    }
}

/// Settings › Working cards: a switch for each kind of card the model's work leaves in a chat, with the card itself
/// under it. Drawn here, where the cards are; Settings pushes it (`SettingsPageHooks`).
public struct WorkingCardsSettingsPage: View {
    @AppStorage(WorkingCard.terminal.defaultsKey) private var terminal = true
    @AppStorage(WorkingCard.fileReads.defaultsKey) private var fileReads = true
    @AppStorage(WorkingCard.fileEdits.defaultsKey) private var fileEdits = true

    public init() {}

    public var body: some View {
        Form {
            Section {
                Toggle("ios:settings.cards.terminal", isOn: $terminal)
                WorkingCardExample(isShown: terminal) {
                    ToolCardView(card: WorkingCardExamples.terminal)
                }
            }
            Section {
                Toggle("ios:settings.cards.fileReads", isOn: $fileReads)
                WorkingCardExample(isShown: fileReads) {
                    ToolCardView(card: WorkingCardExamples.read)
                }
            }
            Section {
                Toggle("ios:settings.cards.fileEdits", isOn: $fileEdits)
                WorkingCardExample(isShown: fileEdits) {
                    ToolCardView(card: WorkingCardExamples.edit)
                }
            } footer: {
                Text("ios:settings.cards.footer")
            }
        }
        .sensoryFeedback(.selection, trigger: [terminal, fileReads, fileEdits])
    }
}

/// A card as a chat draws it, under its switch: a picture, not a control, faded while the switch is off. Beyond the
/// largest standard text size it would not fit a row, and the switch's name says enough.
private struct WorkingCardExample<Card: View>: View {
    let isShown: Bool
    @ViewBuilder let card: Card
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        if !dynamicTypeSize.isAccessibilitySize {
            card
                .dynamicTypeSize(...DynamicTypeSize.large)
                .allowsHitTesting(false)
                .accessibilityHidden(true)
                .opacity(isShown ? 1 : 0.35)
                .saturation(isShown ? 1 : 0)
                .animation(reduceMotion ? nil : .easeOut(duration: 0.2), value: isShown)
        }
    }
}

/// What the examples show: results shaped as the desktop's tools return them.
enum WorkingCardExamples {
    private static func json(_ text: String) -> JSONValue {
        (try? JSONDecoder().decode(JSONValue.self, from: Data(text.utf8))) ?? .null
    }

    static let terminal = ToolCard(
        id: "example-terminal", toolName: "terminal", kind: .terminal,
        payload: json(#"""
            {"command":"node -e \"console.log(require('./package.json').scripts)\"","cwd":"/Users/me/Code/app","exitCode":0,"stdout":"{\n  build: 'vite build',\n  test: 'vitest run'\n}","stderr":""}
            """#))

    static let read = ToolCard(
        id: "example-read", toolName: "read_file", kind: .generic,
        payload: json(#"""
            {"path":"/Users/me/Code/app/README.md","size":64,"content":"# App\n\nA small web app.\n\nbun install && bun run dev"}
            """#),
        arguments: json(#"{"path":"/Users/me/Code/app/README.md"}"#))

    static let edit = ToolCard(
        id: "example-edit", toolName: "edit_file", kind: .generic,
        payload: json(#"""
            {"path":"/Users/me/Code/app/src/retry.ts","replacements":1,"linesBefore":24,"linesAfter":24}
            """#),
        arguments: json(#"""
            {"path":"/Users/me/Code/app/src/retry.ts","old_string":"const maxAttempts = 3","new_string":"const maxAttempts = 5","replace_all":false}
            """#))
}
