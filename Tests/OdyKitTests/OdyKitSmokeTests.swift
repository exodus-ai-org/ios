import Testing

@testable import OdyKit

struct OdyKitSmokeTests {
    @Test func moduleLinks() { #expect(OdyKit.version == 1) }
}
