import SwiftData
import SwiftUI

struct FamilyHistoryView: View {
    let person: Person

    var body: some View {
        let sorted = person.familyHistory.sorted { $0.condition.localizedCaseInsensitiveCompare($1.condition) == .orderedAscending }
        RecordList(
            title: "Family history",
            emptyTitle: "No family history",
            emptyMessage: "For the \"does anyone in your family have...\" questions: add a relative and their condition.",
            systemImage: "person.3",
            sections: [RecordSection(nil, sorted)],
            row: { item in
                RecordRow(title: item.condition, details: [item.relative])
            },
            editor: { FamilyHistoryEditView(person: person, item: $0) }
        )
    }
}

struct FamilyHistoryEditView: View {
    let person: Person
    let item: FamilyHistoryItem?

    @Environment(\.modelContext) private var modelContext
    @State private var relative = ""
    @State private var condition = ""
    @State private var notes = ""
    @State private var didLoad = false

    var body: some View {
        EditorForm(title: item == nil ? "New family history" : "Edit family history", canSave: !condition.isBlank, onSave: save) {
            Section {
                TextField("Condition (e.g. Type 2 diabetes)", text: $condition)
                TextField("Relative (e.g. Maternal grandmother)", text: $relative)
                    .textInputAutocapitalization(.sentences)
            }
            Section { NotesField(text: $notes) }
        }
        .onAppear {
            guard !didLoad else { return }
            didLoad = true
            guard let item else { return }
            relative = item.relative
            condition = item.condition
            notes = item.notes
        }
    }

    private func save() {
        let target = item ?? {
            let new = FamilyHistoryItem(relative: relative.trimmed, condition: condition.trimmed)
            modelContext.insert(new)
            new.person = person
            return new
        }()
        target.relative = relative.trimmed
        target.condition = condition.trimmed
        target.notes = notes.trimmed
    }
}
