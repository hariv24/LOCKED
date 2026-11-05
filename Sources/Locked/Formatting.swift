import Foundation

/// mm:ss, or h:mm:ss when at least an hour remains. Rounds up so 0:00 only shows at the very end.
func formatCountdown(_ interval: TimeInterval) -> String {
    let total = max(0, Int(interval.rounded(.up)))
    let hours = total / 3600
    let minutes = (total % 3600) / 60
    let seconds = total % 60
    if hours > 0 {
        return String(format: "%d:%02d:%02d", hours, minutes, seconds)
    }
    return String(format: "%02d:%02d", minutes, seconds)
}

/// "25 min", "1 h", "1 h 30 min".
func formatMinutes(_ minutes: Int) -> String {
    if minutes < 60 { return "\(minutes) min" }
    let h = minutes / 60
    let m = minutes % 60
    return m == 0 ? "\(h) h" : "\(h) h \(m) min"
}
