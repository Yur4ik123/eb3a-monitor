import EB3AKit
import SwiftUI

/// Вибір станції серед EB3A поблизу.
struct StationPickerView: View {
    let link: StationLink

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("Оберіть станцію").font(.headline)
                Spacer()
                ProgressView().controlSize(.small)
            }
            if link.discovered.isEmpty {
                Text("Шукаю EB3A поблизу… Станцію не має тримати інший застосунок (наприклад, офіційний на телефоні).")
                    .font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            }
            ForEach(link.discovered) { d in
                Button { link.choose(d.id) } label: {
                    HStack {
                        Image(systemName: "bolt.batteryblock").frame(width: 18)
                        VStack(alignment: .leading, spacing: 1) {
                            Text(Station.shortName(d.name))
                            Text(d.name).font(.caption2).foregroundStyle(.secondary)
                        }
                        Spacer()
                        if d.id == link.stationID { Text("поточна").font(.caption).foregroundStyle(.secondary) }
                        Image(systemName: "wifi", variableValue: Double(Station.signalBars(rssi: d.rssi)) / 3)
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .padding(8)
                .background(.quaternary.opacity(0.5), in: .rect(cornerRadius: 8))
            }
            HStack {
                Spacer()
                Button("Скасувати") { link.cancelChoosing() }.controlSize(.small)
            }
        }
    }
}
