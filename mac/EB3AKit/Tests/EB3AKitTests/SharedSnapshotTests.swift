import XCTest
@testable import EB3AKit

final class SharedSnapshotTests: XCTestCase {
    let t0 = sampleTime

    func tmpDir() -> URL {
        let u = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try! FileManager.default.createDirectory(at: u, withIntermediateDirectories: true)
        return u
    }

    func testSnapshotRoundTripAndStale() throws {
        let dir = tmpDir()
        let snap = SharedSnapshot(state: sample(soc: 80, at: t0), remaining: 3600, socLast24h: [80, 81], solarTodayWh: 420)
        try SharedStore.write(snap, to: dir)
        XCTAssertEqual(SharedStore.read(from: dir), snap)
        XCTAssertEqual(SharedStore.read(from: dir)?.solarTodayWh, 420)
        XCTAssertFalse(snap.isStale(now: t0 + 599))
        XCTAssertTrue(snap.isStale(now: t0 + 601))
    }

    func testReadMissingIsNil() { XCTAssertNil(SharedStore.read(from: tmpDir())) }

    func testReloadPolicy() {
        var p = WidgetReloadPolicy()
        XCTAssertTrue(p.shouldReload(sample(soc: 80, solar: 100, at: t0), now: t0))
        XCTAssertFalse(p.shouldReload(sample(soc: 80, solar: 110, at: t0), now: t0 + 120))
        XCTAssertFalse(p.shouldReload(sample(soc: 79, solar: 110, at: t0), now: t0 + 30))
        XCTAssertTrue(p.shouldReload(sample(soc: 79, solar: 110, at: t0), now: t0 + 61))
        XCTAssertTrue(p.shouldReload(sample(soc: 79, solar: 110, grid: false, at: t0), now: t0 + 130))
        XCTAssertTrue(p.shouldReload(sample(soc: 79, solar: 135, grid: false, at: t0), now: t0 + 200))
    }

    func testSocSeriesHalfHourly() {
        let now = t0
        let recs = (0..<(24 * 60)).map { i in
            HistoryRecord(minute: now - Double(24 * 3600 - i * 60), soc: i / 30, solarW: 0, gridW: 0, acOutW: 0, dcOutW: 0,
                          gridPresent: true, solarCharging: false)
        }
        let series = SharedSnapshot.socSeries(from: recs, now: now)
        XCTAssertEqual(series.count, 48)
        XCTAssertEqual(series.first, 0)
        XCTAssertEqual(series.last, 47)
    }
}
