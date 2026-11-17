import XCTest
@testable import EB3AKit

final class RuntimeAndTextTests: XCTestCase {
    func testRemainingSteadyLoad() {
        var e = RuntimeEstimator(); let t0 = Date(timeIntervalSince1970: 0)
        for i in 0...600 { e.add(netW: 100, at: t0 + Double(i)) }
        XCTAssertEqual(e.remaining(soc: 50)!, 268 * 0.9 * 0.5 / 100 * 3600, accuracy: 1)
    }

    func testRemainingNilWhenCharging() {
        var e = RuntimeEstimator(); let t0 = Date(timeIntervalSince1970: 0)
        for i in 0...600 { e.add(netW: -250, at: t0 + Double(i)) }
        XCTAssertNil(e.remaining(soc: 50))
        var z = RuntimeEstimator(); z.add(netW: 3, at: t0)
        XCTAssertNil(z.remaining(soc: 50))
    }

    func testSmoothingFollowsLoadChange() {
        var e = RuntimeEstimator(); let t0 = Date(timeIntervalSince1970: 0)
        e.add(netW: 100, at: t0)
        e.add(netW: 400, at: t0 + 300)
        XCTAssertEqual(e.smoothedW!, 100 + 300 * (1 - exp(-1)), accuracy: 0.01)
    }

    func testFormatRemaining() {
        XCTAssertEqual(formatRemaining(13200), "~3:40")
        XCTAssertEqual(formatRemaining(300), "~0:05")
    }

    func testTextWithGridAndSun() {
        XCTAssertEqual(MenuBarText.make(state: sample(soc: 87, solar: 142, solarPresent: true), now: sampleTime),
                       "⚡ ☀ 142W  🔋 87%")
    }

    func testTextGridNoPanel() {
        XCTAssertEqual(MenuBarText.make(state: sample(soc: 87), now: sampleTime), "⚡ 🔋 87%")
    }

    func testTextBlackout() {
        XCTAssertEqual(MenuBarText.make(state: sample(soc: 87, grid: false), now: sampleTime), "🔋 87%")
        XCTAssertEqual(MenuBarText.make(state: sample(soc: 87, solar: 60, solarPresent: true, grid: false), now: sampleTime),
                       "☀ 60W  🔋 87%")
    }

    func testStaleStateShowsDash() {
        XCTAssertEqual(MenuBarText.make(state: sample(soc: 87), now: sampleTime + 31), "🔋 —")
        XCTAssertEqual(MenuBarText.make(state: nil, now: sampleTime), "🔋 —")
    }
}

final class ReviewFixTests: XCTestCase {
    func testEstimateReseedsWhenChargingTurnsToDischarge() throws {
        var e = RuntimeEstimator(); let t0 = Date(timeIntervalSince1970: 0)
        for i in 0...3600 { e.add(netW: -100, at: t0 + Double(i)) }
        for i in 1...10 { e.add(netW: 150, at: t0 + 3600 + Double(i * 2)) }
        // 87% від 268 Wh × 0.9 при 150 W ≈ 1.4 год, а не десятки годин
        XCTAssertEqual(try XCTUnwrap(e.remaining(soc: 87)), 268 * 0.9 * 0.87 / 150 * 3600, accuracy: 600)
    }

    func testSnapshotStaleAt() {
        let snap = SharedSnapshot(state: sample(at: sampleTime), remaining: nil, socLast24h: [])
        XCTAssertEqual(snap.staleAt, sampleTime + 600)
    }

    func testWithTimeoutThrows() async {
        do {
            _ = try await withTimeout(seconds: 0.1) { try await Task.sleep(for: .seconds(5)); return 1 }
            XCTFail("expected timeout")
        } catch {
            XCTAssertTrue(error is TimeoutError)
        }
    }

    func testWithTimeoutReturnsValue() async throws {
        let v = try await withTimeout(seconds: 1) { 42 }
        XCTAssertEqual(v, 42)
    }
}
