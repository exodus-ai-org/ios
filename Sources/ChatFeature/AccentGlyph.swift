import Models
import SwiftUI
import UIKit

extension EnvironmentValues {
    /// The colour of a glyph drawn on the accent (the send button's arrow): white, as iOS draws it, unless the app's
    /// colour tone is too light for white. The app sets it from the tone; until it does, neutral's.
    @Entry public var accentGlyph: Color = Color(uiColor: .systemBackground)
    /// The app's colour tone, and what it is painted in. `.tint` cannot be read back as a colour, and map content
    /// (a route, a pin) needs one; the app sets these from the tone. `toneAccent` is the tone as a surface or a
    /// shape (its fill); `toneInk` is the tone as text and glyphs on the page, which is also what `.tint` is.
    /// Until the app sets them they are neutral's: black and white, never the system's blue.
    @Entry public var colorTone: ColorTone = .neutral
    @Entry public var toneAccent: Color = .primary
    @Entry public var toneInk: Color = .primary
}

extension View {
    /// A prominent button in the tone: the tone's fill behind its label. The label takes `accentGlyph` — black
    /// on a light fill such as yellow's, white on a dark one.
    func toneFill() -> some View { modifier(ToneFill()) }
}

private struct ToneFill: ViewModifier {
    @Environment(\.toneAccent) private var fill

    func body(content: Content) -> some View {
        content.tint(fill)
    }
}

extension ColorTone {
    /// The surface of what the user wrote: the tone washed far into the page (`surface`). Not the accent thinned
    /// out over whatever is behind it, which reads as a pastel.
    var surfaceColor: Color {
        Color(
            uiColor: UIColor { traits in
                let rgb = surface(traits.userInterfaceStyle == .dark ? .dark : .light)
                return UIColor(red: rgb.red, green: rgb.green, blue: rgb.blue, alpha: 1)
            })
    }
}
