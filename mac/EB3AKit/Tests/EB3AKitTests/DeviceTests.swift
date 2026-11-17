import XCTest
@testable import EB3AKit

final class DeviceTests: XCTestCase {
    func testSupportedNames() {
        XCTAssertTrue(Station.isSupported(name: "EB3A2200000000001"))
        XCTAssertFalse(Station.isSupported(name: "AC180123"))
        XCTAssertFalse(Station.isSupported(name: nil))
    }

    func testShortName() {
        XCTAssertEqual(Station.shortName("EB3A2200000000001"), "EB3A ···0001")
        XCTAssertEqual(Station.shortName("EB3A"), "EB3A")
    }

    func testSignalBars() {
        XCTAssertEqual(Station.signalBars(rssi: -45), 3)
        XCTAssertEqual(Station.signalBars(rssi: -70), 2)
        XCTAssertEqual(Station.signalBars(rssi: -85), 1)
        XCTAssertEqual(Station.signalBars(rssi: -100), 0)
    }
}
