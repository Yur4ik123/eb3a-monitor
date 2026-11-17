import Foundation

public enum Backoff {
    public static func delay(attempt: Int) -> TimeInterval {
        min(30, pow(2, Double(min(attempt, 10))))
    }
}
