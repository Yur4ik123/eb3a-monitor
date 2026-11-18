import EB3AKit
import SwiftUI

@MainActor @Observable
final class AppModel {
    let link = StationLink()
    let history: HistoryRecorder
    /// Тік для перевірки застарілості (TimelineView у мітці MenuBarExtra зациклює рендер).
    private(set) var now = Date()
    @ObservationIgnored private var ticker: Timer?

    init(startLink: Bool = true) {
        history = startLink ? HistoryRecorder.makeDefault()
            : HistoryRecorder(store: HistoryStore(fileURL: FileManager.default.temporaryDirectory.appendingPathComponent("snap.jsonl")))
        let history = history
        let bridge = WidgetBridge()
        let link = link
        link.onState = { s in
            history.ingest(s)
            bridge.publish(state: s, remaining: link.remaining, history: history.last24h)
        }
        if startLink { link.start() }
        ticker = Timer.scheduledTimer(withTimeInterval: 5, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.now = Date() }
        }
    }

    var menuBarText: String {
        MenuBarText.make(state: link.state, now: max(now, link.state?.updatedAt ?? now))
    }
}

@main
struct EB3AMonitorApp: App {
    @State private var model = AppModel()

    init() {
        #if DEBUG
        if CommandLine.arguments.contains("--snapshot") {
            Snapshot.render()
            exit(0)
        }
        #endif
    }

    var body: some Scene {
        MenuBarExtra {
            PopoverView(model: model)
        } label: {
            Text(model.menuBarText)
        }
        .menuBarExtraStyle(.window)

        Window("Сонце", id: "solar") {
            SolarStatsView(days: model.history.days, now: model.now)
        }
        .defaultSize(width: 560, height: 620)
    }
}
