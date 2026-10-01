import Foundation
import Models
import SwiftUI

/// A question asked from Health opens with the day's numbers (`HealthContext`); the transcript shows them as a small
/// card of chips over the question. Tap to see everything that was sent.
struct HealthContextCard: View {
    struct Chip: Equatable {
        let systemImage: String
        let text: String
    }

    let json: String
    @State private var expanded = false

    // Resources, not bare literals: a ternary of literals can pick `Text`'s verbatim overload.
    private static let collapseHint = LocalizedStringResource("ios:chat.health.collapse")
    private static let expandHint = LocalizedStringResource("ios:chat.health.expand")

    static func chips(json: String) -> [Chip] {
        let data = Data(json.utf8)
        if let s = try? JSONDecoder().decode(HealthSnapshot.self, from: data) {
            var out: [Chip] = []
            if let sleep = s.sleep {
                out.append(
                    Chip(
                        systemImage: "moon.zzz.fill",
                        text: Duration.seconds(sleep.asleepMin * 60).formatted(
                            .units(allowed: [.hours, .minutes], width: .narrow))))
            }
            if let a = s.activity { out.append(Chip(systemImage: "figure.walk", text: a.steps.formatted())) }
            if let hr = s.recovery?.restingHr, hr.isFinite {
                let n = Int(hr)
                out.append(
                    Chip(
                        systemImage: "heart.fill",
                        text: String(
                            localized: "ios:chat.health.bpm", defaultValue: "\(n) bpm",
                            comment: "Health card in a chat: resting heart rate.")))
            }
            if let cups = s.body?.waterCups {
                out.append(
                    Chip(
                        systemImage: "drop.fill",
                        text: String(
                            localized: "ios:chat.health.cups", defaultValue: "\(cups) cups",
                            comment: "Health card in a chat: cups of water today.")))
            }
            return out.isEmpty ? [Chip(systemImage: "heart.text.square", text: s.date)] : out
        }
        if let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
            let category = object["category"] as? String
        {
            return [Chip(systemImage: "heart.text.square", text: categoryTitle(category))]
        }
        return [Chip(systemImage: "heart.text.square", text: "Health")]  // l10n:ignore: product name
    }

    /// A week block names its category by its wire name; show Health's own title for it. The keys are Health's
    /// (`ios:health.category.*`), read here by name since Chat does not depend on that module.
    static func categoryTitle(_ wire: String) -> String {
        switch wire {
        case "sleep": String(localized: "ios:health.category.sleep", defaultValue: "Sleep")
        case "activity": String(localized: "ios:health.category.activity", defaultValue: "Activity")
        case "recovery": String(localized: "ios:health.category.recovery", defaultValue: "Heart & recovery")
        case "body": String(localized: "ios:health.category.body", defaultValue: "Body & mood")
        default: wire
        }
    }

    var body: some View {
        let chips = Self.chips(json: json)
        VStack(alignment: .leading, spacing: 6) {
            Button {
                withAnimation(.smooth) { expanded.toggle() }
            } label: {
                HStack(spacing: 8) {
                    ForEach(chips, id: \.systemImage) { chip in
                        Label(chip.text, systemImage: chip.systemImage).font(.caption.weight(.semibold))
                    }
                    Image(systemName: expanded ? "chevron.up" : "chevron.down").font(.caption2)  // l10n:ignore: symbol names
                }
                .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
            // What it is, the numbers, and whether everything that was sent is shown.
            .accessibilityLabel(Text("ios:chat.health.attached"))
            .accessibilityValue(accessibilityValue(chips))
            .accessibilityHint(Text(expanded ? Self.collapseHint : Self.expandHint))
            if expanded {
                Text(verbatim: json).font(.caption2.monospaced()).foregroundStyle(.secondary).textSelection(.enabled)
            }
        }
    }

    private func accessibilityValue(_ chips: [Chip]) -> Text {
        var parts = chips.map(\.text)
        if expanded {
            parts.append(
                String(
                    localized: "ios:chat.health.expanded", defaultValue: "showing everything sent",
                    comment: "Health card in a chat, VoiceOver: the full numbers are shown."))
        }
        return Text(verbatim: parts.joined(separator: ", "))  // l10n:ignore: list separator
    }
}
