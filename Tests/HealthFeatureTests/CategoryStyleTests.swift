import Models
import OdyKit
import Testing

@testable import HealthFeature

struct CategoryStyleTests {
    @Test func heroScenes() {
        #expect(OdyScene(hero: .tired) == .tired)
        #expect(OdyScene(hero: .permission) == .permission)
        #expect(OdyScene(hero: .noData) == .noData)
        #expect(OdyScene(hero: .happy) == .rested)
        #expect(OdyScene(hero: .calm) == .calm)
    }

    @Test func cardScenes() {
        #expect(OdyScene(card: .sleep, mood: .tired) == .tired)
        #expect(OdyScene(card: .activity, mood: .happy) == .active)
        #expect(OdyScene(card: .recovery, mood: .recovering) == .recovering)
        #expect(OdyScene(card: .recovery, mood: .rested) == .calm)
        #expect(OdyScene(card: .body, mood: .happy) == .hydrating)
        #expect(OdyScene(card: .body, mood: .calm) == .calm)
        for c in HealthCategory.allCases { #expect(OdyScene(card: c, mood: .noData) == .noData) }
    }

    @Test func cardValues() {
        let s = HealthRulesTests.snapshot(
            sleep: HealthRulesTests.sleep(372), activity: HealthRulesTests.steps(5840),
            recovery: HealthRulesTests.recovery(.low),
            body: .init(waterCups: 3, weightKg: nil, weightTrend30d: nil, mood: nil))
        #expect(CategoryValue.text(.sleep, in: s) 
            == Duration.seconds(372 * 60).formatted(.units(allowed: [.hours, .minutes], width: .narrow)))
        #expect(CategoryValue.text(.recovery, in: s) != nil)
        #expect(CategoryValue.text(.body, in: s) == CategoryValue.cups(3))
        let noLevel = HealthRulesTests.snapshot(recovery: HealthRulesTests.recovery(nil))
        #expect(CategoryValue.text(.recovery, in: noLevel)?.contains("60") == true)
        #expect(CategoryValue.text(.activity, in: s)?.contains("5") == true)
        #expect(CategoryValue.text(.body, in: s) != nil)
        #expect(CategoryValue.text(.sleep, in: HealthRulesTests.snapshot()) == nil)
    }
}
