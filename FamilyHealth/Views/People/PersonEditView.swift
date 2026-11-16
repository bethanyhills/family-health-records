import PhotosUI
import SwiftData
import SwiftUI

/// Adds a new family member (`person == nil`) or edits an existing one.
struct PersonEditView: View {
    let person: Person?
    var nextSortOrder: Int = 0

    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss

    @State private var name = ""
    @State private var preferredName = ""
    @State private var hasDateOfBirth = false
    @State private var dateOfBirth = Calendar.current.date(byAdding: .year, value: -30, to: .now) ?? .now
    @State private var sex = Sex.unspecified
    @State private var bloodType = BloodType.unknown
    @State private var height = ""
    @State private var weight = ""
    @State private var preferredPharmacy = ""
    @State private var notes = ""
    @State private var photoData: Data?
    @State private var photoItem: PhotosPickerItem?
    @State private var didLoad = false

    var body: some View {
        Form {
            Section {
                HStack {
                    Spacer()
                    VStack(spacing: 8) {
                        AvatarView(photoData: photoData, initials: initials, size: 88)
                        PhotosPicker(selection: $photoItem, matching: .images) {
                            Text(photoData == nil ? "Add photo" : "Change photo")
                        }
                        if photoData != nil {
                            Button("Remove photo", role: .destructive) {
                                photoData = nil
                                photoItem = nil
                            }
                            .font(.footnote)
                        }
                    }
                    Spacer()
                }
            }
            .listRowBackground(Color.clear)

            Section("Name") {
                TextField("Full legal name", text: $name)
                    .textContentType(.name)
                    .textInputAutocapitalization(.words)
                TextField("Preferred name (optional)", text: $preferredName)
                    .textInputAutocapitalization(.words)
            }

            Section("Details") {
                Toggle("Date of birth", isOn: $hasDateOfBirth.animation())
                if hasDateOfBirth {
                    DatePicker("Born", selection: $dateOfBirth, in: ...Date.now, displayedComponents: .date)
                }
                Picker("Sex", selection: $sex) {
                    ForEach(Sex.allCases) { Text($0.label).tag($0) }
                }
                Picker("Blood type", selection: $bloodType) {
                    ForEach(BloodType.allCases) { Text($0.label).tag($0) }
                }
                TextField("Height (e.g. 5 ft 4 in)", text: $height)
                TextField("Weight (e.g. 130 lb)", text: $weight)
                TextField("Preferred pharmacy", text: $preferredPharmacy)
            }

            Section("Notes") {
                TextField("Anything else worth remembering", text: $notes, axis: .vertical)
                    .lineLimit(3...8)
            }
        }
        .navigationTitle(person == nil ? "New family member" : "Edit")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("Cancel") { dismiss() }
            }
            ToolbarItem(placement: .confirmationAction) {
                Button("Save") { save() }
                    .disabled(name.isBlank)
            }
        }
        .onAppear(perform: load)
        .onChange(of: photoItem) { _, item in
            guard let item else { return }
            Task {
                if let data = try? await item.loadTransferable(type: Data.self) {
                    photoData = ImageDownscaler.jpeg(from: data, maxDimension: 600)
                }
            }
        }
    }

    private var initials: String {
        name.split(separator: " ").prefix(2).compactMap { $0.first.map(String.init) }.joined().uppercased()
    }

    private func load() {
        guard !didLoad else { return }
        didLoad = true
        guard let person else { return }
        name = person.name
        preferredName = person.preferredName
        if let dob = person.dateOfBirth {
            hasDateOfBirth = true
            dateOfBirth = dob
        }
        sex = person.sex
        bloodType = person.bloodType
        height = person.height
        weight = person.weight
        preferredPharmacy = person.preferredPharmacy
        notes = person.notes
        photoData = person.photoData
    }

    private func save() {
        let target: Person
        if let person {
            target = person
        } else {
            target = Person(name: name.trimmed, sortOrder: nextSortOrder)
            modelContext.insert(target)
        }
        target.name = name.trimmed
        target.preferredName = preferredName.trimmed
        target.dateOfBirth = hasDateOfBirth ? dateOfBirth : nil
        target.sex = sex
        target.bloodType = bloodType
        target.height = height.trimmed
        target.weight = weight.trimmed
        target.preferredPharmacy = preferredPharmacy.trimmed
        target.notes = notes.trimmed
        target.photoData = photoData
        dismiss()
    }
}

struct EmergencyContactEditView: View {
    let person: Person
    let contact: EmergencyContact?

    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss

    @State private var name = ""
    @State private var relationship = ""
    @State private var phone = ""
    @State private var notes = ""
    @State private var didLoad = false

    var body: some View {
        Form {
            TextField("Name", text: $name)
                .textContentType(.name)
                .textInputAutocapitalization(.words)
            TextField("Relationship (e.g. Spouse)", text: $relationship)
                .textInputAutocapitalization(.words)
            TextField("Phone", text: $phone)
                .textContentType(.telephoneNumber)
                .keyboardType(.phonePad)
            TextField("Notes", text: $notes, axis: .vertical)
        }
        .navigationTitle(contact == nil ? "New contact" : "Edit contact")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("Cancel") { dismiss() }
            }
            ToolbarItem(placement: .confirmationAction) {
                Button("Save") { save() }
                    .disabled(name.isBlank)
            }
        }
        .onAppear {
            guard !didLoad else { return }
            didLoad = true
            if let contact {
                name = contact.name
                relationship = contact.relationship
                phone = contact.phone
                notes = contact.notes
            }
        }
    }

    private func save() {
        let target: EmergencyContact
        if let contact {
            target = contact
        } else {
            target = EmergencyContact(name: name.trimmed)
            modelContext.insert(target)
            target.person = person
        }
        target.name = name.trimmed
        target.relationship = relationship.trimmed
        target.phone = phone.trimmed
        target.notes = notes.trimmed
        dismiss()
    }
}
