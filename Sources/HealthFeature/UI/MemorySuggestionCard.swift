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
                // Side by side, or stacked when large type won't fit them on a line.
                ViewThatFits(in: .horizontal) {
                    HStack(spacing: 6) { buttons }
                    VStack(alignment: .leading, spacing: 6) { buttons }
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

    @ViewBuilder private var buttons: some View {
        Button("ios:health.memory.remember", action: onRemember)
            .buttonStyle(.borderedProminent)
            .tint(OdyPalette.marigold)
        Button("ios:health.memory.dismiss", action: onDismiss)
            .buttonStyle(.bordered)
            .tint(.primary)
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

    @State private var progress: CGFloat = 0
    private static let duration = 0.62

    var body: some View {
        RoundedRectangle(cornerRadius: 18)
            .fill(HealthSurface.card)
            .strokeBorder(OdyPalette.hex(0xF0D58A), style: StrokeStyle(lineWidth: 1.5, dash: [5, 4]))
            .frame(width: from.width, height: from.height)
            .modifier(FlightPath(progress: progress, from: from, to: to))
            .onAppear { withAnimation(.linear(duration: Self.duration)) { progress = 1 } }
            .task {
                try? await Task.sleep(for: .seconds(Self.duration))
                onLanded()
            }
            .allowsHitTesting(false)
            .accessibilityHidden(true)
    }
}

/// Where the flying card is at a point of its flight: eased along a curve that rises above both ends.
private struct FlightPath: ViewModifier, Animatable {
    var progress: CGFloat
    let from: CGRect
    let to: CGRect

    nonisolated var animatableData: CGFloat {
        get { progress }
        set { progress = newValue }
    }

    func body(content: Content) -> some View {
        let p = progress
        let control = CGPoint(x: (from.midX + to.midX) / 2 - 40, y: min(from.minY, to.minY) - 90)
        let e = p < 0.5 ? 4 * p * p * p : 1 - pow(-2 * p + 2, 3) / 2
        let x = (1 - e) * (1 - e) * from.midX + 2 * (1 - e) * e * control.x + e * e * to.midX
        let y = (1 - e) * (1 - e) * from.midY + 2 * (1 - e) * e * control.y + e * e * to.midY
        content
            .scaleEffect(1 - 0.94 * e)
            .rotationEffect(.degrees(-30 * e))
            .opacity(p > 0.9 ? (1 - p) * 10 : 1)
            .position(x: x, y: y)
    }
}
