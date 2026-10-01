// Sources/OdyKit/DaySky.swift
import SwiftUI

public struct RGB: Equatable, Sendable {
    public var r: Double, g: Double, b: Double

    public init(hex: UInt32) {
        r = Double((hex >> 16) & 0xFF) / 255
        g = Double((hex >> 8) & 0xFF) / 255
        b = Double(hex & 0xFF) / 255
    }

    init(r: Double, g: Double, b: Double) {
        self.r = r
        self.g = g
        self.b = b
    }

    public func mixed(with other: RGB, _ t: Double) -> RGB {
        RGB(r: r + (other.r - r) * t, g: g + (other.g - g) * t, b: b + (other.b - b) * t)
    }

    public var color: Color { Color(red: r, green: g, blue: b) }
}

/// The hero's sky by the clock: night indigo, a peach dawn, the brand's warm yellow by day, an orange sunset and a
/// violet dusk. Hours wrap, so a scrub from 18:00 yesterday to now reads straight through midnight.
public enum DaySky {
    /// (clock hour, top, bottom) — 0 and 24 are the same night.
    static let keys: [(Double, RGB, RGB)] = [
        (0, RGB(hex: 0x141235), RGB(hex: 0x3D3480)),
        (5, RGB(hex: 0x1D1A4A), RGB(hex: 0x4A3F99)),
        (6, RGB(hex: 0xF59E7B), RGB(hex: 0xFFD9A0)),
        (8, RGB(hex: 0xFFE9A0), RGB(hex: 0xFFF4D0)),
        (12, RGB(hex: 0xFFE27A), RGB(hex: 0xFFF0BE)),
        (16.5, RGB(hex: 0xFFE27A), RGB(hex: 0xFFF0BE)),
        (18, RGB(hex: 0xF58B6B), RGB(hex: 0xFFC98A)),
        (19.5, RGB(hex: 0x3B2F7A), RGB(hex: 0x7A5FA8)),
        (21, RGB(hex: 0x141235), RGB(hex: 0x3D3480)),
        (24, RGB(hex: 0x141235), RGB(hex: 0x3D3480)),
    ]

    static func wrap(_ h: Double) -> Double {
        let m = h.truncatingRemainder(dividingBy: 24)
        return m < 0 ? m + 24 : m
    }

    public static func gradient(atClockHour hour: Double) -> (top: RGB, bottom: RGB) {
        let h = wrap(hour)
        for i in 0..<(keys.count - 1) where h <= keys[i + 1].0 {
            let (a, t1, b1) = keys[i]
            let (b, t2, b2) = keys[i + 1]
            let t = b > a ? (h - a) / (b - a) : 0
            return (t1.mixed(with: t2, t), b1.mixed(with: b2, t))
        }
        return (keys[0].1, keys[0].2)
    }

    /// 1 at night, 0 by day: fades out 5.5→6.3, back in 18.5→20.5.
    public static func night(atClockHour hour: Double) -> Double {
        let h = wrap(hour)
        switch h {
        case ..<5.5: return 1
        case ..<6.3: return 1 - (h - 5.5) / 0.8
        case ..<18.5: return 0
        case ..<20.5: return (h - 18.5) / 2
        default: return 1
        }
    }

    /// The sun's arc, 06:00 to 18:00, in unit coordinates.
    public static func sun(atClockHour hour: Double) -> CGPoint? {
        let h = wrap(hour)
        guard h >= 6, h <= 18 else { return nil }
        return arc((h - 6) / 12)
    }

    /// The moon's arc, 18:00 to 06:00.
    public static func moon(atClockHour hour: Double) -> CGPoint? {
        let h = wrap(hour)
        guard h >= 18 || h <= 6 else { return nil }
        return arc(wrap(h - 18) / 12)
    }

    private static func arc(_ a: Double) -> CGPoint {
        CGPoint(x: 0.067 + 0.866 * a, y: 0.636 - sin(.pi * a) * 0.508)
    }
}

public struct DaySkyView: View {
    let hour: Double

    public init(clockHour: Double) { hour = clockHour }

    private static let stars: [CGPoint] = [
        CGPoint(x: 0.13, y: 0.13), CGPoint(x: 0.3, y: 0.08), CGPoint(x: 0.47, y: 0.17), CGPoint(x: 0.67, y: 0.09),
        CGPoint(x: 0.87, y: 0.21), CGPoint(x: 0.77, y: 0.38), CGPoint(x: 0.2, y: 0.34), CGPoint(x: 0.57, y: 0.32),
        CGPoint(x: 0.93, y: 0.07),
    ]

    public var body: some View {
        let colors = DaySky.gradient(atClockHour: hour)
        let night = DaySky.night(atClockHour: hour)
        Canvas { context, size in
            let rect = CGRect(origin: .zero, size: size)
            context.fill(
                Path(rect),
                with: .linearGradient(
                    Gradient(stops: [.init(color: colors.top.color, location: 0), .init(color: colors.bottom.color, location: 0.8)]),
                    startPoint: .zero, endPoint: CGPoint(x: 0, y: size.height)))
            for star in Self.stars {
                let p = CGPoint(x: star.x * size.width, y: star.y * size.height)
                context.fill(Path(ellipseIn: CGRect(x: p.x - 1.2, y: p.y - 1.2, width: 2.4, height: 2.4)), with: .color(.white.opacity(0.9 * night)))
            }
            let r = min(size.width, size.height) * 0.085
            if let sun = DaySky.sun(atClockHour: hour) {
                let c = CGPoint(x: sun.x * size.width, y: sun.y * size.height)
                context.fill(
                    Path(ellipseIn: CGRect(x: c.x - r * 2, y: c.y - r * 2, width: r * 4, height: r * 4)),
                    with: .radialGradient(
                        Gradient(colors: [OdyPalette.sun.opacity(0.9 * (1 - night)), OdyPalette.sun.opacity(0)]),
                        center: c, startRadius: 0, endRadius: r * 2))
                context.fill(Path(ellipseIn: CGRect(x: c.x - r, y: c.y - r, width: 2 * r, height: 2 * r)), with: .color(OdyPalette.sun.opacity(1 - night)))
            }
            if let moon = DaySky.moon(atClockHour: hour) {
                let c = CGPoint(x: moon.x * size.width, y: moon.y * size.height)
                var layer = context
                layer.opacity = night
                layer.drawLayer { l in
                    l.fill(Path(ellipseIn: CGRect(x: c.x - r * 0.8, y: c.y - r * 0.8, width: r * 1.6, height: r * 1.6)), with: .color(OdyPalette.hex(0xF4EFFF)))
                    l.blendMode = .destinationOut
                    l.fill(Path(ellipseIn: CGRect(x: c.x - r * 0.4, y: c.y - r * 1.0, width: r * 1.6, height: r * 1.6)), with: .color(.black))
                }
            }
            let ground = RGB(hex: 0xF7E2A0).mixed(with: RGB(hex: 0x2B2660), night)
            context.fill(
                Path(ellipseIn: CGRect(x: -size.width * 0.2, y: size.height * 0.83, width: size.width * 1.4, height: size.height * 0.34)),
                with: .color(ground.color))
        }
        .accessibilityHidden(true)
    }
}
