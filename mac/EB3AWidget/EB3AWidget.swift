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
        let now = entry()
        var entries = [now]
        // Окремий запис на момент застарівання: без нових даних віджет покаже «Немає даних».
        if let stale = now.snapshot?.staleAt, stale > now.date {
            entries.append(StationEntry(date: stale, snapshot: now.snapshot))
        }
        completion(Timeline(entries: entries, policy: .after(.now.addingTimeInterval(15 * 60))))
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
