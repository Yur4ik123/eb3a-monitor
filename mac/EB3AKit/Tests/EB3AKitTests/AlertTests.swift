import XCTest
@testable import EB3AKit

final class AlertTests: XCTestCase {
    func state(_ edit: (inout [UInt16: UInt16]) -> Void) throws -> StationState {
        var r = try fixture("after_app")
        for a: UInt16 in 54...62 { r[a] = 0 }
        edit(&r)
        return try XCTUnwrap(StationState(registers: r, at: sampleTime))
    }

    func testNoAlertsWhenWordsZero() throws {
        XCTAssertEqual(try state { _ in }.alerts, [])
    }

    func testGridLowVoltageA082() throws {
        let s = try state { $0[54] = 2; $0[77] = 1911 }
        XCTAssertEqual(s.alerts.map(\.code), ["A082"])
        XCTAssertEqual(s.alerts.first?.title, "Низька напруга мережі")
        XCTAssertTrue(s.alerts.first?.detail.contains("191") ?? false)
    }

    func testUnknownBitIsReported() throws {
        let s = try state { $0[56] = 0x0010 }
        XCTAssertEqual(s.alerts.count, 1)
        XCTAssertEqual(s.alerts.first?.code, "56.4")
    }

    func testOverTempAndMultipleBits() throws {
        let s = try state { $0[54] = 2 | 128; $0[60] = 1 }
        XCTAssertEqual(Set(s.alerts.compactMap(\.code)), ["A082", "54.7", "60.0"])
    }

    func testMenuBarWarningPrefix() throws {
        let s = try state { $0[54] = 2 }
        XCTAssertTrue(MenuBarText.make(state: s, now: sampleTime).hasPrefix("⚠️ "))
        XCTAssertFalse(MenuBarText.make(state: try state { _ in }, now: sampleTime).hasPrefix("⚠️"))
    }
}
