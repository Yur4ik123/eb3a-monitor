import Charts
import EB3AKit
import SwiftUI

enum WidgetSize { case small, medium }

/// Вигляд віджета; компілюється і в застосунок (для --snapshot).
struct StationWidgetView: View {
    let snapshot: SharedSnapshot?
    let date: Date
    let size: WidgetSize

    var body: some View {
        if let snap = snapshot, !snap.isStale(now: date) {
            switch size {
            case .small: small(snap)
            case .medium: HStack(spacing: 14) { summary(snap); details(snap) }
            }
        } else {
            VStack(spacing: 4) {
                Image(systemName: "battery.0percent").font(.title2)
                Text("Немає даних").font(.caption)
            }
            .foregroundStyle(.secondary)
        }
    }

    private func small(_ snap: SharedSnapshot) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            summary(snap)
            if snap.state.solarPresent {
                Label("\(snap.state.solarW) W", systemImage: "sun.max.fill").font(.caption).foregroundStyle(.yellow)
            }
        }
    }

    private func summary(_ snap: SharedSnapshot) -> some View {
        let s = snap.state
        return VStack(alignment: .leading, spacing: 4) {
            HStack(alignment: .firstTextBaseline, spacing: 4) {
                Text("\(s.soc)%").font(.system(size: 34, weight: .semibold, design: .rounded))
                if s.gridPresent { Image(systemName: "bolt.fill").foregroundStyle(.green).font(.caption) }
            }
            ProgressView(value: Double(s.soc), total: 100).tint(s.soc > 20 ? .green : .red)
            if let a = s.alerts.first {
                Label(s.alerts.count > 1 ? "\(a.title) +\(s.alerts.count - 1)" : a.title, systemImage: "exclamationmark.triangle.fill")
                    .font(.caption2).foregroundStyle(.orange).lineLimit(2)
            } else {
                Text(status(s)).font(.caption2).foregroundStyle(.secondary)
            }
            if !s.gridPresent, s.batteryNetW > 5, let r = snap.remaining {
                Label(formatRemaining(r), systemImage: "hourglass").font(.caption2).foregroundStyle(.orange)
            }
            if snap.socLast24h.count >= 4 {
                Chart(Array(snap.socLast24h.enumerated()), id: \.offset) {
                    LineMark(x: .value("t", $0.offset), y: .value("%", $0.element)).foregroundStyle(.green)
                }
                .chartYScale(domain: 0...100).chartXAxis(.hidden).chartYAxis(.hidden)
                .frame(height: 20)
            }
            Spacer(minLength: 0)
        }
        .frame(maxWidth: size == .medium ? 120 : .infinity, alignment: .leading)
    }

    private func details(_ snap: SharedSnapshot) -> some View {
        let s = snap.state
        return VStack(alignment: .leading, spacing: 7) {
            row("sun.max.fill", .yellow, s.solarPresent ? "\(s.solarW) W" : "—", "сьогодні " + formatEnergy(snap.solarTodayWh))
            row("bolt.fill", s.gridPresent ? .green : .secondary, s.gridPresent ? "\(s.gridW) W" : "без мережі", s.gridPresent ? "мережа" : "")
            row("powerplug.fill", .blue, s.acOn ? "\(s.acOutW) W" : "вимк", "AC")
            row("cable.connector", .purple, s.dcOn ? "\(s.dcOutW) W" : "вимк", "DC")
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func row(_ icon: String, _ tint: Color, _ value: String, _ caption: String) -> some View {
        HStack(spacing: 6) {
            Image(systemName: icon).foregroundStyle(tint).frame(width: 16)
            Text(value).font(.callout.weight(.medium)).monospacedDigit()
            Text(caption).font(.caption2).foregroundStyle(.secondary).lineLimit(1)
        }
    }

    private func status(_ s: StationState) -> String {
        if s.charging { return "заряд \(max(0, -s.batteryNetW)) W" }
        if s.batteryNetW > 5 { return "розряд \(s.batteryNetW) W" }
        return s.gridPresent ? "від мережі" : "очікування"
    }
}
