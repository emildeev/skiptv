import Foundation

public enum TimeFormat {
    /// 75 → "1:15", 3725 → "1:02:05".
    public static func clock(_ seconds: Double) -> String {
        guard seconds.isFinite else { return "0:00" }
        let total = max(0, Int(seconds.rounded(.down)))
        let h = total / 3600, m = (total % 3600) / 60, s = total % 60
        if h > 0 {
            return String(format: "%d:%02d:%02d", h, m, s)
        }
        return String(format: "%d:%02d", m, s)
    }

    /// Duration in ms → "1 ч 52 мин" / "48 мин".
    public static func runtime(milliseconds: Int?) -> String? {
        guard let milliseconds, milliseconds > 0 else { return nil }
        let minutes = Int((Double(milliseconds) / 60000).rounded())
        if minutes >= 60 {
            let h = minutes / 60, m = minutes % 60
            return m == 0 ? "\(h) ч" : "\(h) ч \(m) мин"
        }
        return "\(max(1, minutes)) мин"
    }
}

public enum ResumePolicy {
    /// Offsets shorter than this are not worth asking about.
    public static let minimumOffset: Double = 30

    /// Seconds to resume from, or nil to start at the beginning without asking.
    public static func resumePosition(for item: PlexItem) -> Double? {
        guard let offset = item.viewOffset, offset > 0 else { return nil }
        let seconds = Double(offset) / 1000
        guard seconds >= minimumOffset else { return nil }
        if let duration = item.duration, duration > 0,
           Double(offset) / Double(duration) >= ProgressTracker.watchedFraction {
            return nil
        }
        return seconds
    }
}
