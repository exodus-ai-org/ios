# Health Trends 1 — Archive, Day Records, Trend Math and the Calendar Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Health keeps every daily note on the phone, can read any past day from Apple Health, and shows direction: a calendar (Week · Month · Quarter · Year) of style-C day cells with averages against the period before, a day sheet with that day's note (or its numbers), a "This week" card on the home, and "Clear archive" in the Health menu.

**Architecture:** Three pure, tested layers under the views. `HealthArchive` files each stored note by day next to today's `report.json` (written from the existing `ReportCache.save`). `SnapshotBuilder` is generalised from "today" to any day, plus a batch path that reads a run of days with one HealthKit query per series and assembles every day by the same rules (so the Ody state of a past day is exactly what the home would have shown); `DayRecordStore` caches past days in memory, never today. `TrendMath` turns `DayRecord`s into per-`Period` aggregates and changes (ISO weeks Mon–Sun, months, quarters, years, N-day windows). `TrendsModel` drives the pushed calendar page; `HealthHomeModel` gains the week glance, the archive and `clearArchive()`.

**Tech Stack:** Swift 6, SwiftUI (iOS 27: `NavigationStack` value routes, `.sheet(item:)`, `sensoryFeedback`, `AnyLayout`), HealthKit through the existing `HealthDataSource`, Foundation date/format styles, Swift Testing.

**Spec:** `docs/superpowers/specs/2026-10-02-health-trends-design.md` — this plan is §8 phase 1: §2.1, §2.2, §2.3, §3.1 (without the report line), §3.2 (without the report card), §3.3, §3.6, §6 (local parts), §7 (archive, TrendMath, DayRecord tests; gallery; checklist). Period reports (§2.4, §3.4, §4, §5) and habits (§2.5, §3.5) are phases 2 and 3 with their own plans. Prototype for feel: `.superpowers/brainstorm/36445-1790902464/content/health-calendar-proto.html` (cell style **C**).

**Seams left for phases 2–3 (do not build them now):** `Period.reportID(calendar:)` gives the report file names (`2026-W40`, `2026-09`, `2026-Q3`, `2026`); `Aggregates` is `Codable` (phase 2's request body carries it); `HealthArchive.clear()` deletes the whole `archive/` folder, so phase 2's `archive/reports/` is cleared with it; `TrendsView` has the stats header directly above the period body, where phase 2's report card goes; `DayRecord` holds every number a phase-3 habit checks, and `CalendarCell` is the unit a habit highlight dims.

## Global Constraints

- Repo `/Users/yanceyleo/Code/exodus/exodus-ios`, branch `maintenance`. Read `.superpowers/sdd/constraints.md` once; where it differs from this list (its simulator line), this list wins.
- **Commits only through the helper**, from the repo root: `.superpowers/sdd/commit-mine.sh "<subject>" [--patch FILE.patch ...] <paths you own>`. Never run plain `git add`, `git commit`, `git commit -a`, `git stash`, `git reset`, `git restore` or `git checkout -- <file>`: the tree holds the user's uncommitted edits (e.g. `Resources/App/Localizable.xcstrings`, `Sources/App/ExodusApp.swift`) and a pre-staged foreign file (`Resources/App/Assets.xcassets/LaunchLogo.imageset/Contents.json`) that must stay staged and out of your commits. After each commit run `git show --stat HEAD` and confirm it lists ONLY your files; if not, STOP and report BLOCKED.
- **Never rewrite a file that has foreign edits**; change it with targeted edits only. Run `git diff --stat` at the start and end of every task and compare: only the files your task names may have changed. A file this plan replaces whole is one whose `git diff --stat -- <file>` is empty before you start.
- Never push.
- Swift 6 language mode, iOS 27.0 deployment target, Tuist 4.208 with buildable folders: a new file under an existing `Sources/<Module>` or `Tests/<Target>` folder is picked up without editing `Project.swift`. If `ExodusIos.xcworkspace` is missing, run `tuist generate --no-open` once; run it again after any `Project.swift` edit (none is planned).
- Native frameworks only; no new packages.
- Builds and tests: simulator `D8A2BE45-88F3-46AE-8693-B147F2815724` (iPhone 17e, iOS 27) with `-derivedDataPath /tmp/trends-dd`. Tests: `xcodebuild test -workspace ExodusIos.xcworkspace -scheme HealthFeature -destination "id=D8A2BE45-88F3-46AE-8693-B147F2815724" -derivedDataPath /tmp/trends-dd [-only-testing:HealthFeatureTests/<TypeName>] 2>&1 | grep -E "error:|✘|Test run with|TEST (SUCCEEDED|FAILED)"`. A wrong `-only-testing` name still prints SUCCEEDED — confirm a `Test run with N tests` line with N > 0.
- `python3 scripts/l10n.py audit` reports `0 error(s)` at the end of every task (warnings about unreferenced keys are fine until the task that uses them).
- **Health data never leaves the phone in phase 1.** No new network call. The archive lives in `Application Support/Health/archive/YYYY/MM/DD.json`, each file written with `.completeFileProtection`, the folder and each file `isExcludedFromBackup` (App Review: no health data in iCloud). The only way a day's numbers leave is the existing ask box, when the user sends a question.
- Weeks are ISO 8601: Monday to Sunday and week 1 holds the year's first Thursday, whatever the region's first weekday. "Flat" is a change under 3 % either way. The sleep target is 7 h (420 min) by default; the step goal 8,000 by default.
- Strings: new user-facing keys are `ios:health.<screen>.<element>` and all ten languages come from Task 4. Views use the key literal (`Text("ios:health.calendar.title")`); code outside view literals uses `String(localized: "…", defaultValue: "<exact English>", comment: "…")` or `LocalizedStringResource("…", defaultValue: …, comment: …)` whose `defaultValue` equals the catalog's English exactly. Never concatenate a sentence; never pass a ternary of two string literals to a text initializer; user data and numbers go through `Text(verbatim:)`.
- Dynamic Type: text styles everywhere; calendar cells keep their grid with numerals capped at `.dynamicTypeSize(...DynamicTypeSize.xxLarge)` (the codebase's cap for fixed-size chrome); every other layout switches at `dynamicTypeSize.isAccessibilitySize` (stack vertically, one per row) like `HealthHomeView.columns`.
- Reduce Motion: page turns cross-fade instead of sliding; the cell press scale is off; `ReportStory`'s rise is already off.
- Haptics only through `.sensoryFeedback` (no sounds).
- Match the surrounding code: doc comments short and plain, saying *why*; no comment noise; Swift Testing (`import Testing`, `@Test`, `#expect`, `#require`).
- Do not dispatch subagents from inside a task.

## Review Focus

- Paging ‹ › faster than Apple Health answers (or switching Week → Year while a month is loading): the older period's numbers must never land under the newer title. Test: `TrendsModelTests.aSlowerOlderLoadNeverOverwritesANewerOne` (Task 5).
- A phone whose region starts weeks on Sunday (en_US): weeks still run Monday–Sunday and "Week 40" is the ISO number. Test: `TrendMathTests.weeksStartOnMondayWhateverTheRegion` (Task 1).
- Today while it goes on: the home card and today's cell must show new steps on the next visit, so today is never cached while past days are. Test: `DayRecordTests.todayIsReadAgainEachTime` (Task 3).
- Turning "Write daily notes" off, or pressing "Clear archive": the first keeps every past note and really deletes today's `report.json` (also under "Application Support", whose space the old `path()` call percent-encoded); the second deletes every note (and phase 2's reports folder) but not today's note. Tests: `HealthArchiveTests.clearingTheReportKeepsTheArchive`, `clearingDeletesEveryNoteAndReport` (Task 2), `HealthHomeModelTests.clearingTheArchiveLeavesTodaysNote` (Task 5).
- The Year view on a phone with a year of Watch sleep: one HealthKit query per series for the whole span, not a dozen per day. Test: `DayRecordTests.aYearIsReadWithOneQueryPerSeries` (Task 3).

---

## File Structure

**HealthFeature — new folder `Sources/HealthFeature/Trends/`**
- `Trends/DayRecord.swift` — `DayRecord` (one day's numbers + Ody mood, ring fractions) and `DayTone` (the cell's state colour class).
- `Trends/TrendMath.swift` — `Period` (week/month/quarter/year/N days, previous/next, days, ISO week, report IDs), `MetricSummary`, `Aggregates`, `TrendChange`, `TrendMath` (calendar, aggregate, change).
- `Trends/DayRecordStore.swift` — in-memory cache of past days' records over `SnapshotBuilder`; today never cached.
- `Trends/CalendarGrid.swift` — `CalendarCell`, `MonthBar`, `WeekGlance`, `CalendarGrid` (cells with month padding, month bars).
- `Trends/TrendText.swift` — `TrendScope` (+ labels), `TrendsRoute`, `TrendMetric`, `TrendText` (titles, ranges, number and change text, spoken text, change colour).
- `Trends/TrendsModel.swift` — the calendar page's `@Observable` model.
- `Trends/DayToneStyle.swift` — `DayTone` colours and names, `CornerRing`, `RingInk`.
- `Trends/DaySheet.swift` — the day sheet and `DayNumbers`.
- `Trends/DayCellView.swift` — `DayCellView` (compact/large/row), `DayCellButton`, `PressScale`, `DayCellText`.
- `Trends/TrendStatsHeader.swift` — the three averages with change.
- `Trends/MonthBarsView.swift` — quarter/year month bars.
- `Trends/TrendsView.swift` — the calendar page, `PresentedDay`.
- `Trends/WeekCard.swift` — the home's "This week" card.
- `Report/HealthArchive.swift` — `ArchivedDay`, `HealthArchive`.

**HealthFeature — modified**
- `Data/SnapshotBuilder.swift` — replaced whole: `snapshot(for:now:locale:)`, `records(from:through:now:)`, `StoreSpan`, one shared `assemble`.
- `Data/SleepAnalyzer.swift` — append `SleepAnalyzer.nights(from:days:calendar:)`.
- `Report/ReportStore.swift` — `ReportCache.archive`, archive write in `save`, `clear()` path fix.
- `Report/HealthHomeModel.swift` — `calendar`, `dayRecords`, `week`, `archive`, `loadWeek()`, `trends(_:)`, `clearArchive()`.
- `UI/ReportStory.swift` — an optional eyebrow (the day sheet shows the date instead of "Today").
- `UI/CategoryStyle.swift` — `CategoryValue.steps(_:)` extracted.
- `UI/HealthHomeView.swift` — the week card and the `TrendsRoute` destination.
- `HealthRootView.swift` — "Clear archive" in the menu, its confirmation, success haptic.
- `Debug/HealthPreviewSource.swift` — 400 nights, some low-HRV days, `HealthArchive.writePreview(day:calendar:)`.

**App**: `Sources/App/HealthGallery.swift` — calendar and day-sheet gallery states.

**Resources**: `Resources/App/Localizable.xcstrings` — 38 new `ios:health.*` keys in ten languages (committed as a patch of only those hunks).

**Tests (`Tests/HealthFeatureTests/`)**: new `TrendMathTests.swift`, `HealthArchiveTests.swift`, `DayRecordTests.swift`, `TrendsModelTests.swift`, `DaySheetTests.swift`, `DayCellTextTests.swift`; modified `FakeHealthSource.swift` (a sleep-read counter), `HealthHomeModelTests.swift` (archive, week).

**Docs**: `docs/health-device-checklist.md`, `README.md` (HealthFeature module line).

---

### Task 1: `DayRecord` and `TrendMath`

**Files:**
- Create: `Sources/HealthFeature/Trends/DayRecord.swift`
- Create: `Sources/HealthFeature/Trends/TrendMath.swift`
- Test: `Tests/HealthFeatureTests/TrendMathTests.swift`

**Interfaces:**
- Consumes: `OdyMood`, `HealthSnapshot` (Models); `TestClock` (tests, `Tests/HealthFeatureTests/FakeHealthSource.swift`).
- Produces:
  - `public struct DayRecord: Equatable, Sendable { day: Date; sleepMin: Int?; steps: Int?; stepGoal: Int; exerciseMin: Int?; hrvMs: Double?; restingHr: Double?; waterCups: Int?; bedtime: String?; mood: OdyMood }` with `public init(day:sleepMin:steps:stepGoal:exerciseMin:hrvMs:restingHr:waterCups:bedtime:mood:)` (all but `day` defaulted: numbers `nil`, `stepGoal 8000`, `mood .noData`), `init(day: Date, snapshot: HealthSnapshot, stepGoal: Int)`, `var hasData: Bool`, `var sleepFraction: Double?`, `var stepFraction: Double?`.
  - `enum DayTone: CaseIterable, Equatable, Sendable { case good, tired, recovering, empty; init(_ mood: OdyMood) }`.
  - `public struct Period: Hashable, Sendable { enum Kind { week, month, quarter, year, days(Int) }; kind; start; end }` with `static func containing(_ date: Date, _ kind: Kind, calendar: Calendar) -> Period`, `func previous(calendar:) -> Period`, `func next(calendar:) -> Period`, `func days(calendar:) -> [Date]`, `func contains(_ date: Date) -> Bool`, `func isoWeek(calendar:) -> Int`, `func reportID(calendar:) -> String?`.
  - `public struct MetricSummary: Equatable, Sendable, Codable { average: Double?; min: Double?; max: Double?; days: Int }` + `static func of(_ values: [Double]) -> MetricSummary`.
  - `public struct Aggregates: Equatable, Sendable, Codable { elapsedDays, daysWithData: Int; sleepMin, steps, exerciseMin, hrvMs, restingHr, waterCups: MetricSummary; stepGoalRate, sleepTargetRate: Double? }`.
  - `public struct TrendChange: Equatable, Sendable { enum Direction { up, down, flat }; absolute: Double; relative: Double?; direction: Direction }`.
  - `public enum TrendMath { static let flatThreshold = 0.03; static let sleepTargetMin = 420; static func calendar(_ base: Calendar) -> Calendar; static func aggregate(_ records: [DayRecord], in: Period, today: Date, calendar: Calendar, sleepTarget: Int = 420) -> Aggregates; static func change(_ current: Double?, from previous: Double?) -> TrendChange? }`.

- [ ] **Step 1: Write the failing tests**

Create `Tests/HealthFeatureTests/TrendMathTests.swift`:

```swift
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
```

- [ ] **Step 2: Run them to verify they fail**

Run: `xcodebuild test -workspace ExodusIos.xcworkspace -scheme HealthFeature -destination "id=D8A2BE45-88F3-46AE-8693-B147F2815724" -derivedDataPath /tmp/trends-dd -only-testing:HealthFeatureTests/TrendMathTests 2>&1 | grep -E "error:|Test run with|TEST (SUCCEEDED|FAILED)"`
Expected: build errors `cannot find 'Period' in scope`, `cannot find 'DayRecord' in scope`.

- [ ] **Step 3: Write `DayRecord.swift`**

```swift
// Sources/HealthFeature/Trends/DayRecord.swift
import Foundation
import Models

/// One day's numbers as the calendar and the trends read them (and, later, the habits): computed on the phone from
/// Apple Health for any day, never sent anywhere by itself. A number the day doesn't have is `nil`, so an average
/// skips it instead of counting a zero.
public struct DayRecord: Equatable, Sendable {
    /// The day's start, in the calendar it was read with.
    public var day: Date
    public var sleepMin: Int?
    public var steps: Int?
    public var stepGoal: Int
    public var exerciseMin: Int?
    public var hrvMs: Double?
    public var restingHr: Double?
    public var waterCups: Int?
    /// When the night that ended on this day began, "HH:mm".
    public var bedtime: String?
    /// The day's Ody, by the same rules as the home's.
    public var mood: OdyMood

    public init(
        day: Date, sleepMin: Int? = nil, steps: Int? = nil, stepGoal: Int = 8000, exerciseMin: Int? = nil,
        hrvMs: Double? = nil, restingHr: Double? = nil, waterCups: Int? = nil, bedtime: String? = nil,
        mood: OdyMood = .noData
    ) {
        self.day = day
        self.sleepMin = sleepMin
        self.steps = steps
        self.stepGoal = stepGoal
        self.exerciseMin = exerciseMin
        self.hrvMs = hrvMs
        self.restingHr = restingHr
        self.waterCups = waterCups
        self.bedtime = bedtime
        self.mood = mood
    }

    /// The record of a built day. No cups is no water logged, not zero water.
    init(day: Date, snapshot s: HealthSnapshot, stepGoal: Int) {
        self.init(
            day: day, sleepMin: s.sleep?.asleepMin, steps: s.activity?.steps,
            stepGoal: s.activity?.stepGoal ?? stepGoal, exerciseMin: s.activity?.exerciseMin,
            hrvMs: s.recovery?.hrvMs, restingHr: s.recovery?.restingHr,
            waterCups: s.body.flatMap { $0.waterCups > 0 ? $0.waterCups : nil }, bedtime: s.sleep?.bedtime,
            mood: s.odyState)
    }

    public var hasData: Bool {
        sleepMin != nil || steps != nil || exerciseMin != nil || hrvMs != nil || restingHr != nil || waterCups != nil
    }

    /// The corner ring's outer arc: the night against the sleep target, full at or past it.
    public var sleepFraction: Double? {
        sleepMin.map { min(Double($0) / Double(TrendMath.sleepTargetMin), 1) }
    }

    /// The inner arc: steps against the day's goal.
    public var stepFraction: Double? {
        steps.map { stepGoal > 0 ? min(Double($0) / Double(stepGoal), 1) : 0 }
    }
}

/// A calendar cell's colour (style C): what kind of day it was, read from the day's Ody.
enum DayTone: CaseIterable, Equatable, Sendable {
    case good, tired, recovering, empty

    init(_ mood: OdyMood) {
        switch mood {
        case .active, .rested, .calm, .happy: self = .good
        case .tired: self = .tired
        case .recovering: self = .recovering
        case .noData, .permission: self = .empty
        }
    }
}
```

- [ ] **Step 4: Write `TrendMath.swift`**

```swift
// Sources/HealthFeature/Trends/TrendMath.swift
import Foundation

/// A stretch of whole days: an ISO week (Monday to Sunday, whatever the region's first weekday), a calendar month,
/// quarter or year, or the N days ending on a day. `start` is the first day's start and `end` the start of the day
/// after the last, in the calendar's time zone, so a daylight-saving week is still seven days.
public struct Period: Hashable, Sendable {
    public enum Kind: Hashable, Sendable {
        case week, month, quarter, year
        case days(Int)
    }

    public let kind: Kind
    public let start: Date
    public let end: Date

    /// The period of `kind` that holds `date`; for `.days(n)`, the n days ending on `date`'s day.
    public static func containing(_ date: Date, _ kind: Kind, calendar: Calendar) -> Period {
        let cal = TrendMath.calendar(calendar)
        let day = cal.startOfDay(for: date)
        let c = cal.dateComponents([.year, .month], from: day)
        func first(month: Int) -> Date {
            cal.startOfDay(for: cal.date(from: DateComponents(year: c.year, month: month, day: 1))!)
        }
        let start: Date
        switch kind {
        case .week:
            // Gregorian weekdays run Sunday 1 … Saturday 7; Monday is 0 days into an ISO week.
            let back = (cal.component(.weekday, from: day) + 5) % 7
            start = cal.startOfDay(for: cal.date(byAdding: .day, value: -back, to: day)!)
        case .month: start = first(month: c.month!)
        case .quarter: start = first(month: (c.month! - 1) / 3 * 3 + 1)
        case .year: start = first(month: 1)
        case .days(let n): start = cal.startOfDay(for: cal.date(byAdding: .day, value: -(max(n, 1) - 1), to: day)!)
        }
        return Period(kind: kind, start: start, end: advance(start, kind, by: 1, cal))
    }

    public func previous(calendar: Calendar) -> Period { shifted(-1, calendar) }

    public func next(calendar: Calendar) -> Period { shifted(1, calendar) }

    /// Each day's start, first to last.
    public func days(calendar: Calendar) -> [Date] {
        var out: [Date] = []
        var d = start
        while d < end {
            out.append(d)
            d = calendar.startOfDay(for: calendar.date(byAdding: .day, value: 1, to: d)!)
        }
        return out
    }

    public func contains(_ date: Date) -> Bool { date >= start && date < end }

    /// The ISO week number of a week (1–53).
    public func isoWeek(calendar: Calendar) -> Int {
        TrendMath.calendar(calendar).component(.weekOfYear, from: start)
    }

    /// The name a later phase files this period's report under: "2026-W40", "2026-09", "2026-Q3", "2026"; an N-day
    /// window has none. Weeks use the ISO week-numbering year, so 1 January 2027 is in "2026-W53".
    public func reportID(calendar: Calendar) -> String? {
        let cal = TrendMath.calendar(calendar)
        let c = cal.dateComponents([.year, .month, .weekOfYear, .yearForWeekOfYear], from: start)
        switch kind {
        case .week: return String(format: "%04d-W%02d", c.yearForWeekOfYear!, c.weekOfYear!)
        case .month: return String(format: "%04d-%02d", c.year!, c.month!)
        case .quarter: return String(format: "%04d-Q%d", c.year!, (c.month! - 1) / 3 + 1)
        case .year: return String(format: "%04d", c.year!)
        case .days: return nil
        }
    }

    private func shifted(_ n: Int, _ calendar: Calendar) -> Period {
        let cal = TrendMath.calendar(calendar)
        let s = Self.advance(start, kind, by: n, cal)
        return Period(kind: kind, start: s, end: Self.advance(s, kind, by: 1, cal))
    }

    /// Calendar arithmetic, never seconds: a month, quarter or year from its first day lands on a first day.
    private static func advance(_ start: Date, _ kind: Kind, by n: Int, _ cal: Calendar) -> Date {
        let moved: Date =
            switch kind {
            case .week: cal.date(byAdding: .day, value: 7 * n, to: start)!
            case .month: cal.date(byAdding: .month, value: n, to: start)!
            case .quarter: cal.date(byAdding: .month, value: 3 * n, to: start)!
            case .year: cal.date(byAdding: .year, value: n, to: start)!
            case .days(let d): cal.date(byAdding: .day, value: max(d, 1) * n, to: start)!
            }
        return cal.startOfDay(for: moved)
    }
}

/// One number over a period: its average, lowest and highest, and on how many days it was recorded.
public struct MetricSummary: Equatable, Sendable, Codable {
    public var average: Double?
    public var min: Double?
    public var max: Double?
    public var days: Int

    public init(average: Double?, min: Double?, max: Double?, days: Int) {
        self.average = average
        self.min = min
        self.max = max
        self.days = days
    }

    static func of(_ values: [Double]) -> MetricSummary {
        guard !values.isEmpty else { return MetricSummary(average: nil, min: nil, max: nil, days: 0) }
        return MetricSummary(
            average: values.reduce(0, +) / Double(values.count), min: values.min(), max: values.max(),
            days: values.count)
    }
}

/// A period in numbers: what the home card, the calendar's header and (later) the period reports and habits read.
public struct Aggregates: Equatable, Sendable, Codable {
    /// Days of the period that have begun: all of a past period, up to today in the current one.
    public var elapsedDays: Int
    /// Days with any number at all.
    public var daysWithData: Int
    public var sleepMin: MetricSummary
    public var steps: MetricSummary
    public var exerciseMin: MetricSummary
    public var hrvMs: MetricSummary
    public var restingHr: MetricSummary
    public var waterCups: MetricSummary
    /// Of the days with steps, the share at or over that day's goal.
    public var stepGoalRate: Double?
    /// Of the nights recorded, the share at or over the sleep target.
    public var sleepTargetRate: Double?
}

/// A number against the same number in the period before.
public struct TrendChange: Equatable, Sendable {
    public enum Direction: Equatable, Sendable { case up, down, flat }

    public var absolute: Double
    /// Against the previous value; nil when that was zero.
    public var relative: Double?
    public var direction: Direction
}

/// The trends' arithmetic, in one place for the home card, the calendar and the later phases.
public enum TrendMath {
    /// Under 3 % either way is no change.
    public static let flatThreshold = 0.03
    /// A night at or over 7 hours hit the target.
    public static let sleepTargetMin = 420

    /// The calendar periods are counted in: Gregorian in the given calendar's time zone, weeks from Monday, week 1
    /// the one holding the year's first Thursday (ISO 8601) — the same whatever the region's own first weekday.
    public static func calendar(_ base: Calendar) -> Calendar {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = base.timeZone
        c.firstWeekday = 2
        c.minimumDaysInFirstWeek = 4
        return c
    }

    /// The records inside `period` up to `today` (later or outside ones are ignored), summed up.
    public static func aggregate(
        _ records: [DayRecord], in period: Period, today: Date, calendar: Calendar,
        sleepTarget: Int = TrendMath.sleepTargetMin
    ) -> Aggregates {
        let last = calendar.startOfDay(for: today)
        let days = records.filter { period.contains($0.day) && $0.day <= last }
        func values(_ pick: (DayRecord) -> Double?) -> [Double] { days.compactMap(pick) }
        let withSteps = days.compactMap { r in r.steps.map { (steps: $0, goal: r.stepGoal) } }
        let nights = days.compactMap(\.sleepMin)
        return Aggregates(
            elapsedDays: period.days(calendar: calendar).filter { $0 <= last }.count,
            daysWithData: days.filter(\.hasData).count,
            sleepMin: .of(values { $0.sleepMin.map { Double($0) } }),
            steps: .of(values { $0.steps.map { Double($0) } }),
            exerciseMin: .of(values { $0.exerciseMin.map { Double($0) } }),
            hrvMs: .of(values { $0.hrvMs }),
            restingHr: .of(values { $0.restingHr }),
            waterCups: .of(values { $0.waterCups.map { Double($0) } }),
            stepGoalRate: withSteps.isEmpty
                ? nil : Double(withSteps.filter { $0.steps >= $0.goal }.count) / Double(withSteps.count),
            sleepTargetRate: nights.isEmpty
                ? nil : Double(nights.filter { $0 >= sleepTarget }.count) / Double(nights.count))
    }

    /// The change from `previous` to `current`; nil unless both are known.
    public static func change(_ current: Double?, from previous: Double?) -> TrendChange? {
        guard let current, let previous else { return nil }
        let absolute = current - previous
        let relative: Double? = previous == 0 ? nil : absolute / abs(previous)
        let direction: TrendChange.Direction
        if let relative {
            if abs(relative) < flatThreshold {
                direction = .flat
            } else {
                direction = relative > 0 ? .up : .down
            }
        } else if absolute == 0 {
            direction = .flat
        } else {
            direction = absolute > 0 ? .up : .down
        }
        return TrendChange(absolute: absolute, relative: relative, direction: direction)
    }
}
```

- [ ] **Step 5: Run the tests to verify they pass**

Run: the Step 2 command.
Expected: `Test run with 18 tests … passed`, `** TEST SUCCEEDED **`.

- [ ] **Step 6: Audit and commit**

```bash
python3 scripts/l10n.py audit 2>&1 | tail -1      # 0 error(s)
git diff --stat                                   # only the user's files, as at the start
.superpowers/sdd/commit-mine.sh "feat(health): TrendMath and DayRecord — ISO weeks, months, quarters, years, averages, hit rates and changes" \
  Sources/HealthFeature/Trends/DayRecord.swift Sources/HealthFeature/Trends/TrendMath.swift \
  Tests/HealthFeatureTests/TrendMathTests.swift
git show --stat HEAD                              # exactly those three files
```

---

### Task 2: `HealthArchive` and the report-save hook

**Files:**
- Create: `Sources/HealthFeature/Report/HealthArchive.swift`
- Modify: `Sources/HealthFeature/Report/ReportStore.swift` (`ReportCache.clear()` and `save(_:)`, plus a new `archive` property)
- Test: `Tests/HealthFeatureTests/HealthArchiveTests.swift`

**Interfaces:**
- Consumes: `CachedReport`, `ReportCache` (existing), `HealthWire.encoder()`, `ReportStoreTests.report()` (tests).
- Produces:
  - `public struct ArchivedDay: Codable, Equatable, Sendable { snapshot: HealthSnapshot; summary: HealthSummary; generatedAt: Date }` with `public init(snapshot:summary:generatedAt:)` and `public init(_ report: CachedReport)`.
  - `public struct HealthArchive: Sendable { public let directory: URL; public init(directory: URL); func fileURL(day: String) -> URL?; public func write(_ entry: ArchivedDay) throws; public func read(day: String) -> ArchivedDay?; public func clear() throws }`.
  - `ReportCache.archive: HealthArchive` (public), = `directory/archive`. `ReportCache.save` also writes the archive; `ReportCache.clear()` deletes `report.json` only.

- [ ] **Step 1: Write the failing tests**

Create `Tests/HealthFeatureTests/HealthArchiveTests.swift`:

```swift
import Foundation
import Models
import Testing

@testable import HealthFeature

struct HealthArchiveTests {
    let root = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString, directoryHint: .isDirectory)
    var archive: HealthArchive { HealthArchive(directory: root.appending(path: "archive", directoryHint: .isDirectory)) }

    static func entry(_ day: String = "2026-10-01", headline: String = "h") -> ArchivedDay {
        ArchivedDay(
            snapshot: HealthSnapshot(
                date: day, localTime: "09:00", locale: "en", sleep: nil, activity: nil, recovery: nil, body: nil,
                odyState: .tired),
            summary: HealthSummary(
                headline: headline, summary: "s", categories: .init(sleep: nil, activity: nil, recovery: nil, body: nil),
                memorySuggestion: nil),
            generatedAt: Date(timeIntervalSince1970: 1_790_000_000))
    }

    @Test func aNoteIsFiledByItsDay() throws {
        try archive.write(Self.entry())
        #expect(archive.read(day: "2026-10-01") == Self.entry())
        let path = archive.directory.appending(path: "2026/10/01.json").path(percentEncoded: false)
        #expect(FileManager.default.fileExists(atPath: path))
        #expect(archive.read(day: "2026-10-02") == nil)
    }

    @Test func writingTheSameDayAgainReplacesIt() throws {
        try archive.write(Self.entry(headline: "morning"))
        try archive.write(Self.entry("2026-09-30", headline: "yesterday"))
        try archive.write(Self.entry(headline: "evening"))
        #expect(archive.read(day: "2026-10-01")?.summary.headline == "evening")
        #expect(archive.read(day: "2026-09-30")?.summary.headline == "yesterday")
    }

    @Test func aCorruptFileIsNoNote() throws {
        try archive.write(Self.entry())
        try Data("{ not json".utf8).write(to: try #require(archive.fileURL(day: "2026-10-01")))
        #expect(archive.read(day: "2026-10-01") == nil)
    }

    /// A file that holds another day's note (copied by hand, or a clock gone wrong) is not that day's note.
    @Test func aFileHoldingAnotherDayIsNoNote() throws {
        try archive.write(Self.entry("2026-09-30"))
        let url = try #require(archive.fileURL(day: "2026-10-01"))
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try FileManager.default.copyItem(at: try #require(archive.fileURL(day: "2026-09-30")), to: url)
        #expect(archive.read(day: "2026-10-01") == nil)
    }

    @Test func onlyWireDaysHaveFiles() {
        #expect(archive.fileURL(day: "2026-10-01") != nil)
        for bad in ["", "2026-10", "2026-1-01", "../../x", "2026-10-01/../..", "2026-1O-01", "abcd-ef-gh"] {
            #expect(archive.fileURL(day: bad) == nil)
        }
        #expect(throws: (any Error).self) { try archive.write(Self.entry("../../etc")) }
    }

    @Test func clearingDeletesEveryNoteAndReport() throws {
        try archive.write(Self.entry())
        let reports = archive.directory.appending(path: "reports", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: reports, withIntermediateDirectories: true)
        try Data("{}".utf8).write(to: reports.appending(path: "2026-W40.json"))
        try archive.clear()
        #expect(archive.read(day: "2026-10-01") == nil)
        #expect(!FileManager.default.fileExists(atPath: archive.directory.path(percentEncoded: false)))
        try archive.clear()
    }

    @Test func theArchiveIsExcludedFromBackup() throws {
        try archive.write(Self.entry())
        let file = try #require(archive.fileURL(day: "2026-10-01"))
        #expect(try file.resourceValues(forKeys: [.isExcludedFromBackupKey]).isExcludedFromBackup == true)
        #expect(try archive.directory.resourceValues(forKeys: [.isExcludedFromBackupKey]).isExcludedFromBackup == true)
    }

    // MARK: The report-save path

    /// Under a folder with a space in its name, as on a phone ("Application Support").
    var cache: ReportCache {
        ReportCache(directory: root.appending(path: "Application Support/Health", directoryHint: .isDirectory))
    }

    @Test func savingTodaysReportArchivesIt() throws {
        let report = ReportStoreTests.report()
        try cache.save(report)
        #expect(cache.archive.read(day: "2026-10-01") == ArchivedDay(report))
        #expect(cache.archive.directory == cache.directory.appending(path: "archive", directoryHint: .isDirectory))
    }

    /// Withdrawing consent forgets today's report from the disk — under "Application Support" too — and keeps the
    /// archive.
    @Test func clearingTheReportKeepsTheArchive() throws {
        try cache.save(ReportStoreTests.report())
        try cache.clear()
        #expect(cache.load(date: "2026-10-01") == nil)
        #expect(!FileManager.default.fileExists(atPath: cache.fileURL.path(percentEncoded: false)))
        #expect(cache.archive.read(day: "2026-10-01") != nil)
    }
}
```

- [ ] **Step 2: Run them to verify they fail**

Run: `xcodebuild test -workspace ExodusIos.xcworkspace -scheme HealthFeature -destination "id=D8A2BE45-88F3-46AE-8693-B147F2815724" -derivedDataPath /tmp/trends-dd -only-testing:HealthFeatureTests/HealthArchiveTests 2>&1 | grep -E "error:|Test run with|TEST (SUCCEEDED|FAILED)"`
Expected: build errors `cannot find 'HealthArchive' in scope`, `cannot find 'ArchivedDay' in scope`.

- [ ] **Step 3: Write `HealthArchive.swift`**

```swift
// Sources/HealthFeature/Report/HealthArchive.swift
import Foundation
import Models

/// A day's note as it was written: the note, the numbers it was written from, and when.
public struct ArchivedDay: Codable, Equatable, Sendable {
    public var snapshot: HealthSnapshot
    public var summary: HealthSummary
    public var generatedAt: Date

    public init(snapshot: HealthSnapshot, summary: HealthSummary, generatedAt: Date) {
        self.snapshot = snapshot
        self.summary = summary
        self.generatedAt = generatedAt
    }

    public init(_ report: CachedReport) {
        self.init(snapshot: report.snapshot, summary: report.summary, generatedAt: report.generatedAt)
    }
}

/// Every daily note, one file per day (`archive/2026/10/01.json`), so a past day can be read again as it was. On
/// this phone only: complete file protection, and the folder and each file excluded from backups (App Review allows
/// no health data in iCloud). A note written again the same day replaces that day's file. A later phase files its
/// period reports under `archive/reports/`, so clearing the archive clears them too.
public struct HealthArchive: Sendable {
    public let directory: URL

    public init(directory: URL) { self.directory = directory }

    /// "2026-10-01" → `2026/10/01.json`; anything that is not a wire day has no file.
    func fileURL(day: String) -> URL? {
        let parts = day.split(separator: "-", omittingEmptySubsequences: false)
        guard parts.count == 3, parts.map(\.count) == [4, 2, 2],
            parts.allSatisfy({ $0.allSatisfy { $0.isASCII && $0.isNumber } })
        else { return nil }
        return directory.appending(path: "\(parts[0])/\(parts[1])/\(parts[2]).json")
    }

    public func write(_ entry: ArchivedDay) throws {
        guard let url = fileURL(day: entry.snapshot.date) else { throw CocoaError(.fileWriteInvalidFileName) }
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Self.excludeFromBackup(directory)
        try HealthWire.encoder().encode(entry).write(to: url, options: [.atomic, .completeFileProtection])
        try Self.excludeFromBackup(url)
    }

    /// The note kept for a day; nil when there is none, or its file can't be read — a corrupt file is no note.
    public func read(day: String) -> ArchivedDay? {
        guard let url = fileURL(day: day), let data = try? Data(contentsOf: url),
            let entry = try? JSONDecoder().decode(ArchivedDay.self, from: data), entry.snapshot.date == day
        else { return nil }
        return entry
    }

    /// Deletes every kept note (and every report). Nothing kept is fine.
    public func clear() throws {
        guard FileManager.default.fileExists(atPath: directory.path(percentEncoded: false)) else { return }
        try FileManager.default.removeItem(at: directory)
    }

    private static func excludeFromBackup(_ url: URL) throws {
        var url = url
        var values = URLResourceValues()
        values.isExcludedFromBackup = true
        try url.setResourceValues(values)
    }
}
```

- [ ] **Step 4: Hook the archive into `ReportCache` (targeted edits in `ReportStore.swift`)**

Check first: `git diff --stat -- Sources/HealthFeature/Report/ReportStore.swift` is empty.

Edit 1 — after `public var fileURL: URL { directory.appending(path: "report.json") }` add:

```swift

    /// Every stored note is also kept by day, for the calendar.
    public var archive: HealthArchive {
        HealthArchive(directory: directory.appending(path: "archive", directoryHint: .isDirectory))
    }
```

Edit 2 — in `clear()`, replace

```swift
        guard FileManager.default.fileExists(atPath: fileURL.path()) else { return }
```

with

```swift
        // Not `path()`: it percent-encodes "Application Support", and the file would never be found.
        guard FileManager.default.fileExists(atPath: fileURL.path(percentEncoded: false)) else { return }
```

and replace its doc comment `/// Forgets the stored report (consent withdrawn). Nothing stored is fine.` with `/// Forgets today's stored report (consent withdrawn); the archive stays. Nothing stored is fine.`

Edit 3 — at the end of `save(_:)`, after `try url.setResourceValues(values)`, add:

```swift
        try archive.write(ArchivedDay(report))
```

- [ ] **Step 5: Run the archive tests and the existing report tests**

Run: the Step 2 command, then the same with `-only-testing:HealthFeatureTests/ReportStoreTests`.
Expected: `Test run with 9 tests … passed` and `Test run with 6 tests … passed`.

- [ ] **Step 6: Audit and commit**

```bash
python3 scripts/l10n.py audit 2>&1 | tail -1
git diff --stat
.superpowers/sdd/commit-mine.sh "feat(health): keep every daily note on the phone, by day — and withdrawing consent really deletes today's report" \
  Sources/HealthFeature/Report/HealthArchive.swift Sources/HealthFeature/Report/ReportStore.swift \
  Tests/HealthFeatureTests/HealthArchiveTests.swift
git show --stat HEAD
```

---

### Task 3: Any day from Apple Health — `SnapshotBuilder` for past days, batch records, `DayRecordStore`

**Files:**
- Modify (replace whole; check `git diff --stat -- Sources/HealthFeature/Data/SnapshotBuilder.swift` is empty first): `Sources/HealthFeature/Data/SnapshotBuilder.swift`
- Modify (append): `Sources/HealthFeature/Data/SleepAnalyzer.swift`
- Create: `Sources/HealthFeature/Trends/DayRecordStore.swift`
- Modify: `Tests/HealthFeatureTests/FakeHealthSource.swift` (a sleep-read counter)
- Test: `Tests/HealthFeatureTests/DayRecordTests.swift`

**Interfaces:**
- Consumes: `DayRecord.init(day:snapshot:stepGoal:)` (Task 1); `HealthDataSource`, `SleepAnalyzer`, `HealthRules`, `WireDate` (existing).
- Produces:
  - `SnapshotBuilder.build(now:locale:) -> HealthDay` (unchanged signature and results), `public func snapshot(for date: Date, now: Date, locale: String) async throws -> HealthDay`, `public func records(from first: Date, through last: Date, now: Date) async throws -> [DayRecord]`, `func days(from: Date, through: Date) -> [Date]`.
  - `static func SleepAnalyzer.nights(from samples: [SleepSample], days: [Date], calendar: Calendar) -> [Date: SleepNight]`.
  - `@MainActor final class DayRecordStore { init(builder: SnapshotBuilder, calendar: Calendar, now: @escaping @Sendable () -> Date); func records(from first: Date, through last: Date) async throws -> [Date: DayRecord]; func snapshot(for day: Date, locale: String) async throws -> HealthDay }`.
  - `FakeHealthSource.sleepReads: Int` (tests).

- [ ] **Step 1: Add the read counter to the fake**

In `Tests/HealthFeatureTests/FakeHealthSource.swift`, after `var slowMs = 0` add:

```swift
    /// How many times sleep was read: one per load, however many days it covers.
    var sleepReads = 0
```

and make `sleepSamples` count:

```swift
    func sleepSamples(from start: Date, to end: Date) async throws -> [SleepSample] {
        sleepReads += 1
        if let failure { throw failure }
        return sleep.filter { $0.end > start && $0.start < end }
    }
```

- [ ] **Step 2: Write the failing tests**

Create `Tests/HealthFeatureTests/DayRecordTests.swift`:

```swift
import Foundation
import Models
import Testing

@testable import HealthFeature

struct DayRecordTests: Sendable {
    let cal = TestClock.calendar
    func day(_ offset: Int) -> Date { cal.date(byAdding: .day, value: offset, to: TestClock.today)! }

    /// A night of `minutes` core sleep that ends at 07:00 on the day `offset` from today.
    func night(_ offset: Int, minutes: Int, source: String = "watch") -> SleepSample {
        let wake = cal.date(byAdding: .hour, value: 7, to: day(offset))!
        return SleepSample(start: wake.addingTimeInterval(Double(-minutes * 60)), end: wake, stage: .core, source: source)
    }

    func builder(_ fake: FakeHealthSource) -> SnapshotBuilder { SnapshotBuilder(source: fake, calendar: cal) }

    /// Forty-one days of everything, a little different each day.
    func filled() async -> FakeHealthSource {
        let fake = FakeHealthSource()
        let nights = (0...40).map { night(-$0, minutes: 360 + $0 % 5 * 30) }
        let steps = (0...40).map { DayValue(day: day(-$0), value: Double(5000 + $0 * 400)) }
        let exercise = (0...40).map { DayValue(day: day(-$0), value: Double($0 % 4 * 10)) }
        let water = (0...40).map { DayValue(day: day(-$0), value: Double($0 % 3 * 500)) }
        let hrv = (0...40).reversed().map { DayValue(day: day(-$0), value: Double(44 - $0 % 6 * 2)) }
        let rhr = (0...40).reversed().map { DayValue(day: day(-$0), value: Double(58 + $0 % 3)) }
        let mood = [MoodSample(date: day(-2).addingTimeInterval(9 * 3600), label: .pleasant)]
        let workout = [WorkoutSample(start: day(-3).addingTimeInterval(7 * 3600), minutes: 30, kcal: 200, type: "running")]
        await fake.set {
            $0.sleep = nights
            $0.sums[.steps] = steps
            $0.sums[.exerciseMin] = exercise
            $0.sums[.waterMl] = water
            $0.averages[.hrv] = hrv
            $0.averages[.restingHr] = rhr
            $0.moodList = mood
            $0.workoutList = workout
        }
        return fake
    }

    @Test func aPastDayIsReadWhole() async throws {
        let d = try await builder(await filled()).snapshot(for: day(-1).addingTimeInterval(3600), now: TestClock.now, locale: "en")
        #expect(d.snapshot.date == "2026-09-30")
        #expect(d.snapshot.localTime == "23:59")
        #expect(d.snapshot.activity?.steps == 5400)
        #expect(d.snapshot.sleep?.asleepMin == 390)
    }

    @Test func aPastDaysBaselineIsTheThirtyNightsBeforeIt() async throws {
        let fake = FakeHealthSource()
        let nights = (2...10).map { night(-$0, minutes: 450) } + [night(-1, minutes: 400), night(0, minutes: 300)]
        await fake.set { $0.sleep = nights }
        let d = try await builder(fake).snapshot(for: day(-1), now: TestClock.now, locale: "en")
        #expect(d.snapshot.sleep?.asleepMin == 400)
        #expect(d.snapshot.sleep?.baselineMin == 450)
    }

    @Test func todayIsStillReadToNow() async throws {
        let built = try await builder(await filled()).build(now: TestClock.now, locale: "en")
        #expect(built.snapshot.date == "2026-10-01")
        #expect(built.snapshot.localTime == "15:00")
        #expect(built.snapshot.activity?.steps == 5000)
    }

    /// A run of days read at once and each day read alone agree, day by day — Ody's state included.
    @Test func recordsMatchEachDayBuiltAlone() async throws {
        let b = builder(await filled())
        let records = try await b.records(from: day(-9), through: day(0), now: TestClock.now)
        #expect(records.map(\.day) == (-9...0).map { day($0) })
        for record in records {
            let alone = try await b.snapshot(for: record.day, now: TestClock.now, locale: "en")
            #expect(record == DayRecord(day: record.day, snapshot: alone.snapshot, stepGoal: 8000))
        }
        #expect(records.contains { $0.mood != .noData })
    }

    @Test func recordsStopAtToday() async throws {
        let b = builder(await filled())
        let records = try await b.records(from: day(-2), through: day(5), now: TestClock.now)
        #expect(records.map(\.day) == [day(-2), day(-1), day(0)])
        #expect(try await b.records(from: day(1), through: day(5), now: TestClock.now).isEmpty)
    }

    /// The calendar's year view reads the store once per series, not once per day.
    @Test func aYearIsReadWithOneQueryPerSeries() async throws {
        let fake = await filled()
        let records = try await builder(fake).records(from: day(-364), through: day(0), now: TestClock.now)
        #expect(records.count == 365)
        #expect(await fake.sleepReads == 1)
    }

    @Test func nightsForManyDaysMatchOneAtATime() {
        var samples = (0...6).map { night(-$0, minutes: 400) } + (0...6).map { night(-$0, minutes: 380, source: "phone") }
        // One long sample that reaches into two nights' windows.
        samples.append(
            SleepSample(
                start: day(-3).addingTimeInterval(11 * 3600), end: day(-3).addingTimeInterval(20 * 3600), stage: .core,
                source: "watch"))
        let days = (-8...0).map { day($0) }
        let many = SleepAnalyzer.nights(from: samples, days: days, calendar: cal)
        for d in days {
            #expect(many[d] == SleepAnalyzer.night(from: samples, endingOn: d, calendar: cal))
        }
    }

    // MARK: DayRecordStore

    @MainActor @Test func pastDaysAreReadOnce() async throws {
        let fake = await filled()
        let store = DayRecordStore(builder: builder(fake), calendar: cal, now: { TestClock.now })
        let first = try await store.records(from: day(-20), through: day(-1))
        #expect(first.count == 20)
        #expect(await fake.sleepReads == 1)
        let again = try await store.records(from: day(-10), through: day(-5))
        #expect(again.count == 6)
        #expect(again[day(-7)] == first[day(-7)])
        #expect(await fake.sleepReads == 1)
    }

    /// Today changes as it goes on: it is read again every time, and only today is.
    @MainActor @Test func todayIsReadAgainEachTime() async throws {
        let fake = await filled()
        let store = DayRecordStore(builder: builder(fake), calendar: cal, now: { TestClock.now })
        _ = try await store.records(from: day(-6), through: day(0))
        let more = DayValue(day: day(0), value: 1000)
        await fake.set { $0.sums[.steps]?.append(more) }
        let again = try await store.records(from: day(-6), through: day(0))
        #expect(again.count == 7)
        #expect(again[day(0)]?.steps == 6000)
        #expect(await fake.sleepReads == 2)
    }

    @MainActor @Test func daysToComeHaveNoRecord() async throws {
        let store = DayRecordStore(builder: builder(await filled()), calendar: cal, now: { TestClock.now })
        let r = try await store.records(from: day(-1), through: day(3))
        #expect(Set(r.keys) == [day(-1), day(0)])
    }
}
```

- [ ] **Step 3: Run them to verify they fail**

Run: `xcodebuild test -workspace ExodusIos.xcworkspace -scheme HealthFeature -destination "id=D8A2BE45-88F3-46AE-8693-B147F2815724" -derivedDataPath /tmp/trends-dd -only-testing:HealthFeatureTests/DayRecordTests 2>&1 | grep -E "error:|Test run with|TEST (SUCCEEDED|FAILED)"`
Expected: build errors — `value of type 'SnapshotBuilder' has no member 'snapshot'`, `cannot find 'DayRecordStore' in scope`, `type 'SleepAnalyzer' has no member 'nights'`.

- [ ] **Step 4: Add `SleepAnalyzer.nights` (append to `SleepAnalyzer.swift`)**

```swift

extension SleepAnalyzer {
    /// The night that ended on each of `days`, for many days at once. Each sample is offered only to the windows it
    /// can reach (a window runs from 18:00 the day before to 12:00 on its day), so a year of samples is sorted into
    /// nights in one pass instead of being filtered once per day. Same nights as `night(from:endingOn:)` day by day.
    static func nights(from samples: [SleepSample], days: [Date], calendar: Calendar) -> [Date: SleepNight] {
        let wanted = Set(days)
        var buckets: [Date: [SleepSample]] = [:]
        for sample in samples {
            var day = calendar.startOfDay(for: sample.start)
            let last = calendar.startOfDay(for: calendar.date(byAdding: .day, value: 1, to: sample.end)!)
            while day <= last {
                if wanted.contains(day) {
                    let w = window(endingOn: day, calendar: calendar)
                    if sample.end > w.start && sample.start < w.end { buckets[day, default: []].append(sample) }
                }
                day = calendar.startOfDay(for: calendar.date(byAdding: .day, value: 1, to: day)!)
            }
        }
        var out: [Date: SleepNight] = [:]
        for day in days {
            if let samples = buckets[day], let n = night(from: samples, endingOn: day, calendar: calendar) {
                out[day] = n
            }
        }
        return out
    }
}
```

- [ ] **Step 5: Replace `SnapshotBuilder.swift`**

```swift
// Sources/HealthFeature/Data/SnapshotBuilder.swift
import Foundation
import Models

/// The day as the home screen and the report see it: the wire snapshot, plus last night's stages for the hero.
public struct HealthDay: Sendable, Equatable {
    public var snapshot: HealthSnapshot
    public var night: SleepNight?
}

/// Everything the store holds for a run of days, read with one query per series: sleep from the evening before the
/// first baseline night, averages from 30 days before the first day (their baselines), sums, workouts and moods over
/// the days themselves. Hours stood and the rings' goals are one query per day, so only a single day reads them.
struct StoreSpan: Sendable {
    var sleep: [SleepSample] = []
    var sums: [SumMetric: [DayValue]] = [:]
    var averages: [AverageMetric: [DayValue]] = [:]
    var workouts: [WorkoutSample] = []
    var moods: [MoodSample] = []
    var stand = 0
    var goals: ActivityGoals?
}

/// Reads days from a `HealthDataSource` and turns them into `HealthDay`s and `DayRecord`s. A day runs from local
/// midnight to midnight (today: to `now`); each baseline is the median of the 30 days before that day, once there are
/// seven of them. A category with nothing in it is `nil`, so the report says nothing about it rather than "0". One
/// day or a year, the store is read once per series and every day is put together by the same rules, so a past day's
/// Ody is the one the home would have shown.
public struct SnapshotBuilder: Sendable {
    let source: any HealthDataSource
    let calendar: Calendar
    let stepGoal: Int
    private let format: WireDate

    public init(source: any HealthDataSource, calendar: Calendar = .current, stepGoal: Int = 8000) {
        self.source = source
        self.calendar = calendar
        self.stepGoal = stepGoal
        self.format = WireDate(timeZone: calendar.timeZone)
    }

    public func build(now: Date, locale: String) async throws -> HealthDay {
        try await snapshot(for: now, now: now, locale: locale)
    }

    /// The day holding `date`: today up to `now`, as the home shows it, or a past day whole ("23:59").
    public func snapshot(for date: Date, now: Date, locale: String) async throws -> HealthDay {
        let day = calendar.startOfDay(for: date)
        let authorized = await source.hasRequestedAuthorization()
        var span = try await read(from: day, through: day, now: now)
        span.stand = try await source.standHours(on: day)
        span.goals = try await source.activityGoals(on: day)
        let nights = SleepAnalyzer.nights(
            from: span.sleep, days: days(from: baselineStart(day), through: day), calendar: calendar)
        let next = calendar.date(byAdding: .day, value: 1, to: day)!
        return assemble(
            day: day, span: span, nights: nights, authorized: authorized,
            localTime: clock(min(now, next.addingTimeInterval(-60))), locale: locale)
    }

    /// Each day from `first` through `last` that has begun, as the calendar reads it. Hours stood are not read per
    /// day here, so a day with nothing but stand hours reads as no activity.
    public func records(from first: Date, through last: Date, now: Date) async throws -> [DayRecord] {
        let first = calendar.startOfDay(for: first)
        let last = min(calendar.startOfDay(for: last), calendar.startOfDay(for: now))
        guard first <= last else { return [] }
        let authorized = await source.hasRequestedAuthorization()
        let span = try await read(from: first, through: last, now: now)
        let nights = SleepAnalyzer.nights(
            from: span.sleep, days: days(from: baselineStart(first), through: last), calendar: calendar)
        return days(from: first, through: last).map { day in
            let built = assemble(day: day, span: span, nights: nights, authorized: authorized, localTime: "", locale: "")
            return DayRecord(day: day, snapshot: built.snapshot, stepGoal: stepGoal)
        }
    }

    /// One query per series for the days `first` through `last`.
    func read(from first: Date, through last: Date, now: Date) async throws -> StoreSpan {
        let monthAgo = baselineStart(first)
        let end = calendar.date(byAdding: .day, value: 1, to: last)!
        var span = StoreSpan()
        let sleepFrom = SleepAnalyzer.window(endingOn: monthAgo, calendar: calendar).start
        let sleepTo = min(now, SleepAnalyzer.window(endingOn: last, calendar: calendar).end)
        span.sleep = try await source.sleepSamples(from: sleepFrom, to: sleepTo)
        for metric in [SumMetric.steps, .activeKcal, .exerciseMin] {
            span.sums[metric] = try await source.dailySums(metric, from: first, to: end)
        }
        for metric in [AverageMetric.hrv, .restingHr, .respRate, .weightKg] {
            span.averages[metric] = try await source.dailyAverages(metric, from: monthAgo, to: end)
        }
        span.sums[.waterMl] = try await source.dailySums(.waterMl, from: first, to: end)
        span.workouts = try await source.workouts(from: first, to: end)
        span.moods = try await source.moods(from: first, to: end)
        return span
    }

    /// One day from what was read: the same rules whether the span held one day or a year.
    func assemble(
        day: Date, span: StoreSpan, nights: [Date: SleepNight], authorized: Bool, localTime: String, locale: String
    ) -> HealthDay {
        let next = calendar.date(byAdding: .day, value: 1, to: day)!
        let monthAgo = baselineStart(day)
        func on(_ values: [DayValue]?) -> [DayValue] { (values ?? []).filter { $0.day >= day && $0.day < next } }

        // Sleep: the night that ended this morning, against the 30 before it.
        let night = nights[day]
        let pastNights = (1...30).compactMap { offset -> Double? in
            let earlier = calendar.startOfDay(for: calendar.date(byAdding: .day, value: -offset, to: day)!)
            return nights[earlier].map { Double($0.asleepMin) }
        }
        let sleep = night.map { n in
            HealthSnapshot.Sleep(
                asleepMin: n.asleepMin, baselineMin: HealthRules.baseline(pastNights).map { Int($0.rounded()) },
                deepMin: n.deepMin, coreMin: n.coreMin, remMin: n.remMin, awakeMin: n.awakeMin,
                bedtime: clock(n.bedtime), wake: clock(n.wake))
        }

        // Activity: the day only.
        func sum(_ metric: SumMetric) -> Double { on(span.sums[metric]).reduce(0) { $0 + $1.value } }
        let steps = sum(.steps)
        let kcal = sum(.activeKcal)
        let exercise = sum(.exerciseMin)
        let workouts = span.workouts.filter { $0.start >= day && $0.start < next }
        let hasActivity = steps > 0 || kcal > 0 || exercise > 0 || span.stand > 0 || !workouts.isEmpty
        let activity =
            hasActivity
            ? HealthSnapshot.Activity(
                steps: Int(steps), stepGoal: stepGoal, activeKcal: Int(kcal), kcalGoal: span.goals?.moveKcal,
                exerciseMin: Int(exercise), standHours: span.stand,
                workouts: workouts.prefix(20).map { .init(type: $0.type, minutes: $0.minutes, kcal: $0.kcal) })
            : nil

        // Recovery: the day against the 30 before it.
        func dayAndBaseline(_ metric: AverageMetric) -> (Double?, Double?) {
            let values = span.averages[metric] ?? []
            let before = values.filter { $0.day >= monthAgo && $0.day < day }.map(\.value)
            return (on(values).last?.value, HealthRules.baseline(before))
        }
        let (hrv, hrvBase) = dayAndBaseline(.hrv)
        let (rhr, rhrBase) = dayAndBaseline(.restingHr)
        let (resp, _) = dayAndBaseline(.respRate)
        let recovery =
            (hrv ?? rhr ?? resp) == nil
            ? nil
            : HealthSnapshot.Recovery(
                level: HealthRules.recovery(hrv: hrv, hrvBaseline: hrvBase, restingHr: rhr, restingHrBaseline: rhrBase),
                hrvMs: hrv, hrvBaselineMs: hrvBase, restingHr: rhr, restingHrBaseline: rhrBase, respRate: resp)

        // Body & mood.
        let cups = Int(sum(.waterMl) / 250)
        let weights = (span.averages[.weightKg] ?? []).filter { $0.day >= monthAgo && $0.day < next }
        let trend = weights.count >= 2 ? weights.last!.value - weights.first!.value : nil
        let mood = span.moods.filter { $0.date >= day && $0.date < next }.max { $0.date < $1.date }?.label
        let body =
            cups == 0 && weights.isEmpty && mood == nil
            ? nil
            : HealthSnapshot.Body(waterCups: cups, weightKg: weights.last?.value, weightTrend30d: trend, mood: mood)

        var snapshot = HealthSnapshot(
            date: format.day(day), localTime: localTime, locale: locale,
            sleep: sleep, activity: activity, recovery: recovery, body: body, odyState: .happy)
        snapshot.odyState = HealthRules.hero(snapshot, authorized: authorized)
        return HealthDay(snapshot: snapshot, night: night)
    }

    /// Each day's start from `first` through `last`; a day whose midnight a clock change skipped starts at 01:00.
    func days(from first: Date, through last: Date) -> [Date] {
        var out: [Date] = []
        var d = calendar.startOfDay(for: first)
        while d <= last {
            out.append(d)
            d = calendar.startOfDay(for: calendar.date(byAdding: .day, value: 1, to: d)!)
        }
        return out
    }

    private func baselineStart(_ day: Date) -> Date { calendar.date(byAdding: .day, value: -30, to: day)! }

    func clock(_ date: Date) -> String { format.clock(date) }
}
```

- [ ] **Step 6: Write `DayRecordStore.swift`**

```swift
// Sources/HealthFeature/Trends/DayRecordStore.swift
import Foundation

/// Day records by day, so paging the calendar back and forth reads Apple Health once per day it shows. Today is never
/// kept: it is still going on.
@MainActor
final class DayRecordStore {
    private let builder: SnapshotBuilder
    private let calendar: Calendar
    private let now: @Sendable () -> Date
    private var kept: [Date: DayRecord] = [:]

    init(builder: SnapshotBuilder, calendar: Calendar, now: @escaping @Sendable () -> Date) {
        self.builder = builder
        self.calendar = calendar
        self.now = now
    }

    /// The records of the days `first` through `last` that have begun, by day; days to come have none. What is not
    /// kept yet (and today) is read in one go.
    func records(from first: Date, through last: Date) async throws -> [Date: DayRecord] {
        let today = calendar.startOfDay(for: now())
        let days = builder.days(from: first, through: min(calendar.startOfDay(for: last), today))
        let missing = days.filter { $0 == today || kept[$0] == nil }
        var out: [Date: DayRecord] = [:]
        if let from = missing.first, let to = missing.last {
            for record in try await builder.records(from: from, through: to, now: now()) {
                out[record.day] = record
                if record.day < today { kept[record.day] = record }
            }
        }
        for day in days where out[day] == nil { out[day] = kept[day] }
        return out
    }

    /// A whole day, built as the home builds today: what the day sheet sends with a question.
    func snapshot(for day: Date, locale: String) async throws -> HealthDay {
        try await builder.snapshot(for: day, now: now(), locale: locale)
    }
}
```

- [ ] **Step 7: Run the new tests and every existing Health test**

Run: the Step 3 command; then the whole scheme without `-only-testing`.
Expected: `DayRecordTests` — `Test run with 10 tests … passed`; the whole scheme passes (the existing `SnapshotBuilderTests` and `HealthHomeModelTests` unchanged).

- [ ] **Step 8: Audit and commit**

```bash
python3 scripts/l10n.py audit 2>&1 | tail -1
git diff --stat
.superpowers/sdd/commit-mine.sh "feat(health): read any past day from Apple Health — one query per series for a run of days, same rules as today; day records cached, today never" \
  Sources/HealthFeature/Data/SnapshotBuilder.swift Sources/HealthFeature/Data/SleepAnalyzer.swift \
  Sources/HealthFeature/Trends/DayRecordStore.swift Tests/HealthFeatureTests/FakeHealthSource.swift \
  Tests/HealthFeatureTests/DayRecordTests.swift
git show --stat HEAD
```

---

### Task 4: The strings, in ten languages

`Resources/App/Localizable.xcstrings` carries the user's uncommitted edits. Add the keys to the working file and, identically, to a copy of the committed catalog; commit the difference between the committed catalog and that copy as a patch, so only these keys enter the commit.

**Files:**
- Modify: `Resources/App/Localizable.xcstrings` (38 new `ios:health.*` keys)

**Interfaces:**
- Consumes: nothing.
- Produces (exact English, used by Tasks 5–8; every Swift `defaultValue:` must match):

| Key | English |
|---|---|
| `ios:health.week.title` | This week |
| `ios:health.calendar.title` | Calendar |
| `ios:health.calendar.scope` | Period |
| `ios:health.calendar.scope.week` | Week |
| `ios:health.calendar.scope.month` | Month |
| `ios:health.calendar.scope.quarter` | Quarter |
| `ios:health.calendar.scope.year` | Year |
| `ios:health.calendar.previous` | Previous |
| `ios:health.calendar.next` | Next |
| `ios:health.calendar.weekTitle` | Week %lld |
| `ios:health.calendar.stat.sleep` | Avg. sleep |
| `ios:health.calendar.stat.steps` | Daily steps |
| `ios:health.calendar.stat.hrv` | HRV |
| `ios:health.calendar.vs.week` | vs last week |
| `ios:health.calendar.vs.month` | vs last month |
| `ios:health.calendar.vs.quarter` | vs last quarter |
| `ios:health.calendar.vs.year` | vs last year |
| `ios:health.calendar.change.up` | Up %@ |
| `ios:health.calendar.change.down` | Down %@ |
| `ios:health.calendar.change.flat` | About the same |
| `ios:health.calendar.change.none` | Nothing earlier to compare |
| `ios:health.calendar.empty` | Nothing recorded in this period. |
| `ios:health.calendar.tone.good` | Rested or active |
| `ios:health.calendar.tone.tired` | Short on sleep |
| `ios:health.calendar.tone.recovering` | Recovering |
| `ios:health.calendar.tone.empty` | No data |
| `ios:health.calendar.legend.ring` | Corner ring: sleep and steps against their targets |
| `ios:health.calendar.a11y.sleep` | Sleep %@ |
| `ios:health.calendar.today` | Today |
| `ios:health.day.noNote` | No note for this day |
| `ios:health.day.ask.compare` | How did this day compare to my usual? |
| `ios:health.day.ask.standout` | What stood out on this day? |
| `ios:health.day.steps` | Steps |
| `ios:health.day.exercise` | Exercise |
| `ios:health.day.bedtime` | Bedtime |
| `ios:health.archive.clear` | Clear archive |
| `ios:health.archive.confirmTitle` | Clear the archive? |
| `ios:health.archive.confirmMessage` | This deletes every daily note kept on this iPhone. Today's note and your health data stay. |

- [ ] **Step 1: Write the key script**

Create `/tmp/trends-l10n/add_keys.py`:

```python
# Adds the trends phase-1 keys to the catalog named on the command line. Run from the repo root.
import subprocess
import sys

KEYS = [
    ("ios:health.week.title", "This week", "Health home: title of the card with this week's days and averages."),
    ("ios:health.calendar.title", "Calendar", "Health: the calendar page's title, and the home card's link to it."),
    ("ios:health.calendar.scope", "Period", "Calendar page: VoiceOver label of the Week/Month/Quarter/Year picker."),
    ("ios:health.calendar.scope.week", "Week", "Calendar page picker: show one week."),
    ("ios:health.calendar.scope.month", "Month", "Calendar page picker: show one month."),
    ("ios:health.calendar.scope.quarter", "Quarter", "Calendar page picker: show one quarter (three months)."),
    ("ios:health.calendar.scope.year", "Year", "Calendar page picker: show one year."),
    ("ios:health.calendar.previous", "Previous", "Calendar page: VoiceOver label of the button that shows the previous week, month, quarter or year."),
    ("ios:health.calendar.next", "Next", "Calendar page: VoiceOver label of the button that shows the next week, month, quarter or year."),
    ("ios:health.calendar.weekTitle", "Week %lld", "Calendar page: a week's title. %lld is the ISO week number (1-53)."),
    ("ios:health.calendar.stat.sleep", "Avg. sleep", "Calendar header and home card: average sleep per night over the period."),
    ("ios:health.calendar.stat.steps", "Daily steps", "Calendar header and home card: average steps per day over the period."),
    ("ios:health.calendar.stat.hrv", "HRV", "Calendar header: average heart rate variability (abbreviation) over the period."),
    ("ios:health.calendar.vs.week", "vs last week", "Calendar header: the change shown is against last week."),
    ("ios:health.calendar.vs.month", "vs last month", "Calendar header: the change shown is against last month."),
    ("ios:health.calendar.vs.quarter", "vs last quarter", "Calendar header: the change shown is against the previous quarter."),
    ("ios:health.calendar.vs.year", "vs last year", "Calendar header: the change shown is against last year."),
    ("ios:health.calendar.change.up", "Up %@", "VoiceOver: a number went up against the previous period. %@ is the amount, e.g. 52m or 12%."),
    ("ios:health.calendar.change.down", "Down %@", "VoiceOver: a number went down against the previous period. %@ is the amount, e.g. 52m or 12%."),
    ("ios:health.calendar.change.flat", "About the same", "VoiceOver: a number changed less than 3% against the previous period."),
    ("ios:health.calendar.change.none", "Nothing earlier to compare", "VoiceOver: the previous period has no data for this number."),
    ("ios:health.calendar.empty", "Nothing recorded in this period.", "Calendar page: Apple Health has no data for the shown week, month, quarter or year."),
    ("ios:health.calendar.tone.good", "Rested or active", "Calendar day colour and legend: a good day (rested, active or calm)."),
    ("ios:health.calendar.tone.tired", "Short on sleep", "Calendar day colour and legend: a day after too little sleep."),
    ("ios:health.calendar.tone.recovering", "Recovering", "Calendar day colour and legend: a day with low recovery (HRV under the usual)."),
    ("ios:health.calendar.tone.empty", "No data", "Calendar day colour and legend: Apple Health has nothing for the day."),
    ("ios:health.calendar.legend.ring", "Corner ring: sleep and steps against their targets", "Calendar legend: the small ring in each day's corner. Outer arc sleep, inner arc steps."),
    ("ios:health.calendar.a11y.sleep", "Sleep %@", "VoiceOver for a calendar day: the night's sleep. %@ is a duration, e.g. 7h 40m."),
    ("ios:health.calendar.today", "Today", "VoiceOver for a calendar day: this day is today."),
    ("ios:health.day.noNote", "No note for this day", "Day sheet: no daily note was written or kept for this day."),
    ("ios:health.day.ask.compare", "How did this day compare to my usual?", "Day sheet: suggested question about a past day."),
    ("ios:health.day.ask.standout", "What stood out on this day?", "Day sheet: suggested question about a past day."),
    ("ios:health.day.steps", "Steps", "Day sheet: row label, the day's step count."),
    ("ios:health.day.exercise", "Exercise", "Day sheet: row label, the day's exercise minutes."),
    ("ios:health.day.bedtime", "Bedtime", "Day sheet: row label, when the night before began."),
    ("ios:health.archive.clear", "Clear archive", "Health menu, and its confirmation's button: delete every daily note kept on this iPhone."),
    ("ios:health.archive.confirmTitle", "Clear the archive?", "Confirmation title before deleting every kept daily note."),
    ("ios:health.archive.confirmMessage", "This deletes every daily note kept on this iPhone. Today's note and your health data stay.", "Confirmation message before deleting every kept daily note."),
]

for key, en, comment in KEYS:
    subprocess.run(
        ["python3", "scripts/l10n.py", "add", key, "--en-value", en, "--comment", comment, "--file", sys.argv[1]],
        check=True)
```

- [ ] **Step 2: Write the translations**

Create `/tmp/trends-l10n/translations.json`:

```json
{
  "ios:health.week.title": {"de": "Diese Woche", "es": "Esta semana", "fr": "Cette semaine", "it": "Questa settimana", "ja": "今週", "ko": "이번 주", "pt-BR": "Esta semana", "zh-Hant": "本週", "zh-HK": "今個禮拜"},
  "ios:health.calendar.title": {"de": "Kalender", "es": "Calendario", "fr": "Calendrier", "it": "Calendario", "ja": "カレンダー", "ko": "캘린더", "pt-BR": "Calendário", "zh-Hant": "日曆", "zh-HK": "日曆"},
  "ios:health.calendar.scope": {"de": "Zeitraum", "es": "Periodo", "fr": "Période", "it": "Periodo", "ja": "期間", "ko": "기간", "pt-BR": "Período", "zh-Hant": "期間", "zh-HK": "期間"},
  "ios:health.calendar.scope.week": {"de": "Woche", "es": "Semana", "fr": "Semaine", "it": "Settimana", "ja": "週", "ko": "주", "pt-BR": "Semana", "zh-Hant": "週", "zh-HK": "週"},
  "ios:health.calendar.scope.month": {"de": "Monat", "es": "Mes", "fr": "Mois", "it": "Mese", "ja": "月", "ko": "월", "pt-BR": "Mês", "zh-Hant": "月", "zh-HK": "月"},
  "ios:health.calendar.scope.quarter": {"de": "Quartal", "es": "Trimestre", "fr": "Trimestre", "it": "Trimestre", "ja": "四半期", "ko": "분기", "pt-BR": "Trimestre", "zh-Hant": "季", "zh-HK": "季"},
  "ios:health.calendar.scope.year": {"de": "Jahr", "es": "Año", "fr": "Année", "it": "Anno", "ja": "年", "ko": "연", "pt-BR": "Ano", "zh-Hant": "年", "zh-HK": "年"},
  "ios:health.calendar.previous": {"de": "Zurück", "es": "Anterior", "fr": "Précédent", "it": "Precedente", "ja": "前へ", "ko": "이전", "pt-BR": "Anterior", "zh-Hant": "上一個", "zh-HK": "上一個"},
  "ios:health.calendar.next": {"de": "Weiter", "es": "Siguiente", "fr": "Suivant", "it": "Successivo", "ja": "次へ", "ko": "다음", "pt-BR": "Próximo", "zh-Hant": "下一個", "zh-HK": "下一個"},
  "ios:health.calendar.weekTitle": {"de": "Woche %lld", "es": "Semana %lld", "fr": "Semaine %lld", "it": "Settimana %lld", "ja": "第%lld週", "ko": "%lld주차", "pt-BR": "Semana %lld", "zh-Hant": "第 %lld 週", "zh-HK": "第 %lld 週"},
  "ios:health.calendar.stat.sleep": {"de": "Ø Schlaf", "es": "Sueño medio", "fr": "Sommeil moyen", "it": "Sonno medio", "ja": "平均睡眠", "ko": "평균 수면", "pt-BR": "Sono médio", "zh-Hant": "平均睡眠", "zh-HK": "平均睡眠"},
  "ios:health.calendar.stat.steps": {"de": "Schritte pro Tag", "es": "Pasos diarios", "fr": "Pas par jour", "it": "Passi al giorno", "ja": "1日の歩数", "ko": "하루 걸음 수", "pt-BR": "Passos por dia", "zh-Hant": "每日步數", "zh-HK": "每日步數"},
  "ios:health.calendar.stat.hrv": {"de": "HRV", "es": "VFC", "fr": "VRC", "it": "HRV", "ja": "HRV", "ko": "HRV", "pt-BR": "VFC", "zh-Hant": "HRV", "zh-HK": "HRV"},
  "ios:health.calendar.vs.week": {"de": "ggü. letzter Woche", "es": "vs. la semana pasada", "fr": "vs semaine dernière", "it": "vs settimana scorsa", "ja": "先週比", "ko": "지난주 대비", "pt-BR": "vs. semana passada", "zh-Hant": "與上週相比", "zh-HK": "對比上個禮拜"},
  "ios:health.calendar.vs.month": {"de": "ggü. letztem Monat", "es": "vs. el mes pasado", "fr": "vs mois dernier", "it": "vs mese scorso", "ja": "先月比", "ko": "지난달 대비", "pt-BR": "vs. mês passado", "zh-Hant": "與上月相比", "zh-HK": "對比上個月"},
  "ios:health.calendar.vs.quarter": {"de": "ggü. letztem Quartal", "es": "vs. el trimestre pasado", "fr": "vs trimestre dernier", "it": "vs trimestre scorso", "ja": "前四半期比", "ko": "지난 분기 대비", "pt-BR": "vs. trimestre passado", "zh-Hant": "與上一季相比", "zh-HK": "對比上一季"},
  "ios:health.calendar.vs.year": {"de": "ggü. letztem Jahr", "es": "vs. el año pasado", "fr": "vs année dernière", "it": "vs anno scorso", "ja": "昨年比", "ko": "작년 대비", "pt-BR": "vs. ano passado", "zh-Hant": "與去年相比", "zh-HK": "對比舊年"},
  "ios:health.calendar.change.up": {"de": "%@ mehr", "es": "%@ más", "fr": "%@ de plus", "it": "%@ in più", "ja": "%@増", "ko": "%@ 증가", "pt-BR": "%@ a mais", "zh-Hant": "增加 %@", "zh-HK": "多咗 %@"},
  "ios:health.calendar.change.down": {"de": "%@ weniger", "es": "%@ menos", "fr": "%@ de moins", "it": "%@ in meno", "ja": "%@減", "ko": "%@ 감소", "pt-BR": "%@ a menos", "zh-Hant": "減少 %@", "zh-HK": "少咗 %@"},
  "ios:health.calendar.change.flat": {"de": "Etwa gleich", "es": "Más o menos igual", "fr": "À peu près pareil", "it": "Più o meno uguale", "ja": "ほぼ同じ", "ko": "거의 같음", "pt-BR": "Mais ou menos igual", "zh-Hant": "差不多", "zh-HK": "差唔多"},
  "ios:health.calendar.change.none": {"de": "Kein früherer Zeitraum zum Vergleich", "es": "Nada anterior con que comparar", "fr": "Rien d'antérieur à comparer", "it": "Niente di precedente da confrontare", "ja": "比較できる前の期間がありません", "ko": "비교할 이전 기간이 없음", "pt-BR": "Nada anterior para comparar", "zh-Hant": "沒有更早的資料可比較", "zh-HK": "冇更早嘅資料可以比較"},
  "ios:health.calendar.empty": {"de": "In diesem Zeitraum wurde nichts aufgezeichnet.", "es": "No hay nada registrado en este periodo.", "fr": "Rien d'enregistré sur cette période.", "it": "Niente registrato in questo periodo.", "ja": "この期間の記録はありません。", "ko": "이 기간에는 기록이 없어요.", "pt-BR": "Nada registrado neste período.", "zh-Hant": "這段期間沒有任何紀錄。", "zh-HK": "呢段期間冇任何紀錄。"},
  "ios:health.calendar.tone.good": {"de": "Ausgeruht oder aktiv", "es": "Descansado o activo", "fr": "Reposé ou actif", "it": "Riposato o attivo", "ja": "休養十分・活動的", "ko": "충분한 휴식 또는 활동", "pt-BR": "Descansado ou ativo", "zh-Hant": "休息充足或活躍", "zh-HK": "休息充足或者活躍"},
  "ios:health.calendar.tone.tired": {"de": "Zu wenig Schlaf", "es": "Falta de sueño", "fr": "Manque de sommeil", "it": "Poco sonno", "ja": "睡眠不足", "ko": "수면 부족", "pt-BR": "Pouco sono", "zh-Hant": "睡眠不足", "zh-HK": "瞓得唔夠"},
  "ios:health.calendar.tone.recovering": {"de": "In Erholung", "es": "Recuperándose", "fr": "En récupération", "it": "In recupero", "ja": "回復中", "ko": "회복 중", "pt-BR": "Em recuperação", "zh-Hant": "恢復中", "zh-HK": "恢復緊"},
  "ios:health.calendar.tone.empty": {"de": "Keine Daten", "es": "Sin datos", "fr": "Aucune donnée", "it": "Nessun dato", "ja": "データなし", "ko": "데이터 없음", "pt-BR": "Sem dados", "zh-Hant": "沒有資料", "zh-HK": "冇資料"},
  "ios:health.calendar.legend.ring": {"de": "Eckring: Schlaf und Schritte im Vergleich zum Ziel", "es": "Anillo de la esquina: sueño y pasos frente a sus objetivos", "fr": "Anneau en coin : sommeil et pas par rapport aux objectifs", "it": "Anello nell'angolo: sonno e passi rispetto agli obiettivi", "ja": "角のリング：睡眠と歩数の目標達成度", "ko": "모서리 링: 목표 대비 수면과 걸음 수", "pt-BR": "Anel no canto: sono e passos em relação às metas", "zh-Hant": "角落小環：睡眠與步數的達標程度", "zh-HK": "角落小環：睡眠同步數嘅達標程度"},
  "ios:health.calendar.a11y.sleep": {"de": "Schlaf %@", "es": "Sueño %@", "fr": "Sommeil %@", "it": "Sonno %@", "ja": "睡眠 %@", "ko": "수면 %@", "pt-BR": "Sono %@", "zh-Hant": "睡眠 %@", "zh-HK": "睡眠 %@"},
  "ios:health.calendar.today": {"de": "Heute", "es": "Hoy", "fr": "Aujourd'hui", "it": "Oggi", "ja": "今日", "ko": "오늘", "pt-BR": "Hoje", "zh-Hant": "今天", "zh-HK": "今日"},
  "ios:health.day.noNote": {"de": "Keine Notiz für diesen Tag", "es": "No hay nota de este día", "fr": "Aucune note pour ce jour", "it": "Nessuna nota per questo giorno", "ja": "この日のメモはありません", "ko": "이 날의 노트가 없어요", "pt-BR": "Nenhuma nota para este dia", "zh-Hant": "這天沒有小記", "zh-HK": "呢日冇小記"},
  "ios:health.day.ask.compare": {"de": "Wie war dieser Tag im Vergleich zu sonst?", "es": "¿Cómo fue este día comparado con lo habitual?", "fr": "Comment s'est passée cette journée par rapport à d'habitude ?", "it": "Com'è andato questo giorno rispetto al solito?", "ja": "この日はいつもと比べてどうだった？", "ko": "이 날은 평소와 비교해 어땠어?", "pt-BR": "Como foi este dia comparado ao normal?", "zh-Hant": "這天和平常比起來如何？", "zh-HK": "呢日同平時比起嚟點？"},
  "ios:health.day.ask.standout": {"de": "Was war an diesem Tag auffällig?", "es": "¿Qué destacó de este día?", "fr": "Qu'est-ce qui a marqué cette journée ?", "it": "Cosa è emerso in questo giorno?", "ja": "この日に目立ったことは？", "ko": "이 날 눈에 띈 건 뭐였어?", "pt-BR": "O que se destacou neste dia?", "zh-Hant": "這天有什麼特別的？", "zh-HK": "呢日有咩特別？"},
  "ios:health.day.steps": {"de": "Schritte", "es": "Pasos", "fr": "Pas", "it": "Passi", "ja": "歩数", "ko": "걸음 수", "pt-BR": "Passos", "zh-Hant": "步數", "zh-HK": "步數"},
  "ios:health.day.exercise": {"de": "Training", "es": "Ejercicio", "fr": "Exercice", "it": "Allenamento", "ja": "エクササイズ", "ko": "운동", "pt-BR": "Exercício", "zh-Hant": "運動", "zh-HK": "運動"},
  "ios:health.day.bedtime": {"de": "Schlafenszeit", "es": "Hora de acostarse", "fr": "Coucher", "it": "Ora di andare a letto", "ja": "就寝時刻", "ko": "취침 시간", "pt-BR": "Hora de dormir", "zh-Hant": "就寢時間", "zh-HK": "瞓覺時間"},
  "ios:health.archive.clear": {"de": "Archiv löschen", "es": "Borrar archivo", "fr": "Effacer l'archive", "it": "Cancella archivio", "ja": "アーカイブを消去", "ko": "보관함 지우기", "pt-BR": "Limpar arquivo", "zh-Hant": "清除封存", "zh-HK": "清除封存"},
  "ios:health.archive.confirmTitle": {"de": "Archiv löschen?", "es": "¿Borrar el archivo?", "fr": "Effacer l'archive ?", "it": "Cancellare l'archivio?", "ja": "アーカイブを消去しますか？", "ko": "보관함을 지울까요?", "pt-BR": "Limpar o arquivo?", "zh-Hant": "要清除封存嗎？", "zh-HK": "要清除封存嗎？"},
  "ios:health.archive.confirmMessage": {"de": "Damit werden alle auf diesem iPhone gespeicherten Tagesnotizen gelöscht. Die heutige Notiz und deine Gesundheitsdaten bleiben erhalten.", "es": "Se eliminarán todas las notas diarias guardadas en este iPhone. La nota de hoy y tus datos de salud se conservan.", "fr": "Toutes les notes quotidiennes conservées sur cet iPhone seront supprimées. La note du jour et tes données de santé restent.", "it": "Verranno eliminate tutte le note giornaliere conservate su questo iPhone. La nota di oggi e i tuoi dati sulla salute restano.", "ja": "このiPhoneに保存されている毎日のメモがすべて削除されます。今日のメモとヘルスケアのデータはそのまま残ります。", "ko": "이 iPhone에 보관된 모든 일일 노트가 삭제돼요. 오늘의 노트와 건강 데이터는 그대로 남아요.", "pt-BR": "Isso apaga todas as notas diárias guardadas neste iPhone. A nota de hoje e seus dados de saúde continuam.", "zh-Hant": "這會刪除這部 iPhone 上保存的所有每日小記。今天的小記和你的健康資料都會保留。", "zh-HK": "咁會刪除呢部 iPhone 上面保存嘅所有每日小記。今日嘅小記同你嘅健康資料會保留。"}
}
```

- [ ] **Step 3: Apply to the working catalog and to a copy of the committed one**

```bash
cd /Users/yanceyleo/Code/exodus/exodus-ios
git diff --stat                                   # note the catalog's foreign edits before you start
git show HEAD:Resources/App/Localizable.xcstrings > /tmp/trends-l10n/head.xcstrings
cp /tmp/trends-l10n/head.xcstrings /tmp/trends-l10n/mine.xcstrings
for f in Resources/App/Localizable.xcstrings /tmp/trends-l10n/mine.xcstrings; do
  python3 /tmp/trends-l10n/add_keys.py "$f"
  python3 scripts/l10n.py fill /tmp/trends-l10n/translations.json --file "$f"
done
```

- [ ] **Step 4: Verify both catalogs hold the same new entries, and the audit**

```bash
python3 - <<'PY'
import json
work = json.load(open('Resources/App/Localizable.xcstrings', encoding='utf-8'))['strings']
mine = json.load(open('/tmp/trends-l10n/mine.xcstrings', encoding='utf-8'))['strings']
head = json.load(open('/tmp/trends-l10n/head.xcstrings', encoding='utf-8'))['strings']
new = sorted(set(mine) - set(head))
assert len(new) == 38, len(new)
for k in new:
    assert work.get(k) == mine[k], k
    langs = set(mine[k]['localizations'])
    assert langs == {'en', 'de', 'es', 'fr', 'it', 'ja', 'ko', 'pt-BR', 'zh-Hant', 'zh-HK'}, (k, langs)
print('OK', len(new))
PY
python3 scripts/l10n.py audit 2>&1 | tail -1
```
Expected: `OK 38`, then `0 error(s)` (the new keys show as "not referenced" warnings until Tasks 5–8 use them).

- [ ] **Step 5: Build the patch of only these keys and check it applies to HEAD**

```bash
python3 - <<'PY'
import difflib
head = open('/tmp/trends-l10n/head.xcstrings', encoding='utf-8').read().splitlines(keepends=True)
mine = open('/tmp/trends-l10n/mine.xcstrings', encoding='utf-8').read().splitlines(keepends=True)
with open('/tmp/trends-l10n/catalog.patch', 'w', encoding='utf-8') as f:
    f.writelines(difflib.unified_diff(head, mine, 'a/Resources/App/Localizable.xcstrings', 'b/Resources/App/Localizable.xcstrings'))
PY
GIT_INDEX_FILE=/tmp/trends-l10n/check.idx git read-tree HEAD
GIT_INDEX_FILE=/tmp/trends-l10n/check.idx git apply --cached --check /tmp/trends-l10n/catalog.patch && echo PATCH-OK
rm -f /tmp/trends-l10n/check.idx
```
Expected: `PATCH-OK`. (The private index file never touches the shared one.)

- [ ] **Step 6: Commit the patch**

```bash
.superpowers/sdd/commit-mine.sh "feat(health): calendar, day sheet and archive strings in ten languages" --patch /tmp/trends-l10n/catalog.patch
git show --stat HEAD           # only Resources/App/Localizable.xcstrings, about 38 entries' worth of lines
git diff --stat                # the catalog still shows the user's own edits, nothing of ours
```

---

### Task 5: `TrendsModel`, the calendar grid, trend text, and the home model's archive and week

**Files:**
- Create: `Sources/HealthFeature/Trends/CalendarGrid.swift`
- Create: `Sources/HealthFeature/Trends/TrendText.swift`
- Create: `Sources/HealthFeature/Trends/TrendsModel.swift`
- Modify: `Sources/HealthFeature/Report/HealthHomeModel.swift` (targeted edits)
- Test: `Tests/HealthFeatureTests/TrendsModelTests.swift`
- Modify: `Tests/HealthFeatureTests/HealthHomeModelTests.swift` (four tests appended inside the struct)

**Interfaces:**
- Consumes: `Period`, `Aggregates`, `TrendChange`, `TrendMath`, `DayRecord`, `DayTone` (Task 1); `HealthArchive`, `ArchivedDay`, `ReportCache.archive` (Task 2); `DayRecordStore`, `SnapshotBuilder` (Task 3); keys from Task 4; `ReportInk.green` (`UI/ReportStory.swift`), `WireDate`.
- Produces:
  - `struct CalendarCell: Identifiable, Equatable, Sendable { id: Int; day: Date?; record: DayRecord?; isToday: Bool; isFuture: Bool; var tone: DayTone }`.
  - `struct MonthBar: Identifiable, Equatable, Sendable { month: Period; aggregates: Aggregates; isFuture: Bool; var id: Date }`.
  - `struct WeekGlance: Equatable, Sendable { period: Period; cells: [CalendarCell]; current: Aggregates; previous: Aggregates }`.
  - `enum CalendarGrid { static func cells(_ period: Period, records: [Date: DayRecord], today: Date, calendar: Calendar) -> [CalendarCell]; static func months(_ period: Period, records: [DayRecord], today: Date, calendar: Calendar) -> [MonthBar] }`.
  - `public enum TrendScope: String, CaseIterable, Hashable, Sendable { week, month, quarter, year }` with `var kind: Period.Kind`, `var label: LocalizedStringResource`, `var versusLabel: LocalizedStringResource`.
  - `public struct TrendsRoute: Hashable, Sendable { scope: TrendScope; anchor: Date; presentedDay: Date?; public init(scope:anchor:presentedDay: = nil) }`.
  - `enum TrendMetric: CaseIterable, Hashable, Sendable { sleep, steps, hrv }` with `func value(_ a: Aggregates) -> Double?`, `var title: LocalizedStringResource`, `func format(_ v: Double) -> String`.
  - `enum TrendText { title(_:calendar:), range(_:calendar:), weekdayInitials(calendar:), duration(_ minutes: Double), clock(_ minutes: Int), steps(_ n: Double), compact(_ n: Int), ms(_ v: Double), delta(_ change: TrendChange?, metric:), amount(_ change: TrendChange, metric:), spoken(metric:value:change:scope:), color(_ change: TrendChange?) -> AnyShapeStyle }`.
  - `@MainActor @Observable final class TrendsModel { enum Phase { loading, ready, failed }; scope; period; phase; records: [Date: DayRecord]; current: Aggregates?; previous: Aggregates?; calendar; locale; init(route:store:archive:calendar:locale:now:); today; canGoForward; title; cells; months; select(_:); showPrevious(); showNext(); open(month:); load() async; archived(_ day: Date) -> ArchivedDay?; snapshot(for day: Date) async -> HealthSnapshot? }`.
  - `HealthHomeModel`: `let calendar: Calendar`, `let dayRecords: DayRecordStore`, `private(set) var week: WeekGlance?`, `var archive: HealthArchive`, `func loadWeek() async`, `func trends(_ route: TrendsRoute) -> TrendsModel`, `@discardableResult public func clearArchive() -> Bool`; `load(force:)` also loads the week.

- [ ] **Step 1: Write the failing tests**

Create `Tests/HealthFeatureTests/TrendsModelTests.swift`:

```swift
import Foundation
import Models
import SwiftUI
import Testing

@testable import HealthFeature

@MainActor
struct TrendsModelTests {
    let cal = TestClock.calendar
    let source = FakeHealthSource()
    let archive = HealthArchive(directory: FileManager.default.temporaryDirectory.appending(path: UUID().uuidString))
    func day(_ offset: Int) -> Date { cal.date(byAdding: .day, value: offset, to: TestClock.today)! }

    func model(_ scope: TrendScope = .month, anchor: Date = TestClock.now) -> TrendsModel {
        let store = DayRecordStore(
            builder: SnapshotBuilder(source: source, calendar: cal), calendar: cal, now: { TestClock.now })
        return TrendsModel(
            route: TrendsRoute(scope: scope, anchor: anchor), store: store, archive: archive, calendar: cal,
            locale: "en", now: { TestClock.now })
    }

    /// 1,000 steps every day for ten weeks.
    func steps() async {
        let values = (0..<70).map { DayValue(day: day(-$0), value: 1000) }
        await source.set { $0.sums[.steps] = values }
    }

    @Test func opensOnThePeriodHoldingTheAnchor() {
        let m = model(.month)
        #expect(m.period == Period.containing(TestClock.now, .month, calendar: cal))
        #expect(model(.week).title == "Week 40")
    }

    @Test func aRouteFromTheFutureOpensOnToday() {
        #expect(model(.week, anchor: day(30)).period == Period.containing(TestClock.now, .week, calendar: cal))
    }

    @Test func theCurrentPeriodIsTheLastOne() {
        let m = model(.week)
        #expect(!m.canGoForward)
        m.showNext()
        #expect(m.period == Period.containing(TestClock.now, .week, calendar: cal))
        m.showPrevious()
        #expect(m.canGoForward)
        #expect(m.period.start == day(-10))
    }

    @Test func loadingReadsThePeriodAndTheOneBefore() async {
        await steps()
        let m = model(.week)
        await m.load()
        #expect(m.phase == .ready)
        #expect(m.current?.steps.days == 4)
        #expect(m.previous?.steps.days == 7)
        #expect(m.current?.steps.average == 1000)
        #expect(m.cells.count == 7)
        #expect(m.cells.filter(\.isFuture).count == 3)
        #expect(m.cells.first { $0.isToday }?.day == TestClock.today)
    }

    @Test func aMonthGridOpensWithBlanksUpToItsFirstWeekday() {
        let m = model(.month)  // October 2026 starts on a Thursday
        #expect(m.cells.prefix(3).allSatisfy { $0.day == nil })
        #expect(m.cells[3].day == TestClock.today)
        #expect(m.cells.compactMap(\.day).count == 31)
        #expect(Set(m.cells.map(\.id)).count == m.cells.count)
    }

    @Test func switchingScopeStaysWhereTheUserIsLooking() {
        let m = model(.month)
        m.select(.week)
        #expect(m.period == Period.containing(TestClock.now, .week, calendar: cal))
        m.select(.month)
        m.showPrevious()
        m.select(.week)
        #expect(m.period.start == TestClock.date(2026, 8, 31))
    }

    @Test func aMonthOpensFromTheYear() {
        let m = model(.year)
        let bars = m.months
        #expect(bars.count == 12)
        #expect(bars.filter(\.isFuture).count == 2)
        m.open(month: bars[8].month)
        #expect(m.scope == .month)
        #expect(m.period.start == TestClock.date(2026, 9, 1))
    }

    /// Paging faster than Apple Health answers never lands an older period's numbers under a newer title.
    @Test func aSlowerOlderLoadNeverOverwritesANewerOne() async {
        await steps()
        await source.set { $0.slowMs = 300 }
        let m = model(.week)
        let first = Task { await m.load() }
        try? await Task.sleep(for: .milliseconds(50))
        await source.set { $0.slowMs = 0 }
        m.showPrevious()
        await m.load()
        await first.value
        #expect(m.period.start == day(-10))
        #expect(m.current?.steps.days == 7)
        #expect(m.phase == .ready)
    }

    @Test func aFailedReadSaysSo() async {
        await source.set { $0.failure = URLError(.unknown) }
        let m = model(.week)
        await m.load()
        #expect(m.phase == .failed)
    }

    @Test func aDaysNoteComesFromTheArchive() throws {
        try archive.write(HealthArchiveTests.entry("2026-09-30"))
        let m = model()
        #expect(m.archived(day(-1))?.summary.headline == "h")
        #expect(m.archived(day(-2)) == nil)
    }
}

struct TrendTextTests {
    @Test func deltasSayWhichWayAndHowMuch() {
        #expect(TrendText.delta(nil, metric: .sleep) == "—")
        #expect(TrendText.delta(TrendMath.change(100, from: 99), metric: .steps) == "→")
        #expect(
            TrendText.delta(TrendMath.change(8000, from: 10000), metric: .steps)
                == "↓ " + (0.2).formatted(.percent.precision(.fractionLength(0))))
        #expect(TrendText.delta(TrendMath.change(460, from: 408), metric: .sleep) == "↑ " + TrendText.duration(52))
    }

    @Test func spokenChangesUseWords() {
        let up = TrendText.spoken(metric: .sleep, value: 460, change: TrendMath.change(460, from: 408), scope: .week)
        #expect(up.contains("Up " + TrendText.duration(52)))
        #expect(up.contains("vs last week"))
        let none = TrendText.spoken(metric: .hrv, value: nil, change: nil, scope: .month)
        #expect(none.contains("Nothing earlier to compare"))
    }

    @Test func weekdaysStartOnMonday() {
        var c = TestClock.calendar
        c.firstWeekday = 1
        c.locale = .current
        #expect(TrendText.weekdayInitials(calendar: c).count == 7)
        #expect(TrendText.weekdayInitials(calendar: c).first == c.veryShortStandaloneWeekdaySymbols[1])
    }
}
```

Append inside `struct HealthHomeModelTests` in `Tests/HealthFeatureTests/HealthHomeModelTests.swift`, directly after the last test (`loggingWaterDuringALoadShowsTheCupWithoutRewritingTheReport`) and before the struct's closing `}`:

```swift

    @Test func aWrittenNoteIsKeptForItsDay() async {
        await withData()
        prefs.summaryConsent = true
        await model().load()
        #expect(cache.archive.read(day: "2026-10-01")?.summary == Self.summary)
    }

    @Test func stoppingNotesKeepsThePastOnes() async {
        await withData()
        prefs.summaryConsent = true
        let m = model()
        await m.load()
        m.revokeConsent()
        #expect(cache.load(date: "2026-10-01") == nil)
        #expect(cache.archive.read(day: "2026-10-01") != nil)
    }

    @Test func clearingTheArchiveLeavesTodaysNote() async {
        await withData()
        prefs.summaryConsent = true
        let m = model()
        await m.load()
        #expect(m.clearArchive())
        #expect(cache.archive.read(day: "2026-10-01") == nil)
        #expect(cache.load(date: "2026-10-01") != nil)
        #expect(m.report.readySummary != nil)
    }

    @Test func theWeekCardReadsThisWeekAndLast() async throws {
        await withData()
        let m = model()
        await m.load()
        let week = try #require(m.week)
        #expect(week.period == Period.containing(TestClock.now, .week, calendar: TestClock.calendar))
        #expect(week.cells.count == 7)
        #expect(week.current.steps.average == 9000)
        #expect(week.previous.steps.days == 0)
    }
```

- [ ] **Step 2: Run them to verify they fail**

Run: `xcodebuild test -workspace ExodusIos.xcworkspace -scheme HealthFeature -destination "id=D8A2BE45-88F3-46AE-8693-B147F2815724" -derivedDataPath /tmp/trends-dd -only-testing:HealthFeatureTests/TrendsModelTests -only-testing:HealthFeatureTests/TrendTextTests -only-testing:HealthFeatureTests/HealthHomeModelTests 2>&1 | grep -E "error:|Test run with|TEST (SUCCEEDED|FAILED)"`
Expected: build errors `cannot find 'TrendsModel' in scope`, `cannot find 'TrendScope' in scope`, `value of type 'HealthHomeModel' has no member 'week'`.

- [ ] **Step 3: Write `CalendarGrid.swift`**

```swift
// Sources/HealthFeature/Trends/CalendarGrid.swift
import Foundation

/// One square of the calendar: a day (past, today or still to come), or a blank before a month's first day.
struct CalendarCell: Identifiable, Equatable, Sendable {
    let id: Int
    let day: Date?
    let record: DayRecord?
    let isToday: Bool
    let isFuture: Bool

    var tone: DayTone { record.map { DayTone($0.mood) } ?? .empty }
}

/// A month as a bar in the quarter and year views.
struct MonthBar: Identifiable, Equatable, Sendable {
    let month: Period
    let aggregates: Aggregates
    let isFuture: Bool
    var id: Date { month.start }
}

/// The home's "This week" card: the week's days and its averages beside last week's.
struct WeekGlance: Equatable, Sendable {
    var period: Period
    var cells: [CalendarCell]
    var current: Aggregates
    var previous: Aggregates
}

enum CalendarGrid {
    /// The days of a week or a month, Monday first; a month opens with blanks up to its first weekday. Days to come
    /// carry no record.
    static func cells(_ period: Period, records: [Date: DayRecord], today: Date, calendar: Calendar) -> [CalendarCell] {
        let iso = TrendMath.calendar(calendar)
        let last = calendar.startOfDay(for: today)
        var cells: [CalendarCell] = []
        if period.kind == .month {
            let lead = (iso.component(.weekday, from: period.start) + 5) % 7
            cells += (0..<lead).map { CalendarCell(id: -1 - $0, day: nil, record: nil, isToday: false, isFuture: false) }
        }
        for (i, day) in period.days(calendar: calendar).enumerated() {
            cells.append(
                CalendarCell(
                    id: i, day: day, record: day <= last ? records[day] : nil, isToday: day == last,
                    isFuture: day > last))
        }
        return cells
    }

    /// The months of a quarter or a year, each with its own averages.
    static func months(_ period: Period, records: [DayRecord], today: Date, calendar: Calendar) -> [MonthBar] {
        let last = calendar.startOfDay(for: today)
        var bars: [MonthBar] = []
        var month = Period.containing(period.start, .month, calendar: calendar)
        while month.start < period.end {
            bars.append(
                MonthBar(
                    month: month, aggregates: TrendMath.aggregate(records, in: month, today: last, calendar: calendar),
                    isFuture: month.start > last))
            month = month.next(calendar: calendar)
        }
        return bars
    }
}
```

- [ ] **Step 4: Write `TrendText.swift`**

```swift
// Sources/HealthFeature/Trends/TrendText.swift
import Foundation
import SwiftUI

/// The calendar's four views.
public enum TrendScope: String, CaseIterable, Hashable, Sendable {
    case week, month, quarter, year

    var kind: Period.Kind {
        switch self {
        case .week: .week
        case .month: .month
        case .quarter: .quarter
        case .year: .year
        }
    }

    var label: LocalizedStringResource {
        switch self {
        case .week: LocalizedStringResource("ios:health.calendar.scope.week", defaultValue: "Week", comment: "Calendar page picker: show one week.")
        case .month: LocalizedStringResource("ios:health.calendar.scope.month", defaultValue: "Month", comment: "Calendar page picker: show one month.")
        case .quarter: LocalizedStringResource("ios:health.calendar.scope.quarter", defaultValue: "Quarter", comment: "Calendar page picker: show one quarter (three months).")
        case .year: LocalizedStringResource("ios:health.calendar.scope.year", defaultValue: "Year", comment: "Calendar page picker: show one year.")
        }
    }

    /// What a change is measured against.
    var versusLabel: LocalizedStringResource {
        switch self {
        case .week: LocalizedStringResource("ios:health.calendar.vs.week", defaultValue: "vs last week", comment: "Calendar header: the change shown is against last week.")
        case .month: LocalizedStringResource("ios:health.calendar.vs.month", defaultValue: "vs last month", comment: "Calendar header: the change shown is against last month.")
        case .quarter: LocalizedStringResource("ios:health.calendar.vs.quarter", defaultValue: "vs last quarter", comment: "Calendar header: the change shown is against the previous quarter.")
        case .year: LocalizedStringResource("ios:health.calendar.vs.year", defaultValue: "vs last year", comment: "Calendar header: the change shown is against last year.")
        }
    }
}

/// Where the calendar opens: a view, a day inside the period to show, and optionally a day whose sheet is up.
public struct TrendsRoute: Hashable, Sendable {
    public var scope: TrendScope
    public var anchor: Date
    public var presentedDay: Date?

    public init(scope: TrendScope, anchor: Date, presentedDay: Date? = nil) {
        self.scope = scope
        self.anchor = anchor
        self.presentedDay = presentedDay
    }
}

/// The three numbers the calendar's header (and the home card, sleep and steps) compares.
enum TrendMetric: CaseIterable, Hashable, Sendable {
    case sleep, steps, hrv

    func value(_ a: Aggregates) -> Double? {
        switch self {
        case .sleep: a.sleepMin.average
        case .steps: a.steps.average
        case .hrv: a.hrvMs.average
        }
    }

    var title: LocalizedStringResource {
        switch self {
        case .sleep: LocalizedStringResource("ios:health.calendar.stat.sleep", defaultValue: "Avg. sleep", comment: "Calendar header and home card: average sleep per night over the period.")
        case .steps: LocalizedStringResource("ios:health.calendar.stat.steps", defaultValue: "Daily steps", comment: "Calendar header and home card: average steps per day over the period.")
        case .hrv: LocalizedStringResource("ios:health.calendar.stat.hrv", defaultValue: "HRV", comment: "Calendar header: average heart rate variability (abbreviation) over the period.")
        }
    }

    func format(_ v: Double) -> String {
        switch self {
        case .sleep: TrendText.duration(v)
        case .steps: TrendText.steps(v)
        case .hrv: TrendText.ms(v)
        }
    }
}

/// The calendar's words and numbers, in the user's language.
enum TrendText {
    /// "Week 40", "October 2026", "Q3 2026", "2026": the period row and the screenshot's name.
    static func title(_ p: Period, calendar: Calendar) -> String {
        let style = Date.FormatStyle(calendar: TrendMath.calendar(calendar), timeZone: calendar.timeZone)
        switch p.kind {
        case .week:
            let n = p.isoWeek(calendar: calendar)
            return String(
                localized: "ios:health.calendar.weekTitle", defaultValue: "Week \(n)",
                comment: "Calendar page: a week's title. %lld is the ISO week number (1-53).")
        case .month: return p.start.formatted(style.month(.wide).year())
        case .quarter: return p.start.formatted(style.quarter(.abbreviated).year())
        case .year: return p.start.formatted(style.year())
        case .days: return range(p, calendar: calendar)
        }
    }

    /// "Sep 28 – Oct 4".
    static func range(_ p: Period, calendar: Calendar) -> String {
        let last = calendar.date(byAdding: .day, value: -1, to: p.end)!
        let style = Date.IntervalFormatStyle(calendar: calendar, timeZone: calendar.timeZone).month(.abbreviated).day()
        return (p.start..<last).formatted(style)
    }

    /// Monday first, in the user's language ("M T W T F S S").
    static func weekdayInitials(calendar: Calendar) -> [String] {
        var c = calendar
        c.locale = .current
        let symbols = c.veryShortStandaloneWeekdaySymbols
        return Array(symbols[1...] + symbols[..<1])
    }

    /// "7h 40m".
    static func duration(_ minutes: Double) -> String {
        Duration.seconds(Int(minutes.rounded()) * 60).formatted(.units(allowed: [.hours, .minutes], width: .narrow))
    }

    /// "7:40", for a week cell's narrow column.
    static func clock(_ minutes: Int) -> String {
        Duration.seconds(minutes * 60).formatted(.time(pattern: .hourMinute))
    }

    static func steps(_ n: Double) -> String { Int(n.rounded()).formatted() }

    /// "9.1K".
    static func compact(_ n: Int) -> String { n.formatted(.number.notation(.compactName)) }

    /// "38 ms".
    static func ms(_ v: Double) -> String {
        Measurement(value: v.rounded(), unit: UnitDuration.milliseconds)
            .formatted(.measurement(width: .abbreviated, usage: .asProvided, numberFormatStyle: .number.precision(.fractionLength(0))))
    }

    /// "↑ 52m", "↓ 12%", "→", or "—" with nothing to compare. Steps change by share, the others by amount.
    static func delta(_ change: TrendChange?, metric: TrendMetric) -> String {
        guard let change else { return "—" }
        switch change.direction {
        case .flat: return "→"
        case .up: return "↑ " + amount(change, metric: metric)
        case .down: return "↓ " + amount(change, metric: metric)
        }
    }

    static func amount(_ change: TrendChange, metric: TrendMetric) -> String {
        switch metric {
        case .sleep: duration(abs(change.absolute))
        case .steps:
            change.relative.map { abs($0).formatted(.percent.precision(.fractionLength(0))) }
                ?? steps(abs(change.absolute))
        case .hrv: ms(abs(change.absolute))
        }
    }

    /// What VoiceOver reads for a number: its name, its value, which way it went, against what.
    static func spoken(metric: TrendMetric, value: Double?, change: TrendChange?, scope: TrendScope) -> String {
        let shown = value.map(metric.format) ?? String(localized: DayTone.empty.name)
        let moved: String
        if let change {
            switch change.direction {
            case .up:
                let by = amount(change, metric: metric)
                moved = String(
                    localized: "ios:health.calendar.change.up", defaultValue: "Up \(by)",
                    comment: "VoiceOver: a number went up against the previous period. %@ is the amount, e.g. 52m or 12%.")
            case .down:
                let by = amount(change, metric: metric)
                moved = String(
                    localized: "ios:health.calendar.change.down", defaultValue: "Down \(by)",
                    comment: "VoiceOver: a number went down against the previous period. %@ is the amount, e.g. 52m or 12%.")
            case .flat:
                moved = String(
                    localized: "ios:health.calendar.change.flat", defaultValue: "About the same",
                    comment: "VoiceOver: a number changed less than 3% against the previous period.")
            }
        } else {
            moved = String(
                localized: "ios:health.calendar.change.none", defaultValue: "Nothing earlier to compare",
                comment: "VoiceOver: the previous period has no data for this number.")
        }
        return [String(localized: metric.title), shown, moved, String(localized: scope.versusLabel)]
            .joined(separator: ", ")
    }

    /// Up in the note's green, down in a warm orange (4.5:1 on the card in both modes), level in secondary ink.
    static func color(_ change: TrendChange?) -> AnyShapeStyle {
        switch change?.direction {
        case .up: AnyShapeStyle(ReportInk.green)
        case .down: AnyShapeStyle(Color.adaptive(0xB4470C, dark: 0xFFA27A))
        case .flat, nil: AnyShapeStyle(HierarchicalShapeStyle.secondary)
        }
    }
}
```

`DayTone.empty.name` is added in Task 6 (`Trends/DayToneStyle.swift`). So that this task builds on its own, create that file now with only the `name` part; Task 6 adds the rest of it:

```swift
// Sources/HealthFeature/Trends/DayToneStyle.swift
import SwiftUI

extension DayTone {
    /// What the colour means, for the legend and VoiceOver.
    var name: LocalizedStringResource {
        switch self {
        case .good: LocalizedStringResource("ios:health.calendar.tone.good", defaultValue: "Rested or active", comment: "Calendar day colour and legend: a good day (rested, active or calm).")
        case .tired: LocalizedStringResource("ios:health.calendar.tone.tired", defaultValue: "Short on sleep", comment: "Calendar day colour and legend: a day after too little sleep.")
        case .recovering: LocalizedStringResource("ios:health.calendar.tone.recovering", defaultValue: "Recovering", comment: "Calendar day colour and legend: a day with low recovery (HRV under the usual).")
        case .empty: LocalizedStringResource("ios:health.calendar.tone.empty", defaultValue: "No data", comment: "Calendar day colour and legend: Apple Health has nothing for the day.")
        }
    }
}
```

- [ ] **Step 5: Write `TrendsModel.swift`**

```swift
// Sources/HealthFeature/Trends/TrendsModel.swift
import Foundation
import Models
import Observation

/// The calendar page's state: which view and period is shown, its days' records and the previous period's (for the
/// change), and the day sheet's note and numbers. Moving changes the period at once; the view then calls `load()`,
/// and only the newest load lands.
@MainActor
@Observable
final class TrendsModel {
    enum Phase: Equatable { case loading, ready, failed }

    private(set) var scope: TrendScope
    private(set) var period: Period
    private(set) var phase: Phase = .loading
    /// The shown period's days and the previous period's, by day.
    private(set) var records: [Date: DayRecord] = [:]
    private(set) var current: Aggregates?
    private(set) var previous: Aggregates?
    let calendar: Calendar
    let locale: String

    @ObservationIgnored private let store: DayRecordStore
    @ObservationIgnored private let archive: HealthArchive
    @ObservationIgnored private let now: @Sendable () -> Date
    @ObservationIgnored private var generation = 0

    init(
        route: TrendsRoute, store: DayRecordStore, archive: HealthArchive, calendar: Calendar, locale: String,
        now: @escaping @Sendable () -> Date
    ) {
        self.scope = route.scope
        self.period = Period.containing(min(route.anchor, now()), route.scope.kind, calendar: calendar)
        self.store = store
        self.archive = archive
        self.calendar = calendar
        self.locale = locale
        self.now = now
    }

    var today: Date { calendar.startOfDay(for: now()) }

    /// The next period has begun; the calendar never pages into days with nothing in them yet.
    var canGoForward: Bool { period.end <= today }

    var title: String { TrendText.title(period, calendar: calendar) }

    var cells: [CalendarCell] { CalendarGrid.cells(period, records: records, today: today, calendar: calendar) }

    var months: [MonthBar] {
        CalendarGrid.months(period, records: Array(records.values), today: today, calendar: calendar)
    }

    /// Stays where the user is looking: today if it is on screen, else the shown period's first day.
    func select(_ scope: TrendScope) {
        guard scope != self.scope else { return }
        let anchor = period.contains(today) ? today : period.start
        self.scope = scope
        period = Period.containing(anchor, scope.kind, calendar: calendar)
    }

    func showPrevious() { period = period.previous(calendar: calendar) }

    func showNext() {
        guard canGoForward else { return }
        period = period.next(calendar: calendar)
    }

    func open(month: Period) {
        scope = .month
        period = month
    }

    /// Reads the shown period and the one before it. A load that a newer one overtook is dropped, so paging faster
    /// than Apple Health answers never shows an older period's numbers under a newer title.
    func load() async {
        generation += 1
        let mine = generation
        let shown = period
        let before = shown.previous(calendar: calendar)
        phase = .loading
        do {
            let lastDay = calendar.date(byAdding: .day, value: -1, to: shown.end)!
            let read = try await store.records(from: before.start, through: lastDay)
            guard mine == generation else { return }
            let all = Array(read.values)
            records = read
            current = TrendMath.aggregate(all, in: shown, today: today, calendar: calendar)
            previous = TrendMath.aggregate(all, in: before, today: today, calendar: calendar)
            phase = .ready
        } catch {
            guard mine == generation else { return }
            phase = .failed
        }
    }

    /// The note kept for a day, if any.
    func archived(_ day: Date) -> ArchivedDay? {
        archive.read(day: WireDate(timeZone: calendar.timeZone).day(day))
    }

    /// The whole day as the home builds today, for the day sheet's question; nil when it can't be read.
    func snapshot(for day: Date) async -> HealthSnapshot? {
        try? await store.snapshot(for: day, locale: locale).snapshot
    }
}
```

- [ ] **Step 6: Wire the home model (targeted edits in `HealthHomeModel.swift`)**

Check first: `git diff --stat -- Sources/HealthFeature/Report/HealthHomeModel.swift` is empty.

Edit 1 — after `public private(set) var hasConsent: Bool` add:

```swift
    /// This week for the home's card; nil until it has been read.
    private(set) var week: WeekGlance?
    /// The calendar's day records, kept across visits to it.
    @ObservationIgnored let dayRecords: DayRecordStore
    @ObservationIgnored let calendar: Calendar
```

Edit 2 — in `init`, replace

```swift
        self.builder = SnapshotBuilder(source: source, calendar: calendar)
```

with

```swift
        let builder = SnapshotBuilder(source: source, calendar: calendar)
        self.builder = builder
        self.calendar = calendar
        self.dayRecords = DayRecordStore(builder: builder, calendar: calendar, now: now)
```

Edit 3 — replace `load(force:)`:

```swift
    /// One load at a time: a plain call joins the one running, a forced one replaces it and rewrites the report. The
    /// week's card is read after it.
    public func load(force: Bool = false) async {
        await reload(replacing: force, regenerate: force)
        await loadWeek()
    }
```

Edit 4 — after `func historyLoader(calendar: Calendar = .current) -> HealthHistoryLoader { … }` add:

```swift

    /// Every daily note kept on this phone.
    var archive: HealthArchive { cache.archive }

    /// This week and last, for the home's card. A failed read keeps what is shown.
    func loadWeek() async {
        let today = calendar.startOfDay(for: now())
        let period = Period.containing(today, .week, calendar: calendar)
        let before = period.previous(calendar: calendar)
        guard let records = try? await dayRecords.records(from: before.start, through: today) else { return }
        let all = Array(records.values)
        week = WeekGlance(
            period: period, cells: CalendarGrid.cells(period, records: records, today: today, calendar: calendar),
            current: TrendMath.aggregate(all, in: period, today: today, calendar: calendar),
            previous: TrendMath.aggregate(all, in: before, today: today, calendar: calendar))
    }

    /// The calendar page's model, on the same store and day records as the home.
    func trends(_ route: TrendsRoute) -> TrendsModel {
        TrendsModel(route: route, store: dayRecords, archive: archive, calendar: calendar, locale: locale, now: now)
    }

    /// Deletes every kept note on this phone (the menu's Clear archive). Today's note and Apple Health are untouched.
    @discardableResult
    public func clearArchive() -> Bool { (try? archive.clear()) != nil }
```

- [ ] **Step 7: Run the tests**

Run: the Step 2 command; then the whole `HealthFeature` scheme.
Expected: `TrendsModelTests` 10, `TrendTextTests` 3 and `HealthHomeModelTests` (existing + 4) all pass; the whole scheme passes.

- [ ] **Step 8: Audit and commit**

```bash
python3 scripts/l10n.py audit 2>&1 | tail -1      # 0 error(s)
git diff --stat
.superpowers/sdd/commit-mine.sh "feat(health): the calendar's model — periods paged and switched, records and changes, newest load wins; home keeps the week and can clear the archive" \
  Sources/HealthFeature/Trends/CalendarGrid.swift Sources/HealthFeature/Trends/TrendText.swift \
  Sources/HealthFeature/Trends/TrendsModel.swift Sources/HealthFeature/Trends/DayToneStyle.swift \
  Sources/HealthFeature/Report/HealthHomeModel.swift \
  Tests/HealthFeatureTests/TrendsModelTests.swift Tests/HealthFeatureTests/HealthHomeModelTests.swift
git show --stat HEAD
```

---

### Task 6: The day sheet

**Files:**
- Modify: `Sources/HealthFeature/Trends/DayToneStyle.swift` (add fills, the corner ring)
- Create: `Sources/HealthFeature/Trends/DaySheet.swift`
- Modify: `Sources/HealthFeature/UI/ReportStory.swift` (optional eyebrow)
- Modify: `Sources/HealthFeature/UI/CategoryStyle.swift` (`CategoryValue.steps(_:)`)
- Test: `Tests/HealthFeatureTests/DaySheetTests.swift`

**Interfaces:**
- Consumes: `DayRecord`, `DayTone` (Task 1), `ArchivedDay` (Task 2), `TrendText`, `TrendMetric` (Task 5), `ReportStory`, `AskComposer`, `HealthSurface`, `CategoryStyle`, `CategoryValue`, `OdyScene(hero:)`, `MarkdownView`, `ScreenTitles`, `HealthWire`.
- Produces:
  - `extension DayTone { var fill: Color; var name: LocalizedStringResource }`, `enum RingInk { static let sleep, steps: Color }`, `struct CornerRing: View { init(sleep: Double?, steps: Double?, lineWidth: CGFloat = 2.5) }`.
  - `struct DaySheet: View { init(day: Date, record: DayRecord?, archived: ArchivedDay?, healthTitle: String, calendar: Calendar, loadSnapshot: @escaping () async -> HealthSnapshot?, onAsk: @escaping (String) -> Void) }`.
  - `struct DayNumbers: View { struct Row { title: LocalizedStringResource; symbol: String; value: String }; static func rows(_ r: DayRecord) -> [Row] }`.
  - `ReportStory.init?(_ summary: HealthSummary, eyebrow: Text? = nil)`.
  - `CategoryValue.steps(_ n: Int) -> String`.

- [ ] **Step 1: Write the failing tests**

Create `Tests/HealthFeatureTests/DaySheetTests.swift`:

```swift
import Foundation
import Models
import SwiftUI
import Testing

@testable import HealthFeature

@MainActor
struct DaySheetTests {
    @Test func aDayWithoutANoteShowsTheNumbersItHas() {
        let r = DayRecord(
            day: TestClock.today, sleepMin: 460, steps: 9120, stepGoal: 8000, hrvMs: 48, waterCups: 3,
            bedtime: "23:40", mood: .rested)
        let rows = DayNumbers.rows(r)
        #expect(rows.map(\.symbol) == ["moon.zzz.fill", "bed.double.fill", "figure.walk", "waveform.path.ecg", "drop.fill"])
        #expect(rows[0].value == TrendText.duration(460))
        #expect(rows[1].value == "23:40")
        #expect(rows[2].value == 9120.formatted())
        #expect(rows[3].value == TrendText.ms(48))
        #expect(rows[4].value == CategoryValue.cups(3))
    }

    @Test func anEmptyDayHasNoRows() {
        #expect(DayNumbers.rows(DayRecord(day: TestClock.today)).isEmpty)
    }

    @Test func storiesCanCarryTheDayAsTheirEyebrow() {
        #expect(ReportStory(PreviewSummaryService.sample, eyebrow: Text(verbatim: "Sep 30")) != nil)
        #expect(ReportStory(PreviewSummaryService.sample) != nil)
    }

    @Test func stepsReadAsTheCardDoes() {
        #expect(CategoryValue.steps(9120) == String(localized: "ios:health.value.steps", defaultValue: "\(9120) steps"))
    }
}
```

- [ ] **Step 2: Run them to verify they fail**

Run: `xcodebuild test -workspace ExodusIos.xcworkspace -scheme HealthFeature -destination "id=D8A2BE45-88F3-46AE-8693-B147F2815724" -derivedDataPath /tmp/trends-dd -only-testing:HealthFeatureTests/DaySheetTests 2>&1 | grep -E "error:|Test run with|TEST (SUCCEEDED|FAILED)"`
Expected: build errors `cannot find 'DayNumbers' in scope`, `extra argument 'eyebrow' in call`, `type 'CategoryValue' has no member 'steps'`.

- [ ] **Step 3: Extract `CategoryValue.steps` (targeted edit in `CategoryStyle.swift`)**

Check first: `git diff --stat -- Sources/HealthFeature/UI/CategoryStyle.swift` is empty. In `CategoryValue.text(_:in:)`, replace

```swift
            guard let steps = s.activity?.steps else { return nil }
            return String(
                localized: "ios:health.value.steps", defaultValue: "\(steps) steps",
                comment: "Card value: today's step count.")
```

with

```swift
            guard let steps = s.activity?.steps else { return nil }
            return Self.steps(steps)
```

and after `static func cups(_ n: Int) -> String { … }` add:

```swift

    static func steps(_ n: Int) -> String {
        String(localized: "ios:health.value.steps", defaultValue: "\(n) steps", comment: "Card value: today's step count.")
    }
```

- [ ] **Step 4: Give `ReportStory` an optional eyebrow (targeted edits in `ReportStory.swift`)**

Check first: `git diff --stat -- Sources/HealthFeature/UI/ReportStory.swift` is empty.

Replace

```swift
    let summary: HealthSummary
    private let stories: [(HealthCategory, HealthSummary.Insight)]
```

with

```swift
    let summary: HealthSummary
    private let stories: [(HealthCategory, HealthSummary.Insight)]
    /// "Today" on the home; a past day's sheet names its date.
    private let eyebrow: Text
```

Replace

```swift
    /// Nil when there are no insights this app can draw, so the caller shows the Markdown note instead.
    init?(_ summary: HealthSummary) {
        let stories = ReportText.stories(summary)
        guard !stories.isEmpty else { return nil }
        self.summary = summary
        self.stories = stories
    }
```

with

```swift
    /// Nil when there are no insights this app can draw, so the caller shows the Markdown note instead.
    init?(_ summary: HealthSummary, eyebrow: Text? = nil) {
        let stories = ReportText.stories(summary)
        guard !stories.isEmpty else { return nil }
        self.summary = summary
        self.stories = stories
        self.eyebrow = eyebrow ?? Text("ios:health.report.eyebrow")
    }
```

and in `body` replace `Text("ios:health.report.eyebrow")` with `eyebrow`.

- [ ] **Step 5: Complete `DayToneStyle.swift`**

Replace the whole file (created in Task 5, yours alone) with:

```swift
// Sources/HealthFeature/Trends/DayToneStyle.swift
import OdyKit
import SwiftUI

extension DayTone {
    /// The cell's fill (style C): soft tints on the cream page, deeper ones in Dark Mode; the day's number in primary
    /// ink stays at 4.5:1 or more on each.
    var fill: Color {
        switch self {
        case .good: .adaptive(0xCFEFD8, dark: 0x2F6B54)
        case .tired: .adaptive(0xDDD6FF, dark: 0x4B3F9A)
        case .recovering: .adaptive(0xFFDDBF, dark: 0x8A5A2A)
        case .empty: .adaptive(0xF0EADB, dark: 0x24222C)
        }
    }

    /// What the colour means, for the legend and VoiceOver.
    var name: LocalizedStringResource {
        switch self {
        case .good: LocalizedStringResource("ios:health.calendar.tone.good", defaultValue: "Rested or active", comment: "Calendar day colour and legend: a good day (rested, active or calm).")
        case .tired: LocalizedStringResource("ios:health.calendar.tone.tired", defaultValue: "Short on sleep", comment: "Calendar day colour and legend: a day after too little sleep.")
        case .recovering: LocalizedStringResource("ios:health.calendar.tone.recovering", defaultValue: "Recovering", comment: "Calendar day colour and legend: a day with low recovery (HRV under the usual).")
        case .empty: LocalizedStringResource("ios:health.calendar.tone.empty", defaultValue: "No data", comment: "Calendar day colour and legend: Apple Health has nothing for the day.")
        }
    }
}

/// The ring's two colours: sleep's violet and activity's amber, deep enough to read on every tone's fill.
enum RingInk {
    static let sleep = Color.adaptive(0x6F5FD0, dark: 0xB9A3FF)
    static let steps = Color.adaptive(0xC96A00, dark: 0xF4B63F)
}

/// The corner ring: sleep against the target outside, steps against the goal inside. An arc with no number is only
/// its faint track.
struct CornerRing: View {
    let sleep: Double?
    let steps: Double?
    var lineWidth: CGFloat = 2.5

    var body: some View {
        ZStack {
            arc(sleep, color: RingInk.sleep)
            arc(steps, color: RingInk.steps).padding(lineWidth * 1.6)
        }
        .accessibilityHidden(true)
    }

    private func arc(_ fraction: Double?, color: Color) -> some View {
        ZStack {
            Circle().stroke(color.opacity(0.22), lineWidth: lineWidth)
            if let fraction, fraction > 0 {
                Circle()
                    .trim(from: 0, to: fraction)
                    .stroke(color, style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))
                    .rotationEffect(.degrees(-90))
            }
        }
        .padding(lineWidth / 2)
    }
}
```

- [ ] **Step 6: Write `DaySheet.swift`**

```swift
// Sources/HealthFeature/Trends/DaySheet.swift
import MarkdownKit
import Models
import OdyKit
import SwiftUI

/// A past day up close (spec §3.3): its note as it was written that day — the insight stories, or the Markdown note
/// of an older report — or, with no note, the day's numbers and "No note for this day". The ask box sends the whole
/// day's numbers with the question, so Chat shows them as its health card.
struct DaySheet: View {
    let day: Date
    let record: DayRecord?
    let archived: ArchivedDay?
    /// The workspace's title ("Health"), for the screenshot's name.
    let healthTitle: String
    let calendar: Calendar
    let loadSnapshot: () async -> HealthSnapshot?
    let onAsk: (String) -> Void

    @State private var snapshot: HealthSnapshot?
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    header
                    if let archived {
                        note(archived.summary)
                    } else {
                        Text("ios:health.day.noNote")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(14)
                            .background(HealthSurface.card, in: .rect(cornerRadius: 18))
                        if let record, record.hasData { DayNumbers(record: record) }
                    }
                }
                .padding(.horizontal, 16)
                .padding(.bottom, 24)
            }
            .background(HealthSurface.page)
            .navigationTitle(Text(verbatim: dateText))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("common:action.close") { dismiss() }
                }
            }
            .safeAreaInset(edge: .bottom) {
                AskComposer(
                    suggestions: ["ios:health.day.ask.compare", "ios:health.day.ask.standout"],
                    attachment: { snapshotJSON }, onSend: send)
            }
            .screenTitle(ScreenTitles.join(healthTitle, dateText))
        }
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
        .task { snapshot = await loadSnapshot() }
    }

    private var tone: DayTone { record.map { DayTone($0.mood) } ?? .empty }

    /// "October 1, 2026".
    private var dateText: String {
        day.formatted(Date.FormatStyle(date: .long, time: .omitted, calendar: calendar, timeZone: calendar.timeZone))
    }

    private var header: some View {
        HStack(spacing: 12) {
            OdySceneView(OdyScene(hero: record?.mood ?? .noData))
                .frame(width: 64, height: 64)
                .clipShape(.rect(cornerRadius: 16))
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                Text(verbatim: dateText).font(.headline)
                Text(tone.name).font(.subheadline).foregroundStyle(.secondary)
            }
            Spacer(minLength: 0)
            if record?.hasData == true {
                CornerRing(sleep: record?.sleepFraction, steps: record?.stepFraction, lineWidth: 4)
                    .frame(width: 40, height: 40)
            }
        }
        .padding(.top, 8)
        .accessibilityElement(children: .combine)
    }

    /// The note exactly as that day's home showed it, with the date where "Today" was.
    @ViewBuilder
    private func note(_ summary: HealthSummary) -> some View {
        if let story = ReportStory(summary, eyebrow: Text(verbatim: dateText)) {
            story
        } else {
            VStack(alignment: .leading, spacing: 8) {
                Text(verbatim: summary.headline).font(.headline)
                MarkdownView(text: summary.summary, isStreaming: false)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(14)
            .background(HealthSurface.card, in: .rect(cornerRadius: 18))
        }
    }

    private var snapshotJSON: String? {
        guard let snapshot, let data = try? HealthWire.encoder().encode(snapshot) else { return nil }
        return String(decoding: data, as: UTF8.self)
    }

    /// The question goes to a new chat; the sheet steps out of the way first.
    private func send(_ text: String) {
        dismiss()
        onAsk(text)
    }
}

/// The day's numbers when it has no note: a row each, only the ones the day has.
struct DayNumbers: View {
    struct Row {
        let title: LocalizedStringResource
        let symbol: String
        let value: String
    }

    let record: DayRecord

    var body: some View {
        let rows = Self.rows(record)
        VStack(spacing: 0) {
            ForEach(Array(rows.enumerated()), id: \.offset) { index, row in
                if index > 0 { Divider() }
                LabeledContent {
                    Text(verbatim: row.value).monospacedDigit()
                } label: {
                    Label { Text(row.title) } icon: { Image(systemName: row.symbol) }
                }
                .padding(.vertical, 10)
            }
        }
        .padding(.horizontal, 14)
        .background(HealthSurface.card, in: .rect(cornerRadius: 18))
    }

    static func rows(_ r: DayRecord) -> [Row] {
        var rows: [Row] = []
        if let m = r.sleepMin {
            rows.append(Row(title: CategoryStyle.of(.sleep).title, symbol: "moon.zzz.fill", value: TrendText.duration(Double(m))))
        }
        if let bedtime = r.bedtime {
            rows.append(Row(title: "ios:health.day.bedtime", symbol: "bed.double.fill", value: bedtime))
        }
        if let steps = r.steps {
            rows.append(Row(title: "ios:health.day.steps", symbol: "figure.walk", value: steps.formatted()))
        }
        if let m = r.exerciseMin {
            rows.append(
                Row(
                    title: "ios:health.day.exercise", symbol: "flame.fill",
                    value: Duration.seconds(m * 60).formatted(.units(allowed: [.minutes], width: .abbreviated))))
        }
        if let hrv = r.hrvMs {
            rows.append(Row(title: "ios:health.recovery.hrv", symbol: "waveform.path.ecg", value: TrendText.ms(hrv)))
        }
        if let hr = r.restingHr, hr.isFinite {
            let n = Int(hr.rounded())
            rows.append(
                Row(
                    title: "ios:health.recovery.restingHr", symbol: "heart.fill",
                    value: String(localized: "ios:health.value.bpm", defaultValue: "\(n) bpm", comment: "Card value: resting heart rate.")))
        }
        if let cups = r.waterCups {
            rows.append(Row(title: "ios:health.body.water", symbol: "drop.fill", value: CategoryValue.cups(cups)))
        }
        return rows
    }
}
```

- [ ] **Step 7: Run the tests**

Run: the Step 2 command, then `-only-testing:HealthFeatureTests/ReportStoryTests` and `-only-testing:HealthFeatureTests/CategoryStyleTests`.
Expected: `DaySheetTests` 4 pass; the two existing suites still pass.

- [ ] **Step 8: Audit and commit**

```bash
python3 scripts/l10n.py audit 2>&1 | tail -1
git diff --stat
.superpowers/sdd/commit-mine.sh "feat(health): the day sheet — a past day's note as it was written, or its numbers and 'No note for this day', and a question about that day" \
  Sources/HealthFeature/Trends/DayToneStyle.swift Sources/HealthFeature/Trends/DaySheet.swift \
  Sources/HealthFeature/UI/ReportStory.swift Sources/HealthFeature/UI/CategoryStyle.swift \
  Tests/HealthFeatureTests/DaySheetTests.swift
git show --stat HEAD
```

---

### Task 7: The calendar page

**Files:**
- Create: `Sources/HealthFeature/Trends/DayCellView.swift`
- Create: `Sources/HealthFeature/Trends/TrendStatsHeader.swift`
- Create: `Sources/HealthFeature/Trends/MonthBarsView.swift`
- Create: `Sources/HealthFeature/Trends/TrendsView.swift`
- Modify: `Sources/HealthFeature/UI/HealthHomeView.swift` (the `TrendsRoute` destination)
- Test: `Tests/HealthFeatureTests/DayCellTextTests.swift`

**Interfaces:**
- Consumes: `TrendsModel`, `TrendsRoute`, `TrendScope`, `CalendarCell`, `MonthBar`, `TrendMetric`, `TrendText` (Task 5); `DayTone.fill/name`, `CornerRing`, `RingInk`, `DaySheet`, `CategoryValue.steps` (Task 6); `HealthHomeModel.trends(_:)`, `.calendar`, `.hasConsent` (Task 5); `HealthDetailView.failedText/retryText`, `HealthSurface`, `OdyPalette`, `ScreenTitles`.
- Produces:
  - `struct DayCellView: View { enum Style { compact, large, row }; init(cell: CalendarCell, style: Style, calendar: Calendar) }`.
  - `struct DayCellButton: View { init(cell: CalendarCell, style: DayCellView.Style, calendar: Calendar, onOpen: @escaping (Date) -> Void) }`, `struct PressScale: ButtonStyle`.
  - `enum DayCellText { static func label(_ cell: CalendarCell, calendar: Calendar) -> String }`.
  - `struct TrendStatsHeader: View { init(scope: TrendScope, current: Aggregates?, previous: Aggregates?) }`.
  - `struct MonthBarsView: View { init(bars: [MonthBar], calendar: Calendar, onOpen: @escaping (Period) -> Void) }`.
  - `struct PresentedDay: Identifiable, Equatable { let day: Date }`, `struct TrendsView: View { init(route: TrendsRoute, home: HealthHomeModel, onAsk: @escaping (String) -> Void) }`.
  - `HealthHomeView` navigates `TrendsRoute` values to `TrendsView`.

- [ ] **Step 1: Write the failing tests**

Create `Tests/HealthFeatureTests/DayCellTextTests.swift`:

```swift
import Foundation
import Models
import Testing

@testable import HealthFeature

struct DayCellTextTests {
    let cal = TestClock.calendar

    @Test func aCellReadsItsDayStateAndNumbers() {
        let record = DayRecord(day: TestClock.today, sleepMin: 460, steps: 9120, mood: .rested)
        let cell = CalendarCell(id: 0, day: TestClock.today, record: record, isToday: true, isFuture: false)
        let label = DayCellText.label(cell, calendar: cal)
        let date = TestClock.today.formatted(Date.FormatStyle(calendar: cal, timeZone: cal.timeZone).month(.wide).day())
        #expect(label.hasPrefix(date))
        #expect(label.contains("Today"))
        #expect(label.contains("Rested or active"))
        #expect(label.contains("Sleep " + TrendText.duration(460)))
        #expect(label.contains(CategoryValue.steps(9120)))
    }

    @Test func aDayWithNothingSaysSo() {
        let cell = CalendarCell(id: 0, day: TestClock.today, record: nil, isToday: false, isFuture: false)
        #expect(DayCellText.label(cell, calendar: cal).hasSuffix("No data"))
        #expect(!DayCellText.label(cell, calendar: cal).contains("Today"))
    }
}
```

- [ ] **Step 2: Run them to verify they fail**

Run: `xcodebuild test -workspace ExodusIos.xcworkspace -scheme HealthFeature -destination "id=D8A2BE45-88F3-46AE-8693-B147F2815724" -derivedDataPath /tmp/trends-dd -only-testing:HealthFeatureTests/DayCellTextTests 2>&1 | grep -E "error:|Test run with|TEST (SUCCEEDED|FAILED)"`
Expected: build error `cannot find 'DayCellText' in scope`.

- [ ] **Step 3: Write `DayCellView.swift`**

```swift
// Sources/HealthFeature/Trends/DayCellView.swift
import Models
import OdyKit
import SwiftUI

/// One day of the calendar, style C: the day's state as the cell's colour, sleep and steps as the small ring in its
/// corner, today outlined in marigold. `compact` is a month's square, `large` a week's column with its numbers, `row`
/// a week's line at accessibility text sizes. The numerals are capped so seven cells still fit a row.
struct DayCellView: View {
    enum Style { case compact, large, row }

    let cell: CalendarCell
    let style: Style
    let calendar: Calendar

    var body: some View {
        switch style {
        case .compact: compact
        case .large: large
        case .row: row
        }
    }

    private var fill: Color { cell.isFuture ? DayTone.empty.fill.opacity(0.45) : cell.tone.fill }
    private var number: String { cell.day.map { calendar.component(.day, from: $0).formatted() } ?? "" }
    private var hasNumbers: Bool { cell.record?.hasData == true }
    private var dateStyle: Date.FormatStyle { Date.FormatStyle(calendar: calendar, timeZone: calendar.timeZone) }

    private var compact: some View {
        ZStack(alignment: .topTrailing) {
            RoundedRectangle(cornerRadius: 10).fill(fill)
            Text(verbatim: number)
                .font(.caption.weight(.semibold))
                .monospacedDigit()
                .foregroundStyle(cell.isFuture ? .tertiary : .primary)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            if hasNumbers {
                CornerRing(sleep: cell.record?.sleepFraction, steps: cell.record?.stepFraction, lineWidth: 1.6)
                    .frame(width: 12, height: 12)
                    .padding(3)
            }
        }
        .aspectRatio(1, contentMode: .fit)
        .overlay { todayMark(cornerRadius: 10) }
        .dynamicTypeSize(...DynamicTypeSize.xxLarge)
    }

    private var large: some View {
        VStack(spacing: 6) {
            Text(verbatim: cell.day.map { $0.formatted(dateStyle.weekday(.abbreviated)) } ?? "")
                .font(.caption2.weight(.semibold))
                .foregroundStyle(.secondary)
            Text(verbatim: number)
                .font(.headline)
                .monospacedDigit()
                .foregroundStyle(cell.isFuture ? .tertiary : .primary)
            CornerRing(sleep: cell.record?.sleepFraction, steps: cell.record?.stepFraction, lineWidth: 3)
                .frame(width: 26, height: 26)
                .opacity(hasNumbers ? 1 : 0)
            VStack(spacing: 1) {
                Text(verbatim: cell.record?.sleepMin.map(TrendText.clock) ?? "—")
                Text(verbatim: cell.record?.steps.map(TrendText.compact) ?? "—")
            }
            .font(.caption2.weight(.medium))
            .monospacedDigit()
            .foregroundStyle(.secondary)
            .lineLimit(1)
            .minimumScaleFactor(0.6)
            .opacity(cell.isFuture ? 0 : 1)
        }
        .padding(.vertical, 10)
        .frame(maxWidth: .infinity)
        .background(fill, in: .rect(cornerRadius: 14))
        .overlay { todayMark(cornerRadius: 14) }
        .dynamicTypeSize(...DynamicTypeSize.xxLarge)
    }

    private var row: some View {
        HStack(spacing: 12) {
            RoundedRectangle(cornerRadius: 8)
                .fill(fill)
                .frame(width: 30, height: 30)
                .overlay { todayMark(cornerRadius: 8) }
            VStack(alignment: .leading, spacing: 2) {
                Text(verbatim: cell.day.map { $0.formatted(dateStyle.weekday(.wide).month(.abbreviated).day()) } ?? "")
                    .font(.headline)
                Text(verbatim: values).font(.subheadline).monospacedDigit().foregroundStyle(.secondary)
            }
            Spacer(minLength: 0)
        }
        .padding(12)
        .background(HealthSurface.card, in: .rect(cornerRadius: 14))
        .opacity(cell.isFuture ? 0.5 : 1)
    }

    private var values: String {
        guard let r = cell.record, r.hasData else { return String(localized: DayTone.empty.name) }
        return [r.sleepMin.map { TrendText.duration(Double($0)) }, r.steps.map(CategoryValue.steps)]
            .compactMap { $0 }
            .joined(separator: " · ")
    }

    @ViewBuilder
    private func todayMark(cornerRadius: CGFloat) -> some View {
        if cell.isToday {
            RoundedRectangle(cornerRadius: cornerRadius).strokeBorder(OdyPalette.marigold, lineWidth: 2)
        }
    }
}

/// A day that has begun opens its sheet; a day to come and a month's leading blank are only drawn.
struct DayCellButton: View {
    let cell: CalendarCell
    let style: DayCellView.Style
    let calendar: Calendar
    let onOpen: (Date) -> Void

    var body: some View {
        if let day = cell.day, !cell.isFuture {
            Button { onOpen(day) } label: { DayCellView(cell: cell, style: style, calendar: calendar) }
                .buttonStyle(PressScale())
                .accessibilityLabel(Text(verbatim: DayCellText.label(cell, calendar: calendar)))
        } else if cell.day != nil {
            DayCellView(cell: cell, style: style, calendar: calendar).accessibilityHidden(true)
        } else {
            Color.clear.aspectRatio(1, contentMode: .fit).accessibilityHidden(true)
        }
    }
}

/// A pressed cell gives a little, unless Reduce Motion is on.
struct PressScale: ButtonStyle {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed && !reduceMotion ? 0.94 : 1)
            .animation(.smooth(duration: 0.15), value: configuration.isPressed)
    }
}

/// What VoiceOver reads for a day: "October 1, Today, Rested or active, Sleep 7h 40m, 9,120 steps".
enum DayCellText {
    static func label(_ cell: CalendarCell, calendar: Calendar) -> String {
        guard let day = cell.day else { return "" }
        var parts = [day.formatted(Date.FormatStyle(calendar: calendar, timeZone: calendar.timeZone).month(.wide).day())]
        if cell.isToday {
            parts.append(
                String(localized: "ios:health.calendar.today", defaultValue: "Today", comment: "VoiceOver for a calendar day: this day is today."))
        }
        parts.append(String(localized: cell.tone.name))
        if let m = cell.record?.sleepMin {
            let sleep = TrendText.duration(Double(m))
            parts.append(
                String(
                    localized: "ios:health.calendar.a11y.sleep", defaultValue: "Sleep \(sleep)",
                    comment: "VoiceOver for a calendar day: the night's sleep. %@ is a duration, e.g. 7h 40m."))
        }
        if let steps = cell.record?.steps { parts.append(CategoryValue.steps(steps)) }
        return parts.joined(separator: ", ")
    }
}
```

- [ ] **Step 4: Write `TrendStatsHeader.swift`**

```swift
// Sources/HealthFeature/Trends/TrendStatsHeader.swift
import SwiftUI

/// The three numbers over the calendar: average sleep, daily steps and HRV, each against the period before. Side by
/// side; one under another at accessibility sizes.
struct TrendStatsHeader: View {
    let scope: TrendScope
    let current: Aggregates?
    let previous: Aggregates?
    @Environment(\.dynamicTypeSize) private var typeSize

    var body: some View {
        let layout =
            typeSize.isAccessibilitySize ? AnyLayout(VStackLayout(spacing: 8)) : AnyLayout(HStackLayout(spacing: 8))
        layout {
            ForEach(TrendMetric.allCases, id: \.self) { metric in tile(metric) }
        }
    }

    private func tile(_ metric: TrendMetric) -> some View {
        let value = current.flatMap(metric.value)
        let change = TrendMath.change(value, from: previous.flatMap(metric.value))
        return VStack(alignment: .leading, spacing: 3) {
            Text(metric.title).font(.caption.weight(.semibold)).foregroundStyle(.secondary).lineLimit(2)
            Text(verbatim: value.map(metric.format) ?? "—")
                .font(.title3.weight(.heavy))
                .monospacedDigit()
                .lineLimit(1)
                .minimumScaleFactor(0.7)
                .contentTransition(.numericText())
            Text(verbatim: TrendText.delta(change, metric: metric))
                .font(.caption.weight(.semibold))
                .foregroundStyle(TrendText.color(change))
            Text(scope.versusLabel).font(.caption2).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(10)
        .background(HealthSurface.card, in: .rect(cornerRadius: 14))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(verbatim: TrendText.spoken(metric: metric, value: value, change: change, scope: scope)))
    }
}
```

- [ ] **Step 5: Write `MonthBarsView.swift`**

```swift
// Sources/HealthFeature/Trends/MonthBarsView.swift
import SwiftUI

/// A quarter's or a year's months, a bar each: average sleep against the target, daily steps beside it. Tap a month
/// that has begun to open it.
struct MonthBarsView: View {
    let bars: [MonthBar]
    let calendar: Calendar
    let onOpen: (Period) -> Void
    @Environment(\.dynamicTypeSize) private var typeSize

    var body: some View {
        VStack(spacing: 6) {
            ForEach(bars) { bar in
                Button { onOpen(bar.month) } label: { row(bar) }
                    .buttonStyle(PressScale())
                    .disabled(bar.isFuture)
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel(Text(verbatim: spoken(bar)))
            }
        }
    }

    private func row(_ bar: MonthBar) -> some View {
        let layout =
            typeSize.isAccessibilitySize
            ? AnyLayout(VStackLayout(alignment: .leading, spacing: 6)) : AnyLayout(HStackLayout(spacing: 10))
        return layout {
            Text(verbatim: name(bar, width: .abbreviated))
                .font(.subheadline.weight(.semibold))
                .frame(minWidth: 44, alignment: .leading)
            sleepBar(bar.aggregates.sleepMin.average)
            Text(verbatim: values(bar)).font(.caption).monospacedDigit().foregroundStyle(.secondary).lineLimit(1)
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(HealthSurface.card, in: .rect(cornerRadius: 12))
        .opacity(bar.isFuture ? 0.45 : 1)
    }

    private func sleepBar(_ minutes: Double?) -> some View {
        GeometryReader { g in
            ZStack(alignment: .leading) {
                Capsule().fill(RingInk.sleep.opacity(0.18))
                Capsule()
                    .fill(RingInk.sleep)
                    .frame(width: g.size.width * min((minutes ?? 0) / Double(TrendMath.sleepTargetMin), 1))
            }
        }
        .frame(height: 8)
        .frame(maxWidth: .infinity)
    }

    private func name(_ bar: MonthBar, width: Date.FormatStyle.Symbol.Month) -> String {
        bar.month.start.formatted(Date.FormatStyle(calendar: calendar, timeZone: calendar.timeZone).month(width))
    }

    /// "7h 12m · 8.1K", or "—" for a month with nothing in it.
    private func values(_ bar: MonthBar) -> String {
        let a = bar.aggregates
        let parts = [
            a.sleepMin.average.map(TrendText.duration), a.steps.average.map { TrendText.compact(Int($0.rounded())) },
        ].compactMap { $0 }
        return parts.isEmpty ? "—" : parts.joined(separator: " · ")
    }

    private func spoken(_ bar: MonthBar) -> String {
        let a = bar.aggregates
        var parts = [name(bar, width: .wide)]
        if let sleep = a.sleepMin.average {
            parts += [String(localized: TrendMetric.sleep.title), TrendText.duration(sleep)]
        }
        if let steps = a.steps.average {
            parts += [String(localized: TrendMetric.steps.title), TrendText.steps(steps)]
        }
        if parts.count == 1 { parts.append(String(localized: DayTone.empty.name)) }
        return parts.joined(separator: ", ")
    }
}
```

- [ ] **Step 6: Write `TrendsView.swift`**

```swift
// Sources/HealthFeature/Trends/TrendsView.swift
import Models
import OdyKit
import SwiftUI

/// A day the calendar opened a sheet for.
struct PresentedDay: Identifiable, Equatable {
    let day: Date
    var id: Date { day }
}

/// The calendar (spec §3.2): Week · Month · Quarter · Year, paged with ‹ ›; average sleep, daily steps and HRV
/// against the period before; the days as style-C cells, or for a quarter or a year a bar per month. A day opens its
/// sheet, a month bar opens that month. Each page turn slides in from its side (a cross-fade under Reduce Motion) with
/// a selection tick.
struct TrendsView: View {
    @State private var trends: TrendsModel
    @State private var presented: PresentedDay?
    /// Which way the last page turned, so the new one comes in from that side.
    @State private var forward = true
    let onAsk: (String) -> Void
    /// The workspace's ("Health"): a screenshot of this page is "Health · October 2026".
    @Environment(\.screenTitle) private var enclosingTitle
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.dynamicTypeSize) private var typeSize

    init(route: TrendsRoute, home: HealthHomeModel, onAsk: @escaping (String) -> Void) {
        _trends = State(initialValue: home.trends(route))
        _presented = State(initialValue: route.presentedDay.map { PresentedDay(day: home.calendar.startOfDay(for: $0)) })
        self.onAsk = onAsk
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                Picker(selection: scope) {
                    ForEach(TrendScope.allCases, id: \.self) { s in Text(s.label).tag(s) }
                } label: {
                    Text("ios:health.calendar.scope")
                }
                .pickerStyle(.segmented)
                periodRow
                TrendStatsHeader(scope: trends.scope, current: trends.current, previous: trends.previous)
                    .redacted(reason: trends.current == nil ? .placeholder : [])
                Group {
                    if trends.phase == .failed, trends.records.isEmpty {
                        failedNote
                    } else {
                        VStack(alignment: .leading, spacing: 10) {
                            if trends.phase == .ready, trends.current?.daysWithData == 0 {
                                note(Text("ios:health.calendar.empty"))
                            }
                            periodBody
                        }
                    }
                }
                .id(trends.period)
                .transition(pageTransition)
                legend
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 24)
        }
        .background(HealthSurface.page)
        .navigationTitle(Text("ios:health.calendar.title"))
        .navigationBarTitleDisplayMode(.inline)
        .screenTitle(ScreenTitles.join(enclosingTitle, trends.title))
        .sensoryFeedback(.selection, trigger: trends.period)
        .task(id: trends.period) { await trends.load() }
        .sheet(item: $presented) { p in
            DaySheet(
                day: p.day, record: trends.records[p.day], archived: trends.archived(p.day), healthTitle: enclosingTitle,
                calendar: trends.calendar,
                loadSnapshot: { await trends.snapshot(for: p.day) }, onAsk: onAsk)
        }
    }

    // MARK: Paging

    private var motion: Animation { reduceMotion ? .easeInOut(duration: 0.2) : .smooth(duration: 0.35) }

    private var pageTransition: AnyTransition {
        reduceMotion
            ? .opacity
            : .asymmetric(
                insertion: .move(edge: forward ? .trailing : .leading).combined(with: .opacity), removal: .opacity)
    }

    private var scope: Binding<TrendScope> {
        Binding(
            get: { trends.scope },
            set: { s in
                forward = true
                withAnimation(motion) { trends.select(s) }
            })
    }

    private func turn(forward: Bool) {
        self.forward = forward
        withAnimation(motion) {
            if forward { trends.showNext() } else { trends.showPrevious() }
        }
    }

    private var periodRow: some View {
        HStack(alignment: .center) {
            VStack(alignment: .leading, spacing: 2) {
                Text(verbatim: trends.title).font(.title3.weight(.bold))
                if trends.scope == .week {
                    Text(verbatim: TrendText.range(trends.period, calendar: trends.calendar))
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
            }
            .accessibilityElement(children: .combine)
            .accessibilityAddTraits(.isHeader)
            Spacer(minLength: 8)
            Button { turn(forward: false) } label: {
                Image(systemName: "chevron.left").font(.body.weight(.semibold)).frame(width: 44, height: 44)
            }
            .accessibilityLabel(Text("ios:health.calendar.previous"))
            Button { turn(forward: true) } label: {
                Image(systemName: "chevron.right").font(.body.weight(.semibold)).frame(width: 44, height: 44)
            }
            .accessibilityLabel(Text("ios:health.calendar.next"))
            .disabled(!trends.canGoForward)
        }
        .tint(.primary)
    }

    // MARK: The period

    @ViewBuilder
    private var periodBody: some View {
        switch trends.scope {
        case .week: weekDays
        case .month: monthGrid
        case .quarter, .year:
            MonthBarsView(bars: trends.months, calendar: trends.calendar) { month in
                forward = true
                withAnimation(motion) { trends.open(month: month) }
            }
        }
    }

    @ViewBuilder
    private var weekDays: some View {
        if typeSize.isAccessibilitySize {
            VStack(spacing: 6) {
                ForEach(trends.cells) { cell in
                    DayCellButton(cell: cell, style: .row, calendar: trends.calendar, onOpen: open)
                }
            }
        } else {
            HStack(spacing: 6) {
                ForEach(trends.cells) { cell in
                    DayCellButton(cell: cell, style: .large, calendar: trends.calendar, onOpen: open)
                }
            }
        }
    }

    private var monthGrid: some View {
        LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 6), count: 7), spacing: 6) {
            ForEach(Array(TrendText.weekdayInitials(calendar: trends.calendar).enumerated()), id: \.offset) { _, s in
                Text(verbatim: s)
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .dynamicTypeSize(...DynamicTypeSize.xxLarge)
                    .accessibilityHidden(true)
            }
            ForEach(trends.cells) { cell in
                DayCellButton(cell: cell, style: .compact, calendar: trends.calendar, onOpen: open)
            }
        }
    }

    private func open(_ day: Date) { presented = PresentedDay(day: day) }

    // MARK: Around it

    private var legend: some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: 12) { legendItems }
            VStack(alignment: .leading, spacing: 6) { legendItems }
        }
        .font(.caption2)
        .foregroundStyle(.secondary)
        .accessibilityElement(children: .combine)
    }

    @ViewBuilder
    private var legendItems: some View {
        ForEach([DayTone.good, .tired, .recovering], id: \.self) { tone in
            HStack(spacing: 4) {
                RoundedRectangle(cornerRadius: 3).fill(tone.fill).frame(width: 10, height: 10)
                Text(tone.name)
            }
        }
        HStack(spacing: 4) {
            CornerRing(sleep: 0.75, steps: 0.5, lineWidth: 1.6).frame(width: 12, height: 12)
            Text("ios:health.calendar.legend.ring")
        }
    }

    private func note(_ text: Text) -> some View {
        text.font(.subheadline)
            .foregroundStyle(.secondary)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(14)
            .background(HealthSurface.card, in: .rect(cornerRadius: 18))
    }

    private var failedNote: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(HealthDetailView.failedText).font(.subheadline).foregroundStyle(.secondary)
            Button { Task { await trends.load() } } label: { Text(HealthDetailView.retryText) }
                .buttonStyle(.bordered)
                .buttonBorderShape(.capsule)
                .tint(OdyPalette.marigold)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .background(HealthSurface.card, in: .rect(cornerRadius: 18))
    }
}
```

- [ ] **Step 7: Route `TrendsRoute` from the home (targeted edit in `HealthHomeView.swift`)**

Check first: `git diff --stat -- Sources/HealthFeature/UI/HealthHomeView.swift` is empty. Replace

```swift
        .navigationDestination(for: HealthCategory.self) { c in
            HealthDetailView(category: c, model: model, onAsk: onAsk)
                .navigationTransition(.zoom(sourceID: c, in: zoom))
        }
```

with

```swift
        .navigationDestination(for: HealthCategory.self) { c in
            HealthDetailView(category: c, model: model, onAsk: onAsk)
                .navigationTransition(.zoom(sourceID: c, in: zoom))
        }
        .navigationDestination(for: TrendsRoute.self) { route in
            TrendsView(route: route, home: model, onAsk: onAsk)
        }
```

- [ ] **Step 8: Run the tests and build the app**

```bash
xcodebuild test -workspace ExodusIos.xcworkspace -scheme HealthFeature -destination "id=D8A2BE45-88F3-46AE-8693-B147F2815724" -derivedDataPath /tmp/trends-dd 2>&1 | grep -E "error:|✘|Test run with|TEST (SUCCEEDED|FAILED)"
xcodebuild build -workspace ExodusIos.xcworkspace -scheme App -destination "id=D8A2BE45-88F3-46AE-8693-B147F2815724" -derivedDataPath /tmp/trends-dd 2>&1 | grep -E "error:|BUILD (SUCCEEDED|FAILED)"
```
Expected: all Health tests pass (incl. `DayCellTextTests` 2); `** BUILD SUCCEEDED **`. (The page is reachable from Task 8's card and Task 9's gallery; it is looked at there.)

- [ ] **Step 9: Audit and commit**

```bash
python3 scripts/l10n.py audit 2>&1 | tail -1
git diff --stat
.superpowers/sdd/commit-mine.sh "feat(health): the calendar — week, month, quarter and year of style-C days, three averages against the period before, a day's sheet a tap away" \
  Sources/HealthFeature/Trends/DayCellView.swift Sources/HealthFeature/Trends/TrendStatsHeader.swift \
  Sources/HealthFeature/Trends/MonthBarsView.swift Sources/HealthFeature/Trends/TrendsView.swift \
  Sources/HealthFeature/UI/HealthHomeView.swift Tests/HealthFeatureTests/DayCellTextTests.swift
git show --stat HEAD
```

---

### Task 8: The home's "This week" card and "Clear archive"

**Files:**
- Create: `Sources/HealthFeature/Trends/WeekCard.swift`
- Modify: `Sources/HealthFeature/UI/HealthHomeView.swift` (the card under the note)
- Modify: `Sources/HealthFeature/HealthRootView.swift` (menu item, confirmation, haptic)

**Interfaces:**
- Consumes: `WeekGlance`, `TrendMetric`, `TrendText`, `TrendsRoute` (Task 5); `DayCellView` (Task 7); `HealthHomeModel.week`, `.calendar`, `.clearArchive()` (Task 5).
- Produces: `struct WeekCard: View { init(week: WeekGlance, calendar: Calendar) }`; the home shows it under today's note and pushes `TrendsRoute(scope: .week, anchor: week.period.start)`; the Health menu has "Clear archive" behind a confirmation.

- [ ] **Step 1: Write `WeekCard.swift`**

```swift
// Sources/HealthFeature/Trends/WeekCard.swift
import SwiftUI

/// This week on the home (spec §3.1): seven style-C days, Monday first, and average sleep and daily steps against
/// last week. The whole card opens the calendar on this week.
struct WeekCard: View {
    let week: WeekGlance
    let calendar: Calendar
    @Environment(\.dynamicTypeSize) private var typeSize

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("ios:health.week.title").font(.headline)
                Spacer()
                HStack(spacing: 2) {
                    Text("ios:health.calendar.title")
                    Image(systemName: "chevron.right")
                }
                .font(.footnote.weight(.semibold))
                .foregroundStyle(.secondary)
                .accessibilityHidden(true)
            }
            HStack(spacing: 6) {
                ForEach(week.cells) { cell in DayCellView(cell: cell, style: .compact, calendar: calendar) }
            }
            .accessibilityHidden(true)
            let layout =
                typeSize.isAccessibilitySize
                ? AnyLayout(VStackLayout(alignment: .leading, spacing: 8)) : AnyLayout(HStackLayout(spacing: 16))
            layout {
                stat(.sleep)
                stat(.steps)
            }
        }
        .padding(14)
        .background(HealthSurface.card, in: .rect(cornerRadius: 18))
        .contentShape(.rect(cornerRadius: 18))
        .accessibilityElement(children: .combine)
        .accessibilityHint(Text("ios:health.calendar.title"))
    }

    private func stat(_ metric: TrendMetric) -> some View {
        let value = metric.value(week.current)
        let change = TrendMath.change(value, from: metric.value(week.previous))
        return VStack(alignment: .leading, spacing: 2) {
            Text(metric.title).font(.caption).foregroundStyle(.secondary)
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text(verbatim: value.map(metric.format) ?? "—").font(.title3.weight(.heavy)).monospacedDigit()
                Text(verbatim: TrendText.delta(change, metric: metric))
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(TrendText.color(change))
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(verbatim: TrendText.spoken(metric: metric, value: value, change: change, scope: .week)))
    }
}
```

- [ ] **Step 2: Put the card under today's note (targeted edit in `HealthHomeView.swift`)**

Replace

```swift
                ReportCard(report: model.report) { Task { await model.grantConsent() } }
                if let snapshot = model.day?.snapshot {
```

with

```swift
                ReportCard(report: model.report) { Task { await model.grantConsent() } }
                // Trends are local: shown without a note or consent, hidden only until Health access is asked.
                if let week = model.week, model.day?.snapshot.odyState != .permission {
                    NavigationLink(value: TrendsRoute(scope: .week, anchor: week.period.start)) {
                        WeekCard(week: week, calendar: model.calendar)
                    }
                    .buttonStyle(.plain)
                }
                if let snapshot = model.day?.snapshot {
```

- [ ] **Step 3: Add "Clear archive" to the Health menu (targeted edits in `HealthRootView.swift`)**

Check first: `git diff --stat -- Sources/HealthFeature/HealthRootView.swift` is empty.

Edit 1 — after `@Environment(\.scenePhase) private var scenePhase` add:

```swift
    @State private var confirmClear = false
    /// Bumped when the archive was cleared: the success tap.
    @State private var cleared = 0
```

Edit 2 — replace

```swift
                    if !model.needsOnboarding {
                        Toggle(isOn: notesBinding) {
                            Label(Self.notesText, systemImage: "text.bubble")
                        }
                    }
```

with

```swift
                    if !model.needsOnboarding {
                        Toggle(isOn: notesBinding) {
                            Label(Self.notesText, systemImage: "text.bubble")
                        }
                        Button(role: .destructive) {
                            confirmClear = true
                        } label: {
                            Label(Self.clearArchiveText, systemImage: "trash")
                        }
                    }
```

Edit 3 — replace

```swift
                .accessibilityIdentifier("healthMenu")
            }
        }
    }
```

with

```swift
                .accessibilityIdentifier("healthMenu")
            }
        }
        .alert(Text(Self.clearTitleText), isPresented: $confirmClear) {
            Button(role: .destructive) {
                if model.clearArchive() { cleared += 1 }
            } label: {
                Text(Self.clearArchiveText)
            }
            Button("common:action.cancel", role: .cancel) {}
        } message: {
            Text(Self.clearMessageText)
        }
        .sensoryFeedback(.success, trigger: cleared)
    }
```

Edit 4 — after `private static let menuText = …` add:

```swift
    private static let clearArchiveText = LocalizedStringResource(
        "ios:health.archive.clear", defaultValue: "Clear archive",
        comment: "Health menu, and its confirmation's button: delete every daily note kept on this iPhone.")
    private static let clearTitleText = LocalizedStringResource(
        "ios:health.archive.confirmTitle", defaultValue: "Clear the archive?",
        comment: "Confirmation title before deleting every kept daily note.")
    private static let clearMessageText = LocalizedStringResource(
        "ios:health.archive.confirmMessage",
        defaultValue: "This deletes every daily note kept on this iPhone. Today's note and your health data stay.",
        comment: "Confirmation message before deleting every kept daily note.")
```

- [ ] **Step 4: Build, run the Health tests, and look at it**

```bash
xcodebuild test -workspace ExodusIos.xcworkspace -scheme HealthFeature -destination "id=D8A2BE45-88F3-46AE-8693-B147F2815724" -derivedDataPath /tmp/trends-dd 2>&1 | grep -E "error:|✘|Test run with|TEST (SUCCEEDED|FAILED)"
xcodebuild build -workspace ExodusIos.xcworkspace -scheme App -destination "id=D8A2BE45-88F3-46AE-8693-B147F2815724" -derivedDataPath /tmp/trends-dd 2>&1 | grep -E "error:|BUILD (SUCCEEDED|FAILED)"
xcrun simctl install D8A2BE45-88F3-46AE-8693-B147F2815724 /tmp/trends-dd/Build/Products/Debug-iphonesimulator/Exodus.app
xcrun simctl launch D8A2BE45-88F3-46AE-8693-B147F2815724 app.yancey.exodus.exodus-ios -HealthGallery ready -HealthGalleryAnchor center
mkdir -p .superpowers/trends && xcrun simctl io D8A2BE45-88F3-46AE-8693-B147F2815724 screenshot .superpowers/trends/home-week.png
```
Expected: tests pass; build succeeds; read `.superpowers/trends/home-week.png` — the "This week" card sits under the note: title and "Calendar ›", seven coloured cells Mon–Sun (today outlined in marigold, days to come pale), "Avg. sleep" and "Daily steps" with arrows. Fix what differs before committing.

- [ ] **Step 5: Audit and commit**

```bash
python3 scripts/l10n.py audit 2>&1 | tail -1
git diff --stat
.superpowers/sdd/commit-mine.sh "feat(health): 'This week' on the home opens the calendar; 'Clear archive' in the Health menu, behind a confirmation" \
  Sources/HealthFeature/Trends/WeekCard.swift Sources/HealthFeature/UI/HealthHomeView.swift \
  Sources/HealthFeature/HealthRootView.swift
git show --stat HEAD
```

---

### Task 9: Gallery states, screenshots, device checklist, README

**Files:**
- Modify: `Sources/HealthFeature/Debug/HealthPreviewSource.swift`
- Modify: `Sources/App/HealthGallery.swift`
- Modify: `docs/health-device-checklist.md`
- Modify: `README.md` (the `HealthFeature` module bullet)

**Interfaces:**
- Consumes: `TrendsRoute`, `TrendScope` (Task 5); `HealthArchive`, `ArchivedDay`, `ReportCache.archive` (Task 2); `PreviewSummaryService.sample`; `WireDate`.
- Produces: `-HealthGallery calendar-week | calendar-month | calendar-quarter | calendar-year | day-note | day-empty`; `HealthArchive.writePreview(day:calendar:)` (DEBUG).

- [ ] **Step 1: Give the preview data a year and some recovering days (targeted edits in `HealthPreviewSource.swift`)**

Check first: `git diff --stat -- Sources/HealthFeature/Debug/HealthPreviewSource.swift` is empty.

In `sleepSamples`, replace `return (0..<31).flatMap { offset -> [SleepSample] in` with `return (0..<400).flatMap { offset -> [SleepSample] in`, and the doc comment `/// A believable month in memory, …` with `/// A believable year in memory, for the gallery and previews: sleep with stages each night, steps, heart, water.`

In `dailyAverages`, replace `case .hrv: o == 0 ? 38 : Double(42 + o % 5)` with:

```swift
            // Every ninth day well under the usual, so the calendar has recovering days.
            case .hrv: o == 0 ? 38 : (o % 9 == 4 ? 34 : Double(42 + o % 5))
```

At the end of the file, before the closing `#endif`, add:

```swift

extension HealthArchive {
    /// The gallery's kept note: the sample note, filed under `day`.
    public func writePreview(day: Date, calendar: Calendar = .current) throws {
        let snapshot = HealthSnapshot(
            date: WireDate(timeZone: calendar.timeZone).day(day), localTime: "08:30", locale: "en", sleep: nil,
            activity: nil, recovery: nil, body: nil, odyState: .tired)
        try write(ArchivedDay(snapshot: snapshot, summary: PreviewSummaryService.sample, generatedAt: day))
    }
}
```

- [ ] **Step 2: Add the gallery states (`Sources/App/HealthGallery.swift`, a file with no foreign edits — check `git diff --stat -- Sources/App/HealthGallery.swift` is empty)**

Replace the doc comment of `HealthGalleryLaunch` with:

```swift
/// DEBUG-only visual check of Health: `-HealthGallery <state>` opens the workspace on preview data with the report in
/// `<state>` (`ready` default, `writing`, `offline`, `needsModel`, `failed`, `consent`, `onboarding`), or opens the
/// calendar over it: `calendar-week`, `calendar-month`, `calendar-quarter`, `calendar-year`, and `day-note` /
/// `day-empty` (the month with yesterday's sheet up, which has a kept note, or the sheet of three days ago, which has
/// none). Add `-HealthGalleryAnchor center|bottom` to open the home scrolled down, for a screenshot of the note below
/// the hero.
```

Replace `struct HealthGalleryView` whole with:

```swift
struct HealthGalleryView: View {
    /// Made once: the model mirrors the preferences when it is created, so they are set first.
    @State private var model = Self.makeModel()
    @State private var path = NavigationPath(Self.routes())

    var body: some View {
        NavigationStack(path: $path) { HealthRootView.gallery(model: model) }
            .defaultScrollAnchor(HealthGalleryLaunch.anchor)
    }

    private static func routes() -> [TrendsRoute] {
        let now = Date()
        let cal = Calendar.current
        switch HealthGalleryLaunch.state {
        case "calendar-week": return [TrendsRoute(scope: .week, anchor: now)]
        case "calendar-month": return [TrendsRoute(scope: .month, anchor: now)]
        case "calendar-quarter": return [TrendsRoute(scope: .quarter, anchor: now)]
        case "calendar-year": return [TrendsRoute(scope: .year, anchor: now)]
        case "day-note":
            return [TrendsRoute(scope: .month, anchor: now, presentedDay: cal.date(byAdding: .day, value: -1, to: now))]
        case "day-empty":
            return [TrendsRoute(scope: .month, anchor: now, presentedDay: cal.date(byAdding: .day, value: -3, to: now))]
        default: return []
        }
    }

    private static func makeModel() -> HealthHomeModel {
        let suite = "health-gallery"
        let defaults = UserDefaults(suiteName: suite)!
        defaults.removePersistentDomain(forName: suite)
        let prefs = HealthPreferences(defaults: defaults)
        prefs.hasOnboarded = HealthGalleryLaunch.state != "onboarding"
        prefs.summaryConsent = HealthGalleryLaunch.state != "consent"
        let report: HealthHomeModel.Report =
            switch HealthGalleryLaunch.state {
            case "writing": .writing
            case "offline": .offline
            case "needsModel": .needsModel
            case "failed": .failed
            default: .ready(PreviewSummaryService.sample)
            }
        let cache = ReportCache(directory: FileManager.default.temporaryDirectory.appending(path: UUID().uuidString))
        // Yesterday has a kept note; the days before it have none.
        if let yesterday = Calendar.current.date(byAdding: .day, value: -1, to: Date()) {
            try? cache.archive.writePreview(day: yesterday)
        }
        return HealthHomeModel(
            source: HealthPreviewSource(), summaries: PreviewSummaryService(report: report),
            memory: PreviewMemoryWriter(), cache: cache, preferences: prefs,
            locale: Bundle.main.preferredLocalizations.first ?? "en")
    }
}
```

- [ ] **Step 3: Build, install, and take the screenshots**

Write `/tmp/trends-shots.sh`:

```bash
#!/bin/bash
# Light, dark and AX screenshots of every phase-1 gallery state. Run from the repo root.
set -euo pipefail
SIM=D8A2BE45-88F3-46AE-8693-B147F2815724
APP=app.yancey.exodus.exodus-ios
OUT=.superpowers/trends
mkdir -p "$OUT"
shoot() {
  local name=$1; shift
  xcrun simctl terminate "$SIM" "$APP" 2>/dev/null || true
  xcrun simctl launch "$SIM" "$APP" "$@" >/dev/null
  sleep 4
  xcrun simctl io "$SIM" screenshot "$OUT/$name.png" >/dev/null
}
STATES="calendar-week calendar-month calendar-quarter calendar-year day-note day-empty"
for s in $STATES; do shoot "light-$s" -HealthGallery "$s"; done
shoot light-home-week -HealthGallery ready -HealthGalleryAnchor center
xcrun simctl ui "$SIM" appearance dark
for s in $STATES; do shoot "dark-$s" -HealthGallery "$s"; done
shoot dark-home-week -HealthGallery ready -HealthGalleryAnchor center
xcrun simctl ui "$SIM" appearance light
xcrun simctl ui "$SIM" content_size accessibility-extra-extra-extra-large
for s in calendar-week calendar-month calendar-year day-empty; do shoot "ax-$s" -HealthGallery "$s"; done
shoot ax-home-week -HealthGallery ready -HealthGalleryAnchor center
xcrun simctl ui "$SIM" content_size large
echo done
```

```bash
xcodebuild build -workspace ExodusIos.xcworkspace -scheme App -destination "id=D8A2BE45-88F3-46AE-8693-B147F2815724" -derivedDataPath /tmp/trends-dd 2>&1 | grep -E "error:|BUILD (SUCCEEDED|FAILED)"
xcrun simctl install D8A2BE45-88F3-46AE-8693-B147F2815724 /tmp/trends-dd/Build/Products/Debug-iphonesimulator/Exodus.app
bash /tmp/trends-shots.sh
```

Expected: `** BUILD SUCCEEDED **`, `done`. Read every PNG in `.superpowers/trends/` and check against the prototype (cell style C) and spec §3:
- `calendar-month`: segmented control on Month; "October 2026" with ‹ › (› disabled); three stat tiles with arrows and "vs last month"; Mon-first weekday initials; three blanks before Thursday 1st (in October 2026; whatever the current month, blanks up to its first weekday); tinted cells with corner rings; today outlined in marigold; days to come pale and ring-less; legend below.
- `calendar-week`: "Week N", the date range under it, seven tall columns with weekday, number, ring, "7:40" and "9.1K".
- `calendar-quarter` / `calendar-year`: a bar per month, months to come faded.
- `day-note`: a sheet with yesterday's date, Ody, the insight stories with the date as eyebrow, the ask box with suggestions.
- `day-empty`: "No note for this day" and the numbers card (sleep, bedtime, steps, exercise, HRV, resting heart rate, water).
- `home-week`: the card under the note.
- Dark: every fill is a deep tint, numbers readable. AX: month grid still 7 columns (numbers capped), week as rows, stat tiles stacked, home card stats stacked.
Fix mismatches before committing (re-run the script after a fix).

- [ ] **Step 4: Extend the device checklist**

Append to `docs/health-device-checklist.md`:

```markdown

## Calendar and archive (trends phase 1)

- [ ] The home's "This week" card shows Monday–Sunday, today outlined, days to come pale; tapping it opens the calendar on this week.
- [ ] Week · Month · Quarter · Year switch with a selection tick; ‹ › slide the page in from its side with a tick; › is disabled on the current period; with Reduce Motion the page cross-fades and cells don't shrink when pressed.
- [ ] On a phone with a year of Apple Watch sleep, the Year view appears within about a second, and paging back and forth through months reads instantly the second time.
- [ ] Today's cell and the home card pick up new steps after a walk (leave Health and come back).
- [ ] Tap a past day with a note: the sheet shows that day's note as it was (its date where "Today" was). Tap a day before the archive began: its numbers and "No note for this day".
- [ ] In a day sheet, ask a question with the day attached: a new chat opens with the health card showing that day's numbers and the date.
- [ ] VoiceOver on a month cell reads like "October 1, Rested or active, Sleep 7h 40m, 9,120 steps"; the header tiles read "Avg. sleep, 7h 12m, Up 20m, vs last week".
- [ ] Largest accessibility text size: the month grid keeps seven columns; the week becomes rows; the stat tiles and the home card's numbers stack.
- [ ] Turn off "Write daily notes": today's note goes, past notes still open from the calendar.
- [ ] Health menu → Clear archive → confirm: success tap; past days now say "No note for this day"; today's note is still on the home.
- [ ] Lock the phone while Health is open, unlock: the calendar and today's note load without errors (the archive's files are protected while locked).
- [ ] Change the iPhone's region to United States (weeks start Sunday): the calendar still runs Monday–Sunday and the week number is unchanged.
```

- [ ] **Step 5: Update the README's HealthFeature bullet**

In `README.md`, replace

```markdown
- `HealthFeature`: the Health workspace — reads Apple Health through `HealthDataSource`, builds the day's snapshot,
  asks the computer for a daily note (`POST /api/v1/health/summary`), and hands questions to Chat with the numbers
  attached. Design: [spec](docs/superpowers/specs/2026-10-01-health-workspace-design.md).
```

with

```markdown
- `HealthFeature`: the Health workspace — reads Apple Health through `HealthDataSource`, builds the day's snapshot,
  asks the computer for a daily note (`POST /api/v1/health/summary`), and hands questions to Chat with the numbers
  attached. Every note is kept on the phone by day (`HealthArchive`: `Application Support/Health/archive`, complete
  file protection, never backed up), and a calendar shows any past day and the trend by week, month, quarter and
  year (`DayRecord`, `TrendMath`, `TrendsView`); `-HealthGallery calendar-month` (and `-week`, `-quarter`, `-year`,
  `day-note`, `day-empty`) opens it on preview data. Design: [spec](docs/superpowers/specs/2026-10-01-health-workspace-design.md),
  [trends spec](docs/superpowers/specs/2026-10-02-health-trends-design.md).
```

- [ ] **Step 6: Final checks and commit**

```bash
xcodebuild test -workspace ExodusIos.xcworkspace -scheme HealthFeature -destination "id=D8A2BE45-88F3-46AE-8693-B147F2815724" -derivedDataPath /tmp/trends-dd 2>&1 | grep -E "error:|✘|Test run with|TEST (SUCCEEDED|FAILED)"
python3 scripts/l10n.py audit 2>&1 | tail -1     # 0 error(s); none of the 38 new keys is unreferenced any more
grep -c "ios:health.calendar\|ios:health.day\|ios:health.week\|ios:health.archive" <(python3 scripts/l10n.py audit 2>&1 | grep "not referenced") || true   # 0
git diff --stat
.superpowers/sdd/commit-mine.sh "feat(health): calendar and day-sheet gallery states, a year of preview data, device checklist and README" \
  Sources/HealthFeature/Debug/HealthPreviewSource.swift Sources/App/HealthGallery.swift \
  docs/health-device-checklist.md README.md
git show --stat HEAD
```
Expected: every Health test passes; audit `0 error(s)`; the grep prints `0`; the commit lists exactly the four files.

---

## Self-Review

**Spec coverage (phase 1):**
- §2.1 archive by day, overwrite, protection, backup exclusion, revoke keeps archive, Clear archive with confirmation, corrupt = no note → Tasks 2, 5 (`clearArchive`), 8 (menu, alert).
- §2.2 `DayRecord` for any past day by generalising `SnapshotBuilder` with the same Ody rules; in-memory cache, today never cached → Tasks 1, 3.
- §2.3 `TrendMath`: periods (ISO week, month, quarter, year, N days), averages, min/max, hit rates, days with data, change vs previous period with 3 % flat → Task 1; used by home card, calendar header and bars → Tasks 5, 7, 8.
- §3.1 home "This week" card (seven style-C cells, sleep and steps with ↑/↓, tap → week view) → Tasks 5, 8. The "report ready" line is phase 2.
- §3.2 calendar page: segmented Week · Month · Quarter · Year, ‹ ›, future days empty, three stats with change, month grid, week large cells, quarter/year month bars with tap → month, screen titles "Health · October 2026" / "Health · Week 40" → Tasks 5, 7. The report card is phase 2.
- §3.3 day sheet: archived insight stories as on that day's home; numbers + "No note for this day"; ask with the day attached → Task 6.
- §3.6 light/dark, Dynamic Type to AX sizes, VoiceOver labels for cells, ten languages, Reduce Motion → Tasks 4, 6, 7, 8, 9.
- §6 sparse data shows "—" without a previous period; corrupt archive file is no note → Tasks 1, 2, 5, 7.
- §7 tests for TrendMath (boundaries, leap year, DST), HealthArchive (write/read/overwrite/corrupt/clear), DayRecord builder with a fake source; gallery states; screenshots light/dark/AX; checklist → Tasks 1–3, 9.

**Type consistency:** `Period.containing(_:_:calendar:)`, `previous/next(calendar:)`, `days(calendar:)`, `reportID(calendar:)`, `isoWeek(calendar:)`; `TrendMath.aggregate(_:in:today:calendar:)`, `TrendMath.change(_:from:) -> TrendChange?`; `DayRecord(day:snapshot:stepGoal:)`; `DayTone.empty` (never `.none`); `SnapshotBuilder.snapshot(for:now:locale:)`, `records(from:through:now:)`, `days(from:through:)`; `DayRecordStore.records(from:through:)`, `snapshot(for:locale:)`; `HealthArchive.read(day:)`, `write(_:)`, `clear()`, `fileURL(day:)`; `ReportCache.archive`; `TrendsModel(route:store:archive:calendar:locale:now:)`, `select(_:)`, `showPrevious()`, `showNext()`, `open(month:)`, `load()`, `archived(_:)`, `snapshot(for:)`; `HealthHomeModel.week`, `.calendar`, `.dayRecords`, `.archive`, `loadWeek()`, `trends(_:)`, `clearArchive()`; `DayCellView.Style` `.compact/.large/.row`; `CategoryValue.steps(_:)`; `ReportStory(_:eyebrow:)` — used with these exact names in every task.
