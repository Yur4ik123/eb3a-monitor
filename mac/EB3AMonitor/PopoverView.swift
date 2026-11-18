import EB3AKit
import SwiftUI

struct PopoverView: View {
    let model: AppModel
    @Environment(\.openWindow) private var openWindow
    var debugBusy: String? = nil
    @State private var loginOn = LoginItem.isEnabled

    private var link: StationLink { model.link }
    private var fresh: StationState? {
        guard let s = link.state, model.now.timeIntervalSince(s.updatedAt) <= MenuBarText.staleAfter else { return nil }
        return s
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            if link.choosing {
                StationPickerView(link: link)
            } else if let s = fresh {
                header(s)
                if !s.alerts.isEmpty { AlertsView(alerts: s.alerts) }
                Divider()
                row("sun.max", "Сонце", detail: "сьогодні " + formatEnergy(solarToday), s.solarPresent ? "\(s.solarW) W · \(String(format: "%.1f", s.solarV)) V" + (s.solarCharging ? " · заряджає" : "") : "не підключено")
                row("bolt", "Мережа", s.gridPresent ? "\(s.gridW) W · \(String(format: "%.0f", s.gridV)) V" : "немає")
                row("powerplug", "AC вихід", s.acOn ? "\(s.acOutW) W" : "вимкнено")
                row("cable.connector", "DC вихід", s.dcOn ? "\(s.dcOutW) W" : "вимкнено")
                Divider()
                HistoryChartView(records: model.history.last24h, now: model.now)
                Divider()
                ControlsView(link: link, state: s, busy: debugBusy)
            } else {
                Text(placeholder).foregroundStyle(.secondary).frame(maxWidth: .infinity, minHeight: 60)
            }
            Divider()
            footer
        }
        .frame(width: 332)
        .padding(14)
    }

    private func header(_ s: StationState) -> some View {
        HStack(alignment: .firstTextBaseline) {
            Text("\(s.soc)%").font(.system(size: 34, weight: .semibold, design: .rounded))
            VStack(alignment: .leading) {
                Text(stateText(s)).font(.callout)
                if s.batteryNetW > 5, let r = link.remaining {
                    Text("вистачить \(formatRemaining(r))").font(.caption).foregroundStyle(.secondary)
                }
            }
        }
    }

    private func stateText(_ s: StationState) -> String {
        if s.charging { return "заряджається" }
        if s.batteryNetW > 5 { return "розряджається · \(s.batteryNetW) W" }
        return s.gridPresent ? "від мережі (pass-through)" : "очікування"
    }

    private var solarToday: Double {
        solarEnergyWh(model.history.last24h, since: Calendar.current.startOfDay(for: model.now))
    }

    private func row(_ icon: String, _ title: String, detail: String? = nil, _ value: String) -> some View {
        HStack {
            Image(systemName: icon).frame(width: 18)
            Text(title)
            if let detail { Text(detail).font(.caption).foregroundStyle(.secondary).lineLimit(1) }
            if icon == "sun.max" {
                Button {
                    openWindow(id: "solar")
                    NSApp.activate()
                } label: { Image(systemName: "chart.bar.xaxis") }
                .buttonStyle(.borderless)
                .help("Статистика сонця")
            }
            Spacer()
            Text(value).foregroundStyle(.secondary).monospacedDigit()
        }
    }

    private var placeholder: String {
        switch link.status {
        case .bluetoothOff: "Bluetooth вимкнено або немає дозволу"
        case .paused: "Станцію звільнено"
        case .scanning: "Шукаю EB3A…"
        case .connecting, .idle: "Підключення…"
        case .connected: "Очікую дані…"
        }
    }

    private var footer: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Circle().fill(link.status == .connected ? .green : .orange).frame(width: 7, height: 7)
                Text(statusText).font(.caption).foregroundStyle(.secondary)
                Spacer()
                if link.choosing {
                    EmptyView()
                } else if link.status == .paused {
                    Button("Підключитись") { link.resume() }.controlSize(.small)
                } else {
                    Button("Звільнити станцію") { link.pause() }.controlSize(.small)
                }
            }
            HStack {
                Image(systemName: "bolt.batteryblock").foregroundStyle(.secondary)
                Text(link.stationName.map(Station.shortName) ?? "станцію не обрано").font(.caption).foregroundStyle(.secondary)
                Spacer()
                if !link.choosing {
                    Button("Змінити станцію") { link.startChoosing() }.controlSize(.small)
                }
            }
            HStack {
                Toggle("Запускати при вході", isOn: Binding(get: { loginOn }, set: { on in
                    try? LoginItem.set(on)
                    loginOn = LoginItem.isEnabled
                }))
                .toggleStyle(.checkbox).font(.caption)
                Spacer()
                Button("Вийти") { NSApplication.shared.terminate(nil) }.controlSize(.small)
            }
        }
    }

    private var statusText: String {
        switch link.status {
        case .connected: "Підключено"
        case .connecting: "Підключення…"
        case .scanning: "Пошук…"
        case .paused: "Пауза"
        case .bluetoothOff: "Bluetooth недоступний"
        case .idle: "Перепідключення…"
        }
    }
}

/// Сигнали станції (коди Axxx офіційного додатку або «регістр.біт»).
struct AlertsView: View {
    let alerts: [StationAlert]

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            ForEach(Array(alerts.enumerated()), id: \.offset) { _, a in
                HStack(alignment: .top, spacing: 8) {
                    Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.orange)
                    VStack(alignment: .leading, spacing: 2) {
                        HStack {
                            Text(a.title).font(.callout.weight(.semibold))
                            Spacer()
                            if let c = a.code { Text(c).font(.caption.monospaced()).foregroundStyle(.secondary) }
                        }
                        Text(a.detail).font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.orange.opacity(0.15), in: .rect(cornerRadius: 8))
    }
}
