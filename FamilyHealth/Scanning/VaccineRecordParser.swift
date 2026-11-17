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

    private static func dateMatches(in row: String, dateOfBirth: Date?, now: Date) -> [DateMatch] {
        // Not before the person was born (a hepatitis B shot can be the day of birth) and not in the future.
        let earliest = dateOfBirth?.addingTimeInterval(-86_400)
        return DateScanner.dates(in: row, earliest: earliest, latest: now.addingTimeInterval(86_400), now: now)
            .map { DateMatch(date: $0.date, location: $0.location) }
    }

    private static func isOnlyDatesAndNumbers(_ row: String) -> Bool {
        row.rangeOfCharacter(from: .letters) == nil || DateScanner.hasNamedDate(row)
    }

    private static func dayKey(_ date: Date) -> String { DateScanner.dayKey(date) }
}
