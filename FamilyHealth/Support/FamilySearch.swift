import Foundation

/// Searches every family member's records on the phone: names, medications, allergies,
/// conditions, therapies, procedures, vaccines, family history, the care team, visit notes,
/// and the text of documents.
enum FamilySearch {
    enum Area: String, CaseIterable {
        case person, medication, allergy, condition, therapy, procedure, immunization, familyHistory
        case visit, document, provider, pharmacy, insurance, contact, school

        var label: String {
            switch self {
            case .person: "Family member"
            case .medication: "Medication"
            case .allergy: "Allergy"
            case .condition: "Condition"
            case .therapy: "Therapy"
            case .procedure: "Surgery or procedure"
            case .immunization: "Immunization"
            case .familyHistory: "Family history"
            case .visit: "Visit note"
            case .document: "Document"
            case .provider: "Provider"
            case .pharmacy: "Pharmacy"
            case .insurance: "Insurance"
            case .contact: "Emergency contact"
            case .school: "School"
            }
        }
    }

    struct Hit: Identifiable {
        let id: String
        let person: Person
        let area: Area
        let title: String
        let detail: String
        var document: HealthDocument?
    }

    static func hits(for query: String, in people: [Person]) -> [Hit] {
        let terms = query.lowercased().split(whereSeparator: \.isWhitespace).map(String.init)
        guard !terms.isEmpty else { return [] }
        /// Every word typed appears somewhere in the fields.
        func matches(_ fields: [String]) -> Bool {
            let haystack = fields.joined(separator: " ").lowercased()
            return terms.allSatisfy { haystack.contains($0) }
        }
        var hits: [Hit] = []
        var seenShared = Set<String>()
        func add(_ person: Person, _ area: Area, _ key: String, _ title: String, _ detail: String,
                 document: HealthDocument? = nil) {
            hits.append(Hit(id: "\(area.rawValue)-\(key)-\(person.id)", person: person, area: area,
                            title: title, detail: detail, document: document))
        }
        /// Shared records (a provider, a plan) appear once, under the first person who has them.
        func addShared(_ person: Person, _ area: Area, _ key: String, _ title: String, _ detail: String) {
            guard seenShared.insert("\(area.rawValue)-\(key)").inserted else { return }
            add(person, area, key, title, detail)
        }

        for person in people {
            if matches([person.name, person.preferredName, person.communicationNeeds, person.notes]) {
                add(person, .person, "", person.displayName, person.communicationNeeds)
            }
            for item in person.medications where matches([item.name, item.reason, item.prescriber, item.notes]) {
                add(person, .medication, item.id.uuidString, [item.name, item.dose].joinedNonEmpty(" "),
                    [item.isActive ? "" : "past", item.reason].joinedNonEmpty(", "))
            }
            for item in person.allergies where matches([item.allergen, item.reaction, item.notes]) {
                add(person, .allergy, item.id.uuidString, item.allergen, item.reaction)
            }
            for item in person.conditions where matches([item.name, item.treatingProvider, item.notes]) {
                add(person, .condition, item.id.uuidString, item.name, item.status.label)
            }
            for item in person.therapies where matches([item.displayName, item.provider?.name ?? "", item.goals, item.notes]) {
                add(person, .therapy, item.id.uuidString, item.displayName, item.provider?.name ?? "")
            }
            for item in person.procedures where matches([item.name, item.facility, item.surgeon, item.notes]) {
                add(person, .procedure, item.id.uuidString, item.name, item.date?.formDate ?? "")
            }
            for item in person.immunizations where matches([item.vaccine, item.location, item.notes]) {
                add(person, .immunization, item.id.uuidString, item.vaccine, item.date?.formDate ?? "")
            }
            for item in person.familyHistory where matches([item.condition, item.relative, item.notes]) {
                add(person, .familyHistory, item.id.uuidString, item.condition, item.relative)
            }
            for item in person.visits where matches([item.reason, item.notes, item.followUp, item.provider?.name ?? ""]) {
                add(person, .visit, item.id.uuidString,
                    [item.date?.formDate ?? "", item.provider?.name ?? ""].joinedNonEmpty(" · ").nonEmpty ?? "Visit",
                    snippet(of: [item.reason, item.notes, item.followUp].joinedNonEmpty(". "), around: terms))
            }
            for item in person.documents where matches([item.title, item.kind.label, item.notes, item.recognizedText]) {
                add(person, .document, item.id.uuidString, item.displayTitle,
                    snippet(of: [item.notes, item.recognizedText].joinedNonEmpty(" "), around: terms),
                    document: item)
            }
            for item in person.providers where matches([item.name, item.specialty, item.practice, item.notes]) {
                addShared(person, .provider, item.id.uuidString, item.name, [item.specialty, item.practice].joinedNonEmpty(", "))
            }
            for item in person.pharmacies where matches([item.name, item.address]) {
                addShared(person, .pharmacy, item.id.uuidString, item.name, item.address)
            }
            for item in person.insurancePolicies where matches([item.carrier, item.planName, item.memberID, item.notes]) {
                addShared(person, .insurance, item.id.uuidString, item.carrier, item.kind.label)
            }
            for item in person.contacts where matches([item.name, item.relationship, item.notes]) {
                addShared(person, .contact, item.id.uuidString, item.name, item.relationship)
            }
            if let school = person.school,
               matches([school.name, school.nurseName, person.teacherName, person.schoolGrade]) {
                add(person, .school, school.id.uuidString, school.name,
                    [person.schoolGrade, person.teacherName].joinedNonEmpty(", "))
            }
        }
        return hits
    }

    /// About a line of text around the first word found, for document and note results.
    static func snippet(of text: String, around terms: [String], radius: Int = 50) -> String {
        let flat = text.split(whereSeparator: \.isNewline).joined(separator: " ")
        guard let term = terms.first,
              let range = flat.range(of: term, options: .caseInsensitive)
        else { return String(flat.prefix(radius * 2)) }
        let start = flat.index(range.lowerBound, offsetBy: -radius, limitedBy: flat.startIndex) ?? flat.startIndex
        let end = flat.index(range.upperBound, offsetBy: radius, limitedBy: flat.endIndex) ?? flat.endIndex
        return (start > flat.startIndex ? "…" : "") + flat[start..<end].trimmingCharacters(in: .whitespaces)
            + (end < flat.endIndex ? "…" : "")
    }
}

private extension Array where Element == String {
    func joinedNonEmpty(_ separator: String) -> String {
        map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty }.joined(separator: separator)
    }
}

private extension String {
    var nonEmpty: String? { isEmpty ? nil : self }
}
