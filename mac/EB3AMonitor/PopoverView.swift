import EB3AKit
import SwiftUI

struct PopoverView: View {
    let model: AppModel
    @State private var loginOn = LoginItem.isEnabled

    private var link: StationLink { model.link }
    private var fresh: StationState? {
        guard let s = link.state, model.now.timeIntervalSince(s.updatedAt) <= MenuBarText.staleAfter else { return nil }
        return s
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            if let s = fresh {
                header(s)
                if s.overTemp {
                    Label("Перегрів станції", systemImage: "thermometer.high")
                        .foregroundStyle(.white).padding(6).frame(maxWidth: .infinity).background(.red, in: .rect(cornerRadius: 6))
                }
                Divider()
                row("sun.max", "Сонце", s.solarPresent ? "\(s.solarW) W · \(String(format: "%.1f", s.solarV)) V" + (s.solarCharging ? " · заряджає" : "") : "не підключено")
                row("bolt", "Мережа", s.gridPresent ? "\(s.gridW) W · \(String(format: "%.0f", s.gridV)) V" : "немає")
                row("powerplug", "AC вихід", s.acOn ? "\(s.acOutW) W" : "вимкнено")
                row("cable.connector", "DC вихід", s.dcOn ? "\(s.dcOutW) W" : "вимкнено")
                Divider()
                ControlsView(link: link, state: s)
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

    private func row(_ icon: String, _ title: String, _ value: String) -> some View {
        HStack {
            Image(systemName: icon).frame(width: 18)
            Text(title)
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
                if link.status == .paused {
                    Button("Підключитись") { link.resume() }.controlSize(.small)
                } else {
                    Button("Звільнити станцію") { link.pause() }.controlSize(.small)
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
