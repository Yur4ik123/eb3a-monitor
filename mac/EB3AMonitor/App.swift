import EB3AKit
import SwiftUI

@MainActor @Observable
final class AppModel {
    let link = StationLink()

    init() {
        link.start()
    }
}

@main
struct EB3AMonitorApp: App {
    @State private var model = AppModel()

    var body: some Scene {
        MenuBarExtra {
            Text(String(describing: model.link.status)).padding()
        } label: {
            TimelineView(.periodic(from: .now, by: 5)) { ctx in
                Text(MenuBarText.make(state: model.link.state, remaining: model.link.remaining, now: ctx.date))
            }
        }
        .menuBarExtraStyle(.window)
    }
}
