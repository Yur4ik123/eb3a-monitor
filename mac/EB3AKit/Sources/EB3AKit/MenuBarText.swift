import Foundation

public enum MenuBarText {
    public static let staleAfter: TimeInterval = 30

    public static func make(state: StationState?, remaining: TimeInterval?, now: Date) -> String {
        guard let s = state, now.timeIntervalSince(s.updatedAt) <= staleAfter else { return "🔋 —" }
        if !s.gridPresent {
            return "⚡✕ 🔋 \(s.soc)%" + (remaining.map { " · \(formatRemaining($0))" } ?? "")
        }
        return s.solarPresent ? "☀ \(s.solarW)W  🔋 \(s.soc)%" : "🔋 \(s.soc)%"
    }
}
