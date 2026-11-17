import SwiftData
import SwiftUI

struct ConditionsView: View {
    let person: Person

    var body: some View {
        let sorted = person.conditions.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
        RecordList(
            title: "Conditions",
            emptyTitle: "No conditions",
            emptyMessage: "Add diagnoses such as asthma, ADHD or high blood pressure.",
            systemImage: "stethoscope",
            sections: [
                RecordSection("Current", sorted.filter { $0.status != .resolved }),
                RecordSection("Resolved", sorted.filter { $0.status == .resolved }),
            ],
            row: { condition in
                RecordRow(
                    title: condition.name,
                    details: [
                        condition.diagnosedDate.map { "Diagnosed \($0.shortDate)" } ?? "",
                        condition.treatingProvider,
                    ],
                    badge: condition.status == .managed ? condition.status.label : nil
                )
            },
            editor: { ConditionEditView(person: person, condition: $0) }
        )
    }
}

struct ConditionEditView: View {
    let person: Person
    let condition: Condition?

    @Environment(\.modelContext) private var modelContext
    @Query(sort: [SortDescriptor(\Person.sortOrder), SortDescriptor(\Person.name)]) private var people: [Person]
    @State private var name = ""
    /// Other family members who have this condition too.
    @State private var copyTo: Set<UUID> = []
    @State private var status = ConditionStatus.active
    @State private var diagnosedDate: Date?
    @State private var treatingProvider = ""
    @State private var notes = ""
    @State private var didLoad = false

    var body: some View {
        EditorForm(title: condition == nil ? "New condition" : "Edit condition", canSave: !name.isBlank, onSave: save) {
            Section {
                TextField("Condition (e.g. Asthma)", text: $name)
                Picker("Status", selection: $status) {
                    ForEach(ConditionStatus.allCases) { Text($0.label).tag($0) }
                }
                DateField(label: "Date diagnosed", date: $diagnosedDate)
                TextField("Treated by", text: $treatingProvider)
            }
            Section { NotesField(text: $notes) }
            if !otherPeople.isEmpty {
                Section {
                    PeopleToggles(people: otherPeople, selection: $copyTo)
                } header: {
                    Text("Also add to")
                } footer: {
                    Text("Each person gets their own copy, without the diagnosis date, so you can add their details. Anyone who already has this condition is skipped.")
                }
            }
        }
        .onAppear {
            guard !didLoad else { return }
            didLoad = true
            guard let condition else { return }
            name = condition.name
            status = condition.status
            diagnosedDate = condition.diagnosedDate
            treatingProvider = condition.treatingProvider
            notes = condition.notes
        }
    }

    private func save() {
        let target = condition ?? {
            let new = Condition(name: name.trimmed)
            modelContext.insert(new)
            new.person = person
            return new
        }()
        target.name = name.trimmed
        target.status = status
        target.diagnosedDate = diagnosedDate
        target.treatingProvider = treatingProvider.trimmed
        target.notes = notes.trimmed
        target.copy(to: otherPeople.filter { copyTo.contains($0.id) }, in: modelContext)
    }

    private var otherPeople: [Person] {
        people.filter { $0.id != person.id }
    }
}

extension Condition {
    /// Adds this condition to each person who doesn't already have one with the same name.
    /// The diagnosis date is left for that person's own details.
    func copy(to people: [Person], in context: ModelContext) {
        for other in people where !other.conditions.contains(where: {
            $0.name.localizedCaseInsensitiveCompare(name) == .orderedSame
        }) {
            let copy = Condition(name: name, status: status)
            copy.treatingProvider = treatingProvider
            copy.notes = notes
            context.insert(copy)
            copy.person = other
        }
    }
}
