import SwiftData
import SwiftUI

struct ProceduresView: View {
    let person: Person

    var body: some View {
        let sorted = person.procedures.sorted { ($0.date ?? .distantPast) > ($1.date ?? .distantPast) }
        RecordList(
            title: "Surgeries & procedures",
            emptyTitle: "No surgeries or procedures",
            emptyMessage: "Add surgeries, procedures and hospital stays, newest first.",
            systemImage: "cross.case",
            sections: [RecordSection(nil, sorted)],
            row: { procedure in
                RecordRow(
                    title: procedure.name,
                    details: [procedure.date?.shortDate ?? "", procedure.facility, procedure.surgeon]
                )
            },
            editor: { ProcedureEditView(person: person, procedure: $0) }
        )
    }
}

struct ProcedureEditView: View {
    let person: Person
    let procedure: Procedure?

    @Environment(\.modelContext) private var modelContext
    @State private var name = ""
    @State private var date: Date?
    @State private var facility = ""
    @State private var surgeon = ""
    @State private var notes = ""
    @State private var didLoad = false

    var body: some View {
        EditorForm(title: procedure == nil ? "New procedure" : "Edit procedure", canSave: !name.isBlank, onSave: save) {
            Section {
                TextField("Surgery or procedure (e.g. Tonsillectomy)", text: $name)
                DateField(label: "Date", date: $date)
                TextField("Hospital or facility", text: $facility)
                TextField("Surgeon or doctor", text: $surgeon)
            }
            Section { NotesField(text: $notes) }
        }
        .onAppear {
            guard !didLoad else { return }
            didLoad = true
            guard let procedure else { return }
            name = procedure.name
            date = procedure.date
            facility = procedure.facility
            surgeon = procedure.surgeon
            notes = procedure.notes
        }
    }

    private func save() {
        let target = procedure ?? {
            let new = Procedure(name: name.trimmed)
            modelContext.insert(new)
            new.person = person
            return new
        }()
        target.name = name.trimmed
        target.date = date
        target.facility = facility.trimmed
        target.surgeon = surgeon.trimmed
        target.notes = notes.trimmed
    }
}
