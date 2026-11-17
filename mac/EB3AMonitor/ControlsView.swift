import EB3AKit
import SwiftUI

struct ControlsView: View {
    /// Запис 3007 вмикається лише після ручної перевірки на станції.
    static let acControlVerified = false

    let link: StationLink
    let state: StationState

    @State private var busy: String?

    init(link: StationLink, state: StationState, busy: String? = nil) {
        self.link = link
        self.state = state
        _busy = State(initialValue: busy)
    }
    @State private var error: String?
    @State private var confirmACOff = false

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            if Self.acControlVerified {
                switchRow("AC вихід", key: "ac", isOn: state.acCommand) { on in
                    if !on && !state.gridPresent { confirmACOff = true } else { send("ac", [(Reg.ac, on ? 1 : 0)]) }
                }
            } else {
                HStack {
                    label("AC вихід", key: "ac")
                    Text("не перевірено").font(.caption).foregroundStyle(.secondary)
                }
            }
            switchRow("DC вихід", key: "dc", isOn: state.dcCommand) { send("dc", [(Reg.dc, $0 ? 1 : 0)]) }
            switchRow("ECO", key: "eco", isOn: state.ecoOn) { send("eco", WritePolicy.ecoWrites(on: $0)) }
            switchRow("Power lifting", key: "lift", isOn: state.powerLifting) { send("lift", [(Reg.powerLifting, $0 ? 1 : 0)]) }
            segmentRow("Ліхтар", key: "led", current: state.led.raw,
                       options: [(4, "Вимк"), (1, "Слабкий"), (2, "Сильний"), (3, "SOS")]) { send("led", [(Reg.led, $0)]) }
            segmentRow("Режим заряду" + unknownSuffix, key: "charge", current: state.chargeMode.raw,
                       options: [(0, "Standard"), (1, "Silent"), (2, "Turbo")]) { send("charge", [(Reg.chargeMode, $0)]) }
            if state.ecoOn {
                segmentRow("Таймер ECO", key: "ecoHours", current: UInt16(state.ecoHours),
                           options: (1...4).map { (UInt16($0), "\($0) год") }) { send("ecoHours", [(Reg.ecoHours, $0)]) }
            }
            if let error { Text(error).font(.caption).foregroundStyle(.red).lineLimit(2) }
        }
        // Не .disabled: у неактивному стані сегменти macOS 26 ширшають і вікно «розлазиться».
        .allowsHitTesting(busy == nil)
        .confirmationDialog("Вимкнути AC? Мережі немає — навантаження знеструмиться.", isPresented: $confirmACOff) {
            Button("Вимкнути AC", role: .destructive) { send("ac", [(Reg.ac, 0)]) }
        }
    }

    private var unknownSuffix: String {
        if case .unknown(let n) = state.chargeMode { return " (інший: \(n))" }
        return ""
    }

    private func label(_ title: String, key: String) -> some View {
        HStack(spacing: 4) {
            Text(title).font(.callout).foregroundStyle(.secondary).lineLimit(1)
            Spacer(minLength: 0)
            ProgressView().controlSize(.mini).opacity(busy == key ? 1 : 0)
        }
        .frame(width: 110)
    }

    private func switchRow(_ title: String, key: String, isOn: Bool, action: @escaping (Bool) -> Void) -> some View {
        HStack {
            label(title, key: key)
            Toggle(title, isOn: Binding(get: { isOn }, set: action))
                .toggleStyle(.switch)
                .controlSize(.small)
                .labelsHidden()
            Spacer(minLength: 0)
        }
    }

    /// Підпис над сегментами: сегментам — уся ширина вікна.
    private func segmentRow(_ title: String, key: String, current: UInt16?, options: [(UInt16, String)],
                            action: @escaping (UInt16) -> Void) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            label(title, key: key)
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
        guard busy == nil else { return }
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
