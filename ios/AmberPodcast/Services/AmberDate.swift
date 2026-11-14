import Foundation

/// Shared date parsing/formatting for episode timestamps.
///
/// Backend `pubDate` values arrive as RFC 1123 strings ("Thu, 12 Nov 2026
/// 23:00:00 GMT"); some legacy rows use plain "yyyy-MM-dd". Home shelves show
/// a short localized stamp (11月12日), detail rows the full one (2026年11月12日).
public enum AmberDate {
    private static let rfc1123: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "EEE, dd MMM yyyy HH:mm:ss zzz"
        f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = TimeZone(identifier: "GMT")
        return f
    }()

    private static let isoDay: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd"
        f.locale = Locale(identifier: "en_US_POSIX")
        return f
    }()

    private static let shortFormatter: DateFormatter = {
        let f = DateFormatter()
        f.setLocalizedDateFormatFromTemplate("MMMd")
        f.locale = Locale(identifier: "zh_CN")
        return f
    }()

    private static let fullFormatter: DateFormatter = {
        let f = DateFormatter()
        f.setLocalizedDateFormatFromTemplate("yMMMd")
        f.locale = Locale(identifier: "zh_CN")
        return f
    }()

    public static func parse(_ s: String) -> Date? {
        guard !s.isEmpty else { return nil }
        if let d = rfc1123.date(from: s) { return d }
        if let d = isoDay.date(from: String(s.prefix(10))) { return d }
        if let d = ISO8601DateFormatter().date(from: s) { return d }
        return nil
    }

    /// Home shelf stamp, e.g. "11月12日".
    public static func short(_ s: String) -> String {
        guard let d = parse(s) else { return s }
        return shortFormatter.string(from: d)
    }

    /// Detail row stamp, e.g. "2026年11月12日".
    public static func full(_ s: String) -> String {
        guard let d = parse(s) else { return s }
        return fullFormatter.string(from: d)
    }

    /// Smart relative date stamp: today -> "HH:mm", yesterday -> "1天前", 2-7 days -> "N天前", beyond -> "M月d日" / "yyyy年M月d日"
    public static func relative(_ s: String) -> String {
        guard let d = parse(s) else { return s }
        let calendar = Calendar.current
        let now = Date()

        if calendar.isDateInToday(d) {
            let f = DateFormatter()
            f.dateFormat = "HH:mm"
            f.locale = Locale(identifier: "zh_CN")
            return f.string(from: d)
        }

        if calendar.isDateInYesterday(d) {
            return "1天前"
        }

        let comps = calendar.dateComponents([.day], from: calendar.startOfDay(for: d), to: calendar.startOfDay(for: now))
        if let days = comps.day, days >= 2 && days <= 7 {
            return "\(days)天前"
        }

        let isCurrentYear = calendar.component(.year, from: d) == calendar.component(.year, from: now)
        let f = DateFormatter()
        f.locale = Locale(identifier: "zh_CN")
        if isCurrentYear {
            f.dateFormat = "M月d日"
        } else {
            f.dateFormat = "yyyy年M月d日"
        }
        return f.string(from: d)
    }
}
