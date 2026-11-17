import EB3AKit
import Foundation
import Observation

/// Хвилинна історія: агрегує стани, пише JSON Lines, тримає останню добу в пам'яті.
@MainActor @Observable
final class HistoryRecorder {
    private(set) var last24h: [HistoryRecord] = []

    @ObservationIgnored private var aggregator = MinuteAggregator()
    @ObservationIgnored private let store: HistoryStore
    @ObservationIgnored private var lastPrune = Date.distantPast

    init(store: HistoryStore) {
        self.store = store
        last24h = (try? store.records(since: Date().addingTimeInterval(-86400))) ?? []
    }

    /// Контейнер App Group (його читає віджет), інакше Application Support.
    static func defaultStore() -> HistoryStore {
        let fm = FileManager.default
        let dir = SharedStore.containerURL
            ?? fm.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0].appendingPathComponent("EB3AMonitor")
        try? fm.createDirectory(at: dir, withIntermediateDirectories: true)
        log.notice("history at \(dir.path, privacy: .public)")
        return HistoryStore(fileURL: dir.appendingPathComponent("history.jsonl"))
    }

    func ingest(_ s: StationState) {
        guard let r = aggregator.add(s) else { return }
        do { try store.append(r) } catch { log.error("history append: \(String(describing: error), privacy: .public)") }
        let dayAgo = s.updatedAt.addingTimeInterval(-86400)
        last24h.append(r)
        last24h.removeAll { $0.minute < dayAgo }
        if s.updatedAt.timeIntervalSince(lastPrune) > 3600 {
            try? store.prune(olderThan: s.updatedAt.addingTimeInterval(-7 * 86400))
            lastPrune = s.updatedAt
        }
    }

    #if DEBUG
    func injectForSnapshot(_ records: [HistoryRecord]) { last24h = records }
    #endif
}
