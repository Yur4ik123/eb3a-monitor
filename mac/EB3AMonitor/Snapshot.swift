#if DEBUG
import AppKit
import EB3AKit
import SwiftUI

/// Рендер поповера з тестовими даними в PNG: `EB3AMonitor --snapshot > base64`.
@MainActor
enum Snapshot {
    /// 2x незалежно від екрана, щоб скриншоти були чіткими.
    static func retinaRep(_ view: NSView) -> NSBitmapImageRep? {
        let size = view.bounds.size
        let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: Int(size.width * 2), pixelsHigh: Int(size.height * 2),
                                   bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                                   colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)
        rep?.size = size
        return rep
    }

    static func emit(_ view: some View) {
        let host = NSHostingView(rootView: view)
        host.appearance = NSAppearance(named: .darkAqua)
        host.frame = NSRect(origin: .zero, size: host.fittingSize)
        host.layoutSubtreeIfNeeded()
        guard let rep = retinaRep(host) else { return }
        host.cacheDisplay(in: host.bounds, to: rep)
        print("PNG:" + (rep.representation(using: .png, properties: [:])?.base64EncodedString() ?? ""))
    }

    static func render() {
        var regs: [UInt16: UInt16] = [:]
        for b in Reg.pollBlocks { for a in b.start..<b.start + b.count { regs[a] = 0 } }
        regs[Reg.soc] = 87; regs[Reg.solarPresent] = 1; regs[Reg.solarW] = 142; regs[Reg.solarV] = 2294
        regs[Reg.acOutW] = 180; regs[Reg.acOn] = 1; regs[Reg.ac] = 1; regs[Reg.dc] = 1; regs[Reg.dcOn] = 1
        if ProcessInfo.processInfo.environment["SNAP_ALERT"] != nil { regs[54] = 2; regs[Reg.gridPresent] = 1; regs[Reg.gridV] = 1911 }
        regs[Reg.led] = 4; regs[Reg.eco] = 1; regs[Reg.ecoHours] = 2; regs[Reg.chargeMode] = 0; regs[Reg.powerLifting] = 1
        let model = AppModel(startLink: false)
        model.link.injectForSnapshot(StationState(registers: regs, at: Date())!)
        model.link.nameOverride = "EB3A2200000000001"
        if ProcessInfo.processInfo.environment["SNAP_PICKER"] != nil { model.link.injectChoosingForSnapshot() }
        let now = Date()
        model.history.injectForSnapshot((0..<1440).map { i in
            let t = now.addingTimeInterval(Double(i - 1440) * 60)
            let c = Calendar.current.dateComponents([.hour, .minute], from: t)
            let h = Double(c.hour!) + Double(c.minute!) / 60
            let sun = max(0, sin((h - 7) / 11 * .pi)) * 180
            let soc = Int(55 + 35 * max(0, sin((h - 9) / 10 * .pi)))
            return HistoryRecord(minute: t, soc: soc, solarW: sun, gridW: 0,
                                 acOutW: 100, dcOutW: 0, gridPresent: false, solarCharging: sun > 0)
        })

        if ProcessInfo.processInfo.environment["SNAP_SOLAR"] != nil {
            let cal = Calendar.current
            let today = cal.startOfDay(for: now)
            let fake: [DaySummary] = (0..<30).compactMap { (off: Int) -> DaySummary? in
                guard off != 9 else { return nil }
                let day = cal.date(byAdding: .day, value: -off, to: today)!
                let k = Double((off * 37) % 11) / 10 + 0.2
                let hourly = (0..<24).map { h in max(0, sin(Double(h - 7) / 11 * .pi)) * 140 * k }
                let peakH = 12 + off % 3
                return DaySummary(day: SolarDays.dayKey(day, calendar: cal), wh: hourly.reduce(0, +), hourlyWh: hourly,
                                  peakW: 180 * k, peakAt: day.addingTimeInterval(Double(peakH) * 3600 + 1500),
                                  firstAt: day.addingTimeInterval(7.5 * 3600), lastAt: day.addingTimeInterval(17.2 * 3600),
                                  minutesCovered: off == 4 ? 700 : (off == 0 ? Int(now.timeIntervalSince(today) / 60) : 1440))
            }
            emit(SolarStatsView(days: fake, now: now).frame(width: 560, height: 620).background(Color(nsColor: .windowBackgroundColor)))
            return
        }
        if let w = ProcessInfo.processInfo.environment["SNAP_WIDGET"] {
            let snap = SharedSnapshot(state: model.link.state!, remaining: model.link.remaining,
                                      socLast24h: SharedSnapshot.socSeries(from: model.history.last24h, now: now),
                                      solarTodayWh: 420)
            let size: WidgetSize = w == "small" ? .small : .medium
            emit(StationWidgetView(snapshot: snap, date: now, size: size).padding(16)
                .frame(width: size == .small ? 170 : 364, height: 170).background(Color(white: 0.12)))
            return
        }
        let host = NSHostingView(rootView: PopoverView(model: model, debugBusy: ProcessInfo.processInfo.environment["SNAP_BUSY"]).background(Color(nsColor: .windowBackgroundColor)))
        host.appearance = NSAppearance(named: .darkAqua)
        host.frame = NSRect(origin: .zero, size: host.fittingSize)
        host.layoutSubtreeIfNeeded()
        guard let rep = retinaRep(host) else { return }
        host.cacheDisplay(in: host.bounds, to: rep)
        // Контейнер sandbox закритий для інших процесів — віддаємо PNG через stdout.
        print("PNG:" + (rep.representation(using: .png, properties: [:])?.base64EncodedString() ?? ""))
    }
}
#endif
