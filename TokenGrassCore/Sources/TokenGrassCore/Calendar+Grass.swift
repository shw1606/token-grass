import Foundation

public extension Calendar {
    /// Canonical calendar for grass layout: Gregorian, POSIX locale, configurable
    /// time zone and first weekday. Tests pin this to UTC for determinism; the app
    /// uses the user's local time zone so the day boundary matches their midnight.
    static func grass(timeZone: TimeZone = .current, firstWeekday: Int = 1) -> Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        calendar.firstWeekday = firstWeekday // 1 = Sunday (GitHub default)
        calendar.locale = Locale(identifier: "en_US_POSIX")
        return calendar
    }
}
