import SwiftData
import SwiftUI

/// The providers who see one family member. A provider can be shared, so
/// swiping removes them from this person only.
struct ProvidersView: View {
    let person: Person

    @Environment(\.recordAccess) private var access
    @Query(sort: \Provider.name) private var allProviders: [Provider]
    @State private var isAddingNew = false

    var body: some View {
        let sorted = person.providers.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
        let others = allProviders.filter { provider in !person.providers.contains { $0.id == provider.id } }

        RecordList(
            title: "Providers",
            emptyTitle: "No providers",
            emptyMessage: "Add doctors, therapists, dentists and clinics. A provider who sees several family members only needs to be added once.",
            systemImage: "person.badge.shield.checkmark",
            sections: [RecordSection(nil, sorted)],
            row: { ProviderRow(provider: $0) },
            editor: { ProviderEditView(provider: $0, defaultPatient: person) },
            onRemove: { provider in
                provider.patients.removeAll { $0.id == person.id }
            }
        )
        .toolbar {
            if access.canEdit && !others.isEmpty {
                ToolbarItem(placement: .secondaryAction) {
                    Menu {
                        ForEach(others) { provider in
                            Button(provider.name) {
                                provider.patients.append(person)
                            }
                        }
                    } label: {
                        Label("Add existing provider", systemImage: "person.crop.circle.badge.plus")
                    }
                }
            }
        }
    }
}

struct ProviderRow: View {
    let provider: Provider

    var body: some View {
        RecordRow(
            title: provider.name,
            details: [provider.specialty, provider.practice, provider.phone]
        )
    }
}

struct ProviderEditView: View {
    let provider: Provider?
    let defaultPatient: Person?

    @Environment(\.modelContext) private var modelContext
    @Query(sort: [SortDescriptor(\Person.sortOrder), SortDescriptor(\Person.name)]) private var people: [Person]

    @State private var name = ""
    @State private var specialty = ""
    @State private var practice = ""
    @State private var phone = ""
    @State private var fax = ""
    @State private var address = ""
    @State private var portalURL = ""
    @State private var notes = ""
    @State private var patientIDs: Set<UUID> = []
    @State private var didLoad = false

    var body: some View {
        EditorForm(title: provider == nil ? "New provider" : "Edit provider", canSave: !name.isBlank, onSave: save) {
            Section {
                TextField("Name (e.g. Dr. Jane Rivera)", text: $name)
                    .textContentType(.name)
                TextField("Specialty (e.g. Pediatrics)", text: $specialty)
                TextField("Practice or clinic", text: $practice)
            }
            Section("Contact") {
                TextField("Phone", text: $phone)
                    .keyboardType(.phonePad)
                TextField("Fax", text: $fax)
                    .keyboardType(.phonePad)
                TextField("Address", text: $address, axis: .vertical)
                    .textContentType(.fullStreetAddress)
                TextField("Patient portal website", text: $portalURL)
                    .keyboardType(.URL)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
            }
            Section("Sees") {
                ForEach(people) { person in
                    Toggle(person.displayName, isOn: Binding(
                        get: { patientIDs.contains(person.id) },
                        set: { isOn in
                            if isOn { patientIDs.insert(person.id) } else { patientIDs.remove(person.id) }
                        }
                    ))
                }
            }
            Section { NotesField(text: $notes) }
        }
        .onAppear {
            guard !didLoad else { return }
            didLoad = true
            if let provider {
                name = provider.name
                specialty = provider.specialty
                practice = provider.practice
                phone = provider.phone
                fax = provider.fax
                address = provider.address
                portalURL = provider.portalURL
                notes = provider.notes
                patientIDs = Set(provider.patients.map(\.id))
            } else if let defaultPatient {
                patientIDs = [defaultPatient.id]
            }
        }
    }

    private func save() {
        let target = provider ?? {
            let new = Provider(name: name.trimmed)
            modelContext.insert(new)
            return new
        }()
        target.name = name.trimmed
        target.specialty = specialty.trimmed
        target.practice = practice.trimmed
        target.phone = phone.trimmed
        target.fax = fax.trimmed
        target.address = address.trimmed
        target.portalURL = portalURL.trimmed
        target.notes = notes.trimmed
        target.patients = people.filter { patientIDs.contains($0.id) }
    }
}
