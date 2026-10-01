import Testing

@testable import HealthFeature

struct HealthRootSmokeTests {
    @Test func moduleLinks() { #expect(HealthFeatureInfo.name == "Health") }
}
