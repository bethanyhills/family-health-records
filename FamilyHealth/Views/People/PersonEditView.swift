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
    @State private var dateOfBirth: Date?
    @State private var sex = Sex.unspecified
    @State private var bloodType = BloodType.unknown
    @State private var height = ""
    @State private var weight = ""
    @State private var notes = ""
    @State private var communicationNeeds = ""
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

            Section {
                TextField("Full legal name", text: $name)
                    .textContentType(.name)
                    .textInputAutocapitalization(.words)
                TextField("Preferred name (optional)", text: $preferredName)
                    .textInputAutocapitalization(.words)
                DateField(label: "Date of birth", date: $dateOfBirth, allowsFuture: false, isRequired: true)
            } header: {
                Text("Name and birthday")
            } footer: {
                if !canSave {
                    Text("A name and date of birth are needed to save.")
                }
            }

            Section("Details") {
                Picker("Sex", selection: $sex) {
                    ForEach(Sex.allCases) { Text($0.label).tag($0) }
                }
                Picker("Blood type", selection: $bloodType) {
                    ForEach(BloodType.allCases) { Text($0.label).tag($0) }
                }
                HeightField(text: $height)
                WeightField(text: $weight)
            }

            Section {
                TextField("e.g. Deaf, uses ASL, needs an interpreter", text: $communicationNeeds, axis: .vertical)
                    .lineLimit(1...4)
            } header: {
                Text("Communication needs")
            } footer: {
                Text("Interpreter, language, hearing, vision or speech needs. Shown first on the intake summary.")
            }

            Section("Notes") {
                TextField("Anything else worth remembering", text: $notes, axis: .vertical)
                    .lineLimit(3...8)
            }
        }
        .autocorrectionDisabled()
        .navigationTitle(person == nil ? "New family member" : "Edit")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("Cancel") { dismiss() }
            }
            ToolbarItem(placement: .confirmationAction) {
                Button("Save") { save() }
                    .disabled(!canSave)
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

    private var canSave: Bool { !name.isBlank && dateOfBirth != nil }

    private var initials: String {
        name.split(separator: " ").prefix(2).compactMap { $0.first.map(String.init) }.joined().uppercased()
    }

    private func load() {
        guard !didLoad else { return }
        didLoad = true
        guard let person else { return }
        name = person.name
        preferredName = person.preferredName
        dateOfBirth = person.dateOfBirth
        sex = person.sex
        bloodType = person.bloodType
        height = person.height
        weight = person.weight
        notes = person.notes
        communicationNeeds = person.communicationNeeds
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
        target.dateOfBirth = dateOfBirth
        target.sex = sex
        target.bloodType = bloodType
        target.height = height
        target.weight = weight
        target.notes = notes.trimmed
        target.communicationNeeds = communicationNeeds.trimmed
        target.photoData = photoData
        dismiss()
    }
}
