import Foundation

public struct StationAlert: Equatable, Codable, Sendable {
    /// Код офіційного додатку (A082) або «регістр.біт», якщо невідомий.
    public let code: String?
    public let title: String
    public let detail: String
}

extension StationState {
    public var alerts: [StationAlert] {
        var out: [StationAlert] = []
        for (i, word) in alarmWords.enumerated() where word != 0 {
            let reg = Reg.alarmWords.lowerBound + UInt16(i)
            for bit in 0..<16 where word & (1 << bit) != 0 {
                out.append(Self.describe(reg: reg, bit: bit, state: self))
            }
        }
        return out
    }

    static func describe(reg: UInt16, bit: Int, state s: StationState) -> StationAlert {
        switch (reg, bit) {
        case (54, 1):
            StationAlert(code: "A082", title: "Низька напруга мережі",
                         detail: String(format: "Мережа %.0f V не прийнята, живлення від батареї", s.gridV))
        case (54, 7):
            StationAlert(code: "54.7", title: "Сонячний вхід не заряджає",
                         detail: String(format: "Ймовірно, мало сонця (панель %.1f V)", s.solarV))
        case (60, 0):
            StationAlert(code: "60.0", title: "Перегрів", detail: "Станція обмежує роботу через температуру")
        default:
            StationAlert(code: "\(reg).\(bit)", title: "Сигнал станції",
                         detail: "Невідомий код: регістр \(reg), біт \(bit). Деталі — в офіційному додатку")
        }
    }
}
