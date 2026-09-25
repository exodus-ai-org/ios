import Charts
import Models
import SwiftUI

/// Settings → Profile: the desktop's `profile.tsx`, read-only and sized for a phone — the four stat tiles, token
/// activity over the last 30 days (the desktop's 52-week heatmap does not fit), activity insights with the total
/// cost, and the top models with their cost.
struct ProfileSettingsPage: View {
    @Bindable var viewModel: ProfileViewModel

    var body: some View {
        ScrollViewReader { proxy in
            form
                .task {
                    await viewModel.load()
                    #if DEBUG
                    await applyGalleryAction(proxy)
                    #endif
                }
        }
    }

    #if DEBUG
    private func applyGalleryAction(_ proxy: ScrollViewProxy) async {
        guard SettingsGalleryLaunch.isEnabled else { return }
        try? await Task.sleep(for: .milliseconds(400))
        switch SettingsGalleryLaunch.action {
        case "cumulative": viewModel.mode = .cumulative
        case "bottom": proxy.scrollTo(Self.topModelsID, anchor: .bottom)
        default: break
        }
    }
    #endif

    private static let topModelsID = "profile.topModels"

    private var form: some View {
        Form {
            switch viewModel.state {
            case .idle, .loading:
                Section { ProgressView().frame(maxWidth: .infinity) }
            case .failed(let message):
                Section {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("ios:settings.profile.loadFailed").font(.headline)
                        Text(verbatim: message).foregroundStyle(.secondary)
                    }
                    Button("common:action.retry") { Task { await viewModel.load() } }
                }
            case .loaded:
                if let usage = viewModel.usage, let stats = viewModel.stats {
                    SettingsErrorSection(message: viewModel.refreshError)
                    if usage.isEmpty {
                        Section {
                            ContentUnavailableView {
                                Label("settings:profile.topModels.empty", systemImage: "chart.bar")
                            }
                        }
                    } else {
                        statTiles(usage: usage, stats: stats)
                        activitySection(stats)
                    }
                    insightsSection(usage)
                    if !usage.isEmpty { topModelsSection(stats) }
                }
            }
        }
        .refreshable { await viewModel.load() }
    }

    private func statTiles(usage: UsageSummary, stats: UsageStats) -> some View {
        Section {
            Grid(horizontalSpacing: 12, verticalSpacing: 16) {
                GridRow {
                    StatTile(
                        value: UsageFormat.tokens(usage.totalTokens), label: Text("settings:profile.stats.lifetimeTokens"))
                    StatTile(value: UsageFormat.tokens(stats.peakDay), label: Text("settings:profile.stats.peakDay"))
                }
                GridRow {
                    StatTile(
                        value: UsageFormat.days(stats.currentStreak), label: Text("settings:profile.stats.currentStreak"))
                    StatTile(
                        value: UsageFormat.days(stats.longestStreak), label: Text("settings:profile.stats.longestStreak"))
                }
            }
            .padding(.vertical, 4)
        }
    }

    private func activitySection(_ stats: UsageStats) -> some View {
        Section {
            Picker(selection: $viewModel.mode) {
                Text("settings:profile.activity.mode.daily").tag(ProfileViewModel.ActivityMode.daily)
                Text("settings:profile.activity.mode.cumulative").tag(ProfileViewModel.ActivityMode.cumulative)
            } label: {
                Text("settings:profile.activity.heading")
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            ActivityChart(points: viewModel.mode == .daily ? stats.daily : stats.cumulative, mode: viewModel.mode)
                .dynamicTypeSize(...DynamicTypeSize.accessibility1)
                .frame(height: 180)
                .padding(.vertical, 4)
        } header: {
            Text("settings:profile.activity.heading")
        } footer: {
            Text(verbatim: Self.windowFooter(cost: UsageFormat.cost(stats.windowCost)))
        }
    }

    private static func windowFooter(cost: String) -> String {
        String(
            localized: "ios:settings.profile.windowFooter", defaultValue: "Last 30 days · \(cost) spent",
            comment: "Footer under the token activity chart. %@ is the cost of those 30 days, in US dollars.")
    }

    private func insightsSection(_ usage: UsageSummary) -> some View {
        Section {
            InsightRow(
                label: Text("settings:profile.insights.totalChats"), value: viewModel.chatCount.map { String($0) })
            InsightRow(
                label: Text("settings:profile.insights.modelRequests"),
                value: UsageFormat.tokens(Double(usage.totalRequests)))
            InsightRow(label: Text("ios:settings.profile.totalCost"), value: UsageFormat.cost(usage.totalCost))
            InsightRow(
                label: Text("settings:profile.insights.installedSkills"), value: viewModel.skills.map { String($0.count) })
            InsightRow(
                label: Text("settings:profile.insights.activeSkills"), value: viewModel.activeSkillCount.map { String($0) })
        } header: {
            Text("settings:profile.insights.sectionTitle")
        }
    }

    private func topModelsSection(_ stats: UsageStats) -> some View {
        Section {
            if stats.topModels.isEmpty {
                Text("settings:profile.topModels.empty").foregroundStyle(.secondary)
            }
            ForEach(stats.topModels) { model in
                HStack(alignment: .firstTextBaseline) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(verbatim: model.model).lineLimit(2)
                        if !model.provider.isEmpty {
                            Text(verbatim: model.provider).font(.footnote).foregroundStyle(.secondary)
                        }
                    }
                    Spacer(minLength: 8)
                    VStack(alignment: .trailing, spacing: 2) {
                        Text(verbatim: UsageFormat.tokens(model.tokens)).monospacedDigit()
                        Text(verbatim: UsageFormat.cost(model.cost)).font(.footnote).monospacedDigit()
                            .foregroundStyle(.secondary)
                    }
                }
                .accessibilityElement(children: .combine)
            }
        } header: {
            Text("settings:profile.topModels.sectionTitle")
        }
        .id(Self.topModelsID)
    }
}

private struct StatTile: View {
    let value: String
    let label: Text

    var body: some View {
        VStack(spacing: 4) {
            Text(verbatim: value).font(.title3.weight(.semibold)).monospacedDigit()
            label.font(.caption).foregroundStyle(.secondary).multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .accessibilityElement(children: .combine)
    }
}

private struct InsightRow: View {
    let label: Text
    /// Nil when that figure could not be read.
    let value: String?

    var body: some View {
        LabeledContent {
            Text(verbatim: value ?? "—").monospacedDigit()
        } label: {
            label
        }
    }
}

private struct ActivityChart: View {
    let points: [UsageStats.Point]
    let mode: ProfileViewModel.ActivityMode
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    var body: some View {
        Chart(points) { point in
            switch mode {
            case .daily:
                BarMark(
                    x: .value(Self.dayLabel, point.date, unit: .day),
                    y: .value(Self.tokensLabel, point.tokens)
                )
                .accessibilityLabel(Self.spokenDay(point))
                .accessibilityValue(Self.spokenTokens(point))
            case .cumulative:
                // One element per day for VoiceOver: the fill under the line repeats it.
                AreaMark(
                    x: .value(Self.dayLabel, point.date, unit: .day),
                    y: .value(Self.tokensLabel, point.tokens)
                )
                .opacity(0.25)
                .accessibilityHidden(true)
                LineMark(
                    x: .value(Self.dayLabel, point.date, unit: .day),
                    y: .value(Self.tokensLabel, point.tokens)
                )
                .accessibilityLabel(Self.spokenDay(point))
                .accessibilityValue(Self.spokenTokens(point))
            }
        }
        .chartYAxis {
            AxisMarks { value in
                AxisGridLine()
                AxisValueLabel {
                    if let tokens = value.as(Double.self) { Text(verbatim: UsageFormat.tokens(tokens)) }
                }
            }
        }
        .chartXAxis {
            AxisMarks(values: .stride(by: .day, count: dynamicTypeSize.isAccessibilitySize ? 14 : 7)) { _ in
                AxisGridLine()
                AxisValueLabel(format: .dateTime.month(.abbreviated).day())
            }
        }
    }

    static func spokenDay(_ point: UsageStats.Point, locale: Locale = .current) -> Text {
        Text(verbatim: point.date.formatted(.dateTime.month(.wide).day().locale(locale)))
    }

    static func spokenTokens(_ point: UsageStats.Point) -> Text {
        Text(verbatim: UsageFormat.spokenTokens(point.tokens))
    }

    private static var dayLabel: String {
        String(localized: "ios:settings.profile.chartDay", defaultValue: "Day", comment: "Chart axis: the day.")
    }

    private static var tokensLabel: String {
        String(localized: "ios:settings.profile.chartTokens", defaultValue: "Tokens", comment: "Chart axis: tokens used.")
    }
}
