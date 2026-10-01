// Sources/HealthFeature/UI/CategoryCard.swift
import Models
import OdyKit
import SwiftUI

/// One category on the home: its colour, its number, and its own small Ody.
struct CategoryCard: View {
    let category: HealthCategory
    let snapshot: HealthSnapshot
    let line: String?

    var body: some View {
        let style = CategoryStyle.of(category)
        let mood = HealthRules.card(category, in: snapshot)
        ZStack(alignment: .bottomTrailing) {
            LinearGradient(colors: style.gradient, startPoint: .topLeading, endPoint: .bottomTrailing)
            OdySceneView(OdyScene(card: category, mood: mood), showsBackground: false)
                .frame(width: 70, height: 70)
                .offset(x: 6, y: 8)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                Label { Text(style.title) } icon: { Image(systemName: style.systemImage) }
                    .font(.caption.weight(.bold))
                    .opacity(0.75)
                Text(verbatim: CategoryValue.text(category, in: snapshot) ?? "—")
                    .font(.title3.weight(.heavy))
                    .monospacedDigit()
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                    .contentTransition(.numericText())
                if let line {
                    Text(verbatim: line).font(.caption2).opacity(0.75).lineLimit(2)
                        // Clear of the Ody in the corner.
                        .padding(.trailing, 44)
                }
                Spacer(minLength: 0)
            }
            .padding(12)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
        .foregroundStyle(style.ink)
        .frame(minHeight: 112)
        .clipShape(.rect(cornerRadius: 18))
        .contentShape(.rect(cornerRadius: 18))
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isButton)
    }
}
