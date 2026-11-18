import Foundation

/// Підсумок генерації сонця за один день.
public struct DaySummary: Codable, Equatable, Sendable {
    public var day: String
    public var wh: Double
    public var hourlyWh: [Double]
    public var peakW: Double
    public var peakAt: Date?
    public var firstAt: Date?
    public var lastAt: Date?
    public var minutesCovered: Int

    /// Частка хвилин дня (для сьогодні — тих, що вже минули), коли застосунок писав дані.
    public func coverage(now: Date, calendar: Calendar) -> Double {
        guard let start = SolarDays.date(fromKey: day, calendar: calendar) else { return 0 }
        let elapsed = min(1440, max(1, now.timeIntervalSince(start) / 60))
        return min(1, Double(minutesCovered) / elapsed)
    }
}

public enum SolarDays {
    static let producingW: Double = 5

    public static func dayKey(_ d: Date, calendar: Calendar) -> String {
        let c = calendar.dateComponents([.year, .month, .day], from: d)
        return String(format: "%04d-%02d-%02d", c.year!, c.month!, c.day!)
    }

    static func date(fromKey key: String, calendar: Calendar) -> Date? {
        let p = key.split(separator: "-").compactMap { Int($0) }
        guard p.count == 3 else { return nil }
        return calendar.date(from: DateComponents(year: p[0], month: p[1], day: p[2]))
    }

    public static func build(from records: [HistoryRecord], calendar: Calendar) -> [DaySummary] {
        Dictionary(grouping: records) { dayKey($0.minute, calendar: calendar) }
            .map { key, recs in
                let sorted = recs.sorted { $0.minute < $1.minute }
                var hourly = [Double](repeating: 0, count: 24)
                for r in sorted { hourly[calendar.component(.hour, from: r.minute)] += r.solarW / 60 }
                let producing = sorted.filter { $0.solarW > producingW }
                let peak = producing.max { $0.solarW < $1.solarW }
                return DaySummary(day: key, wh: hourly.reduce(0, +), hourlyWh: hourly, peakW: peak?.solarW ?? 0,
                                  peakAt: peak?.minute, firstAt: producing.first?.minute, lastAt: producing.last?.minute,
                                  minutesCovered: sorted.count)
            }
            .sorted { $0.day < $1.day }
    }

    /// Upsert за днем, сортування, обрізка до `keepDays` останніх днів.
    public static func merge(_ existing: [DaySummary], _ new: [DaySummary], keepDays: Int, now: Date, calendar: Calendar) -> [DaySummary] {
        var byDay = Dictionary(existing.map { ($0.day, $0) }, uniquingKeysWith: { $1 })
        for d in new { byDay[d.day] = d }
        let oldest = dayKey(calendar.date(byAdding: .day, value: -(keepDays - 1), to: now)!, calendar: calendar)
        return byDay.values.filter { $0.day >= oldest }.sorted { $0.day < $1.day }
    }

    /// Останні 7 днів (з сьогодні) проти попередніх 7.
    public static func weekComparison(_ days: [DaySummary], now: Date, calendar: Calendar) -> (thisWh: Double, lastWh: Double, changePct: Double?) {
        func key(_ offset: Int) -> String { dayKey(calendar.date(byAdding: .day, value: -offset, to: now)!, calendar: calendar) }
        let thisRange = key(6)...key(0), lastRange = key(13)...key(7)
        let this = days.filter { thisRange.contains($0.day) }.reduce(0) { $0 + $1.wh }
        let last = days.filter { lastRange.contains($0.day) }.reduce(0) { $0 + $1.wh }
        return (this, last, last > 0 ? (this - last) / last * 100 : nil)
    }
}

public final class SolarDaysStore: @unchecked Sendable {
    let fileURL: URL

    public init(fileURL: URL) { self.fileURL = fileURL }

    public func load() -> [DaySummary] {
        let d = JSONDecoder()
        d.dateDecodingStrategy = .secondsSince1970
        guard let data = try? Data(contentsOf: fileURL), let days = try? d.decode([DaySummary].self, from: data) else { return [] }
        return days
    }

    public func save(_ days: [DaySummary]) throws {
        let e = JSONEncoder()
        e.dateEncodingStrategy = .secondsSince1970
        try e.encode(days).write(to: fileURL, options: .atomic)
    }
}
