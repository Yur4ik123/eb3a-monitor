import EB3AKit
import Foundation
import Observation

/// Хвилинна історія: агрегує стани, пише JSON Lines, тримає останню добу в пам'яті.
@MainActor @Observable
final class HistoryRecorder {
    private(set) var last24h: [HistoryRecord] = []
    /// Денні підсумки сонця (90 днів).
    private(set) var days: [DaySummary] = []

    @ObservationIgnored private var aggregator = MinuteAggregator()
    @ObservationIgnored private let store: HistoryStore
    @ObservationIgnored private var lastPrune = Date.distantPast
    @ObservationIgnored private let daysStore: SolarDaysStore?
    @ObservationIgnored private let calendar = Calendar.current
    static let keepDays = 90

    init(store: HistoryStore, daysStore: SolarDaysStore? = nil) {
        self.store = store
        self.daysStore = daysStore
        let now = Date()
        last24h = (try? store.records(since: now.addingTimeInterval(-86400))) ?? []
        guard let daysStore else { return }
        // Бекфіл з хвилинної історії (до 7 днів) поверх збережених підсумків.
        let week = (try? store.records(since: now.addingTimeInterval(-7 * 86400))) ?? []
        days = SolarDays.merge(daysStore.load(), SolarDays.build(from: week, calendar: calendar),
                               keepDays: Self.keepDays, now: now, calendar: calendar)
        try? daysStore.save(days)
    }

    /// Контейнер App Group (його читає віджет), інакше Application Support.
    static func makeDefault() -> HistoryRecorder {
        let dir = defaultDir()
        return HistoryRecorder(store: HistoryStore(fileURL: dir.appendingPathComponent("history.jsonl")),
                               daysStore: SolarDaysStore(fileURL: dir.appendingPathComponent("solar-days.json")))
    }

    static func defaultDir() -> URL {
        let fm = FileManager.default
        let dir = SharedStore.containerURL
            ?? fm.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0].appendingPathComponent("EB3AMonitor")
        try? fm.createDirectory(at: dir, withIntermediateDirectories: true)
        log.notice("history at \(dir.path, privacy: .public)")
        return dir
    }

    func ingest(_ s: StationState) {
        guard let r = aggregator.add(s) else { return }
        do { try store.append(r) } catch { log.error("history append: \(String(describing: error), privacy: .public)") }
        let dayAgo = s.updatedAt.addingTimeInterval(-86400)
        last24h.append(r)
        last24h.removeAll { $0.minute < dayAgo }
        updateToday(now: s.updatedAt)
        if s.updatedAt.timeIntervalSince(lastPrune) > 3600 {
            try? store.prune(olderThan: s.updatedAt.addingTimeInterval(-7 * 86400))
            lastPrune = s.updatedAt
        }
    }

    private func updateToday(now: Date) {
        guard let daysStore else { return }
        let key = SolarDays.dayKey(now, calendar: calendar)
        let today = SolarDays.build(from: last24h.filter { SolarDays.dayKey($0.minute, calendar: calendar) == key }, calendar: calendar)
        days = SolarDays.merge(days, today, keepDays: Self.keepDays, now: now, calendar: calendar)
        do { try daysStore.save(days) } catch { log.error("solar days save: \(String(describing: error), privacy: .public)") }
    }

    #if DEBUG
    func injectDaysForSnapshot(_ d: [DaySummary]) { days = d }
    func injectForSnapshot(_ records: [HistoryRecord]) { last24h = records }
    #endif
}
