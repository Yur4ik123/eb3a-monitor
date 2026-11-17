import Foundation

/// Те, що застосунок передає віджету.
public struct SharedSnapshot: Codable, Equatable, Sendable {
    public var state: StationState
    public var remaining: TimeInterval?
    public var socLast24h: [Int]
    public var solarTodayWh: Double

    public init(state: StationState, remaining: TimeInterval?, socLast24h: [Int], solarTodayWh: Double = 0) {
        self.state = state
        self.remaining = remaining
        self.socLast24h = socLast24h
        self.solarTodayWh = solarTodayWh
    }

    public func isStale(now: Date, maxAge: TimeInterval = 600) -> Bool {
        now.timeIntervalSince(state.updatedAt) > maxAge
    }

    /// Останній заряд у кожному 30-хв відрізку за добу; порожні відрізки пропускаються.
    public static func socSeries(from records: [HistoryRecord], now: Date) -> [Int] {
        let start = now.addingTimeInterval(-24 * 3600)
        var buckets = [Int?](repeating: nil, count: 48)
        for r in records where r.minute >= start && r.minute < now {
            buckets[min(47, Int(r.minute.timeIntervalSince(start) / 1800))] = r.soc
        }
        return buckets.compactMap { $0 }
    }
}

public enum SharedStore {
    public static let groupID = "<TEAM_ID>.eb3a"
    static let fileName = "snapshot.json"

    public static var containerURL: URL? {
        FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: groupID)
    }

    public static func write(_ s: SharedSnapshot, to dir: URL) throws {
        let e = JSONEncoder()
        e.dateEncodingStrategy = .secondsSince1970
        try e.encode(s).write(to: dir.appendingPathComponent(fileName), options: .atomic)
    }

    public static func read(from dir: URL) -> SharedSnapshot? {
        guard let data = try? Data(contentsOf: dir.appendingPathComponent(fileName)) else { return nil }
        let d = JSONDecoder()
        d.dateDecodingStrategy = .secondsSince1970
        return try? d.decode(SharedSnapshot.self, from: data)
    }
}

/// Коли варто просити систему перемалювати віджет.
public struct WidgetReloadPolicy: Sendable {
    public static let minInterval: TimeInterval = 60
    var last: StationState?
    var lastAt: Date?

    public init() {}

    public mutating func shouldReload(_ new: StationState, now: Date) -> Bool {
        if let at = lastAt, now.timeIntervalSince(at) < Self.minInterval { return false }
        if let old = last,
           old.soc == new.soc,
           old.gridPresent == new.gridPresent,
           abs(old.solarW - new.solarW) < 20 { return false }
        last = new
        lastAt = now
        return true
    }
}
