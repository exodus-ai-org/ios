import OdyKit
import SwiftUI
import WidgetKitShared

/// Text on the sky: white at night, the dark ink by day, as `DaySky.night` decides.
public enum WidgetInk {
    public static func isLight(at date: Date, calendar: Calendar) -> Bool {
        DaySky.night(atClockHour: WidgetPresentation.clockHour(at: date, calendar: calendar)) >= 0.5
    }

    static func color(at date: Date, calendar: Calendar) -> Color {
        isLight(at: date, calendar: calendar) ? .white : Color(red: 0.11, green: 0.10, blue: 0.09)
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
                Canvas { context, size in
                    for (x, y) in [(0.72, 0.12), (0.88, 0.3), (0.58, 0.36), (0.94, 0.08)] {
                        let r = CGRect(x: x * size.width, y: y * size.height, width: 2, height: 2)
                        context.fill(Path(ellipseIn: r), with: .color(.white.opacity(0.8)))
                    }
                }
            }
        }
    }
}
