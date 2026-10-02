import Foundation

/// The hub's groups, in order. A group with no page yet is not shown.
enum SettingsGroup: CaseIterable, Identifiable {
    case general, computer, ai, behaviour, data

    var id: Self { self }

    var title: LocalizedStringResource {
        switch self {
        case .general: LocalizedStringResource("settings:nav.general.title")
        case .computer: LocalizedStringResource("ios:settings.hub.group.computer")
        case .ai: LocalizedStringResource("ios:settings.hub.group.ai")
        case .behaviour: LocalizedStringResource("ios:settings.hub.group.behaviour")
        case .data: LocalizedStringResource("ios:settings.hub.group.data")
        }
    }
}

/// A page the hub pushes. Its row is one line in `SettingsHubRow.all`; its view is a case in
/// `SettingsView.destination(for:)`.
enum SettingsPage: String, Hashable, CaseIterable {
    case colorTone, workingCards, connection, providers, tools, skills, mcp, personality, memory, profile, backup
}

struct SettingsHubRow: Identifiable {
    let page: SettingsPage
    let group: SettingsGroup
    let title: LocalizedStringResource
    let systemImage: String

    var id: SettingsPage { page }

    static let all: [SettingsHubRow] = [
        SettingsHubRow(
            page: .colorTone, group: .general, title: LocalizedStringResource("settings:general.colorTone.label"),
            systemImage: "paintpalette"),
        SettingsHubRow(
            page: .workingCards, group: .general,
            title: LocalizedStringResource(
                "ios:settings.cards.title", defaultValue: "Working cards",
                comment: "Settings row and page title: switches that hide the cards a reply draws while the model works."),
            systemImage: "rectangle.stack"),
        SettingsHubRow(
            page: .connection, group: .computer, title: LocalizedStringResource("ios:settings.hub.connection"),
            systemImage: "desktopcomputer"),
        SettingsHubRow(
            page: .providers, group: .ai, title: LocalizedStringResource("settings:nav.aiProviders.title"),
            systemImage: "sparkles"),
        SettingsHubRow(
            page: .tools, group: .ai, title: LocalizedStringResource("settings:nav.builtinTools.title"),
            systemImage: "wrench.and.screwdriver"),
        SettingsHubRow(
            page: .skills, group: .ai, title: LocalizedStringResource("settings:profile.insights.installedSkills"),
            systemImage: "shippingbox"),
        SettingsHubRow(
            page: .mcp, group: .ai, title: LocalizedStringResource("settings:nav.mcpServers.title"),
            systemImage: "powerplug"),
        SettingsHubRow(
            page: .personality, group: .behaviour, title: LocalizedStringResource("settings:nav.personality.title"),
            systemImage: "person.crop.circle"),
        SettingsHubRow(
            page: .memory, group: .behaviour, title: LocalizedStringResource("settings:nav.memory.title"),
            systemImage: "brain"),
        SettingsHubRow(
            page: .profile, group: .data, title: LocalizedStringResource("settings:nav.profile.title"),
            systemImage: "chart.bar"),
        SettingsHubRow(
            page: .backup, group: .data, title: LocalizedStringResource("settings:dataControls.sections.backups"),
            systemImage: "externaldrive"),
    ]

    static func rows(in group: SettingsGroup) -> [SettingsHubRow] { all.filter { $0.group == group } }

    static func row(for page: SettingsPage) -> SettingsHubRow { all.first { $0.page == page }! }
}
