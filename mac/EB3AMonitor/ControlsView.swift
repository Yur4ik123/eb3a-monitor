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
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                if Self.acControlVerified {
                    toggle("AC", key: "ac", isOn: state.acCommand) { on in
                        if !on && !state.gridPresent { confirmACOff = true } else { send("ac", [(Reg.ac, on ? 1 : 0)]) }
                    }
                } else {
                    Label("AC: не перевірено", systemImage: "exclamationmark.triangle").font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
                toggle("DC", key: "dc", isOn: state.dcCommand) { send("dc", [(Reg.dc, $0 ? 1 : 0)]) }
            }

            picker("Ліхтар", key: "led", current: state.led.raw,
                   options: [(4, "Вимк"), (1, "Слабкий"), (2, "Сильний"), (3, "SOS")]) { send("led", [(Reg.led, $0)]) }

            picker("Заряд" + unknownSuffix(state.chargeMode), key: "charge", current: state.chargeMode.raw,
                   options: [(0, "Standard"), (1, "Silent"), (2, "Turbo")]) { send("charge", [(Reg.chargeMode, $0)]) }

            HStack {
                toggle("ECO", key: "eco", isOn: state.ecoOn) { send("eco", WritePolicy.ecoWrites(on: $0)) }
                if state.ecoOn {
                    picker("", key: "ecoHours", current: UInt16(state.ecoHours),
                           options: (1...4).map { (UInt16($0), "\($0) год") }) { send("ecoHours", [(Reg.ecoHours, $0)]) }
                }
            }

            toggle("Power lifting", key: "lift", isOn: state.powerLifting) { send("lift", [(Reg.powerLifting, $0 ? 1 : 0)]) }

            if let error { Text(error).font(.caption).foregroundStyle(.red) }
        }
        .disabled(busy != nil)
        .confirmationDialog("Вимкнути AC? Мережі немає — навантаження знеструмиться.", isPresented: $confirmACOff) {
            Button("Вимкнути AC", role: .destructive) { send("ac", [(Reg.ac, 0)]) }
        }
    }

    private func unknownSuffix(_ m: ChargeMode) -> String {
        if case .unknown(let n) = m { return " (інший: \(n))" }
        return ""
    }

    private func toggle(_ title: String, key: String, isOn: Bool, action: @escaping (Bool) -> Void) -> some View {
        HStack(spacing: 4) {
            Toggle(title, isOn: Binding(get: { isOn }, set: action))
                .toggleStyle(.switch)
                .controlSize(.small)
            ProgressView().controlSize(.mini).frame(width: 16).opacity(busy == key ? 1 : 0)
        }
    }

    private func picker(_ title: String, key: String, current: UInt16?, options: [(UInt16, String)],
                        action: @escaping (UInt16) -> Void) -> some View {
        HStack {
            if !title.isEmpty { Text(title).font(.caption).foregroundStyle(.secondary) }
            Picker(title, selection: Binding(get: { current ?? UInt16.max }, set: action)) {
                ForEach(options, id: \.0) { Text($0.1).tag($0.0) }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            ProgressView().controlSize(.mini).frame(width: 16).opacity(busy == key ? 1 : 0)
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
