// Sources/HealthFeature/UI/MemorySuggestionCard.swift
import Models
import OdyKit
import SwiftUI

/// "Remember this?" — Remember folds the card and flies it into Ody's bindle; No thanks slides it away.
struct MemorySuggestionCard: View {
    let suggestion: HealthSummary.MemorySuggestion
    let onRemember: () -> Void
    let onDismiss: () -> Void

    var body: some View {
        HStack(alignment: .center, spacing: 10) {
            OdyView(expression: .curious, pokable: false)
                .frame(width: 34, height: 38)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 8) {
                Text(prompt).font(.subheadline)
                HStack(spacing: 6) {
                    Button("ios:health.memory.remember", action: onRemember)
                        .buttonStyle(.borderedProminent)
                        .tint(OdyPalette.marigold)
                    Button("ios:health.memory.dismiss", action: onDismiss)
                        .buttonStyle(.bordered)
                        .tint(OdyPalette.hex(0x3A2A00))
                }
                .buttonBorderShape(.capsule)
                .controlSize(.small)
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(HealthSurface.card, in: .rect(cornerRadius: 18))
        .overlay(
            RoundedRectangle(cornerRadius: 18)
                .strokeBorder(OdyPalette.hex(0xF0D58A), style: StrokeStyle(lineWidth: 1.5, dash: [5, 4])))
    }

    /// "Remember this?" in bold, then the suggestion as the computer wrote it.
    private var prompt: AttributedString {
        var ask = AttributedString(localized: "ios:health.memory.ask")
        ask.inlinePresentationIntent = .stronglyEmphasized
        return ask + AttributedString(" " + suggestion.summary)
    }
}

/// The card's flight: along an arc from where the card was into the bindle, shrinking and turning.
struct MemoryFlight: View {
    let from: CGRect
    let to: CGRect
    let onLanded: () -> Void

    var body: some View {
        let control = CGPoint(x: (from.midX + to.midX) / 2 - 40, y: min(from.minY, to.minY) - 90)
        RoundedRectangle(cornerRadius: 18)
            .fill(HealthSurface.card)
            .strokeBorder(OdyPalette.hex(0xF0D58A), style: StrokeStyle(lineWidth: 1.5, dash: [5, 4]))
            .frame(width: from.width, height: from.height)
            .keyframeAnimator(initialValue: CGFloat(0), repeating: false) { view, p in
                let e = p < 0.5 ? 4 * p * p * p : 1 - pow(-2 * p + 2, 3) / 2
                let x = (1 - e) * (1 - e) * from.midX + 2 * (1 - e) * e * control.x + e * e * to.midX
                let y = (1 - e) * (1 - e) * from.midY + 2 * (1 - e) * e * control.y + e * e * to.midY
                view
                    .scaleEffect(1 - 0.94 * e)
                    .rotationEffect(.degrees(-30 * e))
                    .opacity(p > 0.9 ? (1 - p) * 10 : 1)
                    .position(x: x, y: y)
            } keyframes: { _ in
                LinearKeyframe(CGFloat(1), duration: 0.62)
            }
            .task {
                try? await Task.sleep(for: .milliseconds(620))
                onLanded()
            }
            .allowsHitTesting(false)
            .accessibilityHidden(true)
    }
}
