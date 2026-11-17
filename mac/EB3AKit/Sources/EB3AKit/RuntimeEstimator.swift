import Foundation

/// Прогноз автономності: EMA чистої потужності батареї.
public struct RuntimeEstimator: Sendable {
    let capacityWh: Double
    let usableFactor: Double
    let window: TimeInterval
    public private(set) var smoothedW: Double?
    var lastAt: Date?

    public init(capacityWh: Double = 268, usableFactor: Double = 0.9, window: TimeInterval = 300) {
        self.capacityWh = capacityWh
        self.usableFactor = usableFactor
        self.window = window
    }

    public mutating func add(netW: Double, at date: Date) {
        // Початок розряду після заряду/простою — без «хвоста» від'ємних значень.
        guard let prev = smoothedW, let last = lastAt, !(prev <= 5 && netW > 5) else {
            smoothedW = netW
            lastAt = date
            return
        }
        let alpha = 1 - exp(-max(0, date.timeIntervalSince(last)) / window)
        smoothedW = prev + alpha * (netW - prev)
        lastAt = date
    }

    public func remaining(soc: Int) -> TimeInterval? {
        guard let w = smoothedW, w > 5 else { return nil }
        return capacityWh * usableFactor * Double(soc) / 100 / w * 3600
    }
}

public func formatRemaining(_ t: TimeInterval) -> String {
    let minutes = Int(t / 60)
    return String(format: "~%d:%02d", minutes / 60, minutes % 60)
}
