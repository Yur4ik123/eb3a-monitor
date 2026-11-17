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
        XCTAssertEqual(MenuBarText.make(state: sample(soc: 87, grid: false), now: sampleTime), "⚡✕ 🔋 87%")
        XCTAssertEqual(MenuBarText.make(state: sample(soc: 87, solar: 60, solarPresent: true, grid: false), now: sampleTime),
                       "⚡✕ ☀ 60W  🔋 87%")
    }

    func testStaleStateShowsDash() {
        XCTAssertEqual(MenuBarText.make(state: sample(soc: 87), now: sampleTime + 31), "🔋 —")
        XCTAssertEqual(MenuBarText.make(state: nil, now: sampleTime), "🔋 —")
    }
}
