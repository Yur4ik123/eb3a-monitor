import EB3AKit
import Foundation
import WidgetKit

/// Пише знімок у контейнер групи і просить систему оновити віджет при значущих змінах.
@MainActor
final class WidgetBridge {
    private var policy = WidgetReloadPolicy()
    private var lastWrite = Date.distantPast

    func publish(state: StationState, remaining: TimeInterval?, history: [HistoryRecord]) {
        let reload = policy.shouldReload(state, now: state.updatedAt)
        guard reload || state.updatedAt.timeIntervalSince(lastWrite) >= 30, let dir = SharedStore.containerURL else { return }
        let snap = SharedSnapshot(state: state, remaining: remaining,
                                  socLast24h: SharedSnapshot.socSeries(from: history, now: state.updatedAt))
        do {
            try SharedStore.write(snap, to: dir)
            lastWrite = state.updatedAt
            if reload { WidgetCenter.shared.reloadAllTimelines() }
        } catch {
            log.error("widget snapshot: \(String(describing: error), privacy: .public)")
        }
    }
}
