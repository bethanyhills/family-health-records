import SwiftData
import SwiftUI

/// Emergency contacts for one family member. Contacts are shared, so swiping
/// removes them from this person only.
struct EmergencyContactsView: View {
    let person: Person

    @Environment(\.recordAccess) private var access
    @Query(sort: \EmergencyContact.name) private var allContacts: [EmergencyContact]

    var body: some View {
        let sorted = person.contacts.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
        let others = allContacts.filter { contact in
            contact.person == nil && !person.contacts.contains { $0.id == contact.id }
        }

        RecordList(
            title: "Emergency contacts",
            emptyTitle: "No emergency contacts",
            emptyMessage: "Add the people to call in an emergency. A contact for several family members only needs to be added once.",
            systemImage: "phone.badge.waveform",
            sections: [RecordSection(nil, sorted)],
            row: { contact in
                RecordRow(title: contact.name, details: [contact.relationship, contact.phone])
            },
            editor: { EmergencyContactEditView(contact: $0, defaultPerson: person) },
            onRemove: { contact in
                contact.people.removeAll { $0.id == person.id }
            }
        )
        .toolbar {
            if access.canEdit && !others.isEmpty {
                ToolbarItem(placement: .secondaryAction) {
                    Menu {
                        ForEach(others) { contact in
                            Button(contact.name) { contact.people.append(person) }
                        }
                    } label: {
                        Label("Add existing contact", systemImage: "person.crop.circle.badge.plus")
                    }
                }
            }
        }
    }
}

struct EmergencyContactEditView: View {
    let contact: EmergencyContact?
    let defaultPerson: Person?

    @Environment(\.modelContext) private var modelContext
    @Query(sort: [SortDescriptor(\Person.sortOrder), SortDescriptor(\Person.name)]) private var people: [Person]

    @State private var name = ""
    @State private var relationship = ""
    @State private var phone = ""
    @State private var notes = ""
    @State private var personIDs: Set<UUID> = []
    @State private var didLoad = false

    var body: some View {
        EditorForm(title: contact == nil ? "New contact" : "Edit contact", canSave: !name.isBlank, onSave: save) {
            Section {
                TextField("Name", text: $name)
                    .textContentType(.name)
                    .textInputAutocapitalization(.words)
                TextField("Relationship (e.g. Grandmother)", text: $relationship)
                    .textInputAutocapitalization(.words)
                TextField("Phone", text: $phone)
                    .textContentType(.telephoneNumber)
                    .keyboardType(.phonePad)
            }
            Section("Emergency contact for") {
                PeopleToggles(people: people, selection: $personIDs)
            }
            Section { NotesField(text: $notes) }
        }
        .onAppear {
            guard !didLoad else { return }
            didLoad = true
            if let contact {
                name = contact.name
                relationship = contact.relationship
                phone = contact.phone
                notes = contact.notes
                personIDs = Set(contact.people.map(\.id))
            } else if let defaultPerson {
                personIDs = [defaultPerson.id]
            }
        }
    }

    private func save() {
        let target = contact ?? {
            let new = EmergencyContact(name: name.trimmed)
            modelContext.insert(new)
            return new
        }()
        target.name = name.trimmed
        target.relationship = relationship.trimmed
        target.phone = phone.trimmed
        target.notes = notes.trimmed
        target.people = people.filter { personIDs.contains($0.id) }
    }
}

/// A toggle per family member, for records shared across the family.
struct PeopleToggles: View {
    let people: [Person]
    @Binding var selection: Set<UUID>

    var body: some View {
        ForEach(people) { person in
            Toggle(person.displayName, isOn: Binding(
                get: { selection.contains(person.id) },
                set: { isOn in
                    if isOn { selection.insert(person.id) } else { selection.remove(person.id) }
                }
            ))
        }
    }
}
