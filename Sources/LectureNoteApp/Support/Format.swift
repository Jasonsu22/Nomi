import Foundation

func formatClock(_ seconds: TimeInterval) -> String {
    let total = max(0, Int(seconds.rounded(.down)))
    let hours = total / 3600
    let minutes = (total % 3600) / 60
    let secs = total % 60
    if hours > 0 {
        return String(format: "%d:%02d:%02d", hours, minutes, secs)
    }
    return String(format: "%d:%02d", minutes, secs)
}

func formatDuration(_ seconds: TimeInterval) -> String {
    let total = max(0, Int(seconds.rounded()))
    let hours = total / 3600
    let minutes = (total % 3600) / 60
    if hours > 0 {
        return "\(hours) 小时 \(minutes) 分"
    }
    if minutes > 0 {
        return "\(minutes) 分钟"
    }
    return "\(total) 秒"
}

func languageName(_ code: String) -> String {
    switch code {
    case "zh": "中文"
    case "en": "English"
    case "none": "不翻译"
    default: code
    }
}

func formatMeetingTime(_ date: Date, now: Date = .now) -> String {
    let calendar = Calendar.current
    let time = date.formatted(date: .omitted, time: .shortened)
    if calendar.isDateInToday(date) {
        return "今天 \(time)"
    }
    if calendar.isDateInYesterday(date) {
        return "昨天 \(time)"
    }
    return date.formatted(date: .abbreviated, time: .shortened)
}
