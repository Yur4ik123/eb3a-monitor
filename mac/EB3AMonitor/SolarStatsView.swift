import Charts
import EB3AKit
import SwiftUI

/// Вікно «Сонце»: порівняння днів, деталі й погодинний профіль.
struct SolarStatsView: View {
    let days: [DaySummary]
    let now: Date
    @State private var selected: String?

    private let calendar = Calendar.current
    private static let shown = 30

    /// Останні 30 днів, порожні дні — нулі.
    private var series: [(date: Date, summary: DaySummary?)] {
        let byDay = Dictionary(days.map { ($0.day, $0) }, uniquingKeysWith: { $1 })
        let today = calendar.startOfDay(for: now)
        return (0..<Self.shown).reversed().map { off in
            let d = calendar.date(byAdding: .day, value: -off, to: today)!
            return (d, byDay[SolarDays.dayKey(d, calendar: calendar)])
        }
    }

    private var todayKey: String { SolarDays.dayKey(now, calendar: calendar) }
    private var selectedKey: String { selected ?? todayKey }
    private var selectedSummary: DaySummary? { days.first { $0.day == selectedKey } }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            summaryHeader
            daysChart
            Divider()
            dayDetails
            Spacer(minLength: 0)
        }
        .padding(20)
        .frame(minWidth: 520, minHeight: 560)
        .environment(\.locale, Locale(identifier: "uk_UA"))
    }

    private var summaryHeader: some View {
        let w = SolarDays.weekComparison(days, now: now, calendar: calendar)
        let best = series.compactMap(\.summary).max { $0.wh < $1.wh }
        return HStack(alignment: .top, spacing: 24) {
            stat("За 7 днів", formatEnergy(w.thisWh),
                 w.changePct.map { String(format: "%+.0f%% до попередніх 7", $0) } ?? "немає даних для порівняння")
            if let best, best.wh > 0 {
                stat("Найкращий день", formatEnergy(best.wh), label(forKey: best.day))
            }
        }
    }

    private func stat(_ title: String, _ value: String, _ caption: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title).font(.caption).foregroundStyle(.secondary)
            Text(value).font(.title2.weight(.semibold)).monospacedDigit()
            Text(caption).font(.caption).foregroundStyle(.secondary)
        }
    }

    private var daysChart: some View {
        Chart(series, id: \.date) { item in
            let key = SolarDays.dayKey(item.date, calendar: calendar)
            let partial = (item.summary?.coverage(now: now, calendar: calendar) ?? 1) < 0.9
            BarMark(x: .value("День", item.date, unit: .day), y: .value("кВт·год", (item.summary?.wh ?? 0) / 1000))
                .foregroundStyle(key == selectedKey ? Color.orange : Color.yellow.opacity(partial ? 0.35 : 0.8))
        }
        .chartXAxis {
            AxisMarks(values: .stride(by: .day, count: 5)) { v in
                AxisValueLabel {
                    if let d = v.as(Date.self) {
                        Text(d.formatted(.dateTime.day().month(.abbreviated).locale(Locale(identifier: "uk_UA"))))
                    }
                }
            }
        }
        .chartYAxis { AxisMarks { v in AxisGridLine(); AxisValueLabel { Text(String(format: "%.1f", v.as(Double.self) ?? 0)) } } }
        .chartXSelection(value: Binding(get: { nil as Date? }, set: { d in
            if let d { selected = SolarDays.dayKey(d, calendar: calendar) }
        }))
        .frame(height: 180)
    }

    @ViewBuilder
    private var dayDetails: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(label(forKey: selectedKey)).font(.headline)
            if let d = selectedSummary, d.wh > 0 {
                HStack(spacing: 24) {
                    stat("Зібрано", formatEnergy(d.wh), "")
                    if let at = d.peakAt { stat("Пік", "\(Int(d.peakW)) W", "о " + at.formatted(.dateTime.hour().minute())) }
                    if let a = d.firstAt, let b = d.lastAt {
                        stat("Генерація", a.formatted(.dateTime.hour().minute()) + "–" + b.formatted(.dateTime.hour().minute()), "")
                    }
                }
                let cov = d.coverage(now: now, calendar: calendar)
                if cov < 0.9 {
                    Label("Неповний день: дані є за \(Int(cov * 100))% часу (Mac спав або був вимкнений)", systemImage: "exclamationmark.circle")
                        .font(.caption).foregroundStyle(.secondary)
                }
                Chart(Array(d.hourlyWh.enumerated()), id: \.offset) {
                    BarMark(x: .value("Година", $0.offset), y: .value("Вт·год", $0.element)).foregroundStyle(.yellow)
                }
                .chartXScale(domain: 0...23)
                .chartXAxis { AxisMarks(values: [0, 6, 12, 18, 23]) { v in AxisValueLabel { Text("\(v.as(Int.self) ?? 0):00") } } }
                .frame(height: 120)
            } else {
                Text(selectedSummary == nil ? "Немає даних за цей день" : "Сонячної генерації не було")
                    .foregroundStyle(.secondary)
            }
        }
    }

    private func label(forKey key: String) -> String {
        guard let d = series.first(where: { SolarDays.dayKey($0.date, calendar: calendar) == key })?.date else { return key }
        let text = d.formatted(.dateTime.day().month(.wide).weekday(.wide).locale(Locale(identifier: "uk_UA")))
        return key == todayKey ? "Сьогодні, " + text : text
    }
}
