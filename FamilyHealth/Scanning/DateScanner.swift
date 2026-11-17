import Foundation

/// Finds dates written the ways US medical paperwork writes them:
/// 06/15/2015, 6-15-15, 2015-06-15 and Jun 15, 2015.
enum DateScanner {
    struct Match: Equatable {
        let date: Date
        /// Where the date starts in the text (UTF-16 offset), for telling which label it follows.
        let location: Int
        let length: Int
    }

    private static let months = ["jan", "feb", "mar", "apr", "may", "jun", "jul", "aug", "sep", "oct", "nov", "dec"]

    private static let numericDate = try! NSRegularExpression(
        pattern: #"(?<!\d)(\d{1,2})\s*[/\-.]\s*(\d{1,2})\s*[/\-.]\s*(\d{4}|\d{2})(?!\d)"#
    )
    private static let isoDate = try! NSRegularExpression(
        pattern: #"(?<!\d)(\d{4})[/\-.](\d{1,2})[/\-.](\d{1,2})(?!\d)"#
    )
    private static let namedDate = try! NSRegularExpression(
        pattern: #"(?<![A-Za-z])(jan|feb|mar|apr|may|jun|jul|aug|sep|sept|oct|nov|dec)[a-z]*\.?\s+(\d{1,2}),?\s+(\d{4})"#,
        options: [.caseInsensitive]
    )

    /// Every date in the text, in order, between `earliest` and `latest` when given.
    /// Two-digit years count as this century unless that would be after `now`.
    static func dates(in text: String, earliest: Date? = nil, latest: Date? = nil, now: Date = .now) -> [Match] {
        let full = NSRange(text.startIndex..., in: text)
        let ns = text as NSString
        var results: [Match] = []
        func add(_ range: NSRange, year: Int, month: Int, day: Int) {
            guard !results.contains(where: { NSIntersectionRange(NSRange(location: $0.location, length: $0.length), range).length > 0 }),
                  let date = makeDate(year: year, month: month, day: day) else { return }
            if let earliest, date < earliest { return }
            if let latest, date > latest { return }
            results.append(Match(date: date, location: range.location, length: range.length))
        }
        func number(_ m: NSTextCheckingResult, _ group: Int) -> Int { Int(ns.substring(with: m.range(at: group))) ?? 0 }

        for m in isoDate.matches(in: text, range: full) {
            add(m.range, year: number(m, 1), month: number(m, 2), day: number(m, 3))
        }
        for m in namedDate.matches(in: text, range: full) {
            let month = (months.firstIndex(of: String(ns.substring(with: m.range(at: 1)).lowercased().prefix(3))) ?? -1) + 1
            add(m.range, year: number(m, 3), month: month, day: number(m, 2))
        }
        for m in numericDate.matches(in: text, range: full) {
            var year = number(m, 3)
            if year < 100 {
                let thisYear = Calendar(identifier: .gregorian).component(.year, from: now) % 100
                year += year <= thisYear ? 2000 : 1900
            }
            add(m.range, year: year, month: number(m, 1), day: number(m, 2))
        }
        return results.sorted { $0.location < $1.location }
    }

    /// Whether the text has a date with the month spelled out ("Jun 15, 2015").
    static func hasNamedDate(_ text: String) -> Bool {
        namedDate.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)) != nil
    }

    /// The same key for any time on the same calendar day.
    static func dayKey(_ date: Date) -> String {
        let parts = Calendar(identifier: .gregorian).dateComponents([.year, .month, .day], from: date)
        return "\(parts.year ?? 0)-\(parts.month ?? 0)-\(parts.day ?? 0)"
    }

    private static func makeDate(year: Int, month: Int, day: Int) -> Date? {
        guard (1...12).contains(month), (1...31).contains(day), year >= 1900 else { return nil }
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = .current
        let components = DateComponents(year: year, month: month, day: day, hour: 12)
        guard let date = calendar.date(from: components),
              calendar.component(.day, from: date) == day else { return nil }
        return date
    }
}
