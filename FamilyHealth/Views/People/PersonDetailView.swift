import SwiftData
import SwiftUI

struct PersonDetailView: View {
    @Bindable var person: Person
    @Environment(\.modelContext) private var modelContext
    @Environment(\.recordAccess) private var access

    @State private var isEditing = false
    @State private var isAddingContact = false
    @State private var contactToEdit: EmergencyContact?

    var body: some View {
        List {
            header

            Section("Basics") {
                InfoRow("Date of birth", person.dateOfBirth?.formDate ?? "")
                InfoRow("Sex", person.sex == .unspecified ? "" : person.sex.label)
                InfoRow("Blood type", person.bloodType == .unknown ? "" : person.bloodType.label)
                InfoRow("Height", person.height)
                InfoRow("Weight", person.weight)
                InfoRow("Preferred pharmacy", person.preferredPharmacy)
                if hasNoBasics {
                    Text("No details yet. Tap Edit to add date of birth, blood type and more.")
                        .foregroundStyle(.secondary)
                }
            }

            Section {
                ForEach(sortedContacts) { contact in
                    Button {
                        if access.canEdit { contactToEdit = contact }
                    } label: {
                        EmergencyContactRow(contact: contact)
                    }
                    .foregroundStyle(.primary)
                }
                .onDelete { offsets in
                    let contacts = sortedContacts
                    for index in offsets { modelContext.delete(contacts[index]) }
                }
                .deleteDisabled(!access.canEdit)

                if access.canEdit {
                    Button {
                        isAddingContact = true
                    } label: {
                        Label("Add emergency contact", systemImage: "plus.circle")
                    }
                }
            } header: {
                Text("Emergency contacts")
            }

            if !person.notes.isBlank {
                Section("Notes") {
                    Text(person.notes)
                        .textSelection(.enabled)
                }
            }
        }
        .navigationTitle(person.displayName)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            if access.canEdit {
                Button("Edit") { isEditing = true }
            }
        }
        .sheet(isPresented: $isEditing) {
            NavigationStack { PersonEditView(person: person) }
        }
        .sheet(isPresented: $isAddingContact) {
            NavigationStack { EmergencyContactEditView(person: person, contact: nil) }
        }
        .sheet(item: $contactToEdit) { contact in
            NavigationStack { EmergencyContactEditView(person: person, contact: contact) }
        }
    }

    private var header: some View {
        Section {
            HStack(spacing: 16) {
                AvatarView(photoData: person.photoData, initials: person.initials, size: 72)
                VStack(alignment: .leading, spacing: 4) {
                    Text(person.displayName)
                        .font(.title2.bold())
                    if !person.preferredName.isBlank {
                        Text("Goes by \(person.preferredName)")
                            .foregroundStyle(.secondary)
                    }
                    if let age = person.age {
                        Text("Age \(age)")
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .padding(.vertical, 4)
        }
    }

    private var sortedContacts: [EmergencyContact] {
        person.emergencyContacts.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    private var hasNoBasics: Bool {
        person.dateOfBirth == nil && person.sex == .unspecified && person.bloodType == .unknown
            && person.height.isBlank && person.weight.isBlank && person.preferredPharmacy.isBlank
    }
}

struct EmergencyContactRow: View {
    let contact: EmergencyContact

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(contact.name)
                .font(.body.weight(.medium))
            Text([contact.relationship, contact.phone].filter { !$0.isBlank }.joined(separator: " · "))
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .contextMenu {
            if !contact.phone.isBlank {
                Button {
                    UIPasteboard.general.string = contact.phone
                } label: {
                    Label("Copy phone number", systemImage: "doc.on.doc")
                }
            }
        }
    }
}
