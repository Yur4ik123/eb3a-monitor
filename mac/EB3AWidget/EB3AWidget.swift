import EB3AKit
import SwiftUI
import WidgetKit

struct StationEntry: TimelineEntry {
    let date: Date
    let snapshot: SharedSnapshot?
}

struct Provider: TimelineProvider {
    func placeholder(in context: Context) -> StationEntry { StationEntry(date: .now, snapshot: nil) }

    func getSnapshot(in context: Context, completion: @escaping (StationEntry) -> Void) {
        completion(entry())
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<StationEntry>) -> Void) {
        completion(Timeline(entries: [entry()], policy: .after(.now.addingTimeInterval(15 * 60))))
    }

    private func entry() -> StationEntry {
        StationEntry(date: .now, snapshot: SharedStore.containerURL.flatMap(SharedStore.read(from:)))
    }
}

struct WidgetEntryView: View {
    @Environment(\.widgetFamily) private var family
    let entry: StationEntry

    var body: some View {
        StationWidgetView(snapshot: entry.snapshot, date: entry.date, size: family == .systemSmall ? .small : .medium)
    }
}

@main
struct EB3AWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "EB3AWidget", provider: Provider()) { entry in
            WidgetEntryView(entry: entry).containerBackground(.fill.tertiary, for: .widget)
        }
        .configurationDisplayName("EB3A")
        .description("Заряд, сонце і мережа")
        .supportedFamilies([.systemSmall, .systemMedium])
    }
}
