import Foundation

/// Reads an after-visit summary or discharge sheet: when the visit was, who it was with,
/// why, the diagnoses, the instructions and the follow-up. What it finds fills in a
/// visit note for the person to check before saving.
///
/// Summaries from patient portals are laid out under headings ("Reason for Visit",
/// "Diagnoses", "Instructions", "Follow-up"), so it reads the rows under each heading.
enum VisitSummaryParser {
    struct Result: Equatable {
        var date: Date?
        var provider = ""
        var reason = ""
        var diagnoses: [String] = []
        var instructions: [String] = []
        var medicationChanges: [String] = []
        var followUp = ""
        var followUpDate: Date?

        var isEmpty: Bool {
            date == nil && provider.isEmpty && reason.isEmpty && diagnoses.isEmpty
                && instructions.isEmpty && medicationChanges.isEmpty && followUp.isEmpty
        }

        /// The "What they said" text: diagnoses, medication changes and instructions.
        var notes: String {
            var parts: [String] = []
            if !diagnoses.isEmpty { parts.append("Diagnosis: " + diagnoses.joined(separator: "; ")) }
            if !medicationChanges.isEmpty { parts.append("Medication changes: " + medicationChanges.joined(separator: "; ")) }
            if !instructions.isEmpty { parts.append(instructions.joined(separator: "\n")) }
            return parts.joined(separator: "\n\n")
        }
    }

    // MARK: - Recognizing a summary

    /// Whether a document of another type reads like a visit summary, so the button to
    /// fill in a visit note can be offered there too.
    static func looksLikeVisitSummary(_ text: String) -> Bool {
        let range = NSRange(text.startIndex..., in: text)
        if title.firstMatch(in: text, range: range) != nil { return true }
        let headings = Set(text.components(separatedBy: .newlines).compactMap { heading(in: $0)?.section })
        return headings.count >= 3 && (headings.contains(.diagnoses) || headings.contains(.reason))
    }

    private static let title = try! NSRegularExpression(
        pattern: #"after[\s-]*visit summary|visit summary|discharge (?:summary|instructions)|clinical summary|summary of (?:your|today's) visit"#,
        options: [.caseInsensitive]
    )

    // MARK: - Reading it

    enum Section: Equatable {
        case reason, diagnoses, instructions, followUp, medicationsStarted, medicationsStopped, medicationsChanged, other
    }

    /// Headings, as summaries word them, and the section each starts.
    private static let headings: [(pattern: String, section: Section)] = [
        (#"reason for (?:your |today's |the )?visit|visit reason|chief complaint|why you (?:were seen|came in)|you were seen (?:today )?for|reason for appointment"#, .reason),
        (#"(?:today's |your |visit |final |discharge |primary )?diagnos[ie]s|problems? addressed(?: today)?|assessment(?: and plan)?"#, .diagnoses),
        (#"start taking|new medications?|medications? started|new prescriptions?|begin taking"#, .medicationsStarted),
        (#"stop taking|medications? stopped|discontinue[d]?(?: these)?(?: medications?)?"#, .medicationsStopped),
        (#"change how you take|changed medications?|medication changes|continue taking but change"#, .medicationsChanged),
        (#"follow[\s-]*up(?: instructions| appointments?| care| with)?|return (?:to clinic|visit|precautions)|next (?:appointment|visit|steps)|upcoming appointments?|schedule(?:d)? (?:a )?(?:follow[\s-]*up|appointment)"#, .followUp),
        (#"(?:patient |your |discharge |care |home care |special |additional )?instructions|what to do(?: next| at home)?|plan(?: of care)?|recommendations|provider notes|notes from your (?:doctor|provider)|education"#, .instructions),
        // Sections that are long lists of everything on file, not news from this visit.
        (#"(?:your |current |complete )?medication list|current medications|allergies|immunizations|vitals?(?: signs)?|lab results|results|problem list|health maintenance|preventive care|demographics|insurance|pharmacy|contact (?:us|information)|mychart|patient portal|today's visit|visit information|care team|referrals?"#, .other),
    ]
    private static let headingPatterns: [(regex: NSRegularExpression, section: Section)] = headings.map {
        (try! NSRegularExpression(pattern: #"^\s*(?:"# + $0.pattern + #")\s*(?::|-|$)"#, options: [.caseInsensitive]), $0.section)
    }

    /// The section a row starts, and anything after the heading on the same row ("Diagnosis: Ear infection").
    private static func heading(in row: String) -> (section: Section, rest: String)? {
        let range = NSRange(row.startIndex..., in: row)
        for item in headingPatterns {
            // The heading is the whole row, or is followed by a colon or dash ("Diagnosis: Ear infection").
            guard let match = item.regex.firstMatch(in: row, range: range) else { continue }
            let rest = (row as NSString).substring(from: match.range.length).trimmingCharacters(in: .whitespaces)
            return (item.section, rest)
        }
        return nil
    }

    static func parse(rows: [String], now: Date = .now) -> Result {
        let rows = rows.map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
        var result = Result()

        // Rows under each heading, in order.
        var sections: [(section: Section, rows: [String])] = []
        for row in rows {
            if let found = heading(in: row) {
                sections.append((found.section, found.rest.isEmpty ? [] : [found.rest]))
            } else if !sections.isEmpty {
                sections[sections.count - 1].rows.append(row)
            }
        }
        func rowsIn(_ section: Section) -> [String] {
            sections.filter { $0.section == section }.flatMap(\.rows).map(cleanItem).filter { !$0.isEmpty }
        }

        result.date = visitDate(in: rows, now: now)
        result.provider = provider(in: rows)
        result.reason = rowsIn(.reason).prefix(2).joined(separator: "; ")
        result.diagnoses = unique(rowsIn(.diagnoses).filter(isDiagnosis)).prefix(8).map { $0 }
        result.instructions = joinWrapped(rowsIn(.instructions)).prefix(12).map { $0 }
        result.medicationChanges =
            rowsIn(.medicationsStarted).filter(looksLikeMedication).map { "Start " + $0 }
            + rowsIn(.medicationsChanged).filter(looksLikeMedication).map { "Change " + $0 }
            + rowsIn(.medicationsStopped).filter(looksLikeMedication).map { "Stop " + $0 }

        let followUpRows = joinWrapped(rowsIn(.followUp))
        let followUpText = followUpRows.isEmpty ? (followUpSentence(in: rows).map { [$0] } ?? []) : followUpRows
        result.followUp = followUpText.prefix(3).joined(separator: " ")
        result.followUpDate = followUpDate(in: result.followUp, after: result.date ?? now, now: now)
        return result
    }

    // MARK: Date and provider

    private static let dateLabel = try! NSRegularExpression(
        pattern: #"(visit date|date of (?:visit|service)|service date|appointment date|encounter date|admission date|admit date|seen on|visited on|date)\b"#,
        options: [.caseInsensitive]
    )
    private static let notVisitDate = try! NSRegularExpression(
        pattern: #"(dob|d\.o\.b|birth|born|printed|print date|generated|follow|return|next|due|discharge date|expires|scheduled)"#,
        options: [.caseInsensitive]
    )

    private static func visitDate(in rows: [String], now: Date) -> Date? {
        let latest = now.addingTimeInterval(86_400)
        var labeled: [Date] = []
        var unlabeled: [Date] = []
        for row in rows {
            let ns = row as NSString
            var segmentStart = 0
            for match in DateScanner.dates(in: row, latest: latest, now: now) {
                let before = ns.substring(with: NSRange(location: segmentStart, length: match.location - segmentStart))
                segmentStart = match.location + match.length
                let beforeRange = NSRange(before.startIndex..., in: before)
                let label = dateLabel.matches(in: before, range: beforeRange).last?.range.location ?? -1
                let blocker = notVisitDate.matches(in: before, range: beforeRange).last?.range.location ?? -1
                if blocker > label { continue }
                if label >= 0 { labeled.append(match.date) } else if blocker < 0 { unlabeled.append(match.date) }
            }
        }
        return labeled.first ?? unlabeled.first
    }

    /// "Provider: Jane Smith, MD" needs the colon; "You saw Jane Smith, MD" doesn't.
    /// ("Call your doctor if…" names nobody.)
    private static let providerLabels = [
        #"(?:^|\s)(?:provider|attending(?: physician| provider)?|physician|clinician|doctor|primary care provider|pcp|seen by)\s*:\s*(.+)$"#,
        #"(?:^|\s)(?:seen by|you saw|you were seen by|your visit with|visit with)\s+(.+)$"#,
    ].map { try! NSRegularExpression(pattern: $0, options: [.caseInsensitive]) }

    private static func provider(in rows: [String]) -> String {
        for row in rows {
            let range = NSRange(row.startIndex..., in: row)
            guard let match = providerLabels.lazy.compactMap({ $0.firstMatch(in: row, range: range) }).first else { continue }
            var rest = (row as NSString).substring(with: match.range(at: 1))
            // "You saw Jane Smith, MD on 11/10/2026 at Sunrise Pediatrics"
            if let cut = rest.range(of: #"\s+(?:on|at|in)\s+"#, options: [.regularExpression, .caseInsensitive]) {
                rest = String(rest[..<cut.lowerBound])
            }
            rest = rest.replacingOccurrences(of: #"^(?:dr\.?\s+)"#, with: "", options: [.regularExpression, .caseInsensitive])
            guard rest.first?.isUppercase == true else { continue }
            if let name = PrescriptionParser.displayName(rest, row: row) { return name }
        }
        for row in rows {
            if let name = PrescriptionParser.providerName(in: row) { return name }
        }
        return ""
    }

    // MARK: Items under headings

    /// Bullets, numbering and codes off an item: "1. Otitis media (H66.91)" → "Otitis media".
    private static func cleanItem(_ row: String) -> String {
        var text = row
        text = text.replacingOccurrences(of: #"^\s*(?:[•·\-–*▪◦]|\d{1,2}[.)])\s*"#, with: "", options: .regularExpression)
        text = text.replacingOccurrences(of: #"\s*[\[(](?:ICD[- ]?10[:\s]*)?[A-TV-Z]\d{2}(?:\.\w{1,4})?[\])]"#, with: "",
                                         options: [.regularExpression, .caseInsensitive])
        text = text.replacingOccurrences(of: #"\s*-?\s*(?:primary|secondary)$"#, with: "", options: [.regularExpression, .caseInsensitive])
        text = text.trimmingCharacters(in: CharacterSet(charactersIn: " ;,"))
        let letters = text.filter(\.isLetter)
        if !letters.isEmpty, letters == letters.uppercased(), letters.count > 4 {
            text = text.lowercased()
            if let first = text.first { text = first.uppercased() + text.dropFirst() }
        }
        return text
    }

    private static func isDiagnosis(_ item: String) -> Bool {
        let words = item.split(separator: " ")
        guard item.filter(\.isLetter).count >= 3, words.count <= 12 else { return false }
        return DateScanner.dates(in: item).isEmpty
            && item.range(of: #"^(?:none|no new|n/a|see below|code|icd)"#, options: [.regularExpression, .caseInsensitive]) == nil
    }

    private static func looksLikeMedication(_ item: String) -> Bool {
        item.filter(\.isLetter).count >= 3
            && item.range(of: #"^(?:none|no changes|you have no)"#, options: [.regularExpression, .caseInsensitive]) == nil
    }

    /// Joins rows that wrap mid-sentence: a row that starts in lowercase continues the one above.
    private static func joinWrapped(_ rows: [String]) -> [String] {
        var joined: [String] = []
        for row in rows {
            if let first = row.first, first.isLowercase, !joined.isEmpty {
                joined[joined.count - 1] += " " + row
            } else {
                joined.append(row)
            }
        }
        return joined
    }

    private static func unique(_ items: [String]) -> [String] {
        var seen = Set<String>()
        return items.filter { seen.insert($0.lowercased()).inserted }
    }

    // MARK: Follow-up

    private static let followUpSentencePattern = try! NSRegularExpression(
        pattern: #"\b(?:follow[\s-]*up|return|come back|recheck|see (?:your|the) (?:doctor|provider|pediatrician))\b[^.]*\b(?:in|within)\s+(?:\d+|one|two|three|four|six)(?:\s*(?:-|to)\s*\d+)?\s*(?:days?|weeks?|wks?|months?|mos?)\b[^.]*"#,
        options: [.caseInsensitive]
    )

    /// "Return in 2 weeks", written anywhere on the page when there's no follow-up heading.
    private static func followUpSentence(in rows: [String]) -> String? {
        let text = rows.joined(separator: " ")
        guard let match = followUpSentencePattern.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)) else { return nil }
        return (text as NSString).substring(with: match.range).trimmingCharacters(in: .whitespaces)
    }

    private static let interval = try! NSRegularExpression(
        pattern: #"\b(?:in|within|after)\s+(\d+|one|two|three|four|five|six|eight|ten|twelve)(?:\s*(?:-|to)\s*\d+)?\s*(days?|weeks?|wks?|months?|mos?|years?)\b"#,
        options: [.caseInsensitive]
    )
    private static let numberWords = ["one": 1, "two": 2, "three": 3, "four": 4, "five": 5, "six": 6, "eight": 8, "ten": 10, "twelve": 12]

    /// A date written in the follow-up, or the visit date plus "in 2 weeks".
    static func followUpDate(in text: String, after visit: Date, now: Date = .now) -> Date? {
        guard !text.isEmpty else { return nil }
        if let written = DateScanner.dates(in: text, earliest: visit, now: now).first { return written.date }
        let ns = text as NSString
        guard let match = interval.firstMatch(in: text, range: NSRange(location: 0, length: ns.length)) else { return nil }
        let amountText = ns.substring(with: match.range(at: 1)).lowercased()
        guard let amount = Int(amountText) ?? numberWords[amountText] else { return nil }
        let unit = ns.substring(with: match.range(at: 2)).lowercased()
        var components = DateComponents()
        switch unit.prefix(1) {
        case "d": components.day = amount
        case "w": components.day = amount * 7
        case "m": components.month = amount
        case "y": components.year = amount
        default: return nil
        }
        return Calendar(identifier: .gregorian).date(byAdding: components, to: visit)
    }
}
