import Foundation

/// Адреси EB3A (див. REGISTERS.md).
public enum Reg {
    public static let solarW: UInt16 = 36
    public static let gridW: UInt16 = 37
    public static let acOutW: UInt16 = 38
    public static let dcOutW: UInt16 = 39
    public static let generated: UInt16 = 41
    public static let soc: UInt16 = 43
    public static let solarPresent: UInt16 = 44
    public static let gridPresent: UInt16 = 45
    public static let solarCharging: UInt16 = 46
    public static let upsActive: UInt16 = 47
    public static let acOn: UInt16 = 48
    public static let dcOn: UInt16 = 49
    public static let chargeState: UInt16 = 53
    public static let overTemp: UInt16 = 60
    /// Слова сигналів/помилок (офіційний додаток показує з них коди Axxx).
    public static let alarmWords: ClosedRange<UInt16> = 54...62
    public static let gridV: UInt16 = 77
    public static let solarV: UInt16 = 86

    public static let ac: UInt16 = 3007
    public static let dc: UInt16 = 3008
    public static let led: UInt16 = 3034
    public static let eco2: UInt16 = 3061
    public static let eco: UInt16 = 3063
    public static let ecoHours: UInt16 = 3064
    public static let chargeMode: UInt16 = 3065
    public static let powerLifting: UInt16 = 3066

    /// Дрібні блоки: великі (53+ регістрів) станція віддає за ~3 с.
    public static let pollBlocks: [(start: UInt16, count: UInt16)] = [(36, 14), (50, 13), (77, 10), (3000, 10), (3030, 5), (3060, 7)]

    static let decoded: Set<UInt16> = Set<UInt16>([
        solarW, gridW, acOutW, dcOutW, generated, soc, solarPresent, gridPresent, solarCharging, upsActive,
        acOn, dcOn, chargeState, overTemp, gridV, solarV, ac, dc, led, eco, ecoHours, chargeMode, powerLifting,
    ]).union(alarmWords)
}

public enum WritePolicy {
    static let allowed: [UInt16: Set<UInt16>] = [
        Reg.ac: [0, 1], Reg.dc: [0, 1], Reg.led: [1, 2, 3, 4], Reg.eco2: [0, 1], Reg.eco: [0, 1],
        Reg.ecoHours: [1, 2, 3, 4], Reg.chargeMode: [0, 1, 2], Reg.powerLifting: [0, 1],
    ]

    public static func isAllowed(address: UInt16, value: UInt16) -> Bool {
        allowed[address]?.contains(value) ?? false
    }

    /// ECO пишеться парою, як в офіційному додатку.
    public static func ecoWrites(on: Bool) -> [(address: UInt16, value: UInt16)] {
        let v: UInt16 = on ? 1 : 0
        return [(Reg.eco, v), (Reg.eco2, v)]
    }
}
