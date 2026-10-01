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
            if let r = s.recovery, let hr = r.restingHr {
                out.append(Chip(systemImage: "heart.fill", text: "\(Int(hr)) bpm"))  // l10n:ignore: unit
            }
            if let b = s.body { out.append(Chip(systemImage: "drop.fill", text: "×\(b.waterCups)")) }  // l10n:ignore: count
            return out.isEmpty ? [Chip(systemImage: "heart.text.square", text: s.date)] : out
        }
        if let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
            let category = object["category"] as? String
        {
            return [Chip(systemImage: "heart.text.square", text: category)]
        }
        return [Chip(systemImage: "heart.text.square", text: "Health")]  // l10n:ignore: product name
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Button {
                withAnimation(.smooth) { expanded.toggle() }
            } label: {
                HStack(spacing: 8) {
                    ForEach(Self.chips(json: json), id: \.systemImage) { chip in
                        Label(chip.text, systemImage: chip.systemImage).font(.caption.weight(.semibold))
                    }
                    Image(systemName: expanded ? "chevron.up" : "chevron.down").font(.caption2)
                }
                .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
            if expanded {
                Text(verbatim: json).font(.caption2.monospaced()).foregroundStyle(.secondary).textSelection(.enabled)
            }
        }
        .accessibilityLabel(Text("ios:chat.health.attached"))
    }
}
