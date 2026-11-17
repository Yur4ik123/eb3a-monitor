// Генерація іконки: swift icon.swift <variant 1|2|3> <out.png>
import AppKit

let variant = Int(CommandLine.arguments[1]) ?? 1
let out = URL(fileURLWithPath: CommandLine.arguments[2])
let S: CGFloat = 1024

func color(_ hex: UInt32, _ a: CGFloat = 1) -> NSColor {
    NSColor(srgbRed: CGFloat(hex >> 16 & 0xFF) / 255, green: CGFloat(hex >> 8 & 0xFF) / 255, blue: CGFloat(hex & 0xFF) / 255, alpha: a)
}

func bolt(in r: NSRect) -> NSBezierPath {
    let p = NSBezierPath()
    let pts: [(CGFloat, CGFloat)] = [(0.58, 1.0), (0.12, 0.44), (0.44, 0.44), (0.36, 0.0), (0.88, 0.58), (0.54, 0.58), (0.62, 1.0)]
    for (i, (x, y)) in pts.enumerated() {
        let pt = NSPoint(x: r.minX + x * r.width, y: r.minY + y * r.height)
        i == 0 ? p.move(to: pt) : p.line(to: pt)
    }
    p.close()
    return p
}

func sun(center c: NSPoint, radius r: CGFloat, fill: NSColor) {
    fill.setFill()
    NSBezierPath(ovalIn: NSRect(x: c.x - r, y: c.y - r, width: 2 * r, height: 2 * r)).fill()
    fill.setStroke()
    for i in 0..<8 {
        let a = CGFloat(i) * .pi / 4
        let p = NSBezierPath()
        p.lineWidth = r * 0.22
        p.lineCapStyle = .round
        p.move(to: NSPoint(x: c.x + cos(a) * r * 1.45, y: c.y + sin(a) * r * 1.45))
        p.line(to: NSPoint(x: c.x + cos(a) * r * 1.95, y: c.y + sin(a) * r * 1.95))
        p.stroke()
    }
}

let img = NSImage(size: NSSize(width: S, height: S))
img.lockFocus()
let tile = NSRect(x: 100, y: 100, width: 824, height: 824)
let squircle = NSBezierPath(roundedRect: tile, xRadius: 185, yRadius: 185)

switch variant {
case 1: // Нічне небо + батарея з блискавкою + сонце
    NSGradient(starting: color(0x1B2A4A), ending: color(0x0B1220))!.draw(in: squircle, angle: -90)
    sun(center: NSPoint(x: 745, y: 755), radius: 60, fill: color(0xFFC83D))
    let body = NSRect(x: 330, y: 220, width: 300, height: 470)
    color(0xFFFFFF, 0.9).setStroke()
    let shell = NSBezierPath(roundedRect: body, xRadius: 56, yRadius: 56); shell.lineWidth = 30; shell.stroke()
    color(0xFFFFFF, 0.9).setFill()
    NSBezierPath(roundedRect: NSRect(x: 420, y: 690, width: 120, height: 42), xRadius: 14, yRadius: 14).fill()
    let fill = NSRect(x: body.minX + 32, y: body.minY + 32, width: body.width - 64, height: (body.height - 64) * 0.72)
    NSGradient(starting: color(0x34D17A), ending: color(0x1FA85C))!.draw(in: NSBezierPath(roundedRect: fill, xRadius: 30, yRadius: 30), angle: 90)
    color(0xFFFFFF).setFill()
    bolt(in: NSRect(x: 395, y: 300, width: 170, height: 280)).fill()
case 2: // Сонячний градієнт + велика блискавка
    NSGradient(colors: [color(0xFFB000), color(0xFF6A00), color(0xD9305C)])!.draw(in: squircle, angle: -60)
    color(0xFFFFFF, 0.18).setFill()
    NSBezierPath(ovalIn: NSRect(x: 560, y: 560, width: 300, height: 300)).fill()
    let b = bolt(in: NSRect(x: 300, y: 190, width: 420, height: 640))
    NSGraphicsContext.current?.saveGraphicsState()
    let sh = NSShadow(); sh.shadowColor = color(0x000000, 0.25); sh.shadowBlurRadius = 30; sh.shadowOffset = NSSize(width: 0, height: -14); sh.set()
    color(0xFFFFFF).setFill(); b.fill()
    NSGraphicsContext.current?.restoreGraphicsState()
case 3: // Мінімалізм: кільце заряду
    NSGradient(starting: color(0x0F2E26), ending: color(0x07140F))!.draw(in: squircle, angle: -90)
    let c = NSPoint(x: 512, y: 512)
    let track = NSBezierPath(); track.appendArc(withCenter: c, radius: 280, startAngle: 0, endAngle: 360)
    track.lineWidth = 64; color(0xFFFFFF, 0.12).setStroke(); track.stroke()
    let arc = NSBezierPath(); arc.appendArc(withCenter: c, radius: 280, startAngle: 90, endAngle: 90 - 0.78 * 360, clockwise: true)
    arc.lineWidth = 64; arc.lineCapStyle = .round; color(0x3BE08A).setStroke(); arc.stroke()
    color(0xFFD23F).setFill()
    bolt(in: NSRect(x: 412, y: 352, width: 200, height: 320)).fill()
default: break
}
img.unlockFocus()

let rep = NSBitmapImageRep(data: img.tiffRepresentation!)!
try! rep.representation(using: .png, properties: [:])!.write(to: out)
print("ok \(out.path)")
