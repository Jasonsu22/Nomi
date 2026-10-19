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
        return trf("%d 小时 %d 分", hours, minutes)
    }
    if minutes > 0 {
        return trf("%d 分钟", minutes)
    }
    return trf("%d 秒", total)
}

func languageName(_ code: String) -> String {
    let name: String = switch code {
    case "auto": "自动检测"
    case "zh": "中文"
    case "en": "英文"
    case "ja": "日文"
    case "ko": "韩文"
    case "de": "德文"
    case "fr": "法文"
    case "es": "西班牙文"
    case "ru": "俄文"
    case "ar": "阿拉伯文"
    case "none": "不翻译"
    default: code
    }
    return tr(name)
}

func formatClockTime(_ date: Date) -> String {
    dateFormatter("HH:mm").string(from: date)
}

func formatMonthDay(_ date: Date) -> String {
    dateFormatter(InterfaceLanguage.current == .chinese ? "M月d日" : "MMM d").string(from: date)
}

func formatWeekday(_ date: Date) -> String {
    dateFormatter("EEE").string(from: date)
}

func formatStartStamp(_ date: Date) -> String {
    "\(formatMonthDay(date)) \(formatWeekday(date)) \(formatClockTime(date))"
}

func formatMeetingTime(_ date: Date, now: Date = .now) -> String {
    let time = formatClockTime(date)
    let calendar = Calendar.current
    if calendar.isDateInToday(date) {
        return trf("今天 %@", time)
    }
    if calendar.isDateInYesterday(date) {
        return trf("昨天 %@", time)
    }
    return "\(formatMonthDay(date)) \(time)"
}

func formatRelativeTime(_ date: Date, now: Date = .now) -> String {
    if abs(now.timeIntervalSince(date)) < 45 { return tr("刚刚") }
    let formatter = RelativeDateTimeFormatter()
    formatter.locale = InterfaceLanguage.current.locale
    formatter.unitsStyle = .full
    return formatter.localizedString(for: date, relativeTo: now)
}

func formatTimeRange(start: Date, duration: TimeInterval, liveElapsed: TimeInterval?) -> String {
    let startText = formatClockTime(start)
    if let liveElapsed {
        return "\(startText) · \(formatClock(liveElapsed))"
    }
    let end = formatClockTime(start.addingTimeInterval(duration))
    return "\(startText)–\(end)"
}

private func dateFormatter(_ format: String) -> DateFormatter {
    let formatter = DateFormatter()
    formatter.locale = InterfaceLanguage.current.locale
    formatter.dateFormat = format
    return formatter
}
