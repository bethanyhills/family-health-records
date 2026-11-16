import Foundation

/// Dates typed as MM/DD/YYYY, the way US intake forms ask for them.
enum TypedDate {
    /// Keeps up to 8 digits and adds the slashes: "0615" -> "06/15".
    static func format(_ input: String) -> String {
        let digits = input.filter(\.isNumber).prefix(8)
        var result = ""
        for (index, character) in digits.enumerated() {
            if index == 2 || index == 4 { result.append("/") }
            result.append(character)
        }
        return result
    }

    /// A real calendar date from a complete MM/DD/YYYY string, or nil.
    static func parse(_ text: String, calendar: Calendar = .current) -> Date? {
        let parts = text.split(separator: "/").map(String.init)
        guard parts.count == 3, parts[0].count == 2, parts[1].count == 2, parts[2].count == 4,
              let month = Int(parts[0]), let day = Int(parts[1]), let year = Int(parts[2]),
              (1...12).contains(month), (1...31).contains(day), (1850...2200).contains(year)
        else { return nil }

        let components = DateComponents(year: year, month: month, day: day, hour: 12)
        guard let date = calendar.date(from: components) else { return nil }
        // Rejects dates that roll over, like 02/30.
        let check = calendar.dateComponents([.year, .month, .day], from: date)
        guard check.year == year, check.month == month, check.day == day else { return nil }
        return date
    }

    static func string(from date: Date, calendar: Calendar = .current) -> String {
        let c = calendar.dateComponents([.year, .month, .day], from: date)
        return String(format: "%02d/%02d/%04d", c.month ?? 0, c.day ?? 0, c.year ?? 0)
    }
}
