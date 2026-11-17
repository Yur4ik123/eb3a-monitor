#if DEBUG
import AppKit
import EB3AKit
import SwiftUI

/// Рендер поповера з тестовими даними в PNG: `EB3AMonitor --snapshot > base64`.
@MainActor
enum Snapshot {
    static func render() {
        var regs: [UInt16: UInt16] = [:]
        for b in Reg.pollBlocks { for a in b.start..<b.start + b.count { regs[a] = 0 } }
        regs[Reg.soc] = 87; regs[Reg.solarPresent] = 1; regs[Reg.solarW] = 142; regs[Reg.solarV] = 2294
        regs[Reg.acOutW] = 180; regs[Reg.acOn] = 1; regs[Reg.ac] = 1; regs[Reg.dc] = 1; regs[Reg.dcOn] = 1
        regs[Reg.led] = 4; regs[Reg.eco] = 1; regs[Reg.ecoHours] = 2; regs[Reg.chargeMode] = 0; regs[Reg.powerLifting] = 1
        let model = AppModel(startLink: false)
        model.link.injectForSnapshot(StationState(registers: regs, at: Date())!)

        let host = NSHostingView(rootView: PopoverView(model: model, debugBusy: ProcessInfo.processInfo.environment["SNAP_BUSY"]).background(Color(nsColor: .windowBackgroundColor)))
        host.appearance = NSAppearance(named: .darkAqua)
        host.frame = NSRect(origin: .zero, size: host.fittingSize)
        host.layoutSubtreeIfNeeded()
        guard let rep = host.bitmapImageRepForCachingDisplay(in: host.bounds) else { return }
        host.cacheDisplay(in: host.bounds, to: rep)
        // Контейнер sandbox закритий для інших процесів — віддаємо PNG через stdout.
        print("PNG:" + (rep.representation(using: .png, properties: [:])?.base64EncodedString() ?? ""))
    }
}
#endif
