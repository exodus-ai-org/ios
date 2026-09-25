import SwiftUI

/// Settings → Personality: how Exodus answers in every chat, on the phone and on the computer alike. Sections and
/// fields follow the desktop's `personality.tsx`: Style, Instructions, About you.
struct PersonalitySettingsPage: View {
    @Bindable var viewModel: PersonalityViewModel
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        Form {
            Section {
                stylePicker
                levelPicker(Text("settings:personality.warm"), selection: $viewModel.warm)
                levelPicker(Text("settings:personality.enthusiastic"), selection: $viewModel.enthusiastic)
                levelPicker(Text("settings:personality.headersAndLists"), selection: $viewModel.headersAndLists)
                levelPicker(Text("settings:personality.emoji"), selection: $viewModel.emoji)
            } header: {
                Text("settings:personality.sections.style")
            } footer: {
                Text("settings:personality.baseStyle.description")
            }

            Section {
                SettingsFieldRow {
                    Text("settings:personality.customInstructions.label")
                } field: {
                    TextField(
                        "settings:personality.customInstructions.label", text: $viewModel.customInstructions,
                        prompt: Text("settings:personality.customInstructions.placeholder"), axis: .vertical)
                        .lineLimit(3...10)
                }
            } header: {
                Text("settings:personality.sections.instructions")
            }

            Section {
                SettingsFieldRow {
                    Text("settings:personality.nickname.label")
                } field: {
                    TextField(
                        "settings:personality.nickname.label", text: $viewModel.nickname,
                        prompt: Text("settings:personality.nickname.placeholder"))
                        .textContentType(.nickname)
                }
                SettingsFieldRow {
                    Text("settings:personality.occupation.label")
                } field: {
                    TextField(
                        "settings:personality.occupation.label", text: $viewModel.occupation,
                        prompt: Text("settings:personality.occupation.placeholder"))
                        .textContentType(.jobTitle)
                }
                SettingsFieldRow {
                    Text("settings:personality.aboutYou.label")
                } field: {
                    TextField(
                        "settings:personality.aboutYou.label", text: $viewModel.aboutYou,
                        prompt: Text("settings:personality.aboutYou.placeholder"), axis: .vertical)
                        .lineLimit(3...10)
                }
            } header: {
                Text("settings:personality.sections.aboutYou")
            } footer: {
                Text("ios:settings.personality.appliesToComputer")
            }

            SettingsErrorSection(message: viewModel.errorMessage)
        }
        .disabled(!viewModel.hasLoaded)
        .refreshable { await viewModel.refresh() }
        .overlay {
            if viewModel.isLoading && !viewModel.hasLoaded { ProgressView() }
        }
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                Button("common:action.save") {
                    Task {
                        if await viewModel.save() { dismiss() }
                    }
                }
                .disabled(!viewModel.hasChanges || viewModel.isSaving)
            }
        }
        // Re-read on appear so the form starts from what the computer holds now, unless it has unsaved edits.
        .task {
            if !viewModel.hasChanges { await viewModel.load() }
        }
    }

    private var stylePicker: some View {
        Picker("settings:personality.baseStyle.label", selection: $viewModel.baseStyle) {
            ForEach(PersonalityViewModel.baseStyles, id: \.self) { style in
                Self.baseStyleLabel(style).tag(style)
            }
            unknownOption(viewModel.baseStyle, known: PersonalityViewModel.baseStyles)
        }
    }

    private func levelPicker(_ title: Text, selection: Binding<String>) -> some View {
        Picker(selection: selection) {
            ForEach(PersonalityViewModel.levels, id: \.self) { level in
                Self.levelLabel(level).tag(level)
            }
            unknownOption(selection.wrappedValue, known: PersonalityViewModel.levels)
        } label: {
            title
        }
    }

    /// A value the desktop stored that this app's enum does not have stays selectable, shown as stored.
    @ViewBuilder
    private func unknownOption(_ value: String, known: [String]) -> some View {
        if !known.contains(value) {
            Text(verbatim: value).tag(value)
        }
    }

    @ViewBuilder
    static func baseStyleLabel(_ style: String) -> some View {
        switch style {
        case "professional": Text("settings:personality.baseStyle.options.professional")
        case "friendly": Text("settings:personality.baseStyle.options.friendly")
        case "candid": Text("settings:personality.baseStyle.options.candid")
        case "quirky": Text("settings:personality.baseStyle.options.quirky")
        case "efficient": Text("settings:personality.baseStyle.options.efficient")
        case "cynical": Text("settings:personality.baseStyle.options.cynical")
        default: Text("settings:personality.baseStyle.options.default")
        }
    }

    @ViewBuilder
    static func levelLabel(_ level: String) -> some View {
        switch level {
        case "more": Text("settings:personality.level.more")
        case "less": Text("settings:personality.level.less")
        default: Text("settings:personality.level.default")
        }
    }
}
