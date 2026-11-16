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

            Section {
                NavigationLink {
                    IntakeSummaryView(person: person)
                } label: {
                    Label {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Intake summary")
                                .font(.headline)
                            Text("Everything a new doctor's form asks, ready to copy or share as a PDF")
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                        }
                    } icon: {
                        Image(systemName: "list.clipboard.fill")
                            .foregroundStyle(.tint)
                    }
                    .padding(.vertical, 4)
                }
            }

            Section("Health records") {
                RecordLink("Medications", systemImage: "pills.fill", color: .blue, count: person.medications.filter(\.isActive).count) {
                    MedicationsView(person: person)
                }
                RecordLink("Allergies", systemImage: "allergens.fill", color: .red, count: person.allergies.count) {
                    AllergiesView(person: person)
                }
                RecordLink("Conditions", systemImage: "stethoscope", color: .purple, count: person.conditions.filter { $0.status != .resolved }.count) {
                    ConditionsView(person: person)
                }
                RecordLink("Surgeries & procedures", systemImage: "cross.case.fill", color: .orange, count: person.procedures.count) {
                    ProceduresView(person: person)
                }
                RecordLink("Immunizations", systemImage: "syringe.fill", color: .teal, count: person.immunizations.count) {
                    ImmunizationsView(person: person)
                }
                RecordLink("Family history", systemImage: "person.3.fill", color: .brown, count: person.familyHistory.count) {
                    FamilyHistoryView(person: person)
                }
            }

            Section("Care team") {
                RecordLink("Providers", systemImage: "person.badge.shield.checkmark.fill", color: .green, count: person.providers.count) {
                    ProvidersView(person: person)
                }
                RecordLink("Insurance", systemImage: "creditcard.fill", color: .indigo, count: person.insurancePolicies.count) {
                    InsuranceView(person: person)
                }
            }

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

/// A row linking to one kind of record, with a colored icon and a count.
struct RecordLink<Destination: View>: View {
    let title: String
    let systemImage: String
    let color: Color
    let count: Int
    @ViewBuilder let destination: () -> Destination

    init(
        _ title: String,
        systemImage: String,
        color: Color,
        count: Int,
        @ViewBuilder destination: @escaping () -> Destination
    ) {
        self.title = title
        self.systemImage = systemImage
        self.color = color
        self.count = count
        self.destination = destination
    }

    var body: some View {
        NavigationLink {
            destination()
        } label: {
            HStack(spacing: 12) {
                Image(systemName: systemImage)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.white)
                    .frame(width: 30, height: 30)
                    .background(color.gradient, in: RoundedRectangle(cornerRadius: 7))
                Text(title)
                Spacer()
                if count > 0 {
                    Text("\(count)")
                        .foregroundStyle(.secondary)
                }
            }
        }
    }
}
