import Foundation
import MarkdownKit
import Models

/// What the map_itinerary card draws: the result, or the tool's failure (a missing Google key, most often).
enum MapItineraryCardState: Equatable, Sendable {
    case itinerary(MapItineraryCardModel)
    case failed(title: String?, message: String?)

    var model: MapItineraryCardModel? { if case .itinerary(let model) = self { model } else { nil } }
}

/// A position on the map, kept free of MapKit so the maths stays plain and testable.
struct MapCoordinate: Equatable, Sendable {
    let latitude: Double
    let longitude: Double
}

/// A region to show: its centre and its span in degrees (MapKit's `MKCoordinateRegion`).
struct MapRegion: Equatable, Sendable {
    let center: MapCoordinate
    let latitudeDelta: Double
    let longitudeDelta: Double
}

/// map_itinerary's details prepared once, when the card is built: every stop numbered within its day, the stops that
/// have a position joined into the day's route, and the region each day (and the whole trip) is framed in.
struct MapItineraryCardModel: Equatable, Sendable {
    struct Stop: Equatable, Sendable, Identifiable {
        /// `d<day>-s<index>`: unique in the itinerary, stable across rebuilds.
        let id: String
        let dayIndex: Int
        /// 1-based, within its day, counting stops with no position too (they are still stops of the day).
        let number: Int
        let place: MapItineraryDetails.Place
        let coordinate: MapCoordinate?
    }

    struct Day: Equatable, Sendable, Identifiable {
        let index: Int
        let label: String
        let title: String?
        let summary: String?
        let routeMode: String?
        let stops: [Stop]
        /// The stops that have a position, in visit order: the day's markers and its route.
        let route: [MapCoordinate]
        let region: MapRegion?

        var id: Int { index }
        var mappedStops: [Stop] { stops.filter { $0.coordinate != nil } }
    }

    /// The line that names a day over its stops, so a time under it reads as a time of that day.
    struct DayHeader: Equatable, Sendable {
        let label: String
        let title: String?
    }

    /// What the transcript's card lists for the day picked in it: one day, never the trip's stops laid end to end.
    struct InlineDay: Equatable, Sendable {
        let index: Int
        /// Nil for a trip of one day that has no title: there is no other day to tell it from.
        let header: DayHeader?
        let summary: String?
        /// The day's first stops; the rest are behind "+N more".
        let stops: [Stop]
        let moreCount: Int
    }

    /// The transcript shows this many stops of a day; the rest are behind "+N more".
    static let inlineStopCount = 4

    let title: String?
    let days: [Day]
    let notice: ToolNotice?
    /// Every day's stops together, for the map in the transcript.
    let region: MapRegion?

    init(_ details: MapItineraryDetails) {
        title = details.title
        notice = details.notice
        days = details.days.enumerated().map { dayIndex, day in
            let stops = day.places.enumerated().map { index, place in
                Stop(
                    id: "d\(dayIndex)-s\(index)", dayIndex: dayIndex, number: index + 1, place: place,
                    coordinate: place.lat.flatMap { lat in place.lng.map { MapCoordinate(latitude: lat, longitude: $0) } })
            }
            let route = stops.compactMap(\.coordinate)
            return Day(
                index: dayIndex, label: day.label, title: day.title, summary: day.summary, routeMode: day.routeMode,
                stops: stops, route: route, region: MapRegionMath.fit(route))
        }
        region = MapRegionMath.fit(days.flatMap(\.route))
    }

    var allStops: [Stop] { days.flatMap(\.stops) }
    var stopCount: Int { days.reduce(0) { $0 + $1.stops.count } }
    var hasMap: Bool { region != nil }

    /// A trip of several days is looked at a day at a time.
    var showsDayPicker: Bool { days.count > 1 }

    /// What the transcript lists for day `index`; for a day that is not there, the first.
    func inline(day index: Int) -> InlineDay {
        guard let day = days.indices.contains(index) ? days[index] : days.first else {
            return InlineDay(index: 0, header: nil, summary: nil, stops: [], moreCount: 0)
        }
        let title = day.title?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty
        let header: DayHeader? =
            showsDayPicker || title != nil ? DayHeader(label: MapItineraryText.dayLabel(day), title: title) : nil
        return InlineDay(
            index: day.index, header: header, summary: day.summary?.nilIfEmpty,
            stops: Array(day.stops.prefix(Self.inlineStopCount)),
            moreCount: max(0, day.stops.count - Self.inlineStopCount))
    }

    func stop(id: String?) -> Stop? {
        guard let id else { return nil }
        return allStops.first { $0.id == id }
    }

    /// The stop before or after `id` in its day, wrapping around, as the desktop's detail panel pages.
    func neighbour(of id: String, step: Int) -> Stop? {
        guard let stop = stop(id: id), days.indices.contains(stop.dayIndex) else { return nil }
        let stops = days[stop.dayIndex].stops
        guard let index = stops.firstIndex(where: { $0.id == id }), !stops.isEmpty else { return nil }
        return stops[((index + step) % stops.count + stops.count) % stops.count]
    }
}

// MARK: - Camera

enum MapRegionMath {
    /// One stop alone is shown at street level (the desktop zooms a single pin to 15).
    static let singleStopSpan = 0.01
    /// The narrowest a fitted region gets, so two stops next door are not shown at building level.
    static let minimumSpan = 0.005
    /// Room around the stops on every side, as a share of their extent.
    static let padding = 0.2
    /// More room above: a marker's balloon stands over its point.
    static let topPadding = 0.15

    /// The region that shows every coordinate with padding, or nil when there are none. A set of stops spread across
    /// the antimeridian (Fiji, the Aleutians) is framed across it, not around the rest of the world.
    static func fit(_ coordinates: [MapCoordinate]) -> MapRegion? {
        guard let first = coordinates.first else { return nil }
        if coordinates.allSatisfy({ $0 == first }) {
            return MapRegion(center: first, latitudeDelta: singleStopSpan, longitudeDelta: singleStopSpan)
        }
        let lats = coordinates.map(\.latitude)
        var lngs = coordinates.map(\.longitude)
        if let low = lngs.min(), let high = lngs.max(), high - low > 180 {
            lngs = lngs.map { $0 < 0 ? $0 + 360 : $0 }
        }
        let (minLat, maxLat) = (lats.min()!, lats.max()!)
        let (minLng, maxLng) = (lngs.min()!, lngs.max()!)
        let latExtent = maxLat - minLat
        let lngExtent = maxLng - minLng
        let latDelta = min(max(latExtent * (1 + 2 * padding + topPadding), minimumSpan), 170)
        let lngDelta = min(max(lngExtent * (1 + 2 * padding), minimumSpan), 360)
        let centerLat = min(max((minLat + maxLat) / 2 + latExtent * topPadding / 2, -85), 85)
        return MapRegion(
            center: MapCoordinate(latitude: centerLat, longitude: normalized((minLng + maxLng) / 2)),
            latitudeDelta: latDelta, longitudeDelta: lngDelta)
    }

    /// `region` moved to `coordinate`, keeping its zoom: a tapped stop is brought to the middle, not zoomed into.
    static func centered(on coordinate: MapCoordinate, keeping region: MapRegion?) -> MapRegion {
        let span = region.map { min($0.latitudeDelta, $0.longitudeDelta) } ?? singleStopSpan
        let delta = max(span, minimumSpan)
        return MapRegion(center: coordinate, latitudeDelta: delta, longitudeDelta: delta)
    }

    static func normalized(_ longitude: Double) -> Double {
        var value = longitude.truncatingRemainder(dividingBy: 360)
        if value >= 180 { value -= 360 }
        if value < -180 { value += 360 }
        return value
    }
}

// MARK: - Day colours

/// Each day's colour. The desktop draws every route in one blue; on the phone a trip's days share the map in the
/// transcript, so they need telling apart. The first day takes the colour tone; the others come from a fixed order of
/// system colours, skipping any close in hue to the tone so no later day looks like the first. When the days
/// outnumber the colours, the order repeats with dashed routes.
enum MapDayPalette {
    /// Eight designed colours for the days of a trip, in the family of the colour tones (ChatGPT's accent colours,
    /// the owner's reference) plus a teal and a slate to fill the gaps of the hue circle — not the system's hues,
    /// which read as "standard". In the order days take them: each far in hue from the one before.
    enum Hue: String, CaseIterable, Sendable {
        case orange, teal, purple, green, pink, blue, yellow, slate

        /// The colour as designed, sRGB: what the map's colour for a day is derived from.
        var reference: ColorTone.RGB {
            switch self {
            case .orange: ColorTone.orange.reference ?? .black
            case .teal: ColorTone.RGB(hex: 0x45B3A8)
            case .purple: ColorTone.violet.reference ?? .black
            case .green: ColorTone.emerald.reference ?? .black
            case .pink: ColorTone.rose.reference ?? .black
            case .blue: ColorTone.blue.reference ?? .black
            case .yellow: ColorTone.yellow.reference ?? .black
            case .slate: ColorTone.RGB(hex: 0x7D8CA3)
            }
        }

        /// Hue angle (HSB) of the reference, the measure the tones are told apart by.
        var angle: Double { reference.hueAngle }
    }

    /// The luminance of the map's tiles under each appearance, which a route has to stand out from.
    static func tileLuminances(_ scheme: ColorTone.Scheme) -> [Double] {
        switch scheme {
        case .light: [0.88]
        case .dark: [0.03]
        }
    }

    /// A day's colour on the map: the reference, lightened a touch for a dark map as the tones are, then moved in
    /// lightness only as far as it takes to stand out from the tiles at 3:1 (yellow darkens to ochre on light tiles).
    static func color(_ hue: Hue, _ scheme: ColorTone.Scheme) -> OKLCH {
        let base = OKLCH(hue.reference)
        let shade =
            scheme == .dark
            ? OKLCH(lightness: min(base.lightness + 0.025, 1), chroma: base.chroma * 0.92, hue: base.hue)
            : base
        return shade.readable(on: tileLuminances(scheme), minimum: ColorTone.graphicContrast, in: ColorTone.gamut)
    }

    enum Swatch: Equatable, Sendable {
        case accent
        case palette(Hue)
    }

    struct DayColor: Equatable, Sendable {
        let swatch: Swatch
        let dashed: Bool
    }

    /// Hues this close to the tone's are skipped.
    static let minimumSeparation = 45.0

    /// The hue of the tone as the phone paints it; none for neutral, which is black and white.
    static func angle(of tone: ColorTone) -> Double? { tone.accentHueAngle }

    static func hueDistance(_ a: Double, _ b: Double) -> Double {
        let difference = abs(a - b).truncatingRemainder(dividingBy: 360)
        return min(difference, 360 - difference)
    }

    /// The colours a day after the first can take under `tone`, in order: all of them under neutral, which no colour
    /// can be mistaken for.
    static func palette(for tone: ColorTone) -> [Hue] {
        guard let accent = angle(of: tone) else { return Hue.allCases }
        return Hue.allCases.filter { hueDistance($0.angle, accent) >= minimumSeparation }
    }

    static func colors(dayCount: Int, tone: ColorTone) -> [DayColor] {
        guard dayCount > 0 else { return [] }
        let palette = palette(for: tone)
        return (0..<dayCount).map { index in
            if index == 0 { return DayColor(swatch: .accent, dashed: false) }
            let slot = index - 1
            return DayColor(swatch: .palette(palette[slot % palette.count]), dashed: (slot / palette.count) % 2 == 1)
        }
    }
}

// MARK: - Sharing

/// The desktop's "Copy day as markdown" and "Open route in Google Maps", kept identical.
enum MapItineraryExport {
    static func markdown(_ day: MapItineraryCardModel.Day) -> String {
        let header = "## \(day.label)" + (day.title.map { " — \($0)" } ?? "")
        let summary = day.summary.map { "\n\($0)\n" } ?? ""
        let places = day.stops.map { stop -> String in
            let place = stop.place
            var lines = ["\(stop.number). **\(place.name)**"]
            var meta: [String] = []
            if let type = place.type { meta.append(type) }
            if let rating = place.rating { meta.append("★ \(String(format: "%.1f", rating))") }
            if let time = place.timeLabel { meta.append(time) }
            if !meta.isEmpty { lines.append("   " + meta.joined(separator: " · ")) }
            for field in [place.note, place.address, place.phone, place.websiteUri].compactMap(\.self) {
                lines.append("   \(field)")
            }
            if let link = place.googleMapsUri ?? stop.coordinate.map(searchLink) { lines.append("   \(link)") }
            return lines.joined(separator: "\n")
        }
        return "\(header)\(summary)\n\(places.joined(separator: "\n\n"))"
    }

    static func searchLink(_ coordinate: MapCoordinate) -> String {
        "https://www.google.com/maps/search/?api=1&query=\(coordinate.latitude),\(coordinate.longitude)"
    }

    /// The day's route with its stops as waypoints, in its travel mode; nil for a day with no position.
    static func routeURL(_ day: MapItineraryCardModel.Day) -> URL? {
        let points = day.route
        guard let origin = points.first, let destination = points.last else { return nil }
        if points.count == 1 { return URL(string: searchLink(origin)) }
        func text(_ point: MapCoordinate) -> String { "\(point.latitude),\(point.longitude)" }
        var components = URLComponents(string: "https://www.google.com/maps/dir/")!
        var items = [
            URLQueryItem(name: "api", value: "1"), URLQueryItem(name: "origin", value: text(origin)),
            URLQueryItem(name: "destination", value: text(destination)),
        ]
        if points.count > 2 {
            items.append(URLQueryItem(name: "waypoints", value: points.dropFirst().dropLast().map(text).joined(separator: "|")))
        }
        let mode = ["walking", "driving", "transit"].contains(day.routeMode ?? "") ? day.routeMode! : "walking"
        items.append(URLQueryItem(name: "travelmode", value: mode))
        components.queryItems = items
        return components.url
    }

    /// A link the card may open: what the app's one link allowlist (`ExternalLinkPolicy`) allows, narrowed to the web
    /// with a host (a place's website or its Google Maps page is never a `mailto:`).
    static func webURL(_ text: String?) -> URL? {
        guard let text, let url = ExternalLinkPolicy.openableURL(text), let scheme = url.scheme?.lowercased(),
            scheme == "https" || scheme == "http", url.host() != nil
        else { return nil }
        return url
    }

    /// The one deliberate exception to `ExternalLinkPolicy`: a place's phone number becomes `tel:` (iOS asks before it
    /// dials). Built from ASCII digits and `+` only, never from the text as given.
    static func phoneURL(_ phone: String?) -> URL? {
        guard let phone else { return nil }
        let digits = phone.filter { ($0.isASCII && $0.isNumber) || $0 == "+" }
        guard digits.contains(where: \.isNumber) else { return nil }
        return URL(string: "tel:\(digits)")
    }

    /// "Monday: 9:00 AM – 5:00 PM" as its day and its hours, split at the first ": " as the desktop does.
    static func hoursRow(_ line: String) -> (day: String, hours: String) {
        guard let range = line.range(of: ": ") else { return (line, "") }
        return (String(line[..<range.lowerBound]), String(line[range.upperBound...]))
    }
}

extension String {
    fileprivate var nilIfEmpty: String? { isEmpty ? nil : self }
}
