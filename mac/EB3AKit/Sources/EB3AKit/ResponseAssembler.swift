import Foundation

public enum ModbusResponse: Equatable, Sendable {
    case registers([UInt16])
    case writeAck
    case exception(UInt8)
}

public enum ModbusError: Error, Equatable {
    case crcMismatch
    case unexpectedEcho
    case wrongLength
}

/// Складає відповідь Modbus з BLE-notify фрагментів.
public struct ResponseAssembler {
    public enum Expect {
        case read(count: Int)
        case write(echo: Data)
    }

    let expect: Expect
    var buf: [UInt8] = []

    public init(expect: Expect) { self.expect = expect }

    var function: UInt8 {
        switch expect {
        case .read: 0x03
        case .write: 0x06
        }
    }

    public mutating func append(_ chunk: Data) throws -> ModbusResponse? {
        buf += chunk
        dropLeadingGarbage()
        guard buf.count >= 3 else { return nil }

        if buf[1] == function | 0x80 {
            guard buf.count >= 5 else { return nil }
            try checkCRC(Array(buf[0..<5]))
            return .exception(buf[2])
        }

        switch expect {
        case .read(let count):
            let total = 5 + Int(buf[2])
            guard buf.count >= total else { return nil }
            let frame = Array(buf[0..<total])
            try checkCRC(frame)
            guard Int(frame[2]) == count * 2 else {
                // Цілий валідний кадр іншої довжини — запізніла відповідь на попередній запит.
                buf.removeFirst(total)
                return try append(Data())
            }
            return .registers(stride(from: 3, to: total - 2, by: 2).map { UInt16(frame[$0]) << 8 | UInt16(frame[$0 + 1]) })
        case .write(let echo):
            guard buf.count >= 8 else { return nil }
            let frame = Array(buf[0..<8])
            try checkCRC(frame)
            guard Data(frame) == echo else { throw ModbusError.unexpectedEcho }
            return .writeAck
        }
    }

    mutating func dropLeadingGarbage() {
        let valid: Set<UInt8> = [function, function | 0x80]
        var i = 0
        while i < buf.count {
            if buf[i] == Modbus.slave && (i + 1 == buf.count || valid.contains(buf[i + 1])) { break }
            i += 1
        }
        if i > 0 { buf.removeFirst(i) }
    }

    func checkCRC(_ frame: [UInt8]) throws {
        let body = Array(frame.dropLast(2))
        let got = UInt16(frame[frame.count - 2]) | UInt16(frame[frame.count - 1]) << 8
        guard Modbus.crc16(body) == got else { throw ModbusError.crcMismatch }
    }
}
