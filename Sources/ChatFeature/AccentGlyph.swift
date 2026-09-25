import Models
import SwiftUI

extension EnvironmentValues {
    /// The colour of a glyph drawn on the accent (the send button's arrow): white, as iOS draws it, unless the app's
    /// colour tone is too light for white. The app sets it from the tone.
    @Entry public var accentGlyph: Color = .white
    /// The app's colour tone, and the accent it is painted in. `.tint` cannot be read back as a colour, and map
    /// content (a route, a pin) needs one; the app sets both from the tone.
    @Entry public var colorTone: ColorTone = .neutral
    @Entry public var toneAccent: Color = Color(uiColor: .systemBlue)
}
