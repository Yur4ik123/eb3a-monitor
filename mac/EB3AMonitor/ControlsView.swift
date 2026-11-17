import EB3AKit
import SwiftUI

struct ControlsView: View {
    /// Запис 3007 вмикається лише після ручної перевірки на станції.
    static let acControlVerified = false

    let link: StationLink
    let state: StationState

    @State private var busy: String?
    @State private var error: String?
    @State private var confirmACOff = false

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Grid(alignment: .leading, horizontalSpacing: 8, verticalSpacing: 8) {
                if Self.acControlVerified {
                    switchRow("AC вихід", key: "ac", isOn: state.acCommand) { on in
                        if !on && !state.gridPresent { confirmACOff = true } else { send("ac", [(Reg.ac, on ? 1 : 0)]) }
                    }
                } else {
                    row("AC вихід", key: "ac") {
                        Text("не перевірено").font(.caption).foregroundStyle(.secondary)
                    }
                }
                switchRow("DC вихід", key: "dc", isOn: state.dcCommand) { send("dc", [(Reg.dc, $0 ? 1 : 0)]) }
                segmentRow("Ліхтар", key: "led", current: state.led.raw,
                           options: [(4, "Вимк"), (1, "Слабкий"), (2, "Сильний"), (3, "SOS")]) { send("led", [(Reg.led, $0)]) }
                segmentRow("Заряд", key: "charge", current: state.chargeMode.raw,
                           options: [(0, "Standard"), (1, "Silent"), (2, "Turbo")]) { send("charge", [(Reg.chargeMode, $0)]) }
                switchRow("ECO", key: "eco", isOn: state.ecoOn) { send("eco", WritePolicy.ecoWrites(on: $0)) }
                if state.ecoOn {
                    segmentRow("Таймер ECO", key: "ecoHours", current: UInt16(state.ecoHours),
                               options: (1...4).map { (UInt16($0), "\($0) год") }) { send("ecoHours", [(Reg.ecoHours, $0)]) }
                }
                switchRow("Power lifting", key: "lift", isOn: state.powerLifting) { send("lift", [(Reg.powerLifting, $0 ? 1 : 0)]) }
            }
            if case .unknown(let n) = state.chargeMode {
                Text("Режим заряду: інший (\(n))").font(.caption).foregroundStyle(.secondary)
            }
            if let error { Text(error).font(.caption).foregroundStyle(.red) }
        }
        .disabled(busy != nil)
        .confirmationDialog("Вимкнути AC? Мережі немає — навантаження знеструмиться.", isPresented: $confirmACOff) {
            Button("Вимкнути AC", role: .destructive) { send("ac", [(Reg.ac, 0)]) }
        }
    }

    /// Рядок сітки: підпис зі спінером (фіксована ширина) · контрол.
    private func row(_ title: String, key: String, @ViewBuilder content: () -> some View) -> some View {
        GridRow {
            HStack(spacing: 4) {
                Text(title).font(.callout).foregroundStyle(.secondary).lineLimit(1)
                Spacer(minLength: 0)
                ProgressView().controlSize(.mini).opacity(busy == key ? 1 : 0)
            }
            .frame(width: 96)
            content().frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private func switchRow(_ title: String, key: String, isOn: Bool, action: @escaping (Bool) -> Void) -> some View {
        row(title, key: key) {
            Toggle(title, isOn: Binding(get: { isOn }, set: action))
                .toggleStyle(.switch)
                .controlSize(.small)
                .labelsHidden()
        }
    }

    private func segmentRow(_ title: String, key: String, current: UInt16?, options: [(UInt16, String)],
                            action: @escaping (UInt16) -> Void) -> some View {
        row(title, key: key) {
            Picker(title, selection: Binding(get: { current ?? UInt16.max }, set: action)) {
                ForEach(options, id: \.0) { Text($0.1).tag($0.0) }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .controlSize(.small)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private func send(_ key: String, _ writes: [(address: UInt16, value: UInt16)]) {
        busy = key
        error = nil
        Task {
            do {
                try await link.write(writes)
            } catch {
                self.error = "Не вдалося: \(error)"
                Task { try? await Task.sleep(for: .seconds(3)); self.error = nil }
            }
            busy = nil
        }
    }
}
