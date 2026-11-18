import Foundation

/// Finds vaccine names and the dates they were given in the text of a vaccine record
/// (a school or pediatric printout, a state registry form, or a CDC card).
///
/// It works on rows of text, the way the record reads across: a vaccine name followed
/// by the dates of its doses. Everything it finds is shown for review before saving,
/// because handwriting and faint print can be misread.
enum VaccineRecordParser {
    struct Found: Identifiable, Equatable {
        var id = UUID()
        var vaccine: String
        var date: Date
    }

    /// Vaccine names as they're shown in the app, with the names, abbreviations and
    /// brands that records use. Combinations come first so "DTaP-IPV" isn't read as two.
    static let vaccines: [(name: String, aliases: [String])] = [
        ("Vaxelis (DTaP-IPV-Hib-HepB)", ["Vaxelis", "DTaP-IPV-Hib-HepB"]),
        ("Pediarix (DTaP-HepB-IPV)", ["Pediarix", "DTaP-HepB-IPV"]),
        ("Pentacel (DTaP-IPV/Hib)", ["Pentacel", "DTaP-IPV/Hib", "DTaP-IPV-Hib"]),
        ("Kinrix or Quadracel (DTaP-IPV)", ["Kinrix", "Quadracel", "DTaP-IPV"]),
        ("ProQuad (MMRV)", ["ProQuad", "MMRV", "MMR-V", "MMR/V"]),
        ("Twinrix (HepA-HepB)", ["Twinrix", "HepA-HepB"]),
        ("DTaP", ["DTaP", "DTP", "Infanrix", "Daptacel"]),
        ("Tdap", ["Tdap", "Boostrix", "Adacel"]),
        ("Td", ["Td", "Tenivac", "TDVAX"]),
        ("Hepatitis B", ["Hepatitis B", "Hep B", "HepB", "HBV", "Engerix-B", "Engerix", "Recombivax", "Heplisav"]),
        ("Hepatitis A", ["Hepatitis A", "Hep A", "HepA", "Havrix", "Vaqta"]),
        ("Rotavirus", ["Rotavirus", "RotaTeq", "Rotarix", "RV1", "RV5", "RV"]),
        ("Hib", ["Hib", "ActHIB", "PedvaxHIB", "Hiberix"]),
        ("Pneumococcal (PPSV23)", ["PPSV23", "PPSV", "Pneumovax"]),
        ("Pneumococcal (PCV)", ["PCV13", "PCV15", "PCV20", "PCV7", "PCV", "Prevnar", "Prevnar 13", "Vaxneuvance", "Pneumococcal"]),
        ("Polio (IPV)", ["IPV", "IPOL", "Polio"]),
        ("MMR", ["MMR", "M-M-R", "MMRII", "Priorix", "Measles"]),
        ("Varicella (chickenpox)", ["Varicella", "Varivax", "Chickenpox", "Chicken pox", "VAR", "VZV"]),
        ("Flu", ["Influenza", "Flu", "Fluzone", "Flulaval", "Fluarix", "FluMist", "Flucelvax", "Afluria", "LAIV", "IIV4", "IIV"]),
        ("COVID-19", ["COVID-19", "COVID 19", "COVID", "Comirnaty", "Spikevax", "SARS-CoV-2"]),
        ("HPV", ["HPV", "Gardasil", "Gardasil 9", "HPV9"]),
        ("Meningococcal ACWY", ["MenACWY", "MCV4", "Menactra", "Menveo", "MenQuadfi", "Meningococcal conjugate"]),
        ("Meningococcal B", ["MenB", "Bexsero", "Trumenba"]),
        ("RSV antibody (nirsevimab)", ["Beyfortus", "Nirsevimab", "Enflonsia", "Clesrovimab"]),
        ("RSV", ["RSV", "Abrysvo", "Arexvy", "mResvia"]),
        ("Shingles (Shingrix)", ["Shingrix", "Zoster", "RZV"]),
    ]

    private static let matchers: [(name: String, regex: NSRegularExpression)] = vaccines.flatMap { entry in
        entry.aliases.map { alias in
            let pattern = NSRegularExpression.escapedPattern(for: alias)
                .replacingOccurrences(of: "\\ ", with: "\\s*")
                .replacingOccurrences(of: " ", with: "\\s*")
            // Not inside a longer word or a longer name ("Td" in "Tdap", "MMR" in "MMRV").
            let regex = try! NSRegularExpression(pattern: "(?<![A-Za-z0-9])\(pattern)(?![A-Za-z0-9])", options: [.caseInsensitive])
            return (entry.name, regex)
        }
    }

    /// The app's name for a vaccine as a record or a person wrote it, if it's one it knows.
    static func canonicalName(_ text: String) -> String? {
        let range = NSRange(text.startIndex..., in: text)
        return matchers.first { $0.regex.firstMatch(in: text, range: range) != nil }?.name
    }

    /// Whether a document of another type looks like a vaccine record (it names several vaccines),
    /// so the button to add its vaccines can be offered there too.
    static func looksLikeVaccineRecord(_ text: String) -> Bool {
        let names = Set(text.components(separatedBy: .newlines).flatMap { vaccineMatches(in: $0).map(\.name) })
        return names.count >= 3
    }

    /// Every vaccine and date found, in the order they appear, without repeats.
    static func parse(rows: [String], dateOfBirth: Date? = nil, now: Date = .now) -> [Found] {
        var found: [Found] = []
        var lastVaccine: String?
        for row in rows {
            let names = vaccineMatches(in: row)
            let dates = dateMatches(in: row, dateOfBirth: dateOfBirth, now: now)
            if names.isEmpty {
                // A wrapped row with only more dates belongs to the vaccine above it.
                if let lastVaccine, !dates.isEmpty, isOnlyDatesAndNumbers(row) {
                    found += dates.map { Found(vaccine: lastVaccine, date: $0.date) }
                } else if !dates.isEmpty || row.rangeOfCharacter(from: .letters) != nil {
                    lastVaccine = nil
                }
                continue
            }
            // Dates after a name, up to the next name, belong to it ("DTaP 06/15/15  Hib 06/15/15").
            for (index, name) in names.enumerated() {
                let end = index + 1 < names.count ? names[index + 1].location : Int.max
                let own = dates.filter { $0.location > name.location && $0.location < end }
                // A record laid out as "06/15/2015  DTaP" puts the date first.
                let before = index == 0 && own.isEmpty ? dates.filter { $0.location < name.location } : []
                found += (own + before).map { Found(vaccine: name.name, date: $0.date) }
            }
            lastVaccine = names.last?.name
        }
        var seen = Set<String>()
        return found.filter { seen.insert("\($0.vaccine)|\(dayKey($0.date))").inserted }
    }

    /// Whether the person already has this shot recorded on that day.
    static func isAlreadyRecorded(_ found: Found, in existing: [(vaccine: String, date: Date?)]) -> Bool {
        existing.contains { shot in
            guard let date = shot.date, dayKey(date) == dayKey(found.date) else { return false }
            return (canonicalName(shot.vaccine) ?? shot.vaccine.trimmed) == found.vaccine
        }
    }

    // MARK: - Matching

    private struct NameMatch { let name: String; let location: Int }
    private struct DateMatch { let date: Date; let location: Int }

    private static func vaccineMatches(in row: String) -> [NameMatch] {
        let full = NSRange(row.startIndex..., in: row)
        var claimed: [NSRange] = []
        var matches: [NameMatch] = []
        for matcher in matchers {
            for result in matcher.regex.matches(in: row, range: full)
            where !claimed.contains(where: { NSIntersectionRange($0, result.range).length > 0 }) {
                claimed.append(result.range)
                matches.append(NameMatch(name: matcher.name, location: result.range.location))
            }
        }
        return matches.sorted { $0.location < $1.location }
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

    private static func dateMatches(in row: String, dateOfBirth: Date?, now: Date) -> [DateMatch] {
        let full = NSRange(row.startIndex..., in: row)
        let ns = row as NSString
        var results: [DateMatch] = []
        var claimed: [NSRange] = []
        func add(_ range: NSRange, year: Int, month: Int, day: Int) {
            guard !claimed.contains(where: { NSIntersectionRange($0, range).length > 0 }),
                  let date = makeDate(year: year, month: month, day: day),
                  isPlausible(date, dateOfBirth: dateOfBirth, now: now) else { return }
            claimed.append(range)
            results.append(DateMatch(date: date, location: range.location))
        }
        for m in isoDate.matches(in: row, range: full) {
            add(m.range, year: Int(ns.substring(with: m.range(at: 1)))!,
                month: Int(ns.substring(with: m.range(at: 2)))!, day: Int(ns.substring(with: m.range(at: 3)))!)
        }
        for m in namedDate.matches(in: row, range: full) {
            let month = (months.firstIndex(of: String(ns.substring(with: m.range(at: 1)).lowercased().prefix(3))) ?? -1) + 1
            add(m.range, year: Int(ns.substring(with: m.range(at: 3)))!, month: month,
                day: Int(ns.substring(with: m.range(at: 2)))!)
        }
        for m in numericDate.matches(in: row, range: full) {
            var year = Int(ns.substring(with: m.range(at: 3)))!
            if year < 100 {
                let thisYear = Calendar(identifier: .gregorian).component(.year, from: now) % 100
                year += year <= thisYear ? 2000 : 1900
            }
            add(m.range, year: year, month: Int(ns.substring(with: m.range(at: 1)))!,
                day: Int(ns.substring(with: m.range(at: 2)))!)
        }
        return results.sorted { $0.location < $1.location }
    }

    private static func makeDate(year: Int, month: Int, day: Int) -> Date? {
        guard (1...12).contains(month), (1...31).contains(day) else { return nil }
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = .current
        let components = DateComponents(year: year, month: month, day: day, hour: 12)
        guard let date = calendar.date(from: components),
              calendar.component(.day, from: date) == day else { return nil }
        return date
    }

    /// Not before the person was born (a hepatitis B shot can be the day of birth) and not in the future.
    private static func isPlausible(_ date: Date, dateOfBirth: Date?, now: Date) -> Bool {
        guard date <= now.addingTimeInterval(86_400) else { return false }
        if let dateOfBirth { return date >= dateOfBirth.addingTimeInterval(-86_400) }
        return date >= Date(timeIntervalSince1970: -2_208_988_800) // 1900
    }

    private static func isOnlyDatesAndNumbers(_ row: String) -> Bool {
        row.rangeOfCharacter(from: .letters) == nil
            || namedDate.firstMatch(in: row, range: NSRange(row.startIndex..., in: row)) != nil
    }

    private static func dayKey(_ date: Date) -> String {
        let parts = Calendar(identifier: .gregorian).dateComponents([.year, .month, .day], from: date)
        return "\(parts.year ?? 0)-\(parts.month ?? 0)-\(parts.day ?? 0)"
    }
}
