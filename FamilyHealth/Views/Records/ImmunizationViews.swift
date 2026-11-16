import SwiftData
import SwiftUI

struct ImmunizationsView: View {
    let person: Person

    var body: some View {
        let sorted = person.immunizations.sorted { ($0.date ?? .distantPast) > ($1.date ?? .distantPast) }
        RecordList(
            title: "Immunizations",
            emptyTitle: "No immunizations",
            emptyMessage: "Add vaccines with the date and dose, newest first.",
            systemImage: "syringe",
            sections: [RecordSection(nil, sorted)],
            row: { shot in
                RecordRow(
                    title: shot.vaccine,
                    details: [shot.doseNumber.isBlank ? "" : "Dose \(shot.doseNumber)", shot.date?.shortDate ?? "", shot.location]
                )
            },
            editor: { ImmunizationEditView(person: person, immunization: $0) }
        )
    }
}

struct ImmunizationEditView: View {
    let person: Person
    let immunization: Immunization?

    @Environment(\.modelContext) private var modelContext
    @State private var vaccine = ""
    @State private var date: Date?
    @State private var doseNumber = ""
    @State private var location = ""
    @State private var lotNumber = ""
    @State private var notes = ""
    @State private var didLoad = false

    var body: some View {
        EditorForm(title: immunization == nil ? "New immunization" : "Edit immunization", canSave: !vaccine.isBlank, onSave: save) {
            Section {
                TextField("Vaccine (e.g. Tdap)", text: $vaccine)
                DateField(label: "Date given", date: $date)
                TextField("Dose number (e.g. 2 of 3)", text: $doseNumber)
                TextField("Where given", text: $location)
                TextField("Lot number", text: $lotNumber)
            }
            Section { NotesField(text: $notes) }
        }
        .onAppear {
            guard !didLoad else { return }
            didLoad = true
            guard let immunization else { return }
            vaccine = immunization.vaccine
            date = immunization.date
            doseNumber = immunization.doseNumber
            location = immunization.location
            lotNumber = immunization.lotNumber
            notes = immunization.notes
        }
    }

    private func save() {
        let target = immunization ?? {
            let new = Immunization(vaccine: vaccine.trimmed)
            modelContext.insert(new)
            new.person = person
            return new
        }()
        target.vaccine = vaccine.trimmed
        target.date = date
        target.doseNumber = doseNumber.trimmed
        target.location = location.trimmed
        target.lotNumber = lotNumber.trimmed
        target.notes = notes.trimmed
    }
}
