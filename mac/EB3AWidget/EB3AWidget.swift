import Charts
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

struct StationWidgetView: View {
    @Environment(\.widgetFamily) private var family
    let entry: StationEntry

    var body: some View {
        if let snap = entry.snapshot, !snap.isStale(now: entry.date) {
            content(snap)
        } else {
            VStack(spacing: 4) {
                Image(systemName: "battery.0percent").font(.title2)
                Text("Немає даних").font(.caption)
            }
            .foregroundStyle(.secondary)
        }
    }

    @ViewBuilder
    private func content(_ snap: SharedSnapshot) -> some View {
        let s = snap.state
        HStack(alignment: .top, spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Text("\(s.soc)%").font(.system(size: 38, weight: .semibold, design: .rounded)).minimumScaleFactor(0.7)
                if s.solarPresent { Label("\(s.solarW) W", systemImage: "sun.max.fill").foregroundStyle(.yellow) }
                if s.gridPresent {
                    Label("мережа", systemImage: "bolt.fill").foregroundStyle(.green)
                } else if let r = snap.remaining, s.batteryNetW > 5 {
                    Label(formatRemaining(r), systemImage: "hourglass").foregroundStyle(.orange)
                }
                Spacer(minLength: 0)
            }
            .font(.caption)
            if family == .systemMedium {
                VStack(alignment: .leading, spacing: 4) {
                    Chart(Array(snap.socLast24h.enumerated()), id: \.offset) {
                        LineMark(x: .value("t", $0.offset), y: .value("%", $0.element)).foregroundStyle(.green)
                    }
                    .chartYScale(domain: 0...100)
                    .chartXAxis(.hidden)
                    .chartYAxis(.hidden)
                    Text("AC \(s.acOn ? "\(s.acOutW) W" : "вимк") · DC \(s.dcOn ? "\(s.dcOutW) W" : "вимк")")
                        .font(.caption2).foregroundStyle(.secondary)
                }
            }
        }
    }
}

@main
struct EB3AWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "EB3AWidget", provider: Provider()) { entry in
            StationWidgetView(entry: entry).containerBackground(.fill.tertiary, for: .widget)
        }
        .configurationDisplayName("EB3A")
        .description("Заряд, сонце і мережа")
        .supportedFamilies([.systemSmall, .systemMedium])
    }
}
