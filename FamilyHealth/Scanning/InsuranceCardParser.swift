import Foundation

/// Pulls the usual fields off the text of an insurance card. Anything it isn't
/// sure about is left empty for the person to fill in.
enum InsuranceCardParser {
    struct Result: Equatable {
        var carrier = ""
        var planName = ""
        var memberID = ""
        var groupNumber = ""
        var subscriberName = ""
        var phone = ""
        var rxBIN = ""
        var rxPCN = ""
        var rxGroup = ""

        var filledCount: Int {
            [carrier, planName, memberID, groupNumber, subscriberName, phone, rxBIN, rxPCN, rxGroup]
                .filter { !$0.isEmpty }.count
        }
    }

    /// Display names for carriers, keyed by words that appear on their cards.
    static let carriers: [(match: String, name: String)] = [
        ("unitedhealthcare", "UnitedHealthcare"), ("united healthcare", "UnitedHealthcare"),
        ("blue cross", "Blue Cross Blue Shield"), ("bluecross", "Blue Cross Blue Shield"),
        ("blue shield", "Blue Cross Blue Shield"), ("bcbs", "Blue Cross Blue Shield"),
        ("anthem", "Anthem"), ("aetna", "Aetna"), ("cigna", "Cigna"), ("humana", "Humana"),
        ("kaiser", "Kaiser Permanente"), ("ambetter", "Ambetter"), ("oscar", "Oscar Health"),
        ("molina", "Molina Healthcare"), ("centene", "Centene"), ("wellcare", "WellCare"),
        ("highmark", "Highmark"), ("harvard pilgrim", "Harvard Pilgrim"), ("tricare", "TRICARE"),
        ("medicaid", "Medicaid"), ("medicare", "Medicare"), ("delta dental", "Delta Dental"),
        ("metlife", "MetLife"), ("guardian", "Guardian"), ("vsp", "VSP Vision Care"),
        ("eyemed", "EyeMed"), ("express scripts", "Express Scripts"), ("caremark", "CVS Caremark"),
        ("optumrx", "OptumRx"), ("health alliance", "Health Alliance"),
    ]

    static func parse(_ lines: [String]) -> Result {
        var result = Result()
        let cleaned = lines.map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }

        for (index, line) in cleaned.enumerated() {
            let next = index + 1 < cleaned.count ? cleaned[index + 1] : nil
            let lower = line.lowercased()

            if result.carrier.isEmpty,
               let carrier = carriers.first(where: { lower.contains($0.match) }) {
                result.carrier = carrier.name
            }
            if result.rxBIN.isEmpty, let value = value(in: line, next: next, label: #"(?:rx\s*)?bin"#, pattern: #"\d{6}"#) {
                result.rxBIN = value
            }
            if result.rxPCN.isEmpty, let value = value(in: line, next: next, label: #"(?:rx\s*)?pcn"#, pattern: #"[A-Z0-9]{2,10}"#) {
                result.rxPCN = value
            }
            if result.rxGroup.isEmpty, let value = value(in: line, next: next, label: #"rx\s*(?:grp|group)"#, pattern: #"[A-Z0-9\-]{2,15}"#) {
                result.rxGroup = value
            }
            if result.groupNumber.isEmpty, !lower.contains("rx"),
               let value = value(in: line, next: next, label: #"(?:group|grp)(?:\s*(?:no\.?|number|#|id))?"#, pattern: #"[A-Z0-9\-]{3,20}"#) {
                result.groupNumber = value
            }
            if result.memberID.isEmpty, !lower.contains("group"), !lower.contains("grp"), !lower.contains("rx"),
               let value = value(
                   in: line, next: next,
                   label: #"(?:member|subscriber|identification|ident)\s*(?:id|#|no\.?|number)?|\bid(?:\s*(?:no\.?|number|#))?"#,
                   pattern: #"[A-Z]{0,4}\d[A-Z0-9\-]{4,20}"#
               ) {
                result.memberID = value
            }
            if result.subscriberName.isEmpty,
               let value = value(in: line, next: next, label: #"subscriber(?:\s*name)?|policy\s*holder(?:\s*name)?"#,
                                 pattern: #"[A-Za-z][A-Za-z.'\- ]{2,40}"#, isValid: { $0.trimmed.contains(" ") }) {
                result.subscriberName = value.capitalized
            }
            if result.planName.isEmpty,
               let value = value(in: line, next: next, label: #"plan(?:\s*name)?"#, pattern: #"[A-Za-z0-9][A-Za-z0-9 .+\-]{2,40}"#) {
                result.planName = value
            }
        }

        result.phone = phone(in: cleaned)
        return result
    }

    /// Finds `LABEL: VALUE` on one line, or a label alone on a line with the value on the next.
    private static func value(
        in line: String,
        next: String?,
        label: String,
        pattern: String,
        isValid: (String) -> Bool = { _ in true }
    ) -> String? {
        let sameLine = #"(?i)(?:^|[^A-Za-z])(?:"# + label + #")\s*[:#.]?\s*("# + pattern + #")"#
        if let match = firstGroup(sameLine, in: line)?.trimmed, isValid(match) { return match }

        let labelOnly = #"(?i)^\s*(?:"# + label + #")\s*[:#.]?\s*$"#
        if firstMatch(labelOnly, in: line), let next {
            let whole = #"(?i)^\s*("# + pattern + #")\s*$"#
            if let match = firstGroup(whole, in: next)?.trimmed, isValid(match) { return match }
        }
        return nil
    }

    /// Prefers a number on a "member services" / "customer service" line.
    private static func phone(in lines: [String]) -> String {
        let pattern = #"(?:1[\s.\-]?)?\(?\d{3}\)?[\s.\-]?\d{3}[\s.\-]?\d{4}"#
        let preferred = lines.first { line in
            let lower = line.lowercased()
            return (lower.contains("member") || lower.contains("customer") || lower.contains("service"))
                && firstMatch(pattern, in: line)
        }
        guard let line = preferred ?? lines.first(where: { firstMatch(pattern, in: $0) }) else { return "" }
        return firstGroup("(" + pattern + ")", in: line) ?? ""
    }

    private static func firstMatch(_ pattern: String, in text: String) -> Bool {
        text.range(of: pattern, options: .regularExpression) != nil
    }

    private static func firstGroup(_ pattern: String, in text: String) -> String? {
        guard let regex = try? NSRegularExpression(pattern: pattern),
              let match = regex.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)),
              match.numberOfRanges > 1,
              let range = Range(match.range(at: 1), in: text)
        else { return nil }
        return String(text[range])
    }
}
