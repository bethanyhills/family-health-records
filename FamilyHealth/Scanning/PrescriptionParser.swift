import Foundation

/// Reads a medication off a pharmacy label, a pharmacy printout or a prescription
/// from the doctor's office: the drug and strength, the directions, who prescribed it,
/// the pharmacy and the date it was filled.
///
/// It works on rows of text the way the label reads. What it finds is put into the
/// medication editor for the person to check before saving.
enum PrescriptionParser {
    struct Result: Equatable {
        var name = ""
        var dose = ""
        var directions = ""
        var reason = ""
        var prescriber = ""
        var pharmacy = ""
        var dateFilled: Date?
        var rxNumber = ""
        var quantity = ""
        var refills = ""

        var isEmpty: Bool { name.isEmpty }

        /// "Rx #1234567 · Filled 03/14/2026 · Qty 30 · 2 refills", for the medication's notes.
        var labelDetails: String {
            var parts: [String] = []
            if !rxNumber.isEmpty { parts.append("Rx #\(rxNumber)") }
            if let dateFilled { parts.append("Filled \(dateFilled.formDate)") }
            if !quantity.isEmpty { parts.append("Qty \(quantity)") }
            if !refills.isEmpty {
                parts.append(refills == "0" ? "No refills" : refills == "1" ? "1 refill" : "\(refills) refills")
            }
            return parts.joined(separator: " · ")
        }
    }

    // MARK: - Recognizing a prescription

    /// Whether a document of another type reads like a prescription label or printout,
    /// so the button to add the medication can be offered there too.
    static func looksLikePrescription(_ text: String) -> Bool {
        let rows = text.components(separatedBy: .newlines)
        let hasDrug = rows.contains { drugLineScore($0) > 0 }
        let hasDirections = rows.contains { directionsStart(in: $0) != nil }
        let range = NSRange(text.startIndex..., in: text)
        let hasRxWords = rxWords.firstMatch(in: text, range: range) != nil
        return hasDrug && hasDirections && hasRxWords
    }

    private static let rxWords = try! NSRegularExpression(
        pattern: #"\b(rx\s*(#|no\b|number)|refills?|qty|quantity|dispense|disp\b|prescriber|prescribed by|pharmacy)"#,
        options: [.caseInsensitive]
    )

    // MARK: - Reading the label

    static func parse(rows: [String], now: Date = .now) -> Result {
        let rows = rows.map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
        var result = Result()
        let text = rows.joined(separator: "\n")

        if let drug = drugLine(in: rows) {
            result.name = drug.name
            result.dose = drug.dose
        }
        result.directions = directions(in: rows)
        result.reason = reason(in: rows, directions: result.directions)
        result.prescriber = prescriber(in: rows)
        result.pharmacy = pharmacy(in: rows)
        result.dateFilled = dateFilled(in: rows, now: now)
        result.rxNumber = first(rxNumberPattern, in: text)
        result.quantity = quantity(in: text)
        result.refills = refills(in: text)
        return result
    }

    // MARK: Drug and strength

    private static let strength = try! NSRegularExpression(
        pattern: #"(?<![A-Za-z0-9.])(\d+(?:[.,]\d+)?(?:\s*-\s*\d+(?:\.\d+)?)?)\s*(mg|mcg|µg|ug|g|gm|ml|meq|units?|iu|%)(?:\s*/\s*(\d+(?:\.\d+)?)?\s*(ml|g|actuation|act|hr|h|spray|dose))?(?![A-Za-z])"#,
        options: [.caseInsensitive]
    )

    /// Forms printed on labels, with how the app writes them.
    private static let forms: [(pattern: String, name: String)] = [
        ("tablets?|tabs?", "tablet"), ("capsules?|caps?", "capsule"),
        ("chewable|chew", "chewable tablet"), ("odt|disintegrating", "dissolving tablet"),
        ("suspension|susp|susr", "suspension"), ("solution|soln|sol", "solution"),
        ("syrup", "syrup"), ("elixir", "elixir"), ("liquid", "liquid"),
        ("cream|crm", "cream"), ("ointment|oint", "ointment"), ("gel", "gel"), ("lotion", "lotion"),
        ("inhaler|hfa|aerosol|inh", "inhaler"), ("nebulizer|neb", "nebulizer solution"),
        ("patch(?:es)?", "patch"), ("drops?|gtts", "drops"), ("spray", "spray"),
        ("injection|inj|pen|auto-?injector", "injection"), ("powder|pwd", "powder"),
        ("suppository|supp", "suppository"), ("film", "film"), ("lozenges?", "lozenge"),
    ]
    private static let formPatterns: [(regex: NSRegularExpression, name: String)] = forms.map {
        (try! NSRegularExpression(pattern: #"(?<![A-Za-z])(?:"# + $0.pattern + #")(?![A-Za-z])"#, options: [.caseInsensitive]), $0.name)
    }
    private static let releaseWords = ["er", "xr", "sr", "la", "xl", "dr", "cr", "ec", "odt"]

    /// Words in front of the drug name that aren't part of it.
    private static let namePrefixes = try! NSRegularExpression(
        pattern: #"^(?:(?:rx|medication|medicine|drug|name|product|item|generic(?: for)?|sub(?:stituted)?(?: for)?|dispensed|disp)\s*[:#.\-]?\s*)+"#,
        options: [.caseInsensitive]
    )

    private struct Drug { let name: String; let dose: String }

    private static func drugLine(in rows: [String]) -> Drug? {
        let scored = rows.enumerated().map { (index: $0.offset, row: $0.element, score: drugLineScore($0.element)) }
        guard let best = scored.filter({ $0.score > 0 }).max(by: { $0.score < $1.score || ($0.score == $1.score && $0.index > $1.index) })
        else { return nil }
        return drug(from: best.row)
    }

    /// How much a row reads like "AMOXICILLIN 500MG CAPSULE". Zero means it isn't one.
    private static func drugLineScore(_ row: String) -> Int {
        let full = NSRange(row.startIndex..., in: row)
        guard let match = strength.firstMatch(in: row, range: full),
              directionsStart(in: row) == nil,
              rxWords.firstMatch(in: row, range: full) == nil,
              !row.lowercased().hasPrefix("sig") else { return 0 }
        let before = (row as NSString).substring(to: match.range.location)
        let letters = before.filter(\.isLetter).count
        var score = letters >= 3 ? 2 : (row.filter(\.isLetter).count >= 6 ? 1 : 0)
        guard score > 0 else { return 0 }
        if formPatterns.contains(where: { $0.regex.firstMatch(in: row, range: full) != nil }) { score += 2 }
        return score
    }

    private static func drug(from row: String) -> Drug? {
        let ns = row as NSString
        guard let match = strength.firstMatch(in: row, range: NSRange(location: 0, length: ns.length)) else { return nil }
        let before = ns.substring(to: match.range.location)
        let after = ns.substring(from: match.range.location + match.range.length)

        var nameText = before.trimmingCharacters(in: CharacterSet(charactersIn: " ,:-;(").union(.whitespaces))
        nameText = namePrefixes.stringByReplacingMatches(
            in: nameText, range: NSRange(nameText.startIndex..., in: nameText), withTemplate: "")
        // "AMOXICILLIN" from a row like "500 MG AMOXICILLIN CAPSULE".
        if nameText.filter(\.isLetter).count < 3 {
            nameText = after.components(separatedBy: .whitespaces)
                .filter { word in !word.isEmpty && formName(in: word) == nil && word.contains(where: \.isLetter) }
                .prefix(2).joined(separator: " ")
        }
        let name = drugNameCase(nameText.trimmingCharacters(in: .whitespaces))
        guard name.filter(\.isLetter).count >= 3 else { return nil }

        var dose = strengthText(match, in: ns)
        let release = after.lowercased().components(separatedBy: CharacterSet.letters.inverted)
            .first { releaseWords.contains($0) }
        if let release { dose += " " + release.uppercased() }
        if let form = formName(in: after) ?? formName(in: before) { dose += " " + form }
        return Drug(name: name, dose: dose)
    }

    /// "500 mg", "400 mg/5 mL", "0.1%".
    private static func strengthText(_ match: NSTextCheckingResult, in ns: NSString) -> String {
        func group(_ i: Int) -> String? {
            let range = match.range(at: i)
            return range.location == NSNotFound ? nil : ns.substring(with: range)
        }
        let amount = (group(1) ?? "").replacingOccurrences(of: ",", with: ".").replacingOccurrences(of: " ", with: "")
        let unit = unitText(group(2) ?? "")
        var text = unit == "%" ? amount + "%" : amount + " " + unit
        if let per = group(4) {
            text += "/" + (group(3).map { $0 + " " } ?? "") + unitText(per)
        }
        return text
    }

    private static func unitText(_ unit: String) -> String {
        switch unit.lowercased() {
        case "ml": "mL"
        case "µg", "ug": "mcg"
        case "gm": "g"
        case "meq": "mEq"
        case "unit", "units": "units"
        case "iu": "IU"
        case "act", "actuation": "actuation"
        case "h", "hr": "hr"
        default: unit.lowercased()
        }
    }

    private static func formName(in text: String) -> String? {
        let range = NSRange(text.startIndex..., in: text)
        return formPatterns
            .compactMap { form in form.regex.firstMatch(in: text, range: range).map { (form.name, $0.range.location) } }
            .min { $0.1 < $1.1 }?.0
    }

    /// "AMOXICILLIN-CLAVULANATE" → "Amoxicillin-Clavulanate". Mixed case is left alone.
    private static func drugNameCase(_ text: String) -> String {
        let letters = text.filter(\.isLetter)
        guard !letters.isEmpty, letters == letters.uppercased() else { return text }
        return text.lowercased().capitalized
    }

    // MARK: Directions

    private static let directionVerbs = [
        "take", "give", "use", "apply", "inhale", "instill", "place", "inject", "chew", "dissolve",
        "spray", "insert", "dissolve", "mix", "rub", "nebulize", "swish", "gargle", "put",
    ]
    private static let directionLabel = try! NSRegularExpression(
        pattern: #"^(?:sig|directions|instructions|how to take|dosage)(?![A-Za-z])\s*[:.\-]?\s*"#, options: [.caseInsensitive]
    )

    /// Where the directions start in a row, if they do.
    private static func directionsStart(in row: String) -> String? {
        let range = NSRange(row.startIndex..., in: row)
        var text = row
        if let label = directionLabel.firstMatch(in: row, range: range) {
            text = (row as NSString).substring(from: label.range.length)
            return text.isBlank ? "" : text
        }
        let words = text.lowercased().split(whereSeparator: { !$0.isLetter }).map(String.init)
        guard let first = words.first, directionVerbs.contains(first), words.count >= 2,
              text.lowercased().hasPrefix(first),
              // "USE BY 03/2027" and "TAKE WITH FOOD" stickers aren't the directions.
              !["by", "before", "after", "within"].contains(words[1]) else { return nil }
        return text
    }

    /// Words that carry directions over to the next row: "TAKE 1 TABLET BY MOUTH TWICE" / "DAILY WITH FOOD".
    private static let continuationWords: Set<String> = [
        "daily", "day", "a", "times", "hours", "hour", "needed", "as", "if", "for", "with", "without", "at",
        "bedtime", "every", "twice", "once", "three", "four", "morning", "evening", "night", "food", "meals",
        "mouth", "until", "then", "each", "in", "into", "to", "and", "or", "by", "both", "affected", "area",
        "ear", "ears", "eye", "eyes", "nostril", "nostrils", "before", "after", "the", "on", "of", "per",
        "weekly", "monthly", "days", "weeks", "while", "when", "do", "not", "apply", "skin",
    ]
    private static let danglingWords: Set<String> = [
        "by", "a", "every", "per", "to", "and", "or", "with", "for", "at", "in", "the", "of", "times", "as", "each",
        "into", "twice", "once", "then", "before", "after", "if",
    ]

    private static let doseWords = try! NSRegularExpression(
        pattern: #"\d|daily|times|every|needed|once|twice|bedtime|morning|night|hours"#, options: [.caseInsensitive]
    )

    private static func directions(in rows: [String]) -> String {
        let starts = rows.indices.filter { directionsStart(in: rows[$0]) != nil }
        // Directions say how much and how often; a "Take with food" sticker doesn't.
        let best = starts.first { index in
            var row = rows[index]
            // "Sig:" alone on its row: the directions are the next row.
            if directionsStart(in: row) == "", index + 1 < rows.count { row = rows[index + 1] }
            return doseWords.firstMatch(in: row, range: NSRange(row.startIndex..., in: row)) != nil
        } ?? starts.first
        guard let index = best, var text = directionsStart(in: rows[index]) else { return "" }
        var next = index + 1
        // "Sig:" on a row by itself, with the directions below it.
        if text.isEmpty, next < rows.count {
            text = rows[next]
            next += 1
        }
        var added = 0
        while next < rows.count, added < 3 {
            let candidate = rows[next]
            let range = NSRange(candidate.startIndex..., in: candidate)
            let firstWord = candidate.lowercased().prefix { $0.isLetter }
            let lastWord = text.lowercased().split(separator: " ").last.map(String.init) ?? ""
            guard rxWords.firstMatch(in: candidate, range: range) == nil,
                  DateScanner.dates(in: candidate).isEmpty,
                  !candidate.contains(":"),
                  continuationWords.contains(String(firstWord)) || danglingWords.contains(lastWord)
            else { break }
            text += " " + candidate
            next += 1
            added += 1
        }
        return directionsCase(text)
    }

    /// Shorthand doctors write, spelled out the way a label would say it.
    private static let shorthand: [(pattern: String, words: String)] = [
        (#"p\.?o\.?"#, "by mouth"), (#"b\.?i\.?d\.?"#, "twice a day"),
        (#"t\.?i\.?d\.?"#, "three times a day"), (#"q\.?i\.?d\.?"#, "four times a day"),
        (#"q\.?d\.?"#, "once a day"), (#"q\.?h\.?s\.?"#, "at bedtime"), (#"h\.?s\.?"#, "at bedtime"),
        (#"q\s?(\d+)\s?h(?:rs?)?"#, "every $1 hours"), (#"p\.?r\.?n\.?"#, "as needed"),
        (#"q\.?a\.?m\.?"#, "every morning"), (#"q\.?p\.?m\.?"#, "every evening"),
        (#"ou"#, "in both eyes"), (#"tabs"#, "tablets"), (#"tab"#, "tablet"), (#"caps"#, "capsules"), (#"cap"#, "capsule"),
    ]
    /// Whole words only: "po" but not "pour".
    private static let shorthandPatterns = shorthand.map {
        (regex: try! NSRegularExpression(pattern: #"(?<![A-Za-z])"# + $0.pattern + #"(?![A-Za-z])"#, options: [.caseInsensitive]),
         words: $0.words)
    }

    private static func directionsCase(_ text: String) -> String {
        var result = text.trimmingCharacters(in: .whitespaces)
        let letters = result.filter(\.isLetter)
        if letters == letters.uppercased() { result = result.lowercased() }
        for item in shorthandPatterns {
            result = item.regex.stringByReplacingMatches(
                in: result, range: NSRange(result.startIndex..., in: result), withTemplate: item.words)
        }
        result = result
            .replacingOccurrences(of: #"(\d)\s*ml\b"#, with: "$1 mL", options: [.regularExpression, .caseInsensitive])
            .replacingOccurrences(of: #"\bml\b"#, with: "mL", options: [.regularExpression, .caseInsensitive])
        result = result.replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
        if let first = result.first { result = first.uppercased() + result.dropFirst() }
        if result.hasSuffix(".") { result.removeLast() }
        return result
    }

    // MARK: Reason

    private static let reasonLabel = try! NSRegularExpression(
        pattern: #"^(?:indication|reason|diagnosis|dx|for)\s*:\s*(.+)$"#, options: [.caseInsensitive]
    )
    private static let reasonInDirections = try! NSRegularExpression(
        pattern: #"\bfor\s+([a-z][a-z' \-]{2,40}?)\s*$"#, options: [.caseInsensitive]
    )
    private static let notReasons = try! NSRegularExpression(
        pattern: #"^(?:\d|one|two|three|four|five|six|seven|ten|a |the next|up to|days?\b|weeks?\b|months?\b)"#,
        options: [.caseInsensitive]
    )

    private static func reason(in rows: [String], directions: String) -> String {
        for row in rows {
            if let match = reasonLabel.firstMatch(in: row, range: NSRange(row.startIndex..., in: row)) {
                return sentenceFragment((row as NSString).substring(with: match.range(at: 1)))
            }
        }
        let range = NSRange(directions.startIndex..., in: directions)
        guard let match = reasonInDirections.firstMatch(in: directions, range: range) else { return "" }
        let reason = (directions as NSString).substring(with: match.range(at: 1))
        guard notReasons.firstMatch(in: reason, range: NSRange(reason.startIndex..., in: reason)) == nil else { return "" }
        return sentenceFragment(reason)
    }

    private static func sentenceFragment(_ text: String) -> String {
        let trimmed = text.trimmingCharacters(in: CharacterSet(charactersIn: " .;,"))
        let letters = trimmed.filter(\.isLetter)
        return letters == letters.uppercased() ? trimmed.lowercased() : trimmed
    }

    // MARK: Prescriber

    private static let credentialCodes = "MD|M\\.D\\.|DO|D\\.O\\.|NP|FNP|FNP-C|FNP-BC|CPNP|PNP|APRN|ARNP|PA|PA-C|DDS|DMD|OD|DPM|PharmD"
    private static let prescriberLabels = [
        #"(?:prescriber|prescribed by|prescribing (?:doctor|physician|provider)|ordering provider)\s*[:#.\-]?\s*(?:dr\.?\s+)?(.+)$"#,
        #"(?<![A-Za-z])(?:provider|physician|doctor)\s*:\s*(?:dr\.?\s+)?(.+)$"#,
    ].map { try! NSRegularExpression(pattern: $0, options: [.caseInsensitive]) }
    private static let notDoctorCredential = try! NSRegularExpression(
        pattern: #"(?:,\s*|\s)(NP|FNP|FNP-C|FNP-BC|CPNP|PNP|APRN|ARNP|PA-C|PA)(?![A-Za-z])"#, options: [.caseInsensitive]
    )
    private static let doctorPrefix = try! NSRegularExpression(
        pattern: #"(?:^|\s)dr\.?\s+([A-Za-z][A-Za-z.'\-]*(?:,?\s+[A-Za-z][A-Za-z.'\-]*){0,3})"#,
        options: [.caseInsensitive]
    )
    private static let credentialName = try! NSRegularExpression(
        pattern: #"^([A-Za-z][A-Za-z.'\-]+(?:\s+[A-Za-z][A-Za-z.'\-]*){1,3}),?\s+(?:"# + credentialCodes + #")(?![A-Za-z])"#
    )

    private static func prescriber(in rows: [String]) -> String {
        for row in rows {
            let range = NSRange(row.startIndex..., in: row)
            for label in prescriberLabels {
                if let match = label.firstMatch(in: row, range: range) {
                    let raw = (row as NSString).substring(with: match.range(at: 1))
                    if let name = displayName(raw, row: row) { return name }
                }
            }
        }
        for row in rows {
            let range = NSRange(row.startIndex..., in: row)
            if let match = doctorPrefix.firstMatch(in: row, range: range) {
                // "123 OAK DR" is a street, not a doctor.
                let before = (row as NSString).substring(to: match.range.location)
                if !before.contains(where: \.isNumber),
                   let name = displayName((row as NSString).substring(with: match.range(at: 1)), row: row) {
                    return name
                }
            }
            if let match = credentialName.firstMatch(in: row, range: range),
               let name = displayName((row as NSString).substring(with: match.range(at: 1)), row: row) {
                return name
            }
        }
        return ""
    }

    /// "Dr. Jane Smith", or "Jane Smith, NP" for a nurse practitioner or physician assistant.
    private static func displayName(_ raw: String, row: String) -> String? {
        let name = personName(raw)
        guard !name.isEmpty else { return nil }
        let range = NSRange(row.startIndex..., in: row)
        if let match = notDoctorCredential.firstMatch(in: row, range: range) {
            return name + ", " + (row as NSString).substring(with: match.range(at: 1)).uppercased()
        }
        return "Dr. " + name
    }

    /// "SMITH, JANE A MD NPI 1234567890" → "Jane A Smith".
    private static func personName(_ raw: String) -> String {
        var text = raw
        // Cut at numbers (NPI, DEA, phone) and at credentials.
        if let digit = text.firstIndex(where: \.isNumber) { text = String(text[..<digit]) }
        text = text.replacingOccurrences(
            of: #"(?:,\s*|\s+)(?:"# + credentialCodes + #"|NPI|DEA|PH|PHONE|TEL)(?![A-Za-z]).*$"#,
            with: "", options: [.regularExpression, .caseInsensitive])
        text = text.trimmingCharacters(in: CharacterSet(charactersIn: " ,.:#-"))
        var parts = text.components(separatedBy: ",").map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
        if parts.count == 2 { parts = [parts[1], parts[0]] }
        let words = parts.joined(separator: " ").split(separator: " ").map(String.init)
        guard (1...4).contains(words.count), words.allSatisfy({ $0.first?.isLetter == true }) else { return "" }
        let name = words.joined(separator: " ")
        let letters = name.filter(\.isLetter)
        guard letters.count >= 3 else { return "" }
        return letters == letters.uppercased() || letters == letters.lowercased() ? name.lowercased().capitalized : name
    }

    // MARK: Pharmacy

    /// Pharmacies by the names labels print, with how people say them.
    static let pharmacyChains: [(pattern: String, name: String)] = [
        ("cvs\\s?caremark|caremark", "CVS Caremark"), ("cvs", "CVS Pharmacy"), ("walgreens?", "Walgreens"), ("rite\\s?aid", "Rite Aid"),
        ("wal-?mart", "Walmart Pharmacy"), ("target", "Target Pharmacy"), ("kroger", "Kroger Pharmacy"),
        ("costco", "Costco Pharmacy"), ("sam'?s club", "Sam's Club Pharmacy"), ("publix", "Publix Pharmacy"),
        ("h-?e-?b", "H-E-B Pharmacy"), ("safeway", "Safeway Pharmacy"), ("albertsons", "Albertsons Pharmacy"),
        ("meijer", "Meijer Pharmacy"), ("hy-?vee", "Hy-Vee Pharmacy"), ("wegmans", "Wegmans Pharmacy"),
        ("harris teeter", "Harris Teeter Pharmacy"), ("giant eagle", "Giant Eagle Pharmacy"),
        ("express scripts", "Express Scripts"), ("optum\\s?rx", "OptumRx"),
        ("amazon pharmacy|pillpack", "Amazon Pharmacy"), ("alto pharmacy", "Alto Pharmacy"),
        ("duane reade", "Duane Reade"), ("fred meyer", "Fred Meyer Pharmacy"), ("king soopers", "King Soopers Pharmacy"),
    ]
    private static let chainPatterns = pharmacyChains.map {
        (regex: try! NSRegularExpression(pattern: #"(?<![A-Za-z])(?:"# + $0.pattern + #")(?![A-Za-z])"#, options: [.caseInsensitive]), name: $0.name)
    }
    private static let pharmacyWord = try! NSRegularExpression(
        pattern: #"(?<![A-Za-z])(pharmacy|drug\s?store|drugs|apothecary|chemist)(?![A-Za-z])"#, options: [.caseInsensitive]
    )

    private static func pharmacy(in rows: [String]) -> String {
        for row in rows {
            let range = NSRange(row.startIndex..., in: row)
            if let chain = chainPatterns.first(where: { $0.regex.firstMatch(in: row, range: range) != nil }) {
                return chain.name
            }
        }
        for row in rows {
            let range = NSRange(row.startIndex..., in: row)
            guard let word = pharmacyWord.firstMatch(in: row, range: range) else { continue }
            var text = (row as NSString).substring(to: word.range.location + word.range.length)
            text = text.replacingOccurrences(of: #"^(?:pharmacy|filled at|dispensed by)\s*:\s*"#, with: "",
                                             options: [.regularExpression, .caseInsensitive])
            if let digit = text.firstIndex(where: \.isNumber) { text = String(text[..<digit]) }
            text = text.trimmingCharacters(in: CharacterSet(charactersIn: " ,.:#-"))
            guard text.filter(\.isLetter).count >= 4, text.lowercased() != "pharmacy" else { continue }
            let letters = text.filter(\.isLetter)
            return letters == letters.uppercased() ? text.lowercased().capitalized : text
        }
        return ""
    }

    // MARK: Date, number, quantity, refills

    private static let filledLabel = try! NSRegularExpression(
        pattern: #"(date\s*filled|fill\s*date|filled\s*(on)?|date\s*of\s*fill|dispensed|date\s*dispensed|rx\s*date|date\s*written|written|issued|ordered|date)\b"#,
        options: [.caseInsensitive]
    )
    private static let notFilledLabel = try! NSRegularExpression(
        pattern: #"(discard|use\s*by|use\s*before|exp|expires|expiration|beyond|dob|d\.o\.b|birth|born|next\s*fill|refill\s*(by|after|before)|until)"#,
        options: [.caseInsensitive]
    )

    private static func dateFilled(in rows: [String], now: Date) -> Date? {
        let latest = now.addingTimeInterval(86_400)
        var labeled: [(priority: Int, date: Date)] = []
        var unlabeled: [Date] = []
        for row in rows {
            let ns = row as NSString
            var segmentStart = 0
            for match in DateScanner.dates(in: row, latest: latest, now: now) {
                // Only the words since the previous date label this one.
                let before = ns.substring(with: NSRange(location: segmentStart, length: match.location - segmentStart))
                segmentStart = match.location + match.length
                let beforeRange = NSRange(before.startIndex..., in: before)
                let labels = filledLabel.matches(in: before, range: beforeRange)
                let blockers = notFilledLabel.matches(in: before, range: beforeRange)
                let lastLabel = labels.last?.range.location ?? -1
                let lastBlocker = blockers.last?.range.location ?? -1
                if lastBlocker > lastLabel { continue }
                if let label = labels.last {
                    let word = (before as NSString).substring(with: label.range).lowercased()
                    let priority = word.contains("fill") || word.contains("dispens") ? 0 : word == "date" ? 1 : 2
                    labeled.append((priority, match.date))
                } else if blockers.isEmpty {
                    unlabeled.append(match.date)
                }
            }
        }
        if let best = labeled.min(by: { $0.priority < $1.priority }) { return best.date }
        // A label with one plain date on it: that's when it was filled.
        let threeYearsAgo = now.addingTimeInterval(-3 * 365 * 86_400)
        return unlabeled.first { $0 >= threeYearsAgo }
    }

    private static let rxNumberPattern = try! NSRegularExpression(
        pattern: #"\brx\s*(?:#|no\.?|number|num)?\s*[:.]?\s*#?\s*(\d[\d\-]{3,}\d)"#, options: [.caseInsensitive]
    )
    private static let quantityPattern = try! NSRegularExpression(
        pattern: #"\b(?:qty|quantity|disp(?:ense)?)\s*[:.]?\s*#?\s*(\d+(?:\.\d+)?)\s*(ml|tablets?|tabs?|capsules?|caps?|g|grams?|each|ea|patches|inhalers?)?\b"#,
        options: [.caseInsensitive]
    )
    /// "Refills: 2". Tried first, so "Qty: 30  Refills: 0" isn't read as 30 refills.
    private static let labeledRefillsPattern = try! NSRegularExpression(
        pattern: #"\b(?:refills?|rfl?s?)\s*(?:left|remaining|authorized)?\s*[:.]?\s*(\d+(?![/\-.\d])|no|none|zero)\b"#,
        options: [.caseInsensitive]
    )
    /// "2 refills", "No refills".
    private static let trailingRefillsPattern = try! NSRegularExpression(
        pattern: #"\b(no|\d+)\s+refills?\b"#,
        options: [.caseInsensitive]
    )

    private static func first(_ regex: NSRegularExpression, in text: String) -> String {
        guard let match = regex.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)) else { return "" }
        return (text as NSString).substring(with: match.range(at: 1))
    }

    private static func quantity(in text: String) -> String {
        guard let match = quantityPattern.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)) else { return "" }
        let ns = text as NSString
        let amount = ns.substring(with: match.range(at: 1))
        guard match.range(at: 2).location != NSNotFound else { return amount }
        let unit = ns.substring(with: match.range(at: 2)).lowercased()
        return amount + (unit == "ml" ? " mL" : " " + unit)
    }

    private static func refills(in text: String) -> String {
        var value = first(labeledRefillsPattern, in: text)
        if value.isEmpty { value = first(trailingRefillsPattern, in: text) }
        guard !value.isEmpty else { return "" }
        return Int(value).map(String.init) ?? "0"
    }

    // MARK: - Matching what's already in the app

    /// The saved pharmacy this label came from: the same chain or name, preferring the person's own.
    static func matchPharmacy(_ parsed: String, existing: [String], preferred: [String] = []) -> String? {
        guard !parsed.isBlank else { return nil }
        let key = pharmacyKey(parsed)
        let matches = existing.filter { pharmacyKey($0) == key || $0.localizedCaseInsensitiveContains(parsed) }
        return matches.first(where: { preferred.contains($0) }) ?? matches.first
    }

    private static func pharmacyKey(_ name: String) -> String {
        let range = NSRange(name.startIndex..., in: name)
        if let chain = chainPatterns.first(where: { $0.regex.firstMatch(in: name, range: range) != nil }) {
            return chain.name
        }
        return name.lowercased()
            .replacingOccurrences(of: #"\b(pharmacy|drug\s?store|drugs|the)\b|[^a-z ]"#, with: "", options: .regularExpression)
            .split(separator: " ").joined(separator: " ")
    }

    /// The saved provider who wrote this prescription: same last name, and the same first
    /// initial when both have one. Preferring the person's own providers.
    static func matchProvider(_ parsed: String, existing: [String], preferred: [String] = []) -> String? {
        let wanted = nameParts(parsed)
        guard let last = wanted.last else { return nil }
        let matches = existing.filter { name in
            let parts = nameParts(name)
            guard parts.contains(last) else { return false }
            guard wanted.count > 1, let first = wanted.first?.first,
                  parts.count > 1, let theirs = parts.first?.first else { return true }
            return first == theirs
        }
        return matches.first(where: { preferred.contains($0) }) ?? matches.first
    }

    /// Lowercased name words without titles and credentials: "Dr. Jane Smith, MD" → ["jane", "smith"].
    private static func nameParts(_ name: String) -> [String] {
        let skip: Set<String> = ["dr", "doctor", "md", "do", "np", "pa", "c", "fnp", "aprn", "dds", "dmd", "phd", "rn", "jr", "sr", "ii", "iii"]
        var text = name.lowercased()
        if let comma = text.firstIndex(of: ",") {
            let after = text[text.index(after: comma)...].trimmingCharacters(in: .whitespaces)
            let afterWords = after.split(separator: " ").map(String.init)
            // "Smith, Jane" is last-name first; "Jane Smith, MD" is a credential.
            if !afterWords.isEmpty, !afterWords.allSatisfy({ skip.contains($0.filter(\.isLetter)) }) {
                text = after + " " + text[..<comma]
            }
        }
        return text.split(whereSeparator: { !$0.isLetter && $0 != "'" && $0 != "-" })
            .map(String.init)
            .filter { !skip.contains($0) && $0.count > 1 }
    }

    /// The medication this label is a refill of: the same drug, preferring a current one.
    static func matchingMedication(named name: String, in medications: [(name: String, isActive: Bool)]) -> Int? {
        guard let word = name.lowercased().split(whereSeparator: { !$0.isLetter }).first else { return nil }
        let matches = medications.indices.filter {
            medications[$0].name.lowercased().split(whereSeparator: { !$0.isLetter }).first == word
        }
        return matches.first { medications[$0].isActive } ?? matches.first
    }
}
