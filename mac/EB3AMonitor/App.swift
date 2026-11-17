import EB3AKit
import SwiftUI

@MainActor @Observable
final class AppModel {
    let link = StationLink()
    /// Тік для перевірки застарілості (TimelineView у мітці MenuBarExtra зациклює рендер).
    private(set) var now = Date()
    @ObservationIgnored private var ticker: Timer?

    init() {
        link.start()
        ticker = Timer.scheduledTimer(withTimeInterval: 5, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.now = Date() }
        }
    }

    var menuBarText: String {
        MenuBarText.make(state: link.state, remaining: link.remaining, now: max(now, link.state?.updatedAt ?? now))
    }
}

@main
struct EB3AMonitorApp: App {
    @State private var model = AppModel()

    var body: some Scene {
        MenuBarExtra {
            PopoverView(model: model)
        } label: {
            Text(model.menuBarText)
        }
        .menuBarExtraStyle(.window)
    }
}
