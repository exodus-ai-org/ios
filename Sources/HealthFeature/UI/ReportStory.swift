// Sources/HealthFeature/UI/ReportStory.swift
import Models
import OdyKit
import SwiftUI

/// The day's note as insight stories (direction A): a green eyebrow and a bold headline with its key phrase in the
/// category's gradient, one card per insight (icon, sentence with its numbers coloured, the big number), and a small
/// idea to end on. Colours and icons come from `CategoryStyle`; the model only says which category.
struct ReportStory: View {
    let summary: HealthSummary
    private let stories: [(HealthCategory, HealthSummary.Insight)]
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @ScaledMetric(relativeTo: .title2) private var headlineSize: CGFloat = 26
    @State private var shown = false

    /// Nil when there are no insights this app can draw, so the caller shows the Markdown note instead.
    init?(_ summary: HealthSummary) {
        let stories = ReportText.stories(summary)
        guard !stories.isEmpty else { return nil }
        self.summary = summary
        self.stories = stories
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            VStack(alignment: .leading, spacing: 6) {
                Text("ios:health.report.eyebrow")
                    .font(.footnote.weight(.bold))
                    .foregroundStyle(ReportInk.green)
                headline
                    .font(.system(size: headlineSize, weight: .heavy, design: .rounded))
                    .tracking(-0.5)
                    .lineSpacing(2)
                    .accessibilityAddTraits(.isHeader)
            }
            .padding(.bottom, 4)
            .entrance(0, shown: shown, rise: !reduceMotion)
            ForEach(Array(stories.enumerated()), id: \.offset) { index, story in
                InsightCard(category: story.0, insight: story.1)
                    .entrance(index + 1, shown: shown, rise: !reduceMotion)
            }
            if let nudge = summary.nudge, !nudge.isEmpty {
                NudgeCard(text: nudge)
                    .entrance(stories.count + 1, shown: shown, rise: !reduceMotion)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .onAppear { shown = true }
    }

    /// The headline with its phrase in the category's gradient. An AttributedString can't carry a gradient, so the
    /// pieces are joined as an interpolation built in code: no string literal, so nothing lands in the catalog.
    private var headline: Text {
        guard let phrase = summary.headlineHighlight,
            let category = summary.headlineCategory.flatMap(HealthCategory.init(rawValue:))
        else { return Text(verbatim: summary.headline) }
        let gradient = LinearGradient(
            colors: CategoryStyle.of(category).accentGradient, startPoint: .leading, endPoint: .trailing)
        let runs = ReportText.runs(summary.headline, highlights: [phrase])
        var joined = LocalizedStringKey.StringInterpolation(literalCapacity: 0, interpolationCount: runs.count)
        for run in runs {
            let piece = Text(verbatim: run.text)
            joined.appendInterpolation(run.isHighlight ? piece.foregroundStyle(gradient) : piece)
        }
        return Text(LocalizedStringKey(stringInterpolation: joined))
    }
}

/// One insight: the category's icon and, when there is one, its number at the top; the sentence below.
private struct InsightCard: View {
    let category: HealthCategory
    let insight: HealthSummary.Insight
    @ScaledMetric(relativeTo: .title) private var statSize: CGFloat = 28
    @ScaledMetric(relativeTo: .title2) private var iconSize: CGFloat = 24

    var body: some View {
        let style = CategoryStyle.of(category)
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .top) {
                Image(systemName: style.symbol)
                    .font(.system(size: iconSize, weight: .semibold))
                    .foregroundStyle(style.accent)
                    .frame(minHeight: iconSize + 4, alignment: .topLeading)
                    .accessibilityHidden(true)
                Spacer(minLength: 12)
                if let stat = insight.stat { statView(stat, style: style) }
            }
            ReportText.sentence(insight.text, highlights: insight.highlights, accent: style.accent)
                .font(.body.weight(.semibold))
                .lineSpacing(3)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
        .background(HealthSurface.card, in: .rect(cornerRadius: 22))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(verbatim: spoken))
    }

    private func statView(_ stat: HealthSummary.Stat, style: CategoryStyle) -> some View {
        VStack(alignment: .trailing, spacing: 1) {
            HStack(alignment: .firstTextBaseline, spacing: 3) {
                Text(verbatim: stat.value)
                    .font(.system(size: statSize, weight: .heavy, design: .rounded))
                    .tracking(-0.5)
                    .monospacedDigit()
                    .foregroundStyle(
                        LinearGradient(colors: style.accentGradient, startPoint: .leading, endPoint: .trailing))
                Text(verbatim: stat.unit).font(.caption.weight(.bold)).foregroundStyle(.secondary)
            }
            if let caption = stat.caption {
                Text(verbatim: caption).font(.caption2.weight(.medium)).foregroundStyle(.secondary)
            }
        }
        .lineLimit(1)
        .minimumScaleFactor(0.7)
    }

    /// The sentence, then the number, so VoiceOver reads one card as one thought.
    private var spoken: String {
        guard let stat = insight.stat else { return insight.text }
        return [insight.text, "\(stat.value) \(stat.unit)", stat.caption].compactMap(\.self).joined(separator: ", ")
    }
}

/// The closing idea, on a mint card.
private struct NudgeCard: View {
    let text: String

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("ios:health.report.nudge").font(.footnote.weight(.bold)).foregroundStyle(ReportInk.green)
            Text(verbatim: text).font(.callout.weight(.semibold)).lineSpacing(3)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
        .background(
            LinearGradient(colors: ReportInk.mint, startPoint: .topLeading, endPoint: .bottomTrailing),
            in: .rect(cornerRadius: 22)
        )
        .accessibilityElement(children: .combine)
    }
}

/// The note's own colours: the green of "today" and of the small idea (4.5:1 on the page and the mint), and the
/// mint behind it.
enum ReportInk {
    static let green = Color.adaptive(0x1F7A3A, dark: 0x7FE0A0)
    static let mint = [Color.adaptive(0xE6F6E9, dark: 0x173322), Color.adaptive(0xF4FBF2, dark: 0x1E2B22)]
}

/// Splitting a sentence around the phrases the model marked.
enum ReportText {
    struct Run: Equatable {
        var text: String
        var isHighlight: Bool
    }

    /// The insights this app can draw, in the note's order: one in a category it doesn't know is left out.
    static func stories(_ summary: HealthSummary) -> [(HealthCategory, HealthSummary.Insight)] {
        (summary.insights ?? []).compactMap { i in HealthCategory(rawValue: i.category).map { ($0, i) } }
    }

    /// The text cut at each highlight's first occurrence, in reading order. A highlight that isn't in the text, or
    /// overlaps one already taken, is left plain: the desktop checks them, but a cached or older report may not be.
    static func runs(_ text: String, highlights: [String]) -> [Run] {
        var taken: [Range<String.Index>] = []
        for h in highlights where !h.isEmpty {
            guard let r = text.range(of: h), !taken.contains(where: { $0.overlaps(r) }) else { continue }
            taken.append(r)
        }
        taken.sort { $0.lowerBound < $1.lowerBound }
        var out: [Run] = []
        var cursor = text.startIndex
        for r in taken {
            if cursor < r.lowerBound { out.append(Run(text: String(text[cursor..<r.lowerBound]), isHighlight: false)) }
            out.append(Run(text: String(text[r]), isHighlight: true))
            cursor = r.upperBound
        }
        if cursor < text.endIndex { out.append(Run(text: String(text[cursor...]), isHighlight: false)) }
        return out
    }

    /// The sentence with each highlight bold in the category's colour.
    static func sentence(_ text: String, highlights: [String], accent: Color) -> Text {
        var attributed = AttributedString()
        for run in runs(text, highlights: highlights) {
            var piece = AttributedString(run.text)
            if run.isHighlight {
                piece.foregroundColor = accent
                piece.font = .body.weight(.bold)
            }
            attributed += piece
        }
        return Text(attributed)
    }
}

extension View {
    /// Fades in and rises 8 pt, 60 ms after the one before; under Reduce Motion it only fades.
    fileprivate func entrance(_ index: Int, shown: Bool, rise: Bool) -> some View {
        opacity(shown ? 1 : 0)
            .offset(y: shown || !rise ? 0 : 8)
            .animation(.smooth(duration: 0.45).delay(Double(index) * 0.06), value: shown)
    }
}
