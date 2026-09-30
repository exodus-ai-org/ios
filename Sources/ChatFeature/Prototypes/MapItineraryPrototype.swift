#if DEBUG
import Models
import SwiftUI
import UIKit

/// The map itinerary card is real now: this group draws `MapItineraryCard` from `ToolCard`s built the way the
/// transcript builds them. `-CardPrototypesMapFull <stop id>|day` opens the full-screen map of the Kyoto fixture at
/// launch (`day` for no stop), for screenshots.
struct ProtoMapItinerarySection: View {
    @State private var launchFocus: MapItineraryFocus?

    private static func card(details: JSONValue? = nil, error: String? = nil) -> ToolCardView {
        ToolCardView(
            card: ToolCard(
                id: "map", toolName: "map_itinerary", kind: error == nil ? .mapItinerary : .generic, payload: details,
                arguments: .object(["title": .string("Kyoto in two days")]), isError: error != nil, errorText: error))
    }

    /// A stand-in for the computer's photo proxy: `photos/1` is a drawn picture, any other photo fails (the placeholder
    /// stays), after a short wait so the placeholder shows first.
    private static let photos = PlacePhotoLoader { name, width in
        try await Task.sleep(for: .milliseconds(500))
        guard name.hasSuffix("/photos/1") else { throw URLError(.badServerResponse) }
        return await MainActor.run { Self.drawnPhoto(width: width) }
    }

    @MainActor
    private static func drawnPhoto(width: Int) -> Data {
        let size = CGSize(width: width, height: width * 9 / 16)
        return UIGraphicsImageRenderer(size: size, format: .init(for: .init(displayScale: 1))).pngData { context in
            let colors = [UIColor.systemOrange.cgColor, UIColor.systemRed.cgColor, UIColor.systemPurple.cgColor] as CFArray
            if let gradient = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(), colors: colors, locations: [0, 0.55, 1]) {
                context.cgContext.drawLinearGradient(
                    gradient, start: .zero, end: CGPoint(x: size.width, y: size.height), options: [])
            }
            UIColor.white.withAlphaComponent(0.85).setFill()
            for index in 0..<7 {
                let x = size.width * (0.12 + Double(index) * 0.11)
                context.fill(CGRect(x: x, y: size.height * 0.25, width: size.width * 0.03, height: size.height * 0.75))
            }
        }
    }

    private static var fullLaunch: String? {
        let arguments = ProcessInfo.processInfo.arguments
        guard let index = arguments.firstIndex(of: "-CardPrototypesMapFull"), index + 1 < arguments.count else { return nil }
        return arguments[index + 1]
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 28) {
            UserBubble(text: "Plan two days in Kyoto: temples on day one, Arashiyama on day two.")
            ProtoInReply(state: "Running · a sketch: a chat shows the step in the timeline, no card") {
                ProtoCardHeader(
                    systemImage: "map", title: "Map Itinerary",
                    subtitle: ToolPresentation.itineraryText(ItineraryScale(days: 2, stops: 12))
                ) {
                    ProtoStatusIcon(status: .running)
                }
                .protoCard()
            }
            ProtoInReply(
                state: "Done · two days, expired key notice (tap the map, a stop or +N more)", header: "Worked for 9 sec",
                answer: "Start early at Fushimi Inari, then work north through Higashiyama to Gion for dinner."
            ) {
                Self.card(details: ProtoFixtures.kyoto)
            }
            ProtoInReply(state: "Four days, one colour each; a stop with no position") {
                Self.card(details: ProtoFixtures.vienna)
            }
            ProtoInReply(state: "A week: the day picker scrolls, and the list names its day over its times") {
                Self.card(details: ProtoFixtures.phuket)
            }
            ProtoInReply(state: "A single place") {
                Self.card(details: ProtoFixtures.lookup)
            }
            ProtoInReply(state: "No positions at all: a list") {
                Self.card(details: ProtoFixtures.unplaced)
            }
            ProtoInReply(state: "Error") {
                Self.card(error: ProtoFixtures.mapError)
            }
        }
        .fullScreenCover(item: $launchFocus) { focus in
            // `-CardPrototypesMapFull week`: the seven-day Phuket trip instead of Kyoto.
            if let details = MapItineraryDetails(json: Self.fullLaunch == "week" ? ProtoFixtures.phuket : ProtoFixtures.kyoto) {
                MapItineraryFullView(model: MapItineraryCardModel(details), start: focus)
                    .environment(\.placePhotoLoader, Self.photos)
            }
        }
        .environment(\.placePhotoLoader, Self.photos)
        .task {
            guard let launch = Self.fullLaunch else { return }
            try? await Task.sleep(for: .milliseconds(600))
            launchFocus = MapItineraryFocus(dayIndex: launch.hasPrefix("d1") ? 1 : 0, stopId: launch == "day" || launch == "week" ? nil : launch)
        }
    }
}
#endif
