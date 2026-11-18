import Foundation

public enum MenuBarText {
    public static let staleAfter: TimeInterval = 30

    /// Джерела живлення + заряд. Прогноз — лише в поповері.
    public static func make(state: StationState?, now: Date) -> String {
        guard let s = state, now.timeIntervalSince(s.updatedAt) <= staleAfter else { return "🔋 —" }
        var parts: [String] = s.alerts.isEmpty ? [] : ["⚠️"]
        if s.gridPresent { parts.append("⚡") }
        if s.solarPresent { parts.append("☀ \(s.solarW)W ") }
        parts.append("🔋 \(s.soc)%")
        return parts.joined(separator: " ")
    }
}
