import XCTest
@testable import EB3AKit

final class StationStateTests: XCTestCase {
    func testDecodeRealSnapshot() throws {
        let s = try XCTUnwrap(StationState(registers: try fixture("after_app"), at: .init(timeIntervalSince1970: 0)))
        XCTAssertEqual(s.soc, 100); XCTAssertEqual(s.gridW, 21); XCTAssertEqual(s.acOutW, 21)
        XCTAssertEqual(s.gridV, 209.2, accuracy: 0.001); XCTAssertEqual(s.generatedKWh, 19.5, accuracy: 0.001)
        XCTAssertTrue(s.gridPresent); XCTAssertTrue(s.upsActive); XCTAssertTrue(s.acOn); XCTAssertFalse(s.dcOn)
        XCTAssertFalse(s.charging)
        XCTAssertEqual(s.chargeMode, .turbo); XCTAssertTrue(s.powerLifting); XCTAssertEqual(s.led, .off)
        XCTAssertEqual(s.batteryNetW, 0)
    }

    func testSolarVoltageScale() throws {
        var r = try fixture("after_app"); r[86] = 2294; r[44] = 1
        XCTAssertEqual(StationState(registers: r, at: .now)!.solarV, 22.94, accuracy: 0.001)
    }

    func testUnknownEnumValuesDecode() throws {
        var r = try fixture("after_app"); r[3065] = 4; r[3034] = 0
        let s = try XCTUnwrap(StationState(registers: r, at: .now))
        XCTAssertEqual(s.chargeMode, .unknown(4)); XCTAssertEqual(s.led, .unknown(0))
    }

    func testMissingRegisterReturnsNil() throws {
        var r = try fixture("after_app"); r[43] = nil
        XCTAssertNil(StationState(registers: r, at: .now))
    }

    func testWritePolicy() {
        XCTAssertTrue(WritePolicy.isAllowed(address: 3065, value: 1))
        XCTAssertFalse(WritePolicy.isAllowed(address: 3065, value: 4))
        for a: UInt16 in [3060, 3006, 3015, 3016] { XCTAssertFalse(WritePolicy.isAllowed(address: a, value: 1)) }
        XCTAssertEqual(WritePolicy.ecoWrites(on: true).map { [$0.address, $0.value] }, [[3063, 1], [3061, 1]])
    }

    func testPollBlocksCoverDecodedRegisters() {
        let covered = Set(Reg.pollBlocks.flatMap { b in (b.start..<b.start + b.count) })
        XCTAssertTrue(Reg.decoded.isSubset(of: covered))
    }

    func testPollBlocksAreSmall() {
        // Блоки 53/67 регістрів станція віддає за ~3 с (таймаут), блоки ≤14 — за ~0.1 с.
        XCTAssertTrue(Reg.pollBlocks.allSatisfy { $0.count <= 14 })
    }

    func testPollBlocksStartAtValidAddresses() {
        XCTAssertTrue(Reg.pollBlocks.allSatisfy { (1...210).contains($0.start) || (3000...3077).contains($0.start) })
    }
}
