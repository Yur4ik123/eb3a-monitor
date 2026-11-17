import XCTest
@testable import EB3AKit

final class ResponseAssemblerTests: XCTestCase {
    func testSingleChunkRead() throws {
        var a = ResponseAssembler(expect: .read(count: 2))
        XCTAssertEqual(try a.append(Data([0x01, 0x03, 0x04, 0x00, 0x00, 0x00, 0x01, 0x3B, 0xF3])), .registers([0, 1]))
    }

    func testFragmentedRead() throws {
        var a = ResponseAssembler(expect: .read(count: 6))
        XCTAssertNil(try a.append(Data([0x01, 0x03, 0x0C, 0x45, 0x42])))
        XCTAssertEqual(try a.append(Data([0x33, 0x41, 0, 0, 0, 0, 0, 0, 0, 0, 0x0C, 0x99])),
                       .registers([0x4542, 0x3341, 0, 0, 0, 0]))
    }

    func testExceptionFrame() throws {
        var a = ResponseAssembler(expect: .read(count: 2))
        XCTAssertEqual(try a.append(Data([0x01, 0x83, 0x02, 0xC0, 0xF1])), .exception(2))
    }

    func testWriteEchoSplitInTwo() throws {
        let cmd = Modbus.writeCommand(address: 3034, value: 4)
        var a = ResponseAssembler(expect: .write(echo: cmd))
        XCTAssertNil(try a.append(cmd.prefix(4)))
        XCTAssertEqual(try a.append(cmd.suffix(4)), .writeAck)
    }

    func testCrcMismatchThrows() {
        var a = ResponseAssembler(expect: .read(count: 2))
        XCTAssertThrowsError(try a.append(Data([0x01, 0x03, 0x04, 0, 0, 0, 1, 0x00, 0x00]))) {
            XCTAssertEqual($0 as? ModbusError, .crcMismatch)
        }
    }

    func testLeadingGarbageIsSkipped() throws {
        var a = ResponseAssembler(expect: .read(count: 2))
        XCTAssertEqual(try a.append(Data([0xC0, 0xF1, 0x01, 0x03, 0x04, 0, 0, 0, 1, 0x3B, 0xF3])), .registers([0, 1]))
    }

    func testLateFrameOfOtherLengthIsSkipped() throws {
        var a = ResponseAssembler(expect: .read(count: 2))
        // запізнілий кадр попереднього запиту (1 регістр), далі — наш (2 регістри)
        let late = Data([0x01, 0x03, 0x02, 0x00, 0x05])
        let lateFrame = late + Data([UInt8(Modbus.crc16(Array(late)) & 0xFF), UInt8(Modbus.crc16(Array(late)) >> 8)])
        XCTAssertNil(try a.append(lateFrame))
        XCTAssertEqual(try a.append(Data([0x01, 0x03, 0x04, 0x00, 0x00, 0x00, 0x01, 0x3B, 0xF3])), .registers([0, 1]))
    }
}
