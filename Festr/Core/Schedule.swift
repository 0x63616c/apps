import Foundation

enum Clashes {
    /// IDs of sets in `sets` that overlap at least one other set in `sets`.
    static func ids(in sets: [FestivalSet]) -> Set<String> {
        let sorted = sets.sorted(by: FestivalSet.chronological)
        var clashing: Set<String> = []
        for (index, set) in sorted.enumerated() {
            for other in sorted[(index + 1)...] {
                if other.start >= set.effectiveEnd { break }
                if set.overlaps(other) {
                    clashing.insert(set.id)
                    clashing.insert(other.id)
                }
            }
        }
        return clashing
    }

    /// Chosen sets that overlap `candidate` (excluding itself).
    static func conflicts(of candidate: FestivalSet, with chosen: [FestivalSet]) -> [FestivalSet] {
        chosen.filter { $0.id != candidate.id && $0.overlaps(candidate) }
    }
}

/// Times are always shown in the festival's own time zone, wherever the phone is.
struct FestivalClock: Sendable {
    var timeZone: TimeZone
    var locale: Locale = .autoupdatingCurrent

    func time(_ date: Date) -> String {
        var style = Date.FormatStyle(date: .omitted, time: .shortened, locale: locale, calendar: Calendar.gregorian(timeZone), timeZone: timeZone)
        style.locale = locale
        return date.formatted(style)
    }

    func range(_ set: FestivalSet) -> String {
        guard let end = set.end else { return "\(time(set.start)) – late" }
        return "\(time(set.start)) – \(time(end))"
    }

    func weekday(_ day: LocalDate) -> String {
        day.startOfDay(in: timeZone).formatted(Date.FormatStyle(locale: locale, calendar: Calendar.gregorian(timeZone), timeZone: timeZone).weekday(.wide))
    }

    func shortWeekday(_ day: LocalDate) -> String {
        day.startOfDay(in: timeZone).formatted(Date.FormatStyle(locale: locale, calendar: Calendar.gregorian(timeZone), timeZone: timeZone).weekday(.abbreviated))
    }

    func monthDay(_ day: LocalDate) -> String {
        day.startOfDay(in: timeZone).formatted(Date.FormatStyle(locale: locale, calendar: Calendar.gregorian(timeZone), timeZone: timeZone).month(.abbreviated).day())
    }

    func dateRange(_ festival: Festival) -> String {
        let start = festival.startDate
        let end = festival.endDate
        if start == end { return monthDay(start) }
        if start.year == end.year && start.month == end.month {
            return "\(monthDay(start))–\(end.day)"
        }
        return "\(monthDay(start)) – \(monthDay(end))"
    }
}

enum Countdown {
    static func label(daysUntil: Int) -> String {
        switch daysUntil {
        case ..<0: return "Ended"
        case 0: return "Now on"
        case 1: return "Tomorrow"
        default: return "In \(daysUntil) days"
        }
    }
}
