import Foundation

/// Works out whose document a page is, from the names and birthdays printed on it, so a
/// form scanned into the wrong family member's profile can be caught before it's filed.
enum DocumentOwner {
    struct Candidate: Equatable {
        let id: UUID
        let name: String
        var preferredName: String = ""
        var dateOfBirth: Date?
    }

    /// Another family member the text is clearly about, or nil when it's about `current`,
    /// names nobody, or can't tell. Lines labeled "Student:", "Patient:" or "Name:" count
    /// most, since parents and siblings can be mentioned elsewhere on a form.
    static func otherOwner(of text: String, current: Candidate, family: [Candidate]) -> Candidate? {
        let others = family.filter { $0.id != current.id }
        guard !others.isEmpty, !text.isBlank else { return nil }

        let labeled = text.components(separatedBy: .newlines).filter(isNameLine).joined(separator: "\n")
        if !labeled.isEmpty, let pick = pick(in: labeled, current: current, others: others, minimum: 1) {
            return pick.id == current.id ? nil : pick
        }
        // Elsewhere on the page a first name alone could be a sibling or parent mentioned
        // in passing, so it takes a full name or a birthday to suggest a move.
        guard let pick = pick(in: text, current: current, others: others, minimum: 3) else { return nil }
        return pick.id == current.id ? nil : pick
    }

    /// The clear winner among everyone named in `text`, or nil when it's a tie or nobody
    /// scores `minimum`. The current person wins any tie, so nothing is flagged by mistake.
    private static func pick(in text: String, current: Candidate, others: [Candidate], minimum: Int) -> Candidate? {
        let currentScore = score(current, in: text)
        let ranked = others.map { ($0, score($0, in: text)) }.sorted { $0.1 > $1.1 }
        guard let best = ranked.first else { return nil }
        if currentScore >= minimum, currentScore >= best.1 { return current }
        guard best.1 >= minimum, best.1 > currentScore else { return nil }
        if ranked.count > 1, ranked[1].1 == best.1 { return nil }
        return best.0
    }

    /// 3 for a full name ("Owen Hills" or "Hills, Owen") or birthday, 1 for a first name alone.
    static func score(_ person: Candidate, in text: String) -> Int {
        var total = 0
        let words = person.name.split(whereSeparator: \.isWhitespace).map(String.init)
        if let first = words.first {
            let firsts = [first, person.preferredName.trimmed].filter { $0.count >= 2 }
            if words.count > 1, let last = words.last {
                for name in firsts {
                    let given = NSRegularExpression.escapedPattern(for: name)
                    if contains(text, phrase: "\(given)(?:\\s+\\w+\\.?)?\\s+\(NSRegularExpression.escapedPattern(for: last))", isRegex: true)
                        || contains(text, phrase: "\(NSRegularExpression.escapedPattern(for: last)),?\\s+\(given)", isRegex: true) {
                        total = 3
                    }
                }
            }
            if total == 0, firsts.contains(where: { contains(text, phrase: $0, isRegex: false) }) { total = 1 }
        }
        if let birthday = person.dateOfBirth, mentions(birthday, in: text) { total += 3 }
        return total
    }

    private static let nameLabel = try! NSRegularExpression(
        pattern: #"^\s*(?:student|patient|child|pupil|client|member|name|student name|patient name|child'?s name|name of (?:student|child|patient))\s*(?:name)?\s*[:\-]"#,
        options: [.caseInsensitive]
    )

    private static func isNameLine(_ line: String) -> Bool {
        nameLabel.firstMatch(in: line, range: NSRange(line.startIndex..., in: line)) != nil
    }

    private static func contains(_ text: String, phrase: String, isRegex: Bool) -> Bool {
        let body = isRegex ? phrase : NSRegularExpression.escapedPattern(for: phrase)
        return text.range(of: "\\b\(body)\\b", options: [.regularExpression, .caseInsensitive]) != nil
    }

    private static func mentions(_ date: Date, in text: String) -> Bool {
        let formats = ["MM/dd/yyyy", "M/d/yyyy", "MM/dd/yy", "M/d/yy", "MM-dd-yyyy", "yyyy-MM-dd", "MMMM d, yyyy", "MMM d, yyyy"]
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        return formats.contains { format in
            formatter.dateFormat = format
            let written = formatter.string(from: date)
            return text.range(of: "(?<![\\d/])\(NSRegularExpression.escapedPattern(for: written))(?![\\d/])",
                              options: [.regularExpression, .caseInsensitive]) != nil
        }
    }
}
