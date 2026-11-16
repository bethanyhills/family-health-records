import Foundation

/// Pulls a provider's details off the text of a business card.
enum BusinessCardParser {
    struct Result: Equatable {
        var name = ""
        var specialty = ""
        var practice = ""
        var phone = ""
        var fax = ""
        var address = ""
        var website = ""
        var email = ""

        var filledCount: Int {
            [name, specialty, practice, phone, fax, address, website, email].filter { !$0.isEmpty }.count
        }
    }

    /// Credentials that mark the line with the person's name, and the specialty they imply.
    static let credentials: [(code: String, specialty: String)] = [
        ("OTR/L", "Occupational therapy"), ("COTA/L", "Occupational therapy"), ("COTA", "Occupational therapy"),
        ("OTD", "Occupational therapy"), ("OT", "Occupational therapy"),
        ("DPT", "Physical therapy"), ("PTA", "Physical therapy"), ("PT", "Physical therapy"),
        ("CCC-SLP", "Speech therapy"), ("SLP", "Speech therapy"),
        ("BCBA-D", "Behavior therapy"), ("BCBA", "Behavior therapy"),
        ("PsyD", "Psychology"), ("LCSW", "Counseling"), ("LCPC", "Counseling"), ("LPC", "Counseling"),
        ("LMFT", "Counseling"), ("DDS", "Dentistry"), ("DMD", "Dentistry"), ("OD", "Optometry"),
        ("PA-C", "Physician assistant"), ("FNP-C", "Nurse practitioner"), ("CPNP", "Pediatric nurse practitioner"),
        ("APRN", "Nurse practitioner"), ("NP", "Nurse practitioner"), ("RD", "Nutrition"),
        ("MD", ""), ("DO", ""), ("PhD", ""), ("RN", ""), ("IBCLC", "Lactation"),
    ]

    static let titleWords = [
        "therapist", "pathologist", "pediatrician", "physician", "psychologist", "psychiatrist",
        "counselor", "dentist", "orthodontist", "optometrist", "audiologist", "dietitian", "nurse",
        "surgeon", "specialist", "analyst", "doctor of",
    ]

    static let practiceWords = [
        "therapy", "therapies", "clinic", "center", "centre", "pediatrics", "health", "associates",
        "group", "medical", "hospital", "dental", "llc", "inc", "pllc", "practice", "rehab",
        "wellness", "partners", "care", "institute", "orthodontics", "family",
    ]

    static func parse(_ lines: [String]) -> Result {
        var result = Result()
        let cleaned = lines.map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
        let text = cleaned.joined(separator: "\n")
        var used = Set<Int>()

        // Phones, fax, links, emails and the address, found by Apple's data detectors.
        let types: NSTextCheckingResult.CheckingType = [.phoneNumber, .link, .address]
        if let detector = try? NSDataDetector(types: types.rawValue) {
            for match in detector.matches(in: text, range: NSRange(text.startIndex..., in: text)) {
                guard let range = Range(match.range, in: text) else { continue }
                let lineIndex = text[..<range.lowerBound].filter { $0 == "\n" }.count
                let line = cleaned[min(lineIndex, cleaned.count - 1)].lowercased()
                switch match.resultType {
                case .phoneNumber:
                    let number = match.phoneNumber ?? String(text[range])
                    let isFax = line.contains("fax") || line.hasPrefix("f:") || line.hasPrefix("f ")
                    if isFax, result.fax.isEmpty {
                        result.fax = number
                    } else if !isFax, result.phone.isEmpty {
                        result.phone = number
                    }
                    used.insert(lineIndex)
                case .link:
                    if let url = match.url, url.scheme == "mailto" {
                        if result.email.isEmpty { result.email = url.absoluteString.replacingOccurrences(of: "mailto:", with: "") }
                    } else if result.website.isEmpty {
                        result.website = String(text[range])
                    }
                    used.insert(lineIndex)
                case .address:
                    if result.address.isEmpty {
                        let lineCount = text[range].filter { $0 == "\n" }.count
                        result.address = text[range].split(separator: "\n").joined(separator: ", ")
                        for index in lineIndex...(lineIndex + lineCount) { used.insert(index) }
                    }
                default:
                    break
                }
            }
        }

        // The name: a line ending in a credential, or starting with "Dr.".
        for (index, line) in cleaned.enumerated() where !used.contains(index) {
            if let credential = credential(in: line) {
                result.name = line
                if !credential.specialty.isEmpty { result.specialty = credential.specialty }
                used.insert(index)
                break
            }
            if line.lowercased().hasPrefix("dr.") || line.lowercased().hasPrefix("dr ") {
                result.name = line
                used.insert(index)
                break
            }
        }

        // A job title line, like "Pediatric Occupational Therapist", is the best specialty.
        for (index, line) in cleaned.enumerated() where !used.contains(index) {
            let lower = line.lowercased()
            if titleWords.contains(where: { lower.contains($0) }) && !lower.contains("@") {
                result.specialty = line
                used.insert(index)
                break
            }
        }

        for (index, line) in cleaned.enumerated() where !used.contains(index) {
            let lower = line.lowercased()
            let words = Set(lower.split(whereSeparator: { !$0.isLetter }).map(String.init))
            if practiceWords.contains(where: { words.contains($0) }) {
                result.practice = line
                used.insert(index)
                break
            }
        }

        // No credential found: the first line that looks like a person's name.
        if result.name.isEmpty {
            for (index, line) in cleaned.enumerated() where !used.contains(index) && looksLikeName(line) {
                result.name = line
                break
            }
        }
        return result
    }

    private static func credential(in line: String) -> (code: String, specialty: String)? {
        let tokens = line
            .split(whereSeparator: { $0 == "," || $0 == " " })
            .map { $0.trimmingCharacters(in: CharacterSet(charactersIn: ".")) }
        guard tokens.count >= 2, !line.contains("@"), !line.contains(where: \.isNumber) else { return nil }
        // Only credentials after the name, e.g. "Jane Smith, MS, OTR/L".
        for token in tokens.dropFirst() {
            if let match = credentials.first(where: { $0.code.caseInsensitiveCompare(token) == .orderedSame }),
               token == token.uppercased() || match.code.contains(where: \.isLowercase) {
                return match
            }
        }
        return nil
    }

    private static func looksLikeName(_ line: String) -> Bool {
        let words = line.split(separator: " ")
        guard (2...4).contains(words.count), !line.contains(where: \.isNumber), !line.contains("@") else { return false }
        return words.allSatisfy { $0.first?.isUppercase == true }
    }
}
