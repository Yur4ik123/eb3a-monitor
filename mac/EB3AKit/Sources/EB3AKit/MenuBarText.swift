import Foundation

public enum MenuBarText {
    public static let staleAfter: TimeInterval = 30

    /// Джерела живлення + заряд. Прогноз — лише в поповері.
    public static func make(state: StationState?, now: Date) -> String {
        guard let s = state, now.timeIntervalSince(s.updatedAt) <= staleAfter else { return "🔋 —" }
        let grid = s.gridPresent ? "⚡" : "⚡✕"
        let solar = s.solarPresent ? " ☀ \(s.solarW)W " : ""
        return "\(grid)\(solar) 🔋 \(s.soc)%"
    }
}
