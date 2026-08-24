import Foundation

/// Trailing-dot cycle for in-progress status copy (Searching Gmail / Thinking / launch sync).
/// `.` → `..` → `...` → `.` — display only; stored beat text stays static.
public enum StatusEllipsis: Sendable {
    public static let interval: TimeInterval = 0.45

    public static func dots(tick: Int) -> String {
        let count = (tick % 3) + 1
        return String(repeating: ".", count: count)
    }

    public static func display(stem: String, tick: Int) -> String {
        stem + dots(tick: tick)
    }
}
