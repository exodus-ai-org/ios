import Foundation

/// The weather tool's details (`WeatherResult`, packages/shared/src/types/weather.ts). Numbers arrive as strings and
/// times in the place's local time: ISO (`2026-09-23T06:02`) on new rows, wttr.in's `06:52 AM` / `300` on old ones.
/// Codes are WMO (0–99) or, on old rows, WWO (113–395).
public struct WeatherResult: JSONValueDecodable {
    public struct Current: JSONValueDecodable {
        public let condition: String
        public let weatherCode: String
        public let tempC: String
        public let feelsLikeC: String
        public let humidity: String
        public let windKmph: String
        public let windDirDegree: String
        public let windDir: String
        public let precipMM: String
        public let uvIndex: String
        public let visibility: String
        public let pressure: String
        public let observedAt: String
        /// False at night; absent on old rows.
        public let isDay: Bool?

        public init?(json: JSONValue) {
            guard let fields = JSONFields(json) else { return nil }
            condition = fields.text("condition") ?? ""
            weatherCode = fields.text("weatherCode") ?? ""
            tempC = fields.text("tempC") ?? ""
            feelsLikeC = fields.text("feelsLikeC") ?? ""
            humidity = fields.text("humidity") ?? ""
            windKmph = fields.text("windKmph") ?? ""
            windDirDegree = fields.text("windDirDegree") ?? ""
            windDir = fields.text("windDir") ?? ""
            precipMM = fields.text("precipMM") ?? ""
            uvIndex = fields.text("uvIndex") ?? ""
            visibility = fields.text("visibility") ?? ""
            pressure = fields.text("pressure") ?? ""
            observedAt = fields.text("observedAt") ?? ""
            isDay = fields.bool("isDay")
        }
    }

    public struct Hourly: JSONValueDecodable {
        public let time: String
        public let tempC: String
        public let weatherCode: String
        public let condition: String
        public let rainChance: String

        public init?(json: JSONValue) {
            guard let fields = JSONFields(json), let time = fields.text("time") else { return nil }
            self.time = time
            tempC = fields.text("tempC") ?? ""
            weatherCode = fields.text("weatherCode") ?? ""
            condition = fields.text("condition") ?? ""
            rainChance = fields.text("rainChance") ?? ""
        }
    }

    public struct Day: JSONValueDecodable {
        public let date: String
        public let condition: String
        public let weatherCode: String
        public let maxTempC: String
        public let minTempC: String
        public let sunrise: String
        public let sunset: String
        public let hourly: [Hourly]

        public init?(json: JSONValue) {
            guard let fields = JSONFields(json), let date = fields.text("date") else { return nil }
            self.date = date
            condition = fields.text("condition") ?? ""
            weatherCode = fields.text("weatherCode") ?? ""
            maxTempC = fields.text("maxTempC") ?? ""
            minTempC = fields.text("minTempC") ?? ""
            sunrise = fields.text("sunrise") ?? ""
            sunset = fields.text("sunset") ?? ""
            hourly = fields.list("hourly")
        }
    }

    public let location: String
    public let current: Current
    public let forecast: [Day]

    public init?(json: JSONValue) {
        guard let fields = JSONFields(json), let current: Current = fields.decoded("current") else { return nil }
        location = fields.string("location") ?? ""
        self.current = current
        forecast = fields.list("forecast")
    }
}
