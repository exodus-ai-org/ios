import Testing

@testable import ChatFeature

struct HealthContextCardTests {
    @Test func chipsFromATodaySnapshot() {
        let json = #"{"activity":{"activeKcal":1,"exerciseMin":0,"standHours":0,"stepGoal":8000,"steps":5840,"workouts":[]},"date":"2026-10-01","locale":"en","localTime":"15:00","odyState":"tired","sleep":{"asleepMin":372,"awakeMin":0,"bedtime":"23:48","coreMin":0,"deepMin":0,"remMin":0,"wake":"06:00"}}"#
        let chips = HealthContextCard.chips(json: json)
        #expect(chips.contains { $0.systemImage == "moon.zzz.fill" })
        #expect(chips.contains { $0.systemImage == "figure.walk" })
    }

    @Test func aWeekAttachmentIsOneChip() {
        let chips = HealthContextCard.chips(json: #"{"category":"sleep","days":[]}"#)
        #expect(chips.count == 1)
        #expect(chips.first?.text != "sleep")  // Health's title, not the wire name
    }

    @Test func anUnknownCategoryShowsAsSent() {
        #expect(HealthContextCard.categoryTitle("naps") == "naps")
    }

    @Test func unreadableJSONStillShowsACard() {
        #expect(HealthContextCard.chips(json: "not json").count == 1)
    }
}
