import SwiftUI

/// Ody, the Exodus mascot, as a living SwiftUI character and the scenes it appears in. The body curve and palette
/// come from the desktop's `brand/art.mjs` — keep them in sync.
public enum OdyKit {
    static let version = 1
}

public enum OdyPalette {
    public static func hex(_ value: UInt32, _ opacity: Double = 1) -> Color {
        Color(
            red: Double((value >> 16) & 0xFF) / 255, green: Double((value >> 8) & 0xFF) / 255,
            blue: Double(value & 0xFF) / 255, opacity: opacity)
    }

    public static let ink = hex(0x1B1B1F)
    public static let blush = hex(0xFF7E95, 0.55)
    public static let bindle = hex(0xE5392E)
    public static let bindleDark = hex(0xB82A22)
    public static let stick = hex(0x9C7448)
    public static let sun = hex(0xFFD84A)
    public static let marigold = hex(0xFFAE1A)
    public static let bodyStops: [Gradient.Stop] = [
        .init(color: hex(0xFFFFFF), location: 0), .init(color: hex(0xF6F2EC), location: 0.5),
        .init(color: hex(0xD3C8B8), location: 1),
    ]
}
