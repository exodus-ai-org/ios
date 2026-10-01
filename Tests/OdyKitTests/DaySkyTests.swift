// Tests/OdyKitTests/DaySkyTests.swift
import Testing

@testable import OdyKit

struct DaySkyTests {
    @Test func nightAndDayColours() {
        #expect(DaySky.gradient(atClockHour: 0).top == RGB(hex: 0x141235))
        #expect(DaySky.gradient(atClockHour: 13).top == RGB(hex: 0xFFE27A))
        #expect(DaySky.gradient(atClockHour: 13).bottom == RGB(hex: 0xFFF0BE))
    }

    @Test func wrapsAroundMidnight() {
        #expect(DaySky.gradient(atClockHour: 24) == DaySky.gradient(atClockHour: 0))
        #expect(DaySky.gradient(atClockHour: -2) == DaySky.gradient(atClockHour: 22))
        #expect(DaySky.gradient(atClockHour: 27.5) == DaySky.gradient(atClockHour: 3.5))
    }

    @Test func dawnIsBetweenNightAndMorning() {
        let dawn = DaySky.gradient(atClockHour: 5.5).top
        #expect(dawn != RGB(hex: 0x141235) && dawn != RGB(hex: 0xFFE9A0))
    }

    @Test func nightFactor() {
        #expect(DaySky.night(atClockHour: 2) == 1)
        #expect(DaySky.night(atClockHour: 12) == 0)
        let dawn = DaySky.night(atClockHour: 5.9)
        #expect(dawn > 0 && dawn < 1)
    }

    @Test func sunAndMoonPaths() {
        let noon = try! #require(DaySky.sun(atClockHour: 12))
        #expect(abs(noon.x - 0.5) < 0.001 && noon.y < 0.2)
        #expect(DaySky.sun(atClockHour: 2) == nil)
        let midnight = try! #require(DaySky.moon(atClockHour: 0))
        #expect(abs(midnight.x - 0.5) < 0.001)
        #expect(DaySky.moon(atClockHour: 12) == nil)
    }

    @Test func bodiesFadeAtTheHorizons() {
        #expect(DaySky.sunOpacity(atClockHour: 6) == 0 && DaySky.sunOpacity(atClockHour: 18) == 0)
        #expect(DaySky.sunOpacity(atClockHour: 12) == 1)
        #expect(DaySky.moonOpacity(atClockHour: 18) == 0 && DaySky.moonOpacity(atClockHour: 6) == 0)
        #expect(DaySky.moonOpacity(atClockHour: 0) == 1)
    }

    @Test func everythingIsContinuousThroughTheDay() {
        func parts(_ h: Double) -> [Double] {
            let g = DaySky.gradient(atClockHour: h)
            return [
                DaySky.sunOpacity(atClockHour: h), DaySky.moonOpacity(atClockHour: h), DaySky.night(atClockHour: h),
                g.top.r, g.top.g, g.top.b, g.bottom.r, g.bottom.g, g.bottom.b,
            ]
        }
        var previous = parts(0)
        for i in 1...2400 {
            let now = parts(Double(i) * 0.01)
            for (a, b) in zip(previous, now) { #expect(abs(a - b) < 0.15) }
            previous = now
        }
    }
}
