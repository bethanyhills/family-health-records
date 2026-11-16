import PhotosUI
import SwiftData
import SwiftUI
import VisionKit

/// Insurance policies covering one family member. Policies are shared, so
/// swiping removes coverage for this person only.
struct InsuranceView: View {
    let person: Person

    @Environment(\.recordAccess) private var access
    @Query(sort: \InsurancePolicy.carrier) private var allPolicies: [InsurancePolicy]

    var body: some View {
        let sorted = person.insurancePolicies.sorted { $0.kind.rawValue < $1.kind.rawValue }
        let others = allPolicies.filter { policy in !person.insurancePolicies.contains { $0.id == policy.id } }

        RecordList(
            title: "Insurance",
            emptyTitle: "No insurance",
            emptyMessage: "Add medical, dental, vision and prescription plans, with photos of the cards. A family plan only needs to be added once.",
            systemImage: "creditcard",
            sections: [RecordSection(nil, sorted)],
            row: { InsuranceRow(policy: $0) },
            editor: { InsuranceEditView(policy: $0, defaultMember: person) },
            onRemove: { policy in
                policy.members.removeAll { $0.id == person.id }
            }
        )
        .toolbar {
            if access.canEdit && !others.isEmpty {
                ToolbarItem(placement: .secondaryAction) {
                    Menu {
                        ForEach(others) { policy in
                            Button("\(policy.carrier) (\(policy.kind.label))") {
                                policy.members.append(person)
                            }
                        }
                    } label: {
                        Label("Add existing plan", systemImage: "plus.rectangle.on.rectangle")
                    }
                }
            }
        }
    }
}

struct InsuranceRow: View {
    let policy: InsurancePolicy

    var body: some View {
        HStack(spacing: 12) {
            if let data = policy.cardFrontImage, let image = UIImage(data: data) {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFill()
                    .frame(width: 64, height: 40)
                    .clipShape(RoundedRectangle(cornerRadius: 6))
                    .accessibilityHidden(true)
            }
            RecordRow(
                title: policy.carrier,
                details: [policy.planName, policy.memberID.isBlank ? "" : "Member ID \(policy.memberID)"],
                badge: policy.kind.label
            )
        }
    }
}

struct InsuranceEditView: View {
    let policy: InsurancePolicy?
    let defaultMember: Person?

    @Environment(\.modelContext) private var modelContext
    @Query(sort: [SortDescriptor(\Person.sortOrder), SortDescriptor(\Person.name)]) private var people: [Person]

    @State private var kind = InsuranceKind.medical
    @State private var carrier = ""
    @State private var planName = ""
    @State private var memberID = ""
    @State private var groupNumber = ""
    @State private var subscriberName = ""
    @State private var subscriberDateOfBirth: Date?
    @State private var phone = ""
    @State private var rxBIN = ""
    @State private var rxPCN = ""
    @State private var rxGroup = ""
    @State private var notes = ""
    @State private var front: Data?
    @State private var back: Data?
    @State private var memberIDs: Set<UUID> = []
    @State private var didLoad = false
    @State private var isReadingCard = false
    @State private var scanNote: String?

    var body: some View {
        EditorForm(title: policy == nil ? "New insurance" : "Edit insurance", canSave: !carrier.isBlank, onSave: save) {
            Section {
                CardPhotoField(label: "Front", data: $front, onNewPhoto: readCard)
                CardPhotoField(label: "Back", data: $back, onNewPhoto: readCard)
            } header: {
                Text("Card photos")
            } footer: {
                if isReadingCard {
                    Text("Reading the card…")
                } else if let scanNote {
                    Text(scanNote)
                } else {
                    Text("Scan the card first and the details below fill in for you. The card is read on this iPhone.")
                }
            }
            Section {
                Picker("Type", selection: $kind) {
                    ForEach(InsuranceKind.allCases) { Text($0.label).tag($0) }
                }
                TextField("Insurance company", text: $carrier)
                TextField("Plan name", text: $planName)
                TextField("Member ID", text: $memberID)
                    .textInputAutocapitalization(.characters)
                    .autocorrectionDisabled()
                TextField("Group number", text: $groupNumber)
                    .textInputAutocapitalization(.characters)
                    .autocorrectionDisabled()
                TextField("Member services phone", text: $phone)
                    .keyboardType(.phonePad)
            }
            Section("Policy holder") {
                TextField("Name", text: $subscriberName)
                    .textContentType(.name)
                DateField(label: "Date of birth", date: $subscriberDateOfBirth)
            }
            Section("Prescription (on the card)") {
                TextField("Rx BIN", text: $rxBIN)
                TextField("Rx PCN", text: $rxPCN)
                TextField("Rx Group", text: $rxGroup)
            }
            .autocorrectionDisabled()
            .textInputAutocapitalization(.characters)
            Section("Covers") {
                PeopleToggles(people: people, selection: $memberIDs)
            }
            Section { NotesField(text: $notes) }
        }
        .onAppear {
            guard !didLoad else { return }
            didLoad = true
            if let policy {
                kind = policy.kind
                carrier = policy.carrier
                planName = policy.planName
                memberID = policy.memberID
                groupNumber = policy.groupNumber
                subscriberName = policy.subscriberName
                subscriberDateOfBirth = policy.subscriberDateOfBirth
                phone = policy.phone
                rxBIN = policy.rxBIN
                rxPCN = policy.rxPCN
                rxGroup = policy.rxGroup
                notes = policy.notes
                front = policy.cardFrontImage
                back = policy.cardBackImage
                memberIDs = Set(policy.members.map(\.id))
            } else if let defaultMember {
                memberIDs = [defaultMember.id]
            }
        }
    }

    /// Reads the photo on the phone and fills in any fields that are still empty.
    private func readCard(_ photo: Data) {
        isReadingCard = true
        Task {
            let found = InsuranceCardParser.parse(await TextRecognizer.lines(in: photo))
            var filled = 0
            func fill(_ field: inout String, _ value: String) {
                if field.isBlank && !value.isEmpty {
                    field = value
                    filled += 1
                }
            }
            fill(&carrier, found.carrier)
            fill(&planName, found.planName)
            fill(&memberID, found.memberID)
            fill(&groupNumber, found.groupNumber)
            fill(&subscriberName, found.subscriberName)
            fill(&phone, found.phone)
            fill(&rxBIN, found.rxBIN)
            fill(&rxPCN, found.rxPCN)
            fill(&rxGroup, found.rxGroup)
            isReadingCard = false
            scanNote = filled == 0
                ? "Couldn't read new details from this photo. You can type them in below."
                : "Filled in \(filled) field\(filled == 1 ? "" : "s") from the card. Please check them."
        }
    }

    private func save() {
        let target = policy ?? {
            let new = InsurancePolicy(carrier: carrier.trimmed)
            modelContext.insert(new)
            return new
        }()
        target.kind = kind
        target.carrier = carrier.trimmed
        target.planName = planName.trimmed
        target.memberID = memberID.trimmed
        target.groupNumber = groupNumber.trimmed
        target.subscriberName = subscriberName.trimmed
        target.subscriberDateOfBirth = subscriberDateOfBirth
        target.phone = phone.trimmed
        target.rxBIN = rxBIN.trimmed
        target.rxPCN = rxPCN.trimmed
        target.rxGroup = rxGroup.trimmed
        target.notes = notes.trimmed
        target.cardFrontImage = front
        target.cardBackImage = back
        target.members = people.filter { memberIDs.contains($0.id) }
    }
}

/// Shows a card photo with buttons to scan it with the camera or pick it from Photos.
struct CardPhotoField: View {
    let label: String
    @Binding var data: Data?
    /// Called with each newly added photo, e.g. to read the card.
    var onNewPhoto: ((Data) -> Void)?

    @State private var photoItem: PhotosPickerItem?
    @State private var isScanning = false
    @State private var isViewing = false

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(label)
                .font(.subheadline.weight(.medium))
            if let data, let image = UIImage(data: data) {
                Button {
                    isViewing = true
                } label: {
                    Image(uiImage: image)
                        .resizable()
                        .scaledToFit()
                        .frame(maxHeight: 160)
                        .clipShape(RoundedRectangle(cornerRadius: 8))
                }
                .buttonStyle(.plain)
                .accessibilityLabel("\(label) of card")
            }
            HStack(spacing: 16) {
                if VNDocumentCameraViewController.isSupported {
                    Button {
                        isScanning = true
                    } label: {
                        Label("Scan", systemImage: "doc.viewfinder")
                    }
                }
                PhotosPicker(selection: $photoItem, matching: .images) {
                    Label("Photos", systemImage: "photo")
                }
                if data != nil {
                    Spacer()
                    Button("Remove", role: .destructive) {
                        data = nil
                        photoItem = nil
                    }
                }
            }
            .buttonStyle(.borderless)
        }
        .padding(.vertical, 4)
        .onChange(of: photoItem) { _, item in
            guard let item else { return }
            Task {
                if let raw = try? await item.loadTransferable(type: Data.self),
                   let jpeg = ImageDownscaler.jpeg(from: raw) {
                    data = jpeg
                    onNewPhoto?(jpeg)
                }
            }
        }
        .fullScreenCover(isPresented: $isScanning) {
            DocumentScanner { image in
                if let image, let raw = image.jpegData(compressionQuality: 1),
                   let jpeg = ImageDownscaler.jpeg(from: raw) {
                    data = jpeg
                    onNewPhoto?(jpeg)
                }
                isScanning = false
            }
            .ignoresSafeArea()
        }
        .sheet(isPresented: $isViewing) {
            if let data, let image = UIImage(data: data) {
                NavigationStack {
                    Image(uiImage: image)
                        .resizable()
                        .scaledToFit()
                        .padding()
                        .navigationTitle(label)
                        .navigationBarTitleDisplayMode(.inline)
                        .toolbar {
                            Button("Done") { isViewing = false }
                        }
                }
            }
        }
    }
}

/// Apple's document camera, which finds the card edges and straightens the photo.
struct DocumentScanner: UIViewControllerRepresentable {
    let onFinish: (UIImage?) -> Void

    func makeUIViewController(context: Context) -> VNDocumentCameraViewController {
        let controller = VNDocumentCameraViewController()
        controller.delegate = context.coordinator
        return controller
    }

    func updateUIViewController(_ controller: VNDocumentCameraViewController, context: Context) {}

    func makeCoordinator() -> Coordinator { Coordinator(onFinish: onFinish) }

    final class Coordinator: NSObject, VNDocumentCameraViewControllerDelegate {
        let onFinish: (UIImage?) -> Void

        init(onFinish: @escaping (UIImage?) -> Void) {
            self.onFinish = onFinish
        }

        func documentCameraViewController(_ controller: VNDocumentCameraViewController, didFinishWith scan: VNDocumentCameraScan) {
            onFinish(scan.pageCount > 0 ? scan.imageOfPage(at: 0) : nil)
        }

        func documentCameraViewControllerDidCancel(_ controller: VNDocumentCameraViewController) {
            onFinish(nil)
        }

        func documentCameraViewController(_ controller: VNDocumentCameraViewController, didFailWithError error: Error) {
            onFinish(nil)
        }
    }
}
