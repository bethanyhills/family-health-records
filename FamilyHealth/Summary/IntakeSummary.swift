import Foundation

struct SummaryItem: Identifiable, Equatable {
    /// Stable across re-renders: the section title plus the row's position.
    var id = ""
    let label: String
    let value: String

    init(label: String, value: String) {
        self.label = label
        self.value = value
    }
}

struct SummarySection: Identifiable, Equatable {
    var id: String { title }
    let title: String
    let items: [SummaryItem]
    /// Shown when there are no items, e.g. "None recorded".
    let emptyText: String

    init(title: String, items: [SummaryItem], emptyText: String = "None recorded") {
        self.title = title
        self.emptyText = emptyText
        self.items = items.enumerated().map { index, item in
            var item = item
            item.id = "\(title)#\(index)"
            return item
        }
    }
}

/// Everything an intake form asks about one person, in the order forms usually ask it.
enum IntakeSummary {
    static func sections(for person: Person, today: Date = .now) -> [SummarySection] {
        [
            patient(person, today: today),
            allergies(person),
            medications(person),
            conditions(person, current: true),
            conditions(person, current: false),
            therapies(person),
            procedures(person),
            immunizations(person),
            familyHistory(person),
            providers(person),
            pharmacies(person),
            insurance(person),
            emergencyContacts(person),
            school(person),
        ]
        // Hide empty sections that many people won't have.
        .filter { !$0.items.isEmpty || !["Past conditions", "Current therapies", "School"].contains($0.title) }
    }

    /// Plain text for pasting into an email or a web form's free-text box.
    static func text(for person: Person, today: Date = .now) -> String {
        var lines: [String] = []
        for section in sections(for: person, today: today) {
            lines.append(section.title.uppercased())
            if section.items.isEmpty {
                lines.append(section.emptyText)
            } else {
                for item in section.items {
                    lines.append(item.value.isEmpty ? item.label : "\(item.label): \(item.value)")
                }
            }
            lines.append("")
        }
        return lines.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
    }

    // MARK: Sections

    private static func patient(_ person: Person, today: Date) -> SummarySection {
        var items = [SummaryItem(label: "Name", value: person.displayName)]
        add(&items, "Preferred name", person.preferredName)
        if let dob = person.dateOfBirth {
            items.append(SummaryItem(label: "Date of birth", value: dob.formDate))
            items.append(SummaryItem(label: "Age", value: "\(Person.age(bornOn: dob, on: today))"))
        }
        if person.sex != .unspecified { items.append(SummaryItem(label: "Sex", value: person.sex.label)) }
        if person.bloodType != .unknown { items.append(SummaryItem(label: "Blood type", value: person.bloodType.label)) }
        add(&items, "Height", person.height)
        add(&items, "Weight", person.weight)
        return SummarySection(title: "Patient", items: items)
    }

    private static func allergies(_ person: Person) -> SummarySection {
        let items = person.allergies
            .sorted { $0.allergen.localizedCaseInsensitiveCompare($1.allergen) == .orderedAscending }
            .map { allergy in
                let severity = allergy.severity == .unknown ? "" : "\(allergy.severity.label.lowercased())"
                let reaction = [allergy.reaction, severity.isEmpty ? "" : "(\(severity))"].joined(" ")
                return SummaryItem(label: allergy.allergen, value: reaction)
            }
        return SummarySection(title: "Allergies", items: items, emptyText: "No known allergies recorded")
    }

    private static func medications(_ person: Person) -> SummarySection {
        let items = person.medications
            .filter(\.isActive)
            .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
            .map { med in
                SummaryItem(
                    label: [med.name, med.dose].joined(" "),
                    value: [med.frequency, med.reason.isBlank ? "" : "for \(med.reason)"].joined(", ")
                )
            }
        return SummarySection(title: "Current medications", items: items)
    }

    private static func conditions(_ person: Person, current: Bool) -> SummarySection {
        let items = person.conditions
            .filter { current ? $0.status != .resolved : $0.status == .resolved }
            .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
            .map { condition in
                SummaryItem(
                    label: condition.name,
                    value: condition.diagnosedDate.map { "diagnosed \($0.formDate)" } ?? ""
                )
            }
        return SummarySection(title: current ? "Medical conditions" : "Past conditions", items: items)
    }

    private static func therapies(_ person: Person) -> SummarySection {
        let items = person.therapies
            .filter(\.isActive)
            .sorted { $0.displayName.localizedCaseInsensitiveCompare($1.displayName) == .orderedAscending }
            .map { therapy in
                SummaryItem(
                    label: therapy.displayName,
                    value: [
                        therapy.provider.map { [$0.name, $0.practice, $0.phone].joined(", ") } ?? "",
                        therapy.frequency,
                        therapy.startDate.map { "since \($0.formDate)" } ?? "",
                    ].joined("; ")
                )
            }
        return SummarySection(title: "Current therapies", items: items)
    }

    private static func procedures(_ person: Person) -> SummarySection {
        let items = person.procedures
            .sorted { ($0.date ?? .distantPast) > ($1.date ?? .distantPast) }
            .map { SummaryItem(label: $0.name, value: [$0.date?.formDate ?? "", $0.facility].joined(", ")) }
        return SummarySection(title: "Surgeries & hospital stays", items: items)
    }

    private static func immunizations(_ person: Person) -> SummarySection {
        let items = person.immunizations
            .sorted { ($0.date ?? .distantPast) > ($1.date ?? .distantPast) }
            .map { shot in
                SummaryItem(
                    label: shot.vaccine,
                    value: [shot.doseNumber.isBlank ? "" : "dose \(shot.doseNumber)", shot.date?.formDate ?? ""].joined(", ")
                )
            }
        return SummarySection(title: "Immunizations", items: items)
    }

    private static func familyHistory(_ person: Person) -> SummarySection {
        let items = person.familyHistory
            .sorted { $0.condition.localizedCaseInsensitiveCompare($1.condition) == .orderedAscending }
            .map { SummaryItem(label: $0.condition, value: $0.relative) }
        return SummarySection(title: "Family history", items: items)
    }

    private static func providers(_ person: Person) -> SummarySection {
        let items = person.providers
            .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
            .map { SummaryItem(label: $0.name, value: [$0.specialty, $0.practice, $0.phone].joined(", ")) }
        return SummarySection(title: "Doctors & providers", items: items)
    }

    private static func pharmacies(_ person: Person) -> SummarySection {
        let items = person.pharmacies
            .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
            .map { SummaryItem(label: $0.name, value: [$0.address, $0.phone].joined(", ")) }
        return SummarySection(title: "Pharmacy", items: items)
    }

    private static func insurance(_ person: Person) -> SummarySection {
        var items: [SummaryItem] = []
        for policy in person.insurancePolicies.sorted(by: { $0.kind.rawValue < $1.kind.rawValue }) {
            let prefix = "\(policy.kind.label) insurance"
            items.append(SummaryItem(label: prefix, value: [policy.carrier, policy.planName].joined(", ")))
            add(&items, "Member ID", policy.memberID)
            add(&items, "Group number", policy.groupNumber)
            add(&items, "Policy holder", policy.subscriberName)
            if let dob = policy.subscriberDateOfBirth {
                items.append(SummaryItem(label: "Policy holder date of birth", value: dob.formDate))
            }
            add(&items, "Member services", policy.phone)
            add(&items, "Rx BIN", policy.rxBIN)
            add(&items, "Rx PCN", policy.rxPCN)
            add(&items, "Rx Group", policy.rxGroup)
        }
        return SummarySection(title: "Insurance", items: items)
    }

    private static func emergencyContacts(_ person: Person) -> SummarySection {
        let items = person.contacts
            .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
            .map { SummaryItem(label: $0.name, value: [$0.relationship, $0.phone].joined(", ")) }
        return SummarySection(title: "Emergency contacts", items: items)
    }

    private static func school(_ person: Person) -> SummarySection {
        var items: [SummaryItem] = []
        add(&items, "School", person.school?.name ?? "")
        add(&items, "Grade", person.schoolGrade)
        add(&items, "Teacher", [person.teacherName, person.teacherEmail, person.teacherPhone].joined(", "))
        if let school = person.school {
            add(&items, "School phone", school.phone)
            add(&items, "School address", school.address)
            add(&items, "School nurse", [school.nurseName, school.nursePhone, school.nurseEmail].joined(", "))
        }
        return SummarySection(title: "School", items: items)
    }

    private static func add(_ items: inout [SummaryItem], _ label: String, _ value: String) {
        if !value.isBlank { items.append(SummaryItem(label: label, value: value.trimmed)) }
    }
}

private extension Array where Element == String {
    /// Joins the non-empty parts.
    func joined(_ separator: String) -> String {
        filter { !$0.isBlank }.map(\.trimmed).joined(separator: separator)
    }
}
