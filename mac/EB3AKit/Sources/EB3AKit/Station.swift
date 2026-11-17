import Foundation

/// Відомості про станцію за BLE-іменем.
public enum Station {
    /// Протокол перевірено лише на EB3A.
    public static func isSupported(name: String?) -> Bool { name?.hasPrefix("EB3A") ?? false }

    public static func shortName(_ name: String) -> String {
        name.count > 8 ? "\(name.prefix(4)) ···\(name.suffix(4))" : name
    }

    public static func signalBars(rssi: Int) -> Int {
        switch rssi {
        case (-60)...: 3
        case (-75)...: 2
        case (-90)...: 1
        default: 0
        }
    }
}
