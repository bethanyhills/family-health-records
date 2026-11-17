import Foundation

/// The parts of a 504 plan or IEP that doctors and therapists ask about: what kind of
/// plan, when it was written, when it's reviewed, the eligibility category, the services
/// with their minutes, and the accommodations.
struct SchoolPlanDetails: Equatable {
    var eligibility = ""
    var nextReview: Date?
    var services: [String] = []
    var accommodations: [String] = []

    var isEmpty: Bool { eligibility.isEmpty && nextReview == nil && services.isEmpty && accommodations.isEmpty }

    private static let labels = (eligibility: "Eligibility: ", review: "Next review: ",
                                 services: "Services: ", accommodations: "Accommodations: ")

    /// Lines for the plan document's notes, where the person can read and edit them.
    var notesText: String {
        var lines: [String] = []
        if !eligibility.isEmpty { lines.append(Self.labels.eligibility + eligibility) }
        if let nextReview { lines.append(Self.labels.review + nextReview.formDate) }
        if !services.isEmpty { lines.append(Self.labels.services + services.joined(separator: "; ")) }
        if !accommodations.isEmpty { lines.append(Self.labels.accommodations + accommodations.joined(separator: "; ")) }
        return lines.joined(separator: "\n")
    }

    /// Reads the lines back out of the notes, including after the person edits them.
    init(notes: String) {
        for line in notes.components(separatedBy: .newlines).map(\.trimmed) {
            func value(_ label: String) -> String? {
                line.lowercased().hasPrefix(label.lowercased()) ? String(line.dropFirst(label.count)).trimmed : nil
            }
            func list(_ text: String) -> [String] {
                text.components(separatedBy: ";").map(\.trimmed).filter { !$0.isEmpty }
            }
            if let text = value(Self.labels.eligibility) { eligibility = text }
            if let text = value(Self.labels.review) { nextReview = TypedDate.parse(text) }
            if let text = value(Self.labels.services) { services = list(text) }
            if let text = value(Self.labels.accommodations) { accommodations = list(text) }
        }
    }

    init(eligibility: String = "", nextReview: Date? = nil, services: [String] = [], accommodations: [String] = []) {
        self.eligibility = eligibility
        self.nextReview = nextReview
        self.services = services
        self.accommodations = accommodations
    }

    /// The notes with these details in place of any written before, keeping the person's own lines.
    func merged(into notes: String) -> String {
        let prefixes = [Self.labels.eligibility, Self.labels.review, Self.labels.services, Self.labels.accommodations]
            .map { $0.lowercased() }
        let kept = notes.components(separatedBy: .newlines)
            .filter { line in !prefixes.contains { line.trimmed.lowercased().hasPrefix($0) } }
            .joined(separator: "\n").trimmed
        return [kept, notesText].filter { !$0.isEmpty }.joined(separator: "\n\n")
    }
}

/// Reads a 504 plan or IEP.
enum SchoolPlanParser {
    struct Result: Equatable {
        var plan: SchoolPlan = .noPlan
        var planDate: Date?
        var details = SchoolPlanDetails()
    }

    private static let iepWords = try! NSRegularExpression(
        pattern: #"individuali[sz]ed education(?:al)? (?:program|plan)|\bIEP\b"#, options: [.caseInsensitive]
    )
    private static let plan504Words = try! NSRegularExpression(
        pattern: #"section 504|\b504 (?:plan|accommodation|services|team|meeting|eligibility)|\b504\b"#, options: [.caseInsensitive]
    )

    /// Which plan the text is, by how often each kind is named. `.noPlan` if neither is.
    static func planKind(of text: String) -> SchoolPlan {
        let range = NSRange(text.startIndex..., in: text)
        let iep = iepWords.numberOfMatches(in: text, range: range)
        let plan504 = plan504Words.numberOfMatches(in: text, range: range)
        if iep == 0 && plan504 == 0 { return .noPlan }
        return iep >= plan504 ? .iep : .plan504
    }

    /// Whether a document of another type reads like a 504 plan or IEP.
    static func looksLikeSchoolPlan(_ text: String) -> Bool {
        let range = NSRange(text.startIndex..., in: text)
        let named = iepWords.numberOfMatches(in: text, range: range) + plan504Words.numberOfMatches(in: text, range: range)
        let hasPlanWords = text.range(of: #"accommodations?|related services|special education|eligibility"#,
                                      options: [.regularExpression, .caseInsensitive]) != nil
        return named >= 2 && hasPlanWords
    }

    static func parse(rows: [String], now: Date = .now) -> Result {
        let rows = rows.map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
        var result = Result()
        result.plan = planKind(of: rows.joined(separator: "\n"))
        result.planDate = labeledDate(in: rows, labels: planDateLabels, latest: now.addingTimeInterval(86_400), now: now)
        result.details.nextReview = labeledDate(in: rows, labels: reviewDateLabels, latest: nil, now: now)
        result.details.eligibility = eligibility(in: rows)
        result.details.services = services(in: rows)
        result.details.accommodations = accommodations(in: rows)
        return result
    }

    // MARK: Dates

    private static let planDateLabels = try! NSRegularExpression(
        pattern: #"(meeting date|date of (?:the )?meeting|iep date|plan date|date of (?:the )?plan|initiation date|start date|effective date|date developed|implementation date|504 date|iep start|plan start|developed on)"#,
        options: [.caseInsensitive]
    )
    private static let reviewDateLabels = try! NSRegularExpression(
        pattern: #"(annual review|review date|next review|projected (?:annual )?review|review by|plan end|end date|iep end|expiration|expires|re-?evaluation(?: due| date)?|triennial)"#,
        options: [.caseInsensitive]
    )

    private static func labeledDate(in rows: [String], labels: NSRegularExpression, latest: Date?, now: Date) -> Date? {
        for row in rows {
            let ns = row as NSString
            var segmentStart = 0
            for match in DateScanner.dates(in: row, latest: latest, now: now) {
                let before = ns.substring(with: NSRange(location: segmentStart, length: match.location - segmentStart))
                segmentStart = match.location + match.length
                if labels.firstMatch(in: before, range: NSRange(before.startIndex..., in: before)) != nil {
                    return match.date
                }
            }
        }
        return nil
    }

    // MARK: Eligibility

    private static let eligibilityLabel = try! NSRegularExpression(
        pattern: #"(?:primary |secondary )?(?:disability category|eligibility category|eligibility|primary disability|qualifying (?:condition|disability)|disability|impairment)\s*:\s*(.+)$"#,
        options: [.caseInsensitive]
    )

    private static func eligibility(in rows: [String]) -> String {
        for row in rows {
            guard let match = eligibilityLabel.firstMatch(in: row, range: NSRange(row.startIndex..., in: row)) else { continue }
            let value = (row as NSString).substring(with: match.range(at: 1))
                .replacingOccurrences(of: #"\s*\(\w{1,5}\)\s*$"#, with: "", options: .regularExpression)
                .trimmingCharacters(in: CharacterSet(charactersIn: " .;"))
            if value.filter(\.isLetter).count >= 3, value.count <= 80 { return readable(value) }
        }
        return ""
    }

    // MARK: Services

    private static let serviceWords = try! NSRegularExpression(
        pattern: #"speech|language|occupational|physical therapy|\bOT\b|\bPT\b|\bSLP\b|counsel|social work|psycholog|resource|special education|specialized instruction|\bABA\b|behavior|reading|math|writing|audiolog|vision|orientation and mobility|nurs|transportation|assistive technology|adapted p\.?e\.?|paraprofessional|aide"#,
        options: [.caseInsensitive]
    )
    private static let minutesPattern = try! NSRegularExpression(
        pattern: #"\b\d+\s*(?:min(?:ute)?s?|hrs?|hours?)\b|\b\d+\s*x\s*/?\s*(?:week|wk|month|mo)"#, options: [.caseInsensitive]
    )

    /// Rows naming a service with its minutes: "Speech-language therapy  30 min  1x weekly".
    private static func services(in rows: [String]) -> [String] {
        var found: [String] = []
        for row in rows {
            let range = NSRange(row.startIndex..., in: row)
            guard serviceWords.firstMatch(in: row, range: range) != nil,
                  minutesPattern.firstMatch(in: row, range: range) != nil else { continue }
            let text = readable(cleanItem(row)
                .replacingOccurrences(of: #"\s{2,}|\t"#, with: ", ", options: .regularExpression)
                .replacingOccurrences(of: #"(?:,\s*){2,}"#, with: ", ", options: .regularExpression))
            if text.count <= 140, !found.contains(text) { found.append(text) }
        }
        return Array(found.prefix(10))
    }

    // MARK: Accommodations

    private static let accommodationsHeading = try! NSRegularExpression(
        pattern: #"^\s*(?:(?:classroom|instructional|testing|assessment|state testing|program)\s+)?(?:accommodations?|modifications?)(?:\s+(?:and|&)\s+modifications)?(?:\s*/\s*modifications)?|^\s*supplementary aids(?: and services)?"#,
        options: [.caseInsensitive]
    )
    /// Headings that end the accommodations list.
    private static let otherHeading = try! NSRegularExpression(
        pattern: #"^\s*(?:goals?|annual goals?|present levels?|services|related services|special education services|placement|least restrictive|transition|signatures?|participants|team members|parent|progress|eligibility|behavior(?:al)? (?:intervention )?plan|extended school year|transportation|notice|consent|page \d)"#,
        options: [.caseInsensitive]
    )

    private static func accommodations(in rows: [String]) -> [String] {
        var found: [String] = []
        var inList = false
        for row in rows {
            let range = NSRange(row.startIndex..., in: row)
            if let heading = accommodationsHeading.firstMatch(in: row, range: range) {
                inList = true
                let rest = (row as NSString).substring(from: heading.range.length)
                    .trimmingCharacters(in: CharacterSet(charactersIn: " :-"))
                found += rest.components(separatedBy: ";").map(cleanItem).filter(isAccommodation)
                continue
            }
            guard inList else { continue }
            if otherHeading.firstMatch(in: row, range: range) != nil { inList = false; continue }
            let item = cleanItem(row)
            if isAccommodation(item) {
                // A row that starts in lowercase continues the one above.
                if let first = item.first, first.isLowercase, !found.isEmpty {
                    found[found.count - 1] += " " + item
                } else {
                    found.append(readable(item))
                }
            }
        }
        var seen = Set<String>()
        return Array(found.filter { seen.insert($0.lowercased()).inserted }.prefix(20))
    }

    private static func isAccommodation(_ item: String) -> Bool {
        item.filter(\.isLetter).count >= 3 && item.count <= 160
            && item.range(of: #"^(?:none|n/a|frequency|location|duration|setting|accommodation|description)\b"#,
                          options: [.regularExpression, .caseInsensitive]) == nil
    }

    // MARK: Text

    private static func cleanItem(_ row: String) -> String {
        row.replacingOccurrences(of: #"^\s*(?:[•·\-–*▪◦☐☑✓✔]|\[\s?[xX]?\s?\]|\d{1,2}[.)]|[a-z][.)])\s*"#, with: "", options: .regularExpression)
            .trimmingCharacters(in: CharacterSet(charactersIn: " ;,."))
    }

    /// All-caps text in sentence case.
    private static func readable(_ text: String) -> String {
        let letters = text.filter(\.isLetter)
        guard letters.count > 4, letters == letters.uppercased() else { return text }
        let lower = text.lowercased()
        return lower.prefix(1).uppercased() + lower.dropFirst()
    }
}
