import Foundation

public enum LedMode: Equatable, Codable, Sendable {
    case low, high, sos, off, unknown(Int)

    init(raw: Int) {
        self = switch raw {
        case 1: .low
        case 2: .high
        case 3: .sos
        case 4: .off
        default: .unknown(raw)
        }
    }

    public var raw: UInt16? {
        switch self {
        case .low: 1
        case .high: 2
        case .sos: 3
        case .off: 4
        case .unknown: nil
        }
    }
}

public enum ChargeMode: Equatable, Codable, Sendable {
    case standard, silent, turbo, unknown(Int)

    init(raw: Int) {
        self = switch raw {
        case 0: .standard
        case 1: .silent
        case 2: .turbo
        default: .unknown(raw)
        }
    }

    public var raw: UInt16? {
        switch self {
        case .standard: 0
        case .silent: 1
        case .turbo: 2
        case .unknown: nil
        }
    }
}

public struct StationState: Codable, Equatable, Sendable {
    public var soc: Int
    public var solarW, gridW, acOutW, dcOutW: Int
    public var solarV, gridV: Double
    public var generatedKWh: Double
    public var solarPresent, gridPresent, solarCharging, upsActive, acOn, dcOn, charging, overTemp: Bool
    public var acCommand, dcCommand: Bool
    public var led: LedMode
    public var ecoOn: Bool
    public var ecoHours: Int
    public var chargeMode: ChargeMode
    public var powerLifting: Bool
    /// Регістри 54...62 як є.
    public var alarmWords: [UInt16]
    public var updatedAt: Date

    /// Плюс — батарея розряджається.
    public var batteryNetW: Int { acOutW + dcOutW - solarW - gridW }
}

extension StationState {
    public init?(registers r: [UInt16: UInt16], at date: Date) {
        guard Reg.decoded.allSatisfy({ r[$0] != nil }) else { return nil }
        func i(_ a: UInt16) -> Int { Int(r[a]!) }
        func b(_ a: UInt16) -> Bool { r[a]! != 0 }

        self.init(
            soc: i(Reg.soc),
            solarW: i(Reg.solarW), gridW: i(Reg.gridW), acOutW: i(Reg.acOutW), dcOutW: i(Reg.dcOutW),
            solarV: Double(i(Reg.solarV)) / 100, gridV: Double(i(Reg.gridV)) / 10,
            generatedKWh: Double(i(Reg.generated)) / 10,
            solarPresent: b(Reg.solarPresent), gridPresent: b(Reg.gridPresent),
            solarCharging: b(Reg.solarCharging), upsActive: b(Reg.upsActive),
            acOn: b(Reg.acOn), dcOn: b(Reg.dcOn), charging: i(Reg.chargeState) == 1, overTemp: b(Reg.overTemp),
            acCommand: b(Reg.ac), dcCommand: b(Reg.dc),
            led: LedMode(raw: i(Reg.led)),
            ecoOn: b(Reg.eco), ecoHours: i(Reg.ecoHours),
            chargeMode: ChargeMode(raw: i(Reg.chargeMode)),
            powerLifting: b(Reg.powerLifting),
            alarmWords: Reg.alarmWords.map { r[$0]! },
            updatedAt: date
        )
    }
}
