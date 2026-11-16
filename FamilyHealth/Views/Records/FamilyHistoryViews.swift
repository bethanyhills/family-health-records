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
    @Query(sort: [SortDescriptor(\Person.sortOrder), SortDescriptor(\Person.name)]) private var people: [Person]
    @State private var relative = ""
    /// Other family members to add this to. New entries start with everyone selected.
    @State private var copyTo: Set<UUID> = []
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
            if !otherPeople.isEmpty {
                Section {
                    PeopleToggles(people: otherPeople, selection: $copyTo)
                } header: {
                    Text(item == nil ? "Also add to" : "Also add a copy to")
                } footer: {
                    Text("Each person gets their own copy, so you can reword the relative for them (your mother is the kids' grandmother). Anyone who already has this entry is skipped.")
                }
            }
        }
        .onAppear {
            guard !didLoad else { return }
            didLoad = true
            guard let item else {
                copyTo = Set(otherPeople.map(\.id))
                return
            }
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
        target.copy(to: otherPeople.filter { copyTo.contains($0.id) }, in: modelContext)
    }

    private var otherPeople: [Person] {
        people.filter { $0.id != person.id }
    }
}

extension FamilyHistoryItem {
    /// Adds a separate copy of this entry to each person who doesn't already have the same
    /// condition and relative.
    func copy(to people: [Person], in context: ModelContext) {
        for other in people where !other.familyHistory.contains(where: { isSame(as: $0) }) {
            let copy = FamilyHistoryItem(relative: relative, condition: condition)
            copy.notes = notes
            context.insert(copy)
            copy.person = other
        }
    }

    private func isSame(as other: FamilyHistoryItem) -> Bool {
        condition.localizedCaseInsensitiveCompare(other.condition) == .orderedSame
            && relative.localizedCaseInsensitiveCompare(other.relative) == .orderedSame
    }
}
