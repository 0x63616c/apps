import Foundation

/// A wall-clock calendar date ("2026-10-10") with no time zone attached.
/// Festival days are local dates in the festival's IANA time zone.
struct LocalDate: Hashable, Comparable, Sendable, Codable, CustomStringConvertible {
    var year: Int
    var month: Int
    var day: Int

    init(year: Int, month: Int, day: Int) {
        self.year = year
        self.month = month
        self.day = day
    }

    init?(_ string: String) {
        let parts = string.split(separator: "-")
        guard parts.count == 3, parts[0].count == 4, parts[1].count == 2, parts[2].count == 2,
              let year = Int(parts[0]), let month = Int(parts[1]), let day = Int(parts[2]),
              (1...12).contains(month), (1...31).contains(day) else { return nil }
        self.init(year: year, month: month, day: day)
    }

    /// The local date of `instant` in `timeZone`.
    init(_ instant: Date, in timeZone: TimeZone) {
        let parts = Calendar.gregorian(timeZone).dateComponents([.year, .month, .day], from: instant)
        self.init(year: parts.year!, month: parts.month!, day: parts.day!)
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        let raw = try container.decode(String.self)
        guard let value = LocalDate(raw) else {
            throw DecodingError.dataCorruptedError(in: container, debugDescription: "Expected YYYY-MM-DD, got \(raw)")
        }
        self = value
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(description)
    }

    var description: String {
        String(format: "%04d-%02d-%02d", year, month, day)
    }

    static func < (lhs: LocalDate, rhs: LocalDate) -> Bool {
        (lhs.year, lhs.month, lhs.day) < (rhs.year, rhs.month, rhs.day)
    }

    /// Midnight at the start of this date in `timeZone`.
    func startOfDay(in timeZone: TimeZone) -> Date {
        Calendar.gregorian(timeZone).date(from: DateComponents(year: year, month: month, day: day))!
    }

    /// The instant this date reaches `hour:minute` wall-clock time in `timeZone`.
    func at(hour: Int, minute: Int, in timeZone: TimeZone) -> Date {
        Calendar.gregorian(timeZone).date(from: DateComponents(year: year, month: month, day: day, hour: hour, minute: minute))!
    }

    func adding(days: Int) -> LocalDate {
        let utc = TimeZone(identifier: "UTC")!
        let shifted = Calendar.gregorian(utc).date(byAdding: .day, value: days, to: startOfDay(in: utc))!
        return LocalDate(shifted, in: utc)
    }

    /// Whole calendar days from `self` to `other` (negative when `other` is earlier).
    func days(until other: LocalDate) -> Int {
        let utc = TimeZone(identifier: "UTC")!
        return Calendar.gregorian(utc).dateComponents([.day], from: startOfDay(in: utc), to: other.startOfDay(in: utc)).day!
    }

    /// Weekday 1 (Sunday) ... 7 (Saturday).
    var weekday: Int {
        let utc = TimeZone(identifier: "UTC")!
        return Calendar.gregorian(utc).component(.weekday, from: startOfDay(in: utc))
    }
}

extension Calendar {
    static func gregorian(_ timeZone: TimeZone) -> Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        calendar.locale = Locale(identifier: "en_US_POSIX")
        return calendar
    }
}
