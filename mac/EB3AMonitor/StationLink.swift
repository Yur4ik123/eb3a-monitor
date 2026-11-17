import AppKit
import CoreBluetooth
import EB3AKit
import Observation
import os

let log = Logger(subsystem: "com.legion.eb3amonitor", category: "link")

enum LinkError: Error {
    case notAllowed, notConnected, timeout, exception(UInt8), notConfirmed
}

/// BLE-з'єднання з EB3A: підключення, опитування, записи.
@MainActor @Observable
final class StationLink: NSObject {
    enum Status { case idle, scanning, connecting, connected, paused, bluetoothOff }

    private(set) var status: Status = .idle {
        didSet { if status != oldValue { log.notice("status \(String(describing: self.status), privacy: .public)") } }
    }
    private(set) var state: StationState?
    private(set) var remaining: TimeInterval?
    @ObservationIgnored var onState: ((StationState) -> Void)?

    @ObservationIgnored private var central: CBCentralManager!
    @ObservationIgnored private var peripheral: CBPeripheral?
    @ObservationIgnored private var writeChar: CBCharacteristic?
    @ObservationIgnored private var pending: (id: Int, assembler: ResponseAssembler, cont: CheckedContinuation<ModbusResponse, Error>)?
    @ObservationIgnored private var requestID = 0
    @ObservationIgnored private var writeQueue: [(id: Int, writes: [(address: UInt16, value: UInt16)], cont: CheckedContinuation<Void, Error>)] = []
    @ObservationIgnored private var writeID = 0
    @ObservationIgnored private var watchdog: Task<Void, Never>?
    @ObservationIgnored private var pollTask: Task<Void, Never>?
    @ObservationIgnored private var reconnectTask: Task<Void, Never>?
    @ObservationIgnored private var estimator = RuntimeEstimator()
    @ObservationIgnored private var attempt = 0
    @ObservationIgnored private var timeouts = 0

    nonisolated private static let service = CBUUID(string: "FF00")
    nonisolated private static let notifyUUID = CBUUID(string: "FF01")
    nonisolated private static let writeUUID = CBUUID(string: "FF02")
    private static let cycle: TimeInterval = 2
    private static let responseTimeout: TimeInterval = 3

    private let defaults = UserDefaults.standard
    private var isPaused: Bool {
        get { defaults.bool(forKey: "paused") }
        set { defaults.set(newValue, forKey: "paused") }
    }

    func start() {
        log.notice("start")
        central = CBCentralManager(delegate: self, queue: nil)
        NSWorkspace.shared.notificationCenter.addObserver(forName: NSWorkspace.didWakeNotification, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.wake() }
        }
    }

    #if DEBUG
    func injectForSnapshot(_ s: StationState) {
        state = s
        status = .connected
        remaining = 3 * 3600 + 40 * 60
    }
    #endif

    func pause() {
        isPaused = true
        teardown()
        status = .paused
    }

    func resume() {
        isPaused = false
        attempt = 0
        if central.state == .poweredOn { connectOrScan() } else { status = .bluetoothOff }
    }

    func write(_ writes: [(address: UInt16, value: UInt16)]) async throws {
        guard writes.allSatisfy({ WritePolicy.isAllowed(address: $0.address, value: $0.value) }) else { throw LinkError.notAllowed }
        guard status == .connected else { throw LinkError.notConnected }
        writeID += 1
        let id = writeID
        // Якщо цикл опитування мертвий, запит у черзі не повинен висіти вічно.
        Task { [weak self] in
            try? await Task.sleep(for: .seconds(12))
            guard let self, let i = self.writeQueue.firstIndex(where: { $0.id == id }) else { return }
            self.writeQueue.remove(at: i).cont.resume(throwing: LinkError.timeout)
        }
        try await withCheckedThrowingContinuation { writeQueue.append((id, writes, $0)) }
    }

    // MARK: - Підключення

    private func connectOrScan() {
        guard !isPaused, central.state == .poweredOn else { return }
        reconnectTask?.cancel()
        if let s = defaults.string(forKey: "peripheralID"), let id = UUID(uuidString: s),
           let p = central.retrievePeripherals(withIdentifiers: [id]).first {
            connect(p)
        } else {
            status = .scanning
            central.scanForPeripherals(withServices: [Self.service])
        }
    }

    private func connect(_ p: CBPeripheral) {
        peripheral = p
        p.delegate = self
        status = .connecting
        central.connect(p)
        watchdog?.cancel()
        // З'єднання без робочої підписки не повинне висіти вічно й блокувати станцію.
        watchdog = Task { [weak self] in
            try? await Task.sleep(for: .seconds(15))
            guard !Task.isCancelled, let self, self.status != .connected, self.peripheral === p else { return }
            log.error("watchdog: no notify after 15 s")
            self.recover()
        }
    }

    private func recover() {
        teardown()
        scheduleReconnect()
    }

    private func wake() {
        guard !isPaused, status != .connected else { return }
        attempt = 0
        connectOrScan()
    }

    private func scheduleReconnect() {
        guard !isPaused else { status = .paused; return }
        status = .idle
        let d = Backoff.delay(attempt: attempt)
        attempt += 1
        reconnectTask?.cancel()
        reconnectTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(d))
            guard !Task.isCancelled else { return }
            self?.connectOrScan()
        }
    }

    private func teardown() {
        watchdog?.cancel()
        pollTask?.cancel()
        pollTask = nil
        reconnectTask?.cancel()
        if central?.isScanning == true { central.stopScan() }
        if let p = peripheral, central.state == .poweredOn { central.cancelPeripheralConnection(p) }
        peripheral = nil
        writeChar = nil
        failPending(LinkError.notConnected)
    }

    private func failPending(_ error: Error) {
        if let p = pending { pending = nil; p.cont.resume(throwing: error) }
        let queued = writeQueue
        writeQueue = []
        queued.forEach { $0.cont.resume(throwing: error) }
    }

    // MARK: - Опитування

    private func startPolling() {
        pollTask?.cancel()
        pollTask = Task { [weak self] in
            while !Task.isCancelled {
                guard let self else { return }
                let t0 = Date()
                await self.drainWrites()
                guard await self.poll() else {
                    self.recover()
                    return
                }
                let rest = Self.cycle - Date().timeIntervalSince(t0)
                if rest > 0 { try? await Task.sleep(for: .seconds(rest)) }
            }
        }
    }

    /// false — з'єднання треба розірвати.
    private func poll() async -> Bool {
        do {
            var regs: [UInt16: UInt16] = [:]
            for b in Reg.pollBlocks {
                let values = try await readRegisters(start: b.start, count: b.count)
                for (i, v) in values.enumerated() { regs[b.start + UInt16(i)] = v }
            }
            timeouts = 0
            attempt = 0
            guard let s = StationState(registers: regs, at: Date()) else { return true }
            estimator.add(netW: Double(s.batteryNetW), at: s.updatedAt)
            if state.map({ s.updatedAt.timeIntervalSince($0.updatedAt) > 60 || $0.soc != s.soc }) ?? true {
                log.notice("soc \(s.soc) solar \(s.solarW)W grid \(s.gridPresent)")
            }
            state = s
            remaining = estimator.remaining(soc: s.soc)
            onState?(s)
        } catch LinkError.timeout {
            log.error("timeout")
            timeouts += 1
            if timeouts >= 3 { return false }
        } catch {
            log.error("poll error: \(String(describing: error), privacy: .public)")
            if case LinkError.notConnected = error { return false }
        }
        return true
    }

    private func readRegisters(start: UInt16, count: UInt16) async throws -> [UInt16] {
        switch try await request(Modbus.readCommand(start: start, count: count), expect: .read(count: Int(count))) {
        case .registers(let v): return v
        case .exception(let c): throw LinkError.exception(c)
        case .writeAck: throw LinkError.notConfirmed
        }
    }

    private func drainWrites() async {
        while !writeQueue.isEmpty {
            let job = writeQueue.removeFirst()
            let t0 = Date()
            do {
                for w in job.writes { try await performWrite(w.address, w.value) }
                log.notice("write \(job.writes.map { "\($0.address)=\($0.value)" }.joined(separator: ","), privacy: .public) ok \(Int(Date().timeIntervalSince(t0) * 1000))ms")
                job.cont.resume()
            } catch {
                log.error("write \(job.writes.map { "\($0.address)=\($0.value)" }.joined(separator: ","), privacy: .public) failed: \(String(describing: error), privacy: .public)")
                job.cont.resume(throwing: error)
            }
        }
    }

    private func performWrite(_ address: UInt16, _ value: UInt16) async throws {
        let cmd = Modbus.writeCommand(address: address, value: value)
        if case .exception(let c) = try await request(cmd, expect: .write(echo: cmd)) { throw LinkError.exception(c) }
        let deadline = Date().addingTimeInterval(3)
        while Date() < deadline {
            if try await readRegisters(start: address, count: 1).first == value { return }
            try? await Task.sleep(for: .milliseconds(100))
        }
        throw LinkError.notConfirmed
    }

    private func request(_ cmd: Data, expect: ResponseAssembler.Expect) async throws -> ModbusResponse {
        guard let p = peripheral, let ch = writeChar else { throw LinkError.notConnected }
        requestID += 1
        let id = requestID
        return try await withCheckedThrowingContinuation { cont in
            if let old = pending { old.cont.resume(throwing: LinkError.notConnected) }
            pending = (id, ResponseAssembler(expect: expect), cont)
            p.writeValue(cmd, for: ch, type: .withResponse)
            Task { [weak self] in
                try? await Task.sleep(for: .seconds(Self.responseTimeout))
                guard let self, let cur = self.pending, cur.id == id else { return }
                self.pending = nil
                cur.cont.resume(throwing: LinkError.timeout)
            }
        }
    }
}

// MARK: - CoreBluetooth (колбеки на main queue)

extension StationLink: CBCentralManagerDelegate, CBPeripheralDelegate {
    nonisolated func centralManagerDidUpdateState(_ central: CBCentralManager) {
        let st = central.state.rawValue
        log.notice("central state \(st, privacy: .public)")
        MainActor.assumeIsolated {
            if central.state == .poweredOn {
                if isPaused { status = .paused } else { connectOrScan() }
            } else {
                teardown()
                status = .bluetoothOff
                state = nil
            }
        }
    }

    nonisolated func centralManager(_ central: CBCentralManager, didDiscover peripheral: CBPeripheral,
                                    advertisementData: [String: Any], rssi RSSI: NSNumber) {
        let name = peripheral.name ?? advertisementData[CBAdvertisementDataLocalNameKey] as? String ?? ""
        log.notice("discovered \(name, privacy: .public)")
        MainActor.assumeIsolated {
            guard name.hasPrefix("EB3A") else { return }
            central.stopScan()
            defaults.set(peripheral.identifier.uuidString, forKey: "peripheralID")
            connect(peripheral)
        }
    }

    nonisolated func centralManager(_ central: CBCentralManager, didConnect peripheral: CBPeripheral) {
        peripheral.discoverServices([StationLink.service])
    }

    nonisolated func centralManager(_ central: CBCentralManager, didFailToConnect peripheral: CBPeripheral, error: Error?) {
        log.error("connect failed: \(String(describing: error), privacy: .public)")
        MainActor.assumeIsolated {
            guard peripheral === self.peripheral else { return }
            recover()
        }
    }

    nonisolated func centralManager(_ central: CBCentralManager, didDisconnectPeripheral peripheral: CBPeripheral, error: Error?) {
        MainActor.assumeIsolated {
            // Запізнілий колбек від попереднього з'єднання (після pause/resume) ігноруємо.
            guard peripheral === self.peripheral else { return }
            watchdog?.cancel()
            pollTask?.cancel()
            pollTask = nil
            self.peripheral = nil
            writeChar = nil
            failPending(LinkError.notConnected)
            scheduleReconnect()
        }
    }

    nonisolated func peripheral(_ peripheral: CBPeripheral, didDiscoverServices error: Error?) {
        guard let s = peripheral.services?.first(where: { $0.uuid == StationLink.service }) else { return }
        peripheral.discoverCharacteristics([StationLink.notifyUUID, StationLink.writeUUID], for: s)
    }

    nonisolated func peripheral(_ peripheral: CBPeripheral, didDiscoverCharacteristicsFor service: CBService, error: Error?) {
        let chars = service.characteristics ?? []
        MainActor.assumeIsolated {
            writeChar = chars.first { $0.uuid == Self.writeUUID }
            if let n = chars.first(where: { $0.uuid == Self.notifyUUID }) { peripheral.setNotifyValue(true, for: n) }
        }
    }

    nonisolated func peripheral(_ peripheral: CBPeripheral, didUpdateNotificationStateFor characteristic: CBCharacteristic, error: Error?) {
        let ok = characteristic.isNotifying && error == nil
        MainActor.assumeIsolated {
            guard ok, writeChar != nil else { return }
            watchdog?.cancel()
            status = .connected
            startPolling()
        }
    }

    nonisolated func peripheral(_ peripheral: CBPeripheral, didUpdateValueFor characteristic: CBCharacteristic, error: Error?) {
        guard let data = characteristic.value else { return }
        MainActor.assumeIsolated {
            guard var p = pending else { return }
            do {
                if let r = try p.assembler.append(data) {
                    pending = nil
                    p.cont.resume(returning: r)
                } else {
                    pending = p
                }
            } catch {
                pending = nil
                p.cont.resume(throwing: error)
            }
        }
    }
}
