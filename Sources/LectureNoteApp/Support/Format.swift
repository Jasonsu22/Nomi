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
    case "en": "英文"
    case "ja": "日文"
    case "none": "不翻译"
    default: code
    }
}

func formatClockTime(_ date: Date) -> String {
    clockTimeFormatter.string(from: date)
}

func formatMonthDay(_ date: Date) -> String {
    monthDayFormatter.string(from: date)
}

func formatWeekday(_ date: Date) -> String {
    weekdayFormatter.string(from: date)
}

func formatMeetingTime(_ date: Date, now: Date = .now) -> String {
    let time = formatClockTime(date)
    let calendar = Calendar.current
    if calendar.isDateInToday(date) {
        return "今天 \(time)"
    }
    if calendar.isDateInYesterday(date) {
        return "昨天 \(time)"
    }
    return "\(formatMonthDay(date)) \(time)"
}

func formatTimeRange(start: Date, duration: TimeInterval, liveElapsed: TimeInterval?) -> String {
    let startText = formatClockTime(start)
    if let liveElapsed {
        return "\(startText) · \(formatClock(liveElapsed))"
    }
    let end = formatClockTime(start.addingTimeInterval(duration))
    return "\(startText)–\(end)"
}

private let clockTimeFormatter: DateFormatter = {
    let formatter = DateFormatter()
    formatter.locale = Locale(identifier: "zh_CN")
    formatter.dateFormat = "HH:mm"
    return formatter
}()

private let monthDayFormatter: DateFormatter = {
    let formatter = DateFormatter()
    formatter.locale = Locale(identifier: "zh_CN")
    formatter.dateFormat = "M月d日"
    return formatter
}()

private let weekdayFormatter: DateFormatter = {
    let formatter = DateFormatter()
    formatter.locale = Locale(identifier: "zh_CN")
    formatter.dateFormat = "EEE"
    return formatter
}()
