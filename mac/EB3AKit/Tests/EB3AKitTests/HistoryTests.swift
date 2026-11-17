import XCTest
@testable import EB3AKit

final class HistoryTests: XCTestCase {
    func tmpFile() -> URL { FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".jsonl") }

    func rec(minute: TimeInterval) -> HistoryRecord {
        HistoryRecord(minute: Date(timeIntervalSince1970: minute), soc: 50, solarW: 0, gridW: 0, acOutW: 10, dcOutW: 0,
                      gridPresent: true, solarCharging: false)
    }

    func testAggregatorEmitsOnMinuteRollover() {
        var a = MinuteAggregator(); let m = Date(timeIntervalSince1970: 600)
        XCTAssertNil(a.add(sample(solar: 100, at: m)))
        XCTAssertNil(a.add(sample(solar: 200, at: m + 30)))
        let r = a.add(sample(solar: 0, at: m + 61))
        XCTAssertEqual(r?.minute, m)
        XCTAssertEqual(r?.solarW, 150)
    }

    func testStoreRoundTripAndPrune() throws {
        let s = HistoryStore(fileURL: tmpFile())
        try s.append(rec(minute: 0)); try s.append(rec(minute: 7 * 86400 + 60))
        try s.prune(olderThan: Date(timeIntervalSince1970: 86400))
        XCTAssertEqual(try s.records(since: .distantPast).map(\.minute), [Date(timeIntervalSince1970: 7 * 86400 + 60)])
    }

    func testRecordsSinceFilters() throws {
        let s = HistoryStore(fileURL: tmpFile())
        try s.append(rec(minute: 60)); try s.append(rec(minute: 120))
        XCTAssertEqual(try s.records(since: Date(timeIntervalSince1970: 100)).count, 1)
    }

    func testCorruptLineSkipped() throws {
        let url = tmpFile(); let s = HistoryStore(fileURL: url)
        try s.append(rec(minute: 60))
        let h = try FileHandle(forWritingTo: url); try h.seekToEnd(); try h.write(contentsOf: Data("{\"minute\":12\n".utf8)); try h.close()
        try s.append(rec(minute: 120))
        XCTAssertEqual(try s.records(since: .distantPast).count, 2)
    }

    func testMissingFileIsEmpty() throws {
        XCTAssertEqual(try HistoryStore(fileURL: tmpFile()).records(since: .distantPast), [])
    }
}

final class SolarEnergyTests: XCTestCase {
    func rec(_ minute: TimeInterval, solar: Double) -> HistoryRecord {
        HistoryRecord(minute: Date(timeIntervalSince1970: minute), soc: 50, solarW: solar, gridW: 0, acOutW: 0, dcOutW: 0,
                      gridPresent: true, solarCharging: solar > 0)
    }

    func testSolarEnergySinceSumsMinutes() {
        let recs = (0..<60).map { rec(Double($0) * 60, solar: 120) }
        XCTAssertEqual(solarEnergyWh(recs, since: .distantPast), 120, accuracy: 0.001)
    }

    func testSolarEnergyRespectsSince() {
        let recs = [rec(0, solar: 600), rec(3600, solar: 600)]
        XCTAssertEqual(solarEnergyWh(recs, since: Date(timeIntervalSince1970: 1800)), 10, accuracy: 0.001)
    }

    func testFormatEnergy() {
        XCTAssertEqual(formatEnergy(420), "0,42 кВт·год")
        XCTAssertEqual(formatEnergy(35), "35 Вт·год")
    }
}
