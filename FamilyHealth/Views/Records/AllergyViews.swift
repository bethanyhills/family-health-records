import SwiftData
import SwiftUI

struct AllergiesView: View {
    let person: Person

    var body: some View {
        let sorted = person.allergies.sorted { $0.allergen.localizedCaseInsensitiveCompare($1.allergen) == .orderedAscending }
        RecordList(
            title: "Allergies",
            emptyTitle: "No allergies",
            emptyMessage: "Add medication, food and environmental allergies, with the reaction.",
            systemImage: "allergens",
            sections: [RecordSection(nil, sorted)],
            row: { allergy in
                RecordRow(
                    title: allergy.allergen,
                    details: [allergy.kind.label, allergy.reaction],
                    badge: allergy.severity == .unknown ? nil : allergy.severity.label,
                    badgeColor: allergy.severity.color
                )
            },
            editor: { AllergyEditView(person: person, allergy: $0) }
        )
    }
}

extension AllergySeverity {
    var color: Color {
        switch self {
        case .severe: .red
        case .moderate: .orange
        case .mild: .yellow
        case .unknown: .secondary
        }
    }
}

struct AllergyEditView: View {
    let person: Person
    let allergy: Allergy?

    @Environment(\.modelContext) private var modelContext
    @State private var allergen = ""
    @State private var kind = AllergyKind.medication
    @State private var reaction = ""
    @State private var severity = AllergySeverity.unknown
    @State private var notes = ""
    @State private var didLoad = false

    var body: some View {
        EditorForm(title: allergy == nil ? "New allergy" : "Edit allergy", canSave: !allergen.isBlank, onSave: save) {
            Section {
                TextField("Allergic to (e.g. Penicillin)", text: $allergen)
                Picker("Type", selection: $kind) {
                    ForEach(AllergyKind.allCases) { Text($0.label).tag($0) }
                }
                TextField("Reaction (e.g. hives)", text: $reaction)
                Picker("Severity", selection: $severity) {
                    ForEach(AllergySeverity.allCases) { Text($0.label).tag($0) }
                }
            }
            Section { NotesField(text: $notes) }
        }
        .onAppear {
            guard !didLoad else { return }
            didLoad = true
            guard let allergy else { return }
            allergen = allergy.allergen
            kind = allergy.kind
            reaction = allergy.reaction
            severity = allergy.severity
            notes = allergy.notes
        }
    }

    private func save() {
        let target = allergy ?? {
            let new = Allergy(allergen: allergen.trimmed)
            modelContext.insert(new)
            new.person = person
            return new
        }()
        target.allergen = allergen.trimmed
        target.kind = kind
        target.reaction = reaction.trimmed
        target.severity = severity
        target.notes = notes.trimmed
    }
}
