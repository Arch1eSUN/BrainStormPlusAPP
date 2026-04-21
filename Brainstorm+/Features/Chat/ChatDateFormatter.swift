import Foundation

/// Lightweight date formatter for chat message timestamps.
/// Returns localized (zh_CN) strings at four granularities:
///   - today      → HH:mm
///   - yesterday  → 昨天 HH:mm
///   - this year  → M月d日 HH:mm
///   - earlier    → yyyy年M月d日
public enum ChatDateFormatter {
    private static let zhLocale = Locale(identifier: "zh_CN")

    private static let timeOnly: DateFormatter = {
        let f = DateFormatter()
        f.locale = zhLocale
        f.dateFormat = "HH:mm"
        return f
    }()

    private static let yesterdayFormatter: DateFormatter = {
        let f = DateFormatter()
        f.locale = zhLocale
        f.dateFormat = "'昨天' HH:mm"
        return f
    }()

    private static let thisYearFormatter: DateFormatter = {
        let f = DateFormatter()
        f.locale = zhLocale
        f.dateFormat = "M月d日 HH:mm"
        return f
    }()

    private static let fullDateFormatter: DateFormatter = {
        let f = DateFormatter()
        f.locale = zhLocale
        f.dateFormat = "yyyy年M月d日"
        return f
    }()

    public static func format(_ date: Date?) -> String {
        guard let date = date else { return "" }
        let calendar = Calendar.current
        if calendar.isDateInToday(date) {
            return timeOnly.string(from: date)
        }
        if calendar.isDateInYesterday(date) {
            return yesterdayFormatter.string(from: date)
        }
        if calendar.isDate(date, equalTo: Date(), toGranularity: .year) {
            return thisYearFormatter.string(from: date)
        }
        return fullDateFormatter.string(from: date)
    }
}
