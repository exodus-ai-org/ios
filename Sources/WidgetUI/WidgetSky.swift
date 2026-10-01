import OdyKit
import SwiftUI
import WidgetKit
import WidgetKitShared

/// Text on the sky: white on a dark sky, the dark ink on a light one. Decided by the sky's own brightness, not by
/// the night: at 19:00 the sky is already deep violet while `DaySky.night` is still under a half.
public enum WidgetInk {
    /// Where white and the dark ink are about as legible; both keep ≥ 3.8:1 through the hand-off minutes at dawn
    /// and dusk, and ≥ 4.5:1 the rest of the day.
    static let threshold = 0.18

    public static func isLight(at date: Date, calendar: Calendar) -> Bool {
        let top = DaySky.gradient(atClockHour: WidgetPresentation.clockHour(at: date, calendar: calendar)).top
        return luminance(top) < threshold
    }

    static func color(at date: Date, calendar: Calendar) -> Color {
        isLight(at: date, calendar: calendar) ? .white : Color(red: 0.11, green: 0.10, blue: 0.09)
    }

    /// WCAG relative luminance.
    static func luminance(_ c: RGB) -> Double {
        func linear(_ v: Double) -> Double { v <= 0.04045 ? v / 12.92 : pow((v + 0.055) / 1.055, 2.4) }
        return 0.2126 * linear(c.r) + 0.7152 * linear(c.g) + 0.0722 * linear(c.b)
    }
}

/// Ody in full colour, or his outline where the Home Screen is tinted or clear and only one tone shows.
struct WidgetOdy: View {
    let expression: OdyExpression
    @Environment(\.widgetRenderingMode) private var renderingMode

    var body: some View {
        if renderingMode == .fullColor {
            OdyFigure(expression: expression)
        } else {
            OdyBodyShape().stroke(lineWidth: 2.5).widgetAccentable()
        }
    }
}

/// The Health hero's sky at the entry's hour, with a few stars at night.
public struct WidgetSky: View {
    let date: Date
    let calendar: Calendar

    public init(date: Date, calendar: Calendar) {
        self.date = date
        self.calendar = calendar
    }

    public var body: some View {
        let hour = WidgetPresentation.clockHour(at: date, calendar: calendar)
        let sky = DaySky.gradient(atClockHour: hour)
        ZStack {
            LinearGradient(colors: [sky.top.color, sky.bottom.color], startPoint: .top, endPoint: .bottom)
            if DaySky.night(atClockHour: hour) >= 0.5 {
                // In the margins (14pt of the small widget's 170), so a star never reads as a stop after a word.
                Canvas { context, size in
                    for (x, y) in [(0.62, 0.04), (0.8, 0.055), (0.93, 0.03), (0.975, 0.22)] {
                        let r = CGRect(x: x * size.width, y: y * size.height, width: 2, height: 2)
                        context.fill(Path(ellipseIn: r), with: .color(.white.opacity(0.8)))
                    }
                }
            }
        }
    }
}
