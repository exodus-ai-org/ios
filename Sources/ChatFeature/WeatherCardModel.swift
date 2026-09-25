import Foundation
import Models
import SwiftUI

// MARK: - Conditions

/// The desktop's condition vocabulary (`WeatherConditionName`, packages/shared/src/types/weather.ts): one icon per name.
enum WeatherConditionName: String, CaseIterable, Sendable {
    case sunny, partlyCloudy, cloudy, veryCloudy, fog
    case lightShowers, lightSleetShowers, lightSleet
    case lightSnow, lightSnowShowers, heavySnow, heavySnowShowers
    case lightRain, heavyShowers, heavyRain
    case thunderyShowers, thunderyHeavyRain, thunderySnowShowers
}

enum WeatherCondition {
    /// WMO interpretation codes (Open-Meteo), as the desktop's `WMO_CODE` names them.
    static let wmo: [String: WeatherConditionName] = [
        "0": .sunny, "1": .sunny, "2": .partlyCloudy, "3": .cloudy, "45": .fog, "48": .fog,
        "51": .lightShowers, "53": .lightShowers, "55": .lightShowers, "56": .lightSleet, "57": .lightSleet,
        "61": .lightRain, "63": .lightRain, "65": .heavyRain, "66": .lightSleet, "67": .lightSleet,
        "71": .lightSnow, "73": .lightSnow, "75": .heavySnow, "77": .lightSnow,
        "80": .lightShowers, "81": .heavyShowers, "82": .heavyShowers, "85": .lightSnowShowers, "86": .heavySnowShowers,
        "95": .thunderyShowers, "96": .thunderyHeavyRain, "99": .thunderyHeavyRain,
    ]

    /// World Weather Online codes (wttr.in), on rows saved before the Open-Meteo switch; the desktop's `WWO_CODE`.
    static let wwo: [String: WeatherConditionName] = [
        "113": .sunny, "116": .partlyCloudy, "119": .cloudy, "122": .veryCloudy, "143": .fog,
        "176": .lightShowers, "179": .lightSleetShowers, "182": .lightSleet, "185": .lightSleet, "200": .thunderyShowers,
        "227": .lightSnow, "230": .heavySnow, "248": .fog, "260": .fog, "263": .lightShowers, "266": .lightRain,
        "281": .lightSleet, "284": .lightSleet, "293": .lightRain, "296": .lightRain, "299": .heavyShowers,
        "302": .heavyRain, "305": .heavyShowers, "308": .heavyRain, "311": .lightSleet, "314": .lightSleet,
        "317": .lightSleet, "320": .lightSnow, "323": .lightSnowShowers, "326": .lightSnowShowers, "329": .heavySnow,
        "332": .heavySnow, "335": .heavySnowShowers, "338": .heavySnow, "350": .lightSleet, "353": .lightShowers,
        "356": .heavyShowers, "359": .heavyRain, "362": .lightSleetShowers, "365": .lightSleetShowers,
        "368": .lightSnowShowers, "371": .heavySnowShowers, "374": .lightSleetShowers, "377": .lightSleet,
        "386": .thunderyShowers, "389": .thunderyHeavyRain, "392": .thunderySnowShowers, "395": .heavySnowShowers,
    ]

    /// The two ranges do not overlap (WMO 0–99, WWO 113–395); an unknown code is cloudy, as on the desktop.
    static func name(of code: String) -> WeatherConditionName {
        let code = code.trimmingCharacters(in: .whitespaces)
        return wmo[code] ?? wwo[code] ?? .cloudy
    }

    /// A multicolour SF Symbol; a clear or partly cloudy night is a moon, not a sun.
    static func symbol(_ name: WeatherConditionName, isDay: Bool = true) -> String {
        switch name {
        case .sunny: isDay ? "sun.max.fill" : "moon.stars.fill"  // l10n:ignore: SF Symbol names
        case .partlyCloudy: isDay ? "cloud.sun.fill" : "cloud.moon.fill"  // l10n:ignore: SF Symbol names
        case .cloudy, .veryCloudy: "cloud.fill"
        case .fog: "cloud.fog.fill"
        case .lightShowers: "cloud.drizzle.fill"
        case .lightSleetShowers, .lightSleet: "cloud.sleet.fill"
        case .lightSnow, .lightSnowShowers, .heavySnow, .heavySnowShowers: "cloud.snow.fill"
        case .lightRain: "cloud.rain.fill"
        case .heavyShowers, .heavyRain: "cloud.heavyrain.fill"
        case .thunderyShowers, .thunderyHeavyRain: "cloud.bolt.rain.fill"
        case .thunderySnowShowers: "cloud.bolt.fill"
        }
    }

    static func symbol(code: String, isDay: Bool = true) -> String { symbol(name(of: code), isDay: isDay) }

    /// The colour of what a cloud symbol carries (sun, rain, snow, lightning); nil for a bare cloud or a symbol with
    /// no cloud, which draws in its own colours.
    static func accent(of symbol: String) -> Color? {
        guard symbol.hasPrefix("cloud.") else { return nil }
        if symbol.contains("bolt") || symbol.contains("sun") { return .yellow }
        if symbol.contains("rain") || symbol.contains("drizzle") || symbol.contains("sleet") || symbol.contains("snow") {
            return .cyan
        }
        return nil
    }
}

// MARK: - Clocks

enum WeatherClock {
    /// The hour of a weather time as a fraction (13.5 = 13:30), in any form a row may carry: ISO local
    /// ("2026-09-23T06:02"), wttr.in's clock ("06:52 AM") or its hourly slot ("0" … "2100"). The desktop's
    /// `weatherClockHours`.
    static func hours(_ time: String) -> Double? {
        if let match = time.firstMatch(of: #/T(\d{2}):(\d{2})/#), let h = Double(match.1), let m = Double(match.2) {
            return h + m / 60
        }
        let trimmed = time.trimmingCharacters(in: .whitespacesAndNewlines)
        if let match = trimmed.wholeMatch(of: #/(\d{1,2}):(\d{2})\s*([AaPp][Mm])/#),
            let h = Double(match.1), let m = Double(match.2)
        {
            let pm = match.3.lowercased() == "pm"
            return h.truncatingRemainder(dividingBy: 12) + (pm ? 12 : 0) + m / 60
        }
        if time.wholeMatch(of: #/\d{1,4}/#) != nil, let n = Int(time) {
            return Double(n / 100) + Double(n % 100) / 60
        }
        return nil
    }

    /// A place's wall-clock time as a clock in the user's locale. The time is never converted: it is built and shown in
    /// the phone's own calendar, so 06:02 in Shanghai reads 6:02 anywhere.
    static func format(_ time: String, minutes: Bool = true) -> String {
        guard let hours = hours(time) else { return time }
        return format(hours: hours, minutes: minutes)
    }

    static func format(hours: Double, minutes: Bool = true) -> String {
        let whole = Int(hours)
        let minute = Int(((hours - Double(whole)) * 60).rounded())
        let date = Calendar.current.date(from: DateComponents(year: 2026, month: 1, day: 1, hour: whole, minute: minute)) ?? .now
        return minutes ? date.formatted(date: .omitted, time: .shortened) : date.formatted(.dateTime.hour())
    }

    /// "2026-09-24" → a day of the week, read in the phone's calendar (never through UTC, which would shift the day).
    static func weekday(_ date: String) -> String {
        guard let match = date.firstMatch(of: #/(\d{4})-(\d{2})-(\d{2})/#),
            let year = Int(match.1), let month = Int(match.2), let day = Int(match.3),
            let parsed = Calendar.current.date(from: DateComponents(year: year, month: month, day: day, hour: 12))
        else { return date }
        return parsed.formatted(.dateTime.weekday(.abbreviated))
    }
}

// MARK: - Range bars and the curve

/// The week's scale: every day's low and high. A bar spans a day's low to high on it.
struct WeatherRangeScale: Equatable, Sendable {
    let low: Double
    let span: Double

    /// Nil when no day has a readable low and high.
    init?(lows: [Double?], highs: [Double?]) {
        let lows = lows.compactMap { $0 }.filter(\.isFinite)
        let highs = highs.compactMap { $0 }.filter(\.isFinite)
        guard let low = lows.min(), let high = highs.max() else { return nil }
        self.low = low
        span = max(1, high - low)
    }

    /// Where a day's bar starts and how wide it is, as fractions of the track. A still day keeps a sliver (4%, the
    /// desktop's), and a bar never runs past the track.
    func bar(low dayLow: Double, high dayHigh: Double) -> (start: Double, width: Double) {
        let start = min(max(0, (dayLow - low) / span), 1)
        let width = max(0.04, (dayHigh - dayLow) / span)
        let clampedStart = min(start, 1 - 0.04)
        return (clampedStart, min(width, 1 - clampedStart))
    }
}

enum WeatherCurve {
    /// Below this the curve is drawn on a band of 6°, so a still day stays flat instead of full-height noise.
    static let minimumSpan = 6.0

    /// The curve's vertical domain: the day's own range, at least `minimumSpan` wide, centred on the day.
    static func domain(_ temps: [Double]) -> ClosedRange<Double>? {
        guard let low = temps.min(), let high = temps.max() else { return nil }
        let span = max(minimumSpan, high - low)
        let base = low - (span - (high - low)) / 2
        return base...(base + span)
    }
}

// MARK: - The card's model

/// A weather result made ready to draw: numbers parsed, symbols chosen, clocks read, the week's scale worked out. Built
/// once with the card, never while it draws.
struct WeatherCardModel: Equatable, Sendable {
    struct Now: Equatable, Sendable {
        let temp: String
        let feelsLike: String
        let condition: String
        let symbol: String
        let observedAt: String
    }

    struct Hour: Equatable, Sendable, Identifiable {
        let id: Int
        /// Where it sits on the day's axis: its clock hour, or its slot number when a time does not read.
        let x: Double
        let temp: Double
        let tempText: String
        let time: String
        let rainChance: String
    }

    struct Day: Equatable, Sendable, Identifiable {
        let id: Int
        let date: String
        let condition: String
        let symbol: String
        let high: String
        let low: String
        let bar: Bar?
        let sunrise: String
        let sunset: String
        let hours: [Hour]
        let curveDomain: ClosedRange<Double>?

        /// A curve needs two points; a stub (the faux provider) may give none.
        var hasCurve: Bool { hours.count >= 2 && curveDomain != nil }
        var lastHour: Double { hours.last?.x ?? 23 }
    }

    struct Bar: Equatable, Sendable {
        let start: Double
        let width: Double

        init(_ bar: (start: Double, width: Double)) {
            start = bar.start
            width = bar.width
        }
    }

    enum Reading: String, Equatable, Sendable, CaseIterable {
        case humidity, wind, precip, uvIndex, visibility, pressure
    }

    struct ReadingValue: Equatable, Sendable {
        let reading: Reading
        let value: String
    }

    let location: String
    let now: Now
    let readings: [ReadingValue]
    let days: [Day]

    init(_ result: WeatherResult) {
        location = result.location
        let current = result.current
        now = Now(
            temp: current.tempC, feelsLike: current.feelsLikeC, condition: current.condition,
            symbol: WeatherCondition.symbol(code: current.weatherCode, isDay: current.isDay ?? true),
            observedAt: current.observedAt)
        readings = Self.readings(current)
        let scale = WeatherRangeScale(
            lows: result.forecast.map { Self.number($0.minTempC) }, highs: result.forecast.map { Self.number($0.maxTempC) })
        days = result.forecast.enumerated().map { index, day in
            let bar: Bar? =
                if let scale, let low = Self.number(day.minTempC), let high = Self.number(day.maxTempC) {
                    Bar(scale.bar(low: low, high: high))
                } else { nil }
            let hours = Self.hours(day.hourly)
            return Day(
                id: index, date: day.date, condition: day.condition,
                symbol: WeatherCondition.symbol(code: day.weatherCode), high: day.maxTempC, low: day.minTempC, bar: bar,
                sunrise: day.sunrise, sunset: day.sunset, hours: hours,
                curveDomain: WeatherCurve.domain(hours.map(\.temp)))
        }
    }

    static func number(_ text: String) -> Double? {
        Double(text.trimmingCharacters(in: .whitespaces)).flatMap { $0.isFinite ? $0 : nil }
    }

    /// Every slot with a readable temperature. On the clock when every time reads (24 slots from Open-Meteo, 8 from
    /// wttr.in), else by slot number.
    private static func hours(_ hourly: [WeatherResult.Hourly]) -> [Hour] {
        let clocks = hourly.map { WeatherClock.hours($0.time) }
        let onClock = !clocks.contains(nil)
        return hourly.enumerated().compactMap { index, hour in
            guard let temp = number(hour.tempC) else { return nil }
            return Hour(
                id: index, x: onClock ? clocks[index] ?? Double(index) : Double(index), temp: temp, tempText: hour.tempC,
                time: hour.time, rainChance: hour.rainChance)
        }
    }

    /// The readings the result carries, in the desktop's order; one it left empty is not shown.
    private static func readings(_ current: WeatherResult.Current) -> [ReadingValue] {
        let formatted: [(Reading, String?)] = [
            (.humidity, number(current.humidity).map { ($0 / 100).formatted(.percent.precision(.fractionLength(0...1))) }),
            (.wind, measure(current.windKmph, UnitSpeed.kilometersPerHour).map { [$0, current.windDir].filter { !$0.isEmpty }.joined(separator: " ") }),
            (.precip, measure(current.precipMM, UnitLength.millimeters)),
            (.uvIndex, number(current.uvIndex).map { $0.formatted() }),
            (.visibility, measure(current.visibility, UnitLength.kilometers)),
            (.pressure, measure(current.pressure, UnitPressure.hectopascals)),
        ]
        return formatted.compactMap { reading, value in value.map { ReadingValue(reading: reading, value: $0) } }
    }

    /// Units follow the data (metric, as the desktop shows it); the unit's abbreviation follows the phone's language.
    private static func measure<U: Dimension>(_ text: String, _ unit: U) -> String? {
        number(text).map {
            Measurement(value: $0, unit: unit).formatted(
                .measurement(width: .abbreviated, usage: .asProvided, numberFormatStyle: .number.precision(.fractionLength(0...1))))
        }
    }
}

/// What the weather card draws: a forecast, or the tool's failure with the place it was asked for.
enum WeatherCardState: Equatable, Sendable {
    case forecast(WeatherCardModel)
    case failed(place: String, message: String?)

    var forecast: WeatherCardModel? { if case .forecast(let model) = self { model } else { nil } }
}

// MARK: - Copy

enum WeatherCardText {
    static func weekday(_ day: WeatherCardModel.Day) -> String {
        switch day.id {
        case 0: String(localized: "chat:weatherCard.today", defaultValue: "Today", comment: "The first day of a weather forecast.")
        case 1: String(localized: "chat:weatherCard.tomorrow", defaultValue: "Tmr", comment: "The second day of a weather forecast, abbreviated.")
        default: WeatherClock.weekday(day.date)
        }
    }

    static func feelsLike(_ temp: String) -> String {
        String(localized: "chat:weatherCard.feelsLike", defaultValue: "Feels like \(temp)°", comment: "Weather card: the apparent temperature.")
    }

    static func observedAt(_ time: String) -> String {
        let clock = WeatherClock.format(time)
        return String(localized: "chat:weatherCard.observedAt", defaultValue: "Observed \(clock)", comment: "Weather card: when the reading was taken.")
    }

    static func rainChance(_ percent: String) -> String {
        String(localized: "chat:weatherCard.rainChance", defaultValue: "\(percent)% rain", comment: "Weather card: the chance of rain in an hour.")
    }

    static func label(_ reading: WeatherCardModel.Reading) -> String {
        switch reading {
        case .humidity: String(localized: "chat:weatherCard.humidity", defaultValue: "Humidity", comment: "Weather card reading.")
        case .wind: String(localized: "chat:weatherCard.wind", defaultValue: "Wind", comment: "Weather card reading.")
        case .precip: String(localized: "chat:weatherCard.precip", defaultValue: "Precip", comment: "Weather card reading.")
        case .uvIndex: String(localized: "chat:weatherCard.uvIndex", defaultValue: "UV Index", comment: "Weather card reading.")
        case .visibility: String(localized: "chat:weatherCard.visibility", defaultValue: "Visibility", comment: "Weather card reading.")
        case .pressure: String(localized: "chat:weatherCard.pressure", defaultValue: "Pressure", comment: "Weather card reading.")
        }
    }


    /// VoiceOver's reading of a day: a segment of the compact card, or a row of the week.
    static func dayRange(_ day: WeatherCardModel.Day) -> String {
        let name = weekday(day)
        return String(
            localized: "ios:chat.card.weather.dayRange",
            defaultValue: "\(name), \(day.condition): high \(day.high)°, low \(day.low)°",
            comment: "VoiceOver label of a day in a weather card. First %@ is the day (“Today”, “Wed”), then its condition (“Rain”), its high and its low temperature.")
    }

    /// VoiceOver's reading of the card's line of now; the selected day's range is its value.
    static func summary(_ model: WeatherCardModel) -> String {
        let now = model.now
        let place = model.location
        return String(
            localized: "ios:chat.card.weather.now",
            defaultValue: "\(place): \(now.temp)°, \(now.condition), feels like \(now.feelsLike)°",
            comment: "VoiceOver summary of a weather card. %1$@ is the place, %2$@ the temperature, %3$@ the condition (“Partly cloudy”), %4$@ the apparent temperature.")
    }

    static let chartLabel = String(
        localized: "ios:chat.card.weather.chartLabel", defaultValue: "Temperature by hour",
        comment: "VoiceOver label of a weather card's curve of the day's hourly temperatures.")

    /// The curve for VoiceOver: its lowest and highest hours.
    static func chartValue(_ day: WeatherCardModel.Day) -> String? {
        guard let coolest = day.hours.min(by: { $0.temp < $1.temp }), let warmest = day.hours.max(by: { $0.temp < $1.temp })
        else { return nil }
        let low = coolest.tempText
        let lowAt = WeatherClock.format(coolest.time)
        let high = warmest.tempText
        let highAt = WeatherClock.format(warmest.time)
        return String(
            localized: "ios:chat.card.weather.chartValue",
            defaultValue: "Lowest \(low)° at \(lowAt), highest \(high)° at \(highAt)",
            comment: "VoiceOver value of a weather card's temperature curve. The day's lowest temperature and when, then its highest and when.")
    }
}
