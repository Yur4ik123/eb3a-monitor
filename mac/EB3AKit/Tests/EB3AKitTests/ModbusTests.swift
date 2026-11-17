import XCTest
@testable import EB3AKit

final class ModbusTests: XCTestCase {
    func testCrcReference() {
        XCTAssertEqual(Modbus.crc16([0x01, 0x03, 0x00, 0x00, 0x00, 0x01]), 0x0A84)
    }

    func testReadCommandMatchesDevice() {
        XCTAssertEqual(Modbus.readCommand(start: 10, count: 6), Data([0x01, 0x03, 0x00, 0x0A, 0x00, 0x06, 0xE5, 0xCA]))
        XCTAssertEqual(Modbus.readCommand(start: 17, count: 4), Data([0x01, 0x03, 0x00, 0x11, 0x00, 0x04, 0x14, 0x0C]))
    }

    func testWriteCommand() {
        let c = Modbus.writeCommand(address: 3034, value: 1)
        XCTAssertEqual(Array(c.prefix(6)), [0x01, 0x06, 0x0B, 0xDA, 0x00, 0x01])
        XCTAssertEqual(Modbus.crc16(Array(c.prefix(6))), UInt16(c[6]) | UInt16(c[7]) << 8)
    }
}
