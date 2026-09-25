import Foundation
import MarkdownKit
import Models
import SwiftUI
import Testing
import UIKit

@testable import ChatFeature

private func value(_ json: String) -> JSONValue {
    try! JSONDecoder().decode(JSONValue.self, from: Data(json.utf8))
}

private func model(_ json: String) throws -> MapItineraryCardModel {
    MapItineraryCardModel(try #require(MapItineraryDetails(json: value(json))))
}

private func decode(_ json: String) -> ChatMessage {
    try! JSONDecoder().decode(ChatMessage.self, from: Data(json.utf8))
}

private func near(_ a: Double, _ b: Double) -> Bool { abs(a - b) < 1e-9 }

/// The desktop's shape: two days of 9 and 3 stops, enrichment on some, and the notice an expired key leaves.
private let kyoto = #"""
    {"type":"mapItinerary","title":"Kyoto in two days","days":[
      {"label":"Day 1","title":"Southern Higashiyama","summary":"Shrines early, Gion by evening.","routeMode":"walking","places":[
        {"name":"Fushimi Inari Taisha","lat":34.9671,"lng":135.7727,"type":"Shrine","timeLabel":"07:00","note":"Go before 8 to beat the crowds.","rating":4.7,"reviewCount":61234,"address":"68 Fukakusa Yabunouchicho","openNow":true},
        {"name":"Tofuku-ji","lat":34.9760,"lng":135.7737,"type":"Temple","timeLabel":"09:30","rating":4.6,"reviewCount":10321},
        {"name":"Sanjusangen-do","lat":34.9879,"lng":135.7717,"type":"Temple","timeLabel":"11:00"},
        {"name":"Kyoto National Museum","lat":34.9900,"lng":135.7730,"type":"Museum","timeLabel":"12:00","openNow":false},
        {"name":"Kiyomizu-dera","lat":34.9949,"lng":135.7850},
        {"name":"Sannenzaka","lat":34.9965,"lng":135.7811},
        {"name":"Kodai-ji","lat":35.0005,"lng":135.7811},
        {"name":"Yasaka Shrine","lat":35.0037,"lng":135.7785},
        {"name":"Gion Shirakawa","lat":35.0056,"lng":135.7746}]},
      {"label":"Day 2","title":"Arashiyama","routeMode":"transit","places":[
        {"name":"Arashiyama Bamboo Grove","lat":35.0170,"lng":135.6713},
        {"name":"Tenryu-ji","lat":35.0158,"lng":135.6737},
        {"name":"Togetsukyo Bridge","lat":35.0129,"lng":135.6778}]}],
     "notice":{"level":"warning","message":"Live place data is unavailable — the Google API key has expired."}}
    """#

/// A day whose middle stop has no position, a day with none at all, and a day with no stops.
private let partlyPlaced = #"""
    {"type":"mapItinerary","days":[
      {"label":"Day 1","places":[{"name":"A","lat":35,"lng":135},{"name":"B"},{"name":"C","lat":35.02,"lng":135.03}]},
      {"label":"","places":[{"name":"Somewhere"},{"name":"Elsewhere","lat":"north","lng":1}]},
      {"label":"Rest","places":[]}]}
    """#

@Suite("Map itinerary: the card model")
struct MapItineraryCardModelTests {
    @Test("the desktop's result: days, stops numbered within their day, routes and the notice")
    func kyotoModel() throws {
        let map = try model(kyoto)
        #expect(map.title == "Kyoto in two days")
        #expect(map.days.map(\.stops.count) == [9, 3])
        #expect(map.days.map(\.route.count) == [9, 3])
        #expect(map.days[1].stops.map(\.number) == [1, 2, 3])
        #expect(map.days[1].stops.map(\.id) == ["d1-s0", "d1-s1", "d1-s2"])
        #expect(map.days[0].routeMode == "walking")
        #expect(map.notice?.level == "warning")
        #expect(map.notice?.message.contains("expired") == true)
        #expect(map.hasMap)
        let region = try #require(map.region)
        #expect(region.center.longitude > 135.67 && region.center.longitude < 135.79)
        #expect(region.longitudeDelta > 135.7850 - 135.6713)
    }

    @Test("a place without a position is left off the map but kept in the list, numbered in its day")
    func unplacedStops() throws {
        let map = try model(partlyPlaced)
        #expect(map.days.count == 3)
        #expect(map.days[0].stops.map(\.place.name) == ["A", "B", "C"])
        #expect(map.days[0].stops.map(\.number) == [1, 2, 3])
        #expect(map.days[0].route == [MapCoordinate(latitude: 35, longitude: 135), MapCoordinate(latitude: 35.02, longitude: 135.03)])
        #expect(map.days[0].mappedStops.map(\.place.name) == ["A", "C"])
        #expect(map.days[1].stops.count == 2)
        #expect(map.days[1].route.isEmpty)
        #expect(map.days[1].region == nil)
        #expect(map.days[2].stops.isEmpty)
        #expect(map.stopCount == 5)
        #expect(map.allStops.map(\.place.name) == ["A", "B", "C", "Somewhere", "Elsewhere"])
        #expect(map.region == map.days[0].region)
        let nowhere = try model(#"{"type":"mapItinerary","days":[{"label":"D","places":[{"name":"X"},{"name":"Y"}]}]}"#)
        #expect(!nowhere.hasMap)
        #expect(nowhere.inlineStops.map(\.place.name) == ["X", "Y"])
    }

    @Test("the transcript lists the first 4 stops across the days; +N more counts every other one")
    func moreCount() throws {
        let map = try model(kyoto)
        #expect(map.inlineStops.map(\.id) == ["d0-s0", "d0-s1", "d0-s2", "d0-s3"])
        #expect(map.moreCount == 8)
        func places(_ counts: [Int]) -> String {
            let days = counts.enumerated().map { day, count in
                let places = (0..<count).map { #"{"name":"P\#(day)-\#($0)","lat":1,"lng":\#(Double($0) / 10)}"# }
                return #"{"label":"D\#(day)","places":[\#(places.joined(separator: ","))]}"#
            }
            return #"{"type":"mapItinerary","days":[\#(days.joined(separator: ","))]}"#
        }
        #expect(try model(places([4])).moreCount == 0)
        #expect(try model(places([3])).moreCount == 0)
        #expect(try model(places([5])).moreCount == 1)
        #expect(try model(places([])).moreCount == 0)
        let split = try model(places([2, 3]))
        #expect(split.inlineStops.map(\.id) == ["d0-s0", "d0-s1", "d1-s0", "d1-s1"])
        #expect(split.moreCount == 1)
        #expect(try model(partlyPlaced).moreCount == 1)
    }

    @Test("paging through a day's stops wraps around, as the desktop's detail panel does")
    func paging() throws {
        let map = try model(kyoto)
        #expect(map.neighbour(of: "d1-s0", step: 1)?.id == "d1-s1")
        #expect(map.neighbour(of: "d1-s2", step: 1)?.id == "d1-s0")
        #expect(map.neighbour(of: "d1-s0", step: -1)?.id == "d1-s2")
        #expect(map.neighbour(of: "d0-s0", step: -1)?.id == "d0-s8")
        #expect(map.neighbour(of: "nope", step: 1) == nil)
        #expect(map.stop(id: "d0-s3")?.place.name == "Kyoto National Museum")
    }
}

@Suite("Map itinerary: framing the camera")
struct MapRegionMathTests {
    @Test("no stops frame nothing; one stop, or several at one spot, is shown at street level")
    func singleAndEmpty() {
        #expect(MapRegionMath.fit([]) == nil)
        let one = MapCoordinate(latitude: 48.2, longitude: 16.37)
        let expected = MapRegion(center: one, latitudeDelta: 0.01, longitudeDelta: 0.01)
        #expect(MapRegionMath.fit([one]) == expected)
        #expect(MapRegionMath.fit([one, one, one]) == expected)
    }

    @Test("several stops are framed with padding on every side and more above, for the pins")
    func padded() throws {
        let region = try #require(
            MapRegionMath.fit([MapCoordinate(latitude: 0, longitude: 0), MapCoordinate(latitude: 1, longitude: 2)]))
        #expect(near(region.latitudeDelta, 1.55))
        #expect(near(region.longitudeDelta, 2.8))
        #expect(near(region.center.latitude, 0.575))
        #expect(near(region.center.longitude, 1))
        // Every stop is inside, with room to spare.
        #expect(region.center.latitude - region.latitudeDelta / 2 < -0.1)
        #expect(region.center.latitude + region.latitudeDelta / 2 > 1.1)
    }

    @Test("two stops next door are not framed at building level")
    func minimumSpan() throws {
        let region = try #require(
            MapRegionMath.fit([MapCoordinate(latitude: 35, longitude: 135), MapCoordinate(latitude: 35.0001, longitude: 135.0001)]))
        #expect(region.latitudeDelta == MapRegionMath.minimumSpan)
        #expect(region.longitudeDelta == MapRegionMath.minimumSpan)
    }

    @Test("stops on both sides of the antimeridian are framed across it, not around the world")
    func antimeridian() throws {
        let fiji = try #require(
            MapRegionMath.fit([MapCoordinate(latitude: -17, longitude: 178), MapCoordinate(latitude: -18, longitude: -179)]))
        #expect(near(fiji.longitudeDelta, 3 * 1.4))
        #expect(near(fiji.center.longitude, 179.5))
        let east = try #require(
            MapRegionMath.fit([
                MapCoordinate(latitude: 0, longitude: 179), MapCoordinate(latitude: 0, longitude: -179),
                MapCoordinate(latitude: 0, longitude: -178),
            ]))
        #expect(near(east.center.longitude, -179.5))
        #expect(near(east.longitudeDelta, 3 * 1.4))
        let pacific = try #require(
            MapRegionMath.fit([MapCoordinate(latitude: 34, longitude: -118), MapCoordinate(latitude: 35.7, longitude: 139.7)]))
        #expect(pacific.longitudeDelta < 180)
    }

    @Test("a region spanning the globe is capped where MapKit accepts it")
    func capped() throws {
        let world = try #require(
            MapRegionMath.fit([MapCoordinate(latitude: -80, longitude: 0), MapCoordinate(latitude: 80, longitude: 90)]))
        #expect(world.latitudeDelta == 170)
        #expect(world.center.latitude <= 85)
    }

    @Test("centring on a stop keeps the current zoom")
    func centered() {
        let stop = MapCoordinate(latitude: 35, longitude: 135)
        let current = MapRegion(center: MapCoordinate(latitude: 0, longitude: 0), latitudeDelta: 0.2, longitudeDelta: 0.5)
        #expect(MapRegionMath.centered(on: stop, keeping: current) == MapRegion(center: stop, latitudeDelta: 0.2, longitudeDelta: 0.2))
        #expect(MapRegionMath.centered(on: stop, keeping: nil) == MapRegion(center: stop, latitudeDelta: 0.01, longitudeDelta: 0.01))
    }
}

@Suite("Map itinerary: day colours")
struct MapDayPaletteTests {
    @Test("the first day takes the tone; the next days skip the hues close to it (neutral is the system blue)")
    func neutral() {
        let colors = MapDayPalette.colors(dayCount: 6, tone: .neutral)
        #expect(colors.map(\.swatch) == [.accent, .system(.orange), .system(.purple), .system(.green), .system(.pink), .system(.brown)])
        #expect(colors.allSatisfy { !$0.dashed })
        #expect(MapDayPalette.palette(for: .blue) == MapDayPalette.palette(for: .neutral))
        #expect(MapDayPalette.palette(for: .emerald) == [.orange, .teal, .purple, .pink, .brown, .indigo, .blue])
        #expect(MapDayPalette.palette(for: .orange) == [.teal, .purple, .green, .pink, .indigo, .blue])
    }

    @Test("under every tone no later day is near the tone's hue, and neighbouring days always differ")
    func separation() {
        for tone in ColorTone.allCases {
            let palette = MapDayPalette.palette(for: tone)
            #expect(palette.count >= 4, "\(tone)")
            for hue in palette {
                #expect(MapDayPalette.hueDistance(hue.angle, MapDayPalette.angle(of: tone)) >= 45, "\(tone) \(hue)")
            }
            let colors = MapDayPalette.colors(dayCount: 20, tone: tone)
            #expect(colors.first?.swatch == .accent)
            #expect(colors.dropFirst().allSatisfy { $0.swatch != .accent })
            for (a, b) in zip(colors, colors.dropFirst()) {
                #expect(a != b, "\(tone)")
            }
        }
    }

    @Test("more days than colours repeat the order with dashed routes, then solid again")
    func cycles() {
        let palette = MapDayPalette.palette(for: .neutral)
        let colors = MapDayPalette.colors(dayCount: 1 + palette.count * 3, tone: .neutral)
        #expect(colors[1] == .init(swatch: .system(palette[0]), dashed: false))
        #expect(colors[1 + palette.count] == .init(swatch: .system(palette[0]), dashed: true))
        #expect(colors[palette.count * 2] == .init(swatch: .system(palette.last!), dashed: true))
        #expect(colors[1 + palette.count * 2] == .init(swatch: .system(palette[0]), dashed: false))
        #expect(MapDayPalette.colors(dayCount: 0, tone: .rose).isEmpty)
        #expect(MapDayPalette.colors(dayCount: 1, tone: .rose) == [.init(swatch: .accent, dashed: false)])
    }

    @Test("hue distance goes the short way round the circle")
    func hueDistance() {
        #expect(MapDayPalette.hueDistance(349, 35) == 46)
        #expect(MapDayPalette.hueDistance(10, 350) == 20)
        #expect(MapDayPalette.hueDistance(90, 270) == 180)
    }
}

@Suite("Map itinerary: copying and links")
struct MapItineraryExportTests {
    @Test("a day as markdown, the desktop's Copy output")
    func markdown() throws {
        let map = try model(
            #"{"type":"mapItinerary","days":[{"label":"Day 1","title":"Old town","summary":"On foot.","places":[{"name":"Café Central","lat":48.21,"lng":16.365,"type":"Café","rating":4.5,"timeLabel":"09:00","note":"Breakfast.","address":"Herrengasse 14","googleMapsUri":"https://maps.google.com/?cid=7"},{"name":"Stephansdom"}]}]}"#
        )
        #expect(
            MapItineraryExport.markdown(map.days[0]) == """
                ## Day 1 — Old town
                On foot.

                1. **Café Central**
                   Café · ★ 4.5 · 09:00
                   Breakfast.
                   Herrengasse 14
                   https://maps.google.com/?cid=7

                2. **Stephansdom**
                """)
    }

    @Test("the route link takes the day's placed stops in order, in its travel mode")
    func routeURL() throws {
        let map = try model(kyoto)
        let url = try #require(MapItineraryExport.routeURL(map.days[1])).absoluteString
        #expect(url.hasPrefix("https://www.google.com/maps/dir/?api=1&origin=35.017,135.6713&destination=35.0129,135.6778"))
        #expect(url.contains("waypoints=35.0158,135.6737"))
        #expect(url.hasSuffix("travelmode=transit"))
        let placed = try model(partlyPlaced)
        #expect(MapItineraryExport.routeURL(placed.days[0])?.absoluteString.contains("waypoints") == false)
        #expect(MapItineraryExport.routeURL(placed.days[0])?.absoluteString.hasSuffix("travelmode=walking") == true)
        #expect(MapItineraryExport.routeURL(placed.days[1]) == nil)
    }

    @Test("only web links open from a result; a phone number dials its digits; hours split at the first colon")
    func links() {
        #expect(MapItineraryExport.webURL("https://www.kiyomizudera.or.jp/")?.host() == "www.kiyomizudera.or.jp")
        #expect(MapItineraryExport.webURL("javascript:alert(1)") == nil)
        #expect(MapItineraryExport.webURL("file:///etc/passwd") == nil)
        #expect(MapItineraryExport.webURL("maps.google.com") == nil)
        #expect(MapItineraryExport.phoneURL("+81 75-561-1234")?.absoluteString == "tel:+81755611234")
        // Only ASCII digits: "½", "²" and Arabic-Indic digits are numbers to Character, not to the dialer.
        #expect(MapItineraryExport.phoneURL("+81 ٣٤٥ ½²")?.absoluteString == "tel:+81")
        #expect(MapItineraryExport.phoneURL("٣٤٥") == nil)
        #expect(MapItineraryExport.webURL("mailto:a@example.com") == nil)
        #expect(MapItineraryExport.webURL(" https://example.com/x ")?.host() == "example.com")
        #expect(MapItineraryExport.phoneURL("call us") == nil)
        #expect(MapItineraryExport.hoursRow("Monday: 6:00 AM – 6:00 PM") == ("Monday", "6:00 AM – 6:00 PM"))
        #expect(MapItineraryExport.hoursRow("Closed today") == ("Closed today", ""))
    }
}

@Suite("Map itinerary: text")
struct MapItineraryTextTests {
    @Test("English copy")
    func english() throws {
        let map = try model(partlyPlaced)
        #expect(MapItineraryText.more(8) == "+8 more")
        #expect(MapItineraryText.pagination(2, 9) == "2 of 9")
        #expect(MapItineraryText.dayLabel(map.days[1]) == "Day 2")
        #expect(MapItineraryText.dayLabel(map.days[0]) == "Day 1")
        #expect(MapItineraryText.accessibilityLabel(map.days[0].stops[1], dayLabel: nil) == "Stop 2, B, Not on the map")
        #expect(MapItineraryText.accessibilityLabel(map.days[0].stops[0], dayLabel: "Day 1") == "Day 1, stop 1, A")
        let kyotoMap = try model(kyoto)
        let first = kyotoMap.days[0].stops[0]
        #expect(MapItineraryText.accessibilityLabel(first, dayLabel: nil) == "Stop 1, Fushimi Inari Taisha, 07:00, Shrine, Rated 4.7 out of 5, Open")
        #expect(MapItineraryText.meta(kyotoMap.days[0].stops[3].place) == "Museum · Closed")
        #expect(MapItineraryText.ratingAndType(kyotoMap.days[0].stops[1].place).hasPrefix("Rated 4.6 out of 5 from 10,321 reviews"))
        #expect(MapItineraryText.bareHost("https://example.com/x") == "example.com/x")
        #expect(MapItineraryText.initial(nil) == "·")
        #expect(MapItineraryText.initial("ann") == "A")
    }
}

@Suite("Map itinerary: built with the turn")
struct MapItineraryContentTests {
    private func turn(_ messages: [String]) throws -> AssistantTurn {
        var cache = RunGrouper.Cache()
        let segments = RunGrouper.group(messages.map(decode), cache: &cache)
        return try #require(segments.compactMap { if case .assistantTurn(let turn) = $0 { turn } else { nil } }.first)
    }

    private let user = #"{"id":"u1","runId":"u1","role":"user","content":"plan","timestamp":1}"#
    private let call =
        #"{"id":"a1","runId":"u1","role":"assistant","content":[{"type":"toolCall","id":"k1","name":"map_itinerary","arguments":{"title":"Kyoto","days":[]}}],"stopReason":"toolUse","timestamp":2}"#

    @Test("a result becomes the prepared card model, decoded once")
    func result() throws {
        let row = #"{"id":"t1","runId":"u1","role":"toolResult","toolCallId":"k1","toolName":"map_itinerary","content":[{"type":"text","text":"ok"}],"details":\#(kyoto),"isError":false,"timestamp":3}"#
        let built = try turn([user, call, row])
        let card = try #require(built.toolCards.first)
        #expect(card.kind == .mapItinerary)
        #expect(card.content.mapItinerary?.model?.stopCount == 12)
        #expect(ToolCardRegistry.canDraw(card))
    }

    @Test("a failed call draws the card with the tool's own error, under the trip's title")
    func failed() throws {
        let row = #"{"id":"t1","runId":"u1","role":"toolResult","toolCallId":"k1","toolName":"map_itinerary","content":[{"type":"text","text":"Map Itinerary requires a Google API Key."}],"details":null,"isError":true,"timestamp":3}"#
        let built = try turn([user, call, row])
        let card = try #require(built.toolCards.first)
        #expect(card.isError)
        #expect(card.content.mapItinerary == .failed(title: "Kyoto", message: "Map Itinerary requires a Google API Key."))
    }

    @Test("details that are not an itinerary fall back to the generic card and are reported")
    func unreadable() {
        let card = ToolCard(
            id: "t", toolName: "map_itinerary", kind: .mapItinerary, payload: value(#"{"type":"mapItinerary"}"#))
        #expect(card.content == .undecodable)
        #expect(ToolPresentation.renderIssue(for: card)?.message == "Unreadable map_itinerary card shown as the generic card")
    }
}

@MainActor
@Suite("Map itinerary: the card draws every state without falling back")
struct MapItineraryRenderTests {
    @Test("a trip, a trip with unplaced stops, an empty one and a failed call draw their own card and report nothing")
    func drawsWithoutReports() async {
        let reports = MapReportLog()
        let diagnostics = RenderDiagnostics { _, message, _ in reports.append(message) }
        let cards = [
            ToolCard(id: "t1", toolName: "map_itinerary", kind: .mapItinerary, payload: value(kyoto)),
            ToolCard(id: "t2", toolName: "map_itinerary", kind: .mapItinerary, payload: value(partlyPlaced)),
            ToolCard(
                id: "t3", toolName: "map_itinerary", kind: .mapItinerary, payload: value(#"{"type":"mapItinerary","days":[]}"#)),
            ToolCard(id: "t4", toolName: "map_itinerary", kind: .generic, isError: true, errorText: "No key"),
        ]
        for card in cards {
            guard case .card = ToolCardRegistry.resolve(card) else {
                Issue.record("\(card.id) fell back to the generic card")
                continue
            }
        }
        let root = VStack { ForEach(cards) { ToolCardView(card: $0) } }
            .environment(\.renderDiagnostics, diagnostics)
            .environment(\.colorTone, .violet)
        let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 390, height: 1600))
        window.rootViewController = UIHostingController(rootView: root)
        window.makeKeyAndVisible()
        window.layoutIfNeeded()
        try? await Task.sleep(for: .milliseconds(150))
        #expect(reports.entries.isEmpty)
        window.isHidden = true
    }
}

private final class MapReportLog: @unchecked Sendable {
    private let lock = NSLock()
    private var stored: [String] = []

    var entries: [String] { lock.withLock { stored } }

    func append(_ entry: String) { lock.withLock { stored.append(entry) } }
}
