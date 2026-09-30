import SwiftUI

/// The measures of everything that stands in a reply as a card. One set, so that cards of different tools read as
/// one family: the same corner, the same margin inside it, the same header.
enum CardStyle {
    /// A card's corner. Large enough to sit with the system's own surfaces (sheets, the composer), and continuous.
    static let radius: CGFloat = 20
    /// The corner of what stands inside a card — a thumbnail, a preview, a selected row — and of a block that is
    /// not a card: concentric with the card's at the margin below.
    static let innerRadius: CGFloat = 12
    /// A card's margin: what stands inside keeps this far from its edge.
    static let inset: CGFloat = 16

    static var shape: RoundedRectangle { RoundedRectangle(cornerRadius: radius, style: .continuous) }
    static var innerShape: RoundedRectangle { RoundedRectangle(cornerRadius: innerRadius, style: .continuous) }
}

/// What a card is made of.
enum CardMaterial: String {
    /// Liquid Glass: the card is a pane over the transcript.
    case glass
    /// A quiet fill of the system's own, without an edge.
    case solid

    #if DEBUG
    /// `-CardMaterial glass|solid`: the same screen in either, to compare them.
    static let launchOverride: CardMaterial? = {
        let arguments = ProcessInfo.processInfo.arguments
        guard let index = arguments.firstIndex(of: "-CardMaterial"), index + 1 < arguments.count else { return nil }
        return CardMaterial(rawValue: arguments[index + 1])
    }()
    #endif
}

extension EnvironmentValues {
    @Entry var cardMaterial: CardMaterial = .glass
}

/// A card's surface. Glass where the system draws it; with Reduce Transparency, or where a card is asked to be
/// solid, the fill the system uses for grouped content.
struct CardSurface: ViewModifier {
    @Environment(\.cardMaterial) private var chosen
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    private var material: CardMaterial {
        #if DEBUG
        if let override = CardMaterial.launchOverride { return override }
        #endif
        return reduceTransparency ? .solid : chosen
    }

    func body(content: Content) -> some View {
        let framed = content
            .frame(maxWidth: .infinity, alignment: .leading)
            .clipShape(CardStyle.shape)
        switch material {
        case .glass:
            framed.glassEffect(.regular, in: CardStyle.shape)
        case .solid:
            framed.background(Color(.secondarySystemBackground), in: CardStyle.shape)
        }
    }
}

extension View {
    /// The band a card opens with — its tool's icon, a title, where it stands. No fill of its own: the title is
    /// type on the card, not a bar across it, which read as a row that was selected.
    func cardHeader() -> some View {
        padding(.horizontal, CardStyle.inset)
            .padding(.top, 14)
            .padding(.bottom, 12)
    }
}
