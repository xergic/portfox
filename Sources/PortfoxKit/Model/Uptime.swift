import Foundation

/// Compact, locale-stable relative times for a process's start time.
/// `RelativeDateTimeFormatter` produces verbose, locale-variable strings like
/// "12 minutes ago", so this is built by hand.
public enum Uptime {
    /// When it started, for the dashboard header: "3h ago".
    public static func label(since start: Date, now: Date = Date()) -> String {
        let interval = now.timeIntervalSince(start)
        guard interval >= 10 else { return "just now" }
        return duration(seconds: Int(interval)) + " ago"
    }

    /// How long it has been up, for a list row: "3h".
    ///
    /// Nil under ten seconds, so a service that has just come up does not flash a
    /// counter through `0s`, `1s`, `2s` on every tick.
    public static func duration(since start: Date, now: Date = Date()) -> String? {
        let interval = now.timeIntervalSince(start)
        guard interval >= 10 else { return nil }
        return duration(seconds: Int(interval))
    }

    private static func duration(seconds: Int) -> String {
        switch seconds {
        case ..<60: "\(seconds)s"
        case ..<3600: "\(seconds / 60)m"
        case ..<86400: "\(seconds / 3600)h"
        default: "\(seconds / 86400)d"
        }
    }
}
