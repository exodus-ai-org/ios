#if DEBUG
import Models
import SwiftUI

/// The weather card is real now: this group draws `WeatherCard` from `ToolCard`s built the way the transcript builds
/// them, in its states.
struct ProtoWeatherSection: View {
    private static func card(details: JSONValue? = nil, error: String? = nil) -> ToolCardView {
        ToolCardView(
            card: ToolCard(
                id: "weather", toolName: "weather", kind: .weather, payload: details,
                arguments: .object(["location": .string("Atlantis")]), isError: error != nil, errorText: error))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 28) {
            UserBubble(text: "What's the weather in Shanghai this week?")
            ProtoInReply(state: "Running · a sketch: a chat shows the step in the timeline, no card") {
                ProtoCardHeader(systemImage: "cloud.sun", title: "Weather", subtitle: "Shanghai") {
                    ProtoStatusIcon(status: .running)
                }
                .protoCard()
            }
            ProtoInReply(
                state: "Done · compact (tap Details, drag the curve)", header: "Worked for 2 sec",
                answer: "Mild and partly cloudy today; rain moves in tomorrow, then a clear weekend."
            ) {
                Self.card(details: ProtoFixtures.weatherShanghai)
            }
            ProtoInReply(state: "Done · opened") {
                Self.card(details: ProtoFixtures.weatherShanghai)
                    .environment(\.weatherCardStartsOpen, true)
            }
            ProtoInReply(state: "Long place name, at night") {
                Self.card(details: ProtoFixtures.weatherLongName)
            }
            ProtoInReply(state: "Legacy wttr.in row (WWO codes, 8 slots, “06:52 AM”)") {
                Self.card(details: ProtoFixtures.weatherLegacy)
            }
            ProtoInReply(state: "Legacy row, opened") {
                Self.card(details: ProtoFixtures.weatherLegacy)
                    .environment(\.weatherCardStartsOpen, true)
            }
            ProtoInReply(state: "Error") {
                Self.card(error: "No place found for \"Atlantis\"")
            }
        }
    }
}
#endif
