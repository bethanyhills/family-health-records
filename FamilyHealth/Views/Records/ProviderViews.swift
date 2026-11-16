import PhotosUI
import SwiftData
import SwiftUI
import VisionKit

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
    var onSaved: ((Provider) -> Void)?

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
    @State private var isScanning = false
    @State private var photoItem: PhotosPickerItem?
    @State private var isReadingCard = false
    @State private var scanNote: String?

    var body: some View {
        EditorForm(title: provider == nil ? "New provider" : "Edit provider", canSave: !name.isBlank, onSave: save) {
            Section {
                HStack(spacing: 20) {
                    if VNDocumentCameraViewController.isSupported {
                        Button {
                            isScanning = true
                        } label: {
                            Label("Scan business card", systemImage: "person.text.rectangle")
                        }
                    }
                    PhotosPicker(selection: $photoItem, matching: .images) {
                        Label("Photos", systemImage: "photo")
                    }
                }
                .buttonStyle(.borderless)
            } footer: {
                if isReadingCard {
                    Text("Reading the card…")
                } else if let scanNote {
                    Text(scanNote)
                } else {
                    Text("Got a business card? Scan it and the details below fill in. The card is read on this iPhone.")
                }
            }
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
                TextField("Website or patient portal", text: $portalURL)
                    .keyboardType(.URL)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
            }
            Section("Sees") {
                PeopleToggles(people: people, selection: $patientIDs)
            }
            Section { NotesField(text: $notes) }
        }
        .fullScreenCover(isPresented: $isScanning) {
            DocumentScanner { image in
                isScanning = false
                if let data = image?.jpegData(compressionQuality: 0.9) { readCard(data) }
            }
            .ignoresSafeArea()
        }
        .onChange(of: photoItem) { _, item in
            guard let item else { return }
            Task {
                if let data = try? await item.loadTransferable(type: Data.self) { readCard(data) }
            }
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

    /// Reads a business card on the phone and fills in any fields that are still empty.
    private func readCard(_ photo: Data) {
        isReadingCard = true
        Task {
            let found = BusinessCardParser.parse(await TextRecognizer.lines(in: photo))
            var filled = 0
            func fill(_ field: inout String, _ value: String) {
                if field.isBlank && !value.isEmpty {
                    field = value
                    filled += 1
                }
            }
            fill(&name, found.name)
            fill(&specialty, found.specialty)
            fill(&practice, found.practice)
            fill(&phone, found.phone)
            fill(&fax, found.fax)
            fill(&address, found.address)
            fill(&portalURL, found.website)
            if !found.email.isEmpty && !notes.contains(found.email) {
                notes = [notes.trimmed, "Email: \(found.email)"].filter { !$0.isEmpty }.joined(separator: "\n")
                filled += 1
            }
            isReadingCard = false
            scanNote = filled == 0
                ? "Couldn't read details from this card. You can type them in below."
                : "Filled in \(filled) field\(filled == 1 ? "" : "s") from the card. Please check them."
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
        onSaved?(target)
    }
}
