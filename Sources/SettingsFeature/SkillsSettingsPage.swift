import Models
import SwiftUI

/// Settings → Installed skills: the desktop's Installed tab — name, version, source and install date, and the
/// switch. Finding, installing and uninstalling a skill stay on the computer.
struct SkillsSettingsPage: View {
    @Bindable var viewModel: SkillsSettingsViewModel

    var body: some View {
        Form {
            if let message = viewModel.errorMessage {
                Section {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("settings:skillsMarket.toast.updateFailed").font(.headline)
                        Text(verbatim: message).foregroundStyle(.secondary)
                    }
                }
            }
            SettingsErrorSection(message: viewModel.refreshError)
            switch viewModel.listState {
            case .idle, .loading:
                Section { ProgressView().frame(maxWidth: .infinity) }
            case .failed(let message):
                ListLoadFailedSection(title: Text("ios:settings.skills.loadFailed"), message: message) {
                    await viewModel.load()
                }
            case .loaded where viewModel.skills.isEmpty:
                Section {
                    ContentUnavailableView {
                        Label("settings:skillsMarket.installedTab.empty", systemImage: "shippingbox")
                    }
                } footer: {
                    Text("ios:settings.skills.desktopOnly")
                }
            case .loaded:
                Section {
                    ForEach(viewModel.skills) { skill in
                        Toggle(
                            isOn: Binding(
                                get: { skill.isActive }, set: { viewModel.setActive(skill.slug, $0) })
                        ) {
                            SkillRow(skill: skill)
                        }
                        .disabled(viewModel.pending.contains(skill.slug))
                    }
                } footer: {
                    Text("ios:settings.skills.desktopOnly")
                }
            }
        }
        .refreshable { await viewModel.load() }
        .task { if viewModel.pending.isEmpty { await viewModel.load() } }
    }
}

private struct SkillRow: View {
    let skill: InstalledSkill
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    var body: some View {
        let titleLayout =
            dynamicTypeSize.isAccessibilitySize
            ? AnyLayout(VStackLayout(alignment: .leading, spacing: 2))
            : AnyLayout(HStackLayout(alignment: .firstTextBaseline, spacing: 6))
        VStack(alignment: .leading, spacing: 3) {
            titleLayout {
                Text(verbatim: skill.displayName)
                if !skill.version.isEmpty {
                    Text(verbatim: skill.version).font(.caption.monospacedDigit()).foregroundStyle(.secondary)
                }
                if skill.isLegacy {
                    Text("settings:skillsMarket.installedTab.legacy")
                        .font(.caption2)
                        .padding(.horizontal, 5)
                        .padding(.vertical, 1)
                        .background(.fill.tertiary, in: .capsule)
                        .fixedSize()
                }
            }
            Text(verbatim: skill.registryId ?? skill.slug)
                .font(.footnote.monospaced())
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .truncationMode(.middle)
            if let date = skill.installedDate {
                Text(verbatim: Self.installed(date)).font(.footnote).foregroundStyle(.secondary)
            }
        }
    }

    private static func installed(_ date: Date) -> String {
        let formatted = date.formatted(date: .abbreviated, time: .omitted)
        return String(
            localized: "settings:skillsMarket.installedTab.installedAt", defaultValue: "Installed \(formatted)",
            comment: "When a skill was installed. %@ is the date.")
    }
}

/// A list's first load failed: what failed, the server's message, and Retry.
struct ListLoadFailedSection: View {
    let title: Text
    let message: String
    let retry: () async -> Void

    var body: some View {
        Section {
            VStack(alignment: .leading, spacing: 4) {
                title.font(.headline)
                Text(verbatim: message).foregroundStyle(.secondary)
            }
            Button("common:action.retry") { Task { await retry() } }
        }
    }
}
