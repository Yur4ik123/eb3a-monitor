import Foundation

public struct HistoryRecord: Codable, Equatable, Sendable {
    public var minute: Date
    public var soc: Int
    public var solarW, gridW, acOutW, dcOutW: Double
    public var gridPresent, solarCharging: Bool

    public init(minute: Date, soc: Int, solarW: Double, gridW: Double, acOutW: Double, dcOutW: Double,
                gridPresent: Bool, solarCharging: Bool) {
        self.minute = minute
        self.soc = soc
        self.solarW = solarW
        self.gridW = gridW
        self.acOutW = acOutW
        self.dcOutW = dcOutW
        self.gridPresent = gridPresent
        self.solarCharging = solarCharging
    }
}

/// Збирає стани в хвилинні агрегати.
public struct MinuteAggregator: Sendable {
    var minute: Date?
    var states: [StationState] = []

    public init() {}

    public mutating func add(_ s: StationState) -> HistoryRecord? {
        let m = Date(timeIntervalSince1970: (s.updatedAt.timeIntervalSince1970 / 60).rounded(.down) * 60)
        defer {
            if minute != m { minute = m; states = [] }
            states.append(s)
        }
        guard let cur = minute, cur != m, !states.isEmpty else { return nil }
        return aggregate(cur)
    }

    func aggregate(_ m: Date) -> HistoryRecord {
        func avg(_ f: (StationState) -> Int) -> Double { Double(states.map(f).reduce(0, +)) / Double(states.count) }
        return HistoryRecord(minute: m, soc: states.last!.soc,
                             solarW: avg(\.solarW), gridW: avg(\.gridW), acOutW: avg(\.acOutW), dcOutW: avg(\.dcOutW),
                             gridPresent: states.contains(where: \.gridPresent),
                             solarCharging: states.contains(where: \.solarCharging))
    }
}

/// JSON Lines, по рядку на хвилину.
public final class HistoryStore: @unchecked Sendable {
    let fileURL: URL
    let encoder: JSONEncoder = {
        let e = JSONEncoder()
        e.dateEncodingStrategy = .secondsSince1970
        return e
    }()
    let decoder: JSONDecoder = {
        let d = JSONDecoder()
        d.dateDecodingStrategy = .secondsSince1970
        return d
    }()

    public init(fileURL: URL) { self.fileURL = fileURL }

    public func append(_ r: HistoryRecord) throws {
        let line = try encoder.encode(r) + Data("\n".utf8)
        if !FileManager.default.fileExists(atPath: fileURL.path) {
            try line.write(to: fileURL)
            return
        }
        let h = try FileHandle(forWritingTo: fileURL)
        defer { try? h.close() }
        try h.seekToEnd()
        try h.write(contentsOf: line)
    }

    public func records(since: Date) throws -> [HistoryRecord] {
        guard let data = try? Data(contentsOf: fileURL) else { return [] }
        return data.split(separator: UInt8(ascii: "\n"))
            .compactMap { try? decoder.decode(HistoryRecord.self, from: Data($0)) }
            .filter { $0.minute >= since }
    }

    public func prune(olderThan date: Date) throws {
        let keep = try records(since: date)
        let data = try keep.reduce(into: Data()) { $0 += try encoder.encode($1) + Data("\n".utf8) }
        try data.write(to: fileURL, options: .atomic)
    }
}

/// Енергія від сонця: кожен запис — середня потужність за хвилину.
public func solarEnergyWh(_ records: [HistoryRecord], since: Date) -> Double {
    records.filter { $0.minute >= since }.reduce(0) { $0 + $1.solarW / 60 }
}

public func formatEnergy(_ wh: Double) -> String {
    wh < 100 ? "\(Int(wh.rounded())) Вт·год" : String(format: "%.2f кВт·год", wh / 1000).replacingOccurrences(of: ".", with: ",")
}
