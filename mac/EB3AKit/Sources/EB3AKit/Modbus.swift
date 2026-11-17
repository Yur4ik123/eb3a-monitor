import Foundation

public enum Modbus {
    static let slave: UInt8 = 0x01

    public static func crc16(_ bytes: [UInt8]) -> UInt16 {
        var crc: UInt16 = 0xFFFF
        for b in bytes {
            crc ^= UInt16(b)
            for _ in 0..<8 {
                crc = crc & 1 != 0 ? (crc >> 1) ^ 0xA001 : crc >> 1
            }
        }
        return crc
    }

    public static func readCommand(start: UInt16, count: UInt16) -> Data {
        frame([slave, 0x03] + be(start) + be(count))
    }

    public static func writeCommand(address: UInt16, value: UInt16) -> Data {
        frame([slave, 0x06] + be(address) + be(value))
    }

    static func be(_ v: UInt16) -> [UInt8] { [UInt8(v >> 8), UInt8(v & 0xFF)] }

    static func frame(_ body: [UInt8]) -> Data {
        let crc = crc16(body)
        return Data(body + [UInt8(crc & 0xFF), UInt8(crc >> 8)])
    }
}
