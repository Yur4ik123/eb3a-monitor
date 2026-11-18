import XCTest
@testable import EB3AKit

final class SolarDaysTests: XCTestCase {
    let cal: Calendar = { var c = Calendar(identifier: .gregorian); c.timeZone = TimeZone(identifier: "UTC")!; return c }()
    let day0 = Date(timeIntervalSince1970: 1_763_337_600) // 2025-11-17 00:00 UTC

    func rec(_ t: Date, _ solar: Double) -> HistoryRecord {
        HistoryRecord(minute: t, soc: 50, solarW: solar, gridW: 0, acOutW: 0, dcOutW: 0, gridPresent: true, solarCharging: solar > 0)
    }

    func minutes(from start: Date, count: Int, solar: Double) -> [HistoryRecord] {
        (0..<count).map { rec(start + Double($0) * 60, solar) }
    }

    func testBuildSumsAndHourly() throws {
        let ten = day0 + 10 * 3600
        let d = try XCTUnwrap(SolarDays.build(from: minutes(from: ten, count: 60, solar: 120), calendar: cal).first)
        XCTAssertEqual(d.day, "2025-11-17")
        XCTAssertEqual(d.wh, 120, accuracy: 0.001)
        XCTAssertEqual(d.hourlyWh[10], 120, accuracy: 0.001)
        XCTAssertEqual(d.peakW, 120)
        XCTAssertEqual(d.firstAt, ten)
        XCTAssertEqual(d.lastAt, ten + 59 * 60)
        XCTAssertEqual(d.minutesCovered, 60)
    }

    func testSplitsAtLocalMidnight() {
        let days = SolarDays.build(from: [rec(day0 + 86400 - 60, 60), rec(day0 + 86400, 60)], calendar: cal)
        XCTAssertEqual(days.map(\.day), ["2025-11-17", "2025-11-18"])
    }

    func testUpsertReplacesDay() {
        let a = SolarDays.build(from: minutes(from: day0 + 36000, count: 60, solar: 120), calendar: cal)
        let merged = SolarDays.merge(a, a, keepDays: 90, now: day0 + 86000, calendar: cal)
        XCTAssertEqual(merged.count, 1)
        XCTAssertEqual(merged[0].wh, 120, accuracy: 0.001)
    }

    func testDayWithoutSun() throws {
        let d = try XCTUnwrap(SolarDays.build(from: minutes(from: day0, count: 30, solar: 0), calendar: cal).first)
        XCTAssertEqual(d.wh, 0)
        XCTAssertNil(d.peakAt)
        XCTAssertNil(d.firstAt)
        XCTAssertEqual(d.minutesCovered, 30)
    }

    func testMergeTrimsTo90Days() {
        let old = SolarDays.build(from: (0..<100).map { rec(day0 + Double($0) * 86400, 50) }, calendar: cal)
        let merged = SolarDays.merge([], old, keepDays: 90, now: day0 + 99 * 86400, calendar: cal)
        XCTAssertEqual(merged.count, 90)
        XCTAssertEqual(merged.last?.day, SolarDays.dayKey(day0 + 99 * 86400, calendar: cal))
    }

    func testCorruptStoreIsEmpty() throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".json")
        try Data("{oops".utf8).write(to: url)
        XCTAssertEqual(SolarDaysStore(fileURL: url).load(), [])
    }

    func testStoreRoundTrip() throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".json")
        let days = SolarDays.build(from: minutes(from: day0 + 36000, count: 10, solar: 60), calendar: cal)
        try SolarDaysStore(fileURL: url).save(days)
        XCTAssertEqual(SolarDaysStore(fileURL: url).load(), days)
    }

    func testWeekComparison() throws {
        var recs: [HistoryRecord] = []
        for d in 0..<14 { recs += minutes(from: day0 + Double(d) * 86400 + 43200, count: 60, solar: d >= 7 ? 100 : 50) }
        let days = SolarDays.build(from: recs, calendar: cal)
        let w = SolarDays.weekComparison(days, now: day0 + 13 * 86400 + 80000, calendar: cal)
        XCTAssertEqual(w.thisWh, 700, accuracy: 0.01)
        XCTAssertEqual(w.lastWh, 350, accuracy: 0.01)
        XCTAssertEqual(try XCTUnwrap(w.changePct), 100, accuracy: 0.01)
    }

    func testWeekComparisonNoPrevious() {
        let days = SolarDays.build(from: minutes(from: day0 + 43200, count: 60, solar: 100), calendar: cal)
        let w = SolarDays.weekComparison(days, now: day0 + 80000, calendar: cal)
        XCTAssertNil(w.changePct)
    }
}
