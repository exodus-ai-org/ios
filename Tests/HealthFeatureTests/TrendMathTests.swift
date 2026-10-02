import Foundation
import Models
import Testing

@testable import HealthFeature

struct TrendMathTests {
    let cal = TestClock.calendar
    func d(_ y: Int, _ m: Int, _ day: Int, _ h: Int = 0) -> Date { TestClock.date(y, m, day, h) }

    static func zone(_ id: String) -> Calendar {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: id)!
        return c
    }

    // MARK: Periods

    @Test func aWeekRunsMondayToSunday() {
        let p = Period.containing(d(2026, 10, 1, 15), .week, calendar: cal)
        #expect(p.start == d(2026, 9, 28))
        #expect(p.end == d(2026, 10, 5))
        #expect(p.days(calendar: cal).count == 7)
        #expect(p.reportID(calendar: cal) == "2026-W40")
        #expect(p.isoWeek(calendar: cal) == 40)
    }

    @Test func sundayEndsItsWeek() {
        #expect(Period.containing(d(2026, 10, 4, 23), .week, calendar: cal).start == d(2026, 9, 28))
        #expect(Period.containing(d(2026, 10, 5), .week, calendar: cal).start == d(2026, 10, 5))
    }

    /// A phone set to a region whose weeks start on Sunday still gets Monday-to-Sunday weeks and ISO numbers.
    @Test func weeksStartOnMondayWhateverTheRegion() {
        var us = cal
        us.locale = Locale(identifier: "en_US")
        us.firstWeekday = 1
        us.minimumDaysInFirstWeek = 1
        let p = Period.containing(d(2026, 10, 4, 12), .week, calendar: us)
        #expect(p.start == d(2026, 9, 28))
        #expect(p.reportID(calendar: us) == "2026-W40")
        #expect(p.isoWeek(calendar: us) == 40)
    }

    @Test func isoWeeksAcrossNewYear() {
        let jan1 = Period.containing(d(2027, 1, 1), .week, calendar: cal)
        #expect(jan1.start == d(2026, 12, 28))
        #expect(jan1.reportID(calendar: cal) == "2026-W53")
        #expect(Period.containing(d(2025, 12, 29), .week, calendar: cal).reportID(calendar: cal) == "2026-W01")
        #expect(Period.containing(d(2027, 1, 4), .week, calendar: cal).reportID(calendar: cal) == "2027-W01")
        #expect(jan1.next(calendar: cal).reportID(calendar: cal) == "2027-W01")
        #expect(jan1.previous(calendar: cal).reportID(calendar: cal) == "2026-W52")
    }

    @Test func monthsQuartersAndYears() {
        let month = Period.containing(d(2026, 10, 1, 15), .month, calendar: cal)
        #expect(month.start == d(2026, 10, 1) && month.end == d(2026, 11, 1))
        #expect(month.days(calendar: cal).count == 31)
        #expect(month.reportID(calendar: cal) == "2026-10")
        let q3 = Period.containing(d(2026, 8, 15), .quarter, calendar: cal)
        #expect(q3.start == d(2026, 7, 1) && q3.end == d(2026, 10, 1))
        #expect(q3.days(calendar: cal).count == 92)
        #expect(q3.reportID(calendar: cal) == "2026-Q3")
        let year = Period.containing(d(2026, 10, 1), .year, calendar: cal)
        #expect(year.start == d(2026, 1, 1) && year.end == d(2027, 1, 1))
        #expect(year.days(calendar: cal).count == 365)
        #expect(year.reportID(calendar: cal) == "2026")
    }

    @Test func leapYears() {
        #expect(Period.containing(d(2028, 2, 10), .month, calendar: cal).days(calendar: cal).count == 29)
        #expect(Period.containing(d(2027, 2, 10), .month, calendar: cal).days(calendar: cal).count == 28)
        #expect(Period.containing(d(2028, 3, 1), .quarter, calendar: cal).days(calendar: cal).count == 91)
        #expect(Period.containing(d(2028, 7, 1), .year, calendar: cal).days(calendar: cal).count == 366)
    }

    @Test func previousAndNext() {
        let jan = Period.containing(d(2027, 1, 20), .month, calendar: cal)
        #expect(jan.previous(calendar: cal) == Period.containing(d(2026, 12, 5), .month, calendar: cal))
        let mar = Period.containing(d(2027, 3, 31), .month, calendar: cal)
        #expect(mar.previous(calendar: cal).start == d(2027, 2, 1))
        #expect(mar.previous(calendar: cal).end == d(2027, 3, 1))
        let q1 = Period.containing(d(2027, 2, 1), .quarter, calendar: cal)
        #expect(q1.previous(calendar: cal).reportID(calendar: cal) == "2026-Q4")
        #expect(q1.next(calendar: cal).reportID(calendar: cal) == "2027-Q2")
        #expect(Period.containing(d(2026, 6, 1), .year, calendar: cal).previous(calendar: cal).reportID(calendar: cal) == "2025")
    }

    @Test func aWindowOfDaysEndsOnItsDay() {
        let w = Period.containing(d(2026, 10, 1, 15), .days(7), calendar: cal)
        #expect(w.start == d(2026, 9, 25) && w.end == d(2026, 10, 2))
        #expect(w.previous(calendar: cal).start == d(2026, 9, 18))
        #expect(w.reportID(calendar: cal) == nil)
    }

    /// The week the clocks go forward in New York is seven days, though it is an hour short.
    @Test func aDaylightSavingWeekStillHasSevenDays() {
        let ny = Self.zone("America/New_York")
        let sunday = ny.date(from: DateComponents(year: 2026, month: 3, day: 8, hour: 12))!
        let p = Period.containing(sunday, .week, calendar: ny)
        #expect(p.start == ny.date(from: DateComponents(year: 2026, month: 3, day: 2))!)
        #expect(p.end == ny.date(from: DateComponents(year: 2026, month: 3, day: 9))!)
        #expect(p.days(calendar: ny).count == 7)
        #expect(p.end.timeIntervalSince(p.start) == 7 * 86_400 - 3_600)
    }

    /// São Paulo skipped midnight on 4 November 2018: that day starts at 01:00, and November still has 30 days.
    @Test func aMonthWithAMissingMidnight() {
        let sp = Self.zone("America/Sao_Paulo")
        let p = Period.containing(sp.date(from: DateComponents(year: 2018, month: 11, day: 20))!, .month, calendar: sp)
        let days = p.days(calendar: sp)
        #expect(days.count == 30)
        #expect(days.map { sp.component(.day, from: $0) } == Array(1...30))
        #expect(sp.component(.hour, from: days[3]) == 1)
    }

    // MARK: Aggregates

    func record(_ day: Int, sleep: Int? = nil, steps: Int? = nil, hrv: Double? = nil, goal: Int = 8000) -> DayRecord {
        DayRecord(day: d(2026, 9, day), sleepMin: sleep, steps: steps, stepGoal: goal, hrvMs: hrv, mood: .happy)
    }

    /// 21–27 September 2026, a whole week before today.
    var lastFullWeek: Period { Period.containing(d(2026, 9, 23), .week, calendar: cal) }

    @Test func averagesSkipDaysWithoutTheNumber() {
        let records = [record(21, sleep: 420, steps: 9000, hrv: 40), record(22, sleep: 360), record(23, steps: 7000, hrv: 50), record(24)]
        let a = TrendMath.aggregate(records, in: lastFullWeek, today: TestClock.today, calendar: cal)
        #expect(a.elapsedDays == 7)
        #expect(a.daysWithData == 3)
        #expect(a.sleepMin == MetricSummary(average: 390, min: 360, max: 420, days: 2))
        #expect(a.steps.average == 8000)
        #expect(a.hrvMs.average == 45)
        #expect(a.waterCups == MetricSummary(average: nil, min: nil, max: nil, days: 0))
    }

    @Test func targetHitRates() {
        let records = [
            record(21, sleep: 420, steps: 9000), record(22, sleep: 419, steps: 8000), record(23, steps: 7999),
            record(24, steps: 5000, goal: 4000),
        ]
        let a = TrendMath.aggregate(records, in: lastFullWeek, today: TestClock.today, calendar: cal)
        #expect(a.stepGoalRate == 0.75)
        #expect(a.sleepTargetRate == 0.5)
    }

    @Test func noDaysNoRates() {
        let a = TrendMath.aggregate([], in: lastFullWeek, today: TestClock.today, calendar: cal)
        #expect(a.daysWithData == 0)
        #expect(a.stepGoalRate == nil && a.sleepTargetRate == nil && a.sleepMin.average == nil)
    }

    @Test func onlyTheDaysOfThePeriodUpToTodayCount() {
        let week = Period.containing(TestClock.now, .week, calendar: cal)  // 28 Sep – 4 Oct; today is Thursday 1 Oct
        let records = [
            DayRecord(day: d(2026, 9, 27), steps: 100_000),
            DayRecord(day: d(2026, 9, 28), steps: 4000),
            DayRecord(day: d(2026, 10, 1), steps: 6000),
            DayRecord(day: d(2026, 10, 2), steps: 100_000),
        ]
        let a = TrendMath.aggregate(records, in: week, today: TestClock.now, calendar: cal)
        #expect(a.elapsedDays == 4)
        #expect(a.steps.average == 5000)
    }

    // MARK: Change

    @Test func changeAgainstThePreviousPeriod() throws {
        let up = try #require(TrendMath.change(100, from: 96))
        #expect(up.direction == .up && up.absolute == 4)
        let down = try #require(TrendMath.change(90, from: 100))
        #expect(down.direction == .down && down.relative == -0.1)
        #expect(TrendMath.change(100, from: 98)?.direction == .flat)
        #expect(TrendMath.change(97.1, from: 100)?.direction == .flat)
        #expect(TrendMath.change(103, from: 100)?.direction == .up)
        #expect(TrendMath.change(100, from: nil) == nil)
        #expect(TrendMath.change(nil, from: 100) == nil)
    }

    @Test func fromZeroThereIsNoShare() throws {
        let c = try #require(TrendMath.change(5, from: 0))
        #expect(c.relative == nil && c.direction == .up)
        #expect(TrendMath.change(0, from: 0)?.direction == .flat)
    }

    // MARK: DayRecord

    @Test func ringsAndTones() {
        let r = DayRecord(day: TestClock.today, sleepMin: 210, steps: 12_000, stepGoal: 8000, mood: .tired)
        #expect(r.sleepFraction == 0.5)
        #expect(r.stepFraction == 1)
        #expect(DayRecord(day: TestClock.today, sleepMin: 600).sleepFraction == 1)
        #expect(DayRecord(day: TestClock.today, steps: 100, stepGoal: 0).stepFraction == 0)
        #expect(DayRecord(day: TestClock.today).sleepFraction == nil)
        #expect(!DayRecord(day: TestClock.today).hasData)
        #expect(DayTone(.tired) == .tired)
        #expect(DayTone(.recovering) == .recovering)
        #expect([OdyMood.active, .rested, .calm, .happy].allSatisfy { DayTone($0) == .good })
        #expect(DayTone(.noData) == .empty && DayTone(.permission) == .empty)
    }

    @Test func aRecordFromASnapshot() {
        let s = HealthSnapshot(
            date: "2026-10-01", localTime: "23:59", locale: "en",
            sleep: .init(
                asleepMin: 400, baselineMin: nil, deepMin: 0, coreMin: 400, remMin: 0, awakeMin: 0, bedtime: "23:30",
                wake: "06:10"),
            activity: .init(
                steps: 9000, stepGoal: 8000, activeKcal: 0, kcalGoal: nil, exerciseMin: 25, standHours: 0, workouts: []),
            recovery: nil, body: .init(waterCups: 0, weightKg: 70, weightTrend30d: nil, mood: nil), odyState: .active)
        let r = DayRecord(day: TestClock.today, snapshot: s, stepGoal: 8000)
        #expect(
            r == DayRecord(
                day: TestClock.today, sleepMin: 400, steps: 9000, stepGoal: 8000, exerciseMin: 25, bedtime: "23:30",
                mood: .active))
    }
}
