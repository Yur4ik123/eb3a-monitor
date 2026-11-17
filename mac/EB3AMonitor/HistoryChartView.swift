import Charts
import EB3AKit
import SwiftUI

/// Дві смуги за 24 год зі спільною віссю часу: заряд % і сонце W.
struct HistoryChartView: View {
    let records: [HistoryRecord]
    let now: Date

    private var start: Date { now.addingTimeInterval(-86400) }

    var body: some View {
        if records.count < 2 {
            Text("Історія з'явиться за кілька хвилин").font(.caption).foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, minHeight: 40)
        } else {
            VStack(alignment: .leading, spacing: 6) {
                Text("За добу").font(.caption).foregroundStyle(.secondary)
                Chart(records, id: \.minute) {
                    LineMark(x: .value("Час", $0.minute), y: .value("Заряд", $0.soc))
                        .foregroundStyle(.green)
                        .interpolationMethod(.monotone)
                }
                .chartYScale(domain: 0...100)
                .chartYAxis {
                    AxisMarks(values: [0, 50, 100]) { value in
                        AxisGridLine()
                        if let v = value.as(Int.self), v > 0 { AxisValueLabel { Text("\(v)%") } }
                    }
                }
                .chartXScale(domain: start...now)
                .chartXAxis(.hidden)
                .frame(height: 64)

                Chart(records, id: \.minute) {
                    AreaMark(x: .value("Час", $0.minute), y: .value("Сонце", $0.solarW))
                        .foregroundStyle(.yellow.opacity(0.5))
                }
                .chartXScale(domain: start...now)
                .chartXAxis {
                    AxisMarks(values: .stride(by: .hour, count: 6)) { _ in
                        AxisGridLine()
                        AxisValueLabel(format: .dateTime.hour())
                    }
                }
                .chartYAxis {
                    AxisMarks(values: .automatic(desiredCount: 2)) { value in
                        AxisValueLabel { Text("\(value.as(Int.self) ?? 0)W") }
                    }
                }
                .frame(height: 48)
            }
        }
    }
}
