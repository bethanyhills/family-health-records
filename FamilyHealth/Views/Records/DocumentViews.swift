import PDFKit
import PhotosUI
import SwiftData
import SwiftUI
import UniformTypeIdentifiers
import VisionKit

/// A person's documents: lab and diagnostic reports, letters and legal papers, each kept
/// whole as a PDF. Always viewable, even when editing is locked.
struct DocumentsView: View {
    let person: Person

    @Environment(\.modelContext) private var modelContext
    @Environment(\.recordAccess) private var access
    @State private var isAdding = false
    @State private var message: String?

    var body: some View {
        let legal = sorted(person.documents.filter { $0.kind.isLegal })
        let schoolPlans = sorted(person.documents.filter { $0.kind.isSchoolPlan })
        let other = sorted(person.documents.filter { !$0.kind.isLegal && !$0.kind.isSchoolPlan })
        List {
            if !legal.isEmpty {
                Section("Legal papers") { rows(legal) }
            }
            if !schoolPlans.isEmpty {
                Section("504 plans and IEPs") { rows(schoolPlans) }
            }
            if !other.isEmpty {
                Section {
                    rows(other)
                } header: {
                    if !legal.isEmpty || !schoolPlans.isEmpty { Text("Medical documents") }
                }
            }
        }
        .brandedBackground()
        .overlay {
            if person.documents.isEmpty {
                ContentUnavailableView {
                    Label("No documents", systemImage: "doc.text")
                } description: {
                    Text("Keep lab results, evaluations, referrals and legal papers whole. Scan pages, or add a PDF from an email or Files.")
                } actions: {
                    if access.canEdit {
                        Button("Add") { isAdding = true }
                            .buttonStyle(.borderedProminent)
                    }
                }
            }
        }
        .navigationTitle("Documents")
        .toolbar {
            if access.canEdit {
                ToolbarItem(placement: .primaryAction) {
                    Button {
                        isAdding = true
                    } label: {
                        Label("Add", systemImage: "plus")
                    }
                }
            }
        }
        .sheet(isPresented: $isAdding) {
            NavigationStack { DocumentEditView(person: person, document: nil) { message = $0 } }
        }
        .successBanner($message)
    }

    private func sorted(_ documents: [HealthDocument]) -> [HealthDocument] {
        documents.sorted { ($0.date ?? $0.createdAt) > ($1.date ?? $1.createdAt) }
    }

    @ViewBuilder
    private func rows(_ documents: [HealthDocument]) -> some View {
        ForEach(documents) { document in
            NavigationLink {
                DocumentDetailView(person: person, document: document)
            } label: {
                DocumentRow(document: document)
            }
        }
        .onDelete { offsets in
            for index in offsets { modelContext.delete(documents[index]) }
        }
        .deleteDisabled(!access.canEdit)
    }
}

struct DocumentRow: View {
    let document: HealthDocument

    var body: some View {
        HStack(spacing: 12) {
            DocumentThumbnail(data: document.pdfData)
                .frame(width: 36, height: 46)
            RecordRow(title: document.displayTitle, details: DocumentRow.details(for: document))
        }
    }

    static func details(for document: HealthDocument) -> [String] {
        [
            document.title.isBlank ? "" : document.kind.label,
            document.date?.formDate ?? "",
            document.provider?.name ?? "",
            document.pageCount > 1 ? "\(document.pageCount) pages" : "",
        ]
    }
}

struct DocumentThumbnail: View {
    let data: Data?
    @State private var image: UIImage?

    var body: some View {
        Group {
            if let image {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFit()
                    .overlay(RoundedRectangle(cornerRadius: 3).stroke(.quaternary))
            } else {
                Image(systemName: "doc.text")
                    .font(.title2)
                    .foregroundStyle(.secondary)
            }
        }
        .task(id: data?.count) {
            image = data.flatMap { DocumentPDF.thumbnail(of: $0) }
        }
    }
}

/// Shows the document's pages, with its details, a share button and Edit.
struct DocumentDetailView: View {
    let person: Person
    let document: HealthDocument

    @Environment(\.recordAccess) private var access
    @Environment(\.dismiss) private var dismiss
    @Query(sort: \Person.name) private var family: [Person]
    @State private var isEditing = false
    @State private var importing: DocumentImport?
    @State private var message: String?
    @State private var movingTo: Person?
    @State private var keptOwnerID: UUID?

    /// Another family member this document names instead, if it looks misfiled.
    private var namedOwner: Person? {
        guard access.canEdit, let owner = DocumentOwner.otherOwner(
            of: document.recognizedText, filedUnder: person, family: family) else { return nil }
        return owner.id == keptOwnerID ? nil : owner
    }

    var body: some View {
        Group {
            if let data = document.pdfData {
                PDFPreview(data: data)
                    .ignoresSafeArea(edges: .bottom)
            } else {
                ContentUnavailableView("No pages", systemImage: "doc", description: Text("Edit the document to scan or add its pages."))
            }
        }
        .safeAreaInset(edge: .top) {
            VStack(spacing: 0) {
                if let owner = namedOwner {
                    MisfiledNotice(filedUnder: person, owner: owner,
                                   onMove: { movingTo = owner }, onKeep: { keptOwnerID = owner.id })
                }
                let details = DocumentRow.details(for: document).filter { !$0.isEmpty }
                if !details.isEmpty || !document.notes.isBlank {
                    VStack(alignment: .leading, spacing: 2) {
                        if !details.isEmpty {
                            Text(details.joined(separator: " · ")).font(.subheadline)
                        }
                        if !document.notes.isBlank {
                            Text(document.notes).font(.footnote).foregroundStyle(.secondary)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal)
                    .padding(.vertical, 8)
                    .background(.bar)
                }
            }
        }
        .safeAreaInset(edge: .bottom) {
            if document.pdfData != nil, access.canEdit, let action = DocumentImport.offered(for: document) {
                Group {
                    if let importedAt = document.importedAt {
                        // Already added: say so, and keep a quieter way to go through it again.
                        HStack {
                            Label("Added to \(action.destination) on \(importedAt.formDate)", systemImage: "checkmark.circle.fill")
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                            Spacer()
                            Button("Review again") { importing = action }
                                .font(.subheadline)
                        }
                    } else {
                        Button {
                            importing = action
                        } label: {
                            Label(action.buttonTitle, systemImage: action.systemImage)
                                .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.borderedProminent)
                    }
                }
                .padding()
                .background(.bar)
            }
        }
        .sheet(item: $importing) { action in
            DocumentImportSheet(person: person, document: document, action: action) { message = $0 }
        }
        .successBanner($message)
        .confirmationDialog(
            "Move this document to \(movingTo?.shortName ?? "")'s profile?",
            isPresented: Binding(get: { movingTo != nil }, set: { if !$0 { movingTo = nil } }),
            titleVisibility: .visible,
            presenting: movingTo
        ) { owner in
            Button("Move to \(owner.shortName)") { move(to: owner) }
        } message: { _ in
            Text(document.importedAt == nil
                 ? "It leaves \(person.shortName)'s documents. You won't need to scan it again."
                 : "It leaves \(person.shortName)'s documents. Anything already added from it to \(person.shortName)'s records stays there, so check and remove it.")
        }
        .navigationTitle(document.displayTitle)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            if let data = document.pdfData {
                ToolbarItem(placement: .primaryAction) {
                    ShareLink(
                        item: SharedPDF(data: data, name: document.displayTitle),
                        preview: SharePreview(document.displayTitle)
                    )
                }
            }
            if access.canEdit {
                ToolbarItem(placement: .primaryAction) {
                    Button("Edit") { isEditing = true }
                }
            }
        }
        .sheet(isPresented: $isEditing) {
            NavigationStack { DocumentEditView(person: person, document: document) }
        }
    }

    private func move(to owner: Person) {
        document.person = owner
        // The provider stays: it's shared. What it said still needs adding for the right person.
        document.importedAt = nil
        dismiss()
    }
}

/// "This looks like Owen's document", with Move and Keep.
struct MisfiledNotice: View {
    let filedUnder: Person
    let owner: Person
    var moveTitle: String? = nil
    let onMove: () -> Void
    let onKeep: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label {
                Text("This looks like **\(owner.displayName)**'s document, not \(filedUnder.shortName)'s.")
            } icon: {
                Image(systemName: "person.crop.circle.badge.exclamationmark")
                    .foregroundStyle(.orange)
            }
            .font(.subheadline)
            HStack {
                Button(moveTitle ?? "Move to \(owner.shortName)", action: onMove)
                    .buttonStyle(.borderedProminent)
                Button("It's \(filedUnder.shortName)'s", action: onKeep)
                    .buttonStyle(.bordered)
            }
            .font(.subheadline)
            .controlSize(.small)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal)
        .padding(.vertical, 10)
        .background(Color.orange.opacity(0.12))
    }
}

/// A PDF handed to the share sheet with a readable file name.
struct SharedPDF: Transferable {
    let data: Data
    let name: String

    static var transferRepresentation: some TransferRepresentation {
        FileRepresentation(exportedContentType: .pdf) { item in
            let safe = item.name.components(separatedBy: CharacterSet(charactersIn: "/\\:?*\"<>|")).joined()
            let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            let url = folder.appendingPathComponent((safe.isEmpty ? "Document" : safe) + ".pdf")
            try item.data.write(to: url, options: .completeFileProtection)
            return SentTransferredFile(url)
        }
    }
}

struct PDFPreview: UIViewRepresentable {
    let data: Data

    func makeUIView(context: Context) -> PDFView {
        let view = PDFView()
        view.autoScales = true
        view.displayMode = .singlePageContinuous
        view.document = PDFDocument(data: data)
        return view
    }

    func updateUIView(_ view: PDFView, context: Context) {
        if view.document?.dataRepresentation()?.count != data.count {
            view.document = PDFDocument(data: data)
        }
    }
}

struct DocumentEditView: View {
    let person: Person
    let document: HealthDocument?
    /// The type a new document starts as, e.g. an IEP added from the school details.
    var initialKind: DocumentKind? = nil
    /// Open the camera right away, for a Scan button in a record list.
    var startsScanning = false
    /// Called with a short message after the document is saved and anything in it added.
    var onFinished: ((String) -> Void)? = nil

    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @Environment(\.recordAccess) private var access
    @Query(sort: \Provider.name) private var providers: [Provider]
    @Query(sort: \Person.name) private var family: [Person]
    @State private var title = ""
    @State private var kind = DocumentKind.labResults
    @State private var date: Date?
    @State private var providerChoice = ""
    @State private var notes = ""
    @State private var pdfData: Data?
    @State private var recognizedText = ""
    @State private var isReading = false
    @State private var isScanning = false
    @State private var isImportingPDF = false
    @State private var photoItems: [PhotosPickerItem] = []
    @State private var error: String?
    @State private var didLoad = false
    /// Who the document is saved to: another family member when the page names them.
    @State private var owner: Person?
    @State private var keptOwnerID: UUID?
    /// Add what the document says (vaccines, a medication, …) right after saving.
    @State private var addContents = true
    @State private var review: DocumentReview?
    @State private var savedMessage: String?

    private var target: Person { owner ?? person }

    /// What a new document's text can be added as, once it has been read.
    private var offeredImport: DocumentImport? {
        guard document == nil, pdfData != nil, !isReading, access.canEdit else { return nil }
        return DocumentImport.offered(kind: kind, text: recognizedText)
    }

    private var willReview: Bool { offeredImport != nil && addContents }

    /// Another family member the pages name, if they don't seem to be this person's.
    private var namedOwner: Person? {
        guard owner == nil, pdfData != nil, !isReading,
              let other = DocumentOwner.otherOwner(of: recognizedText, filedUnder: person, family: family),
              other.id != keptOwnerID else { return nil }
        return other
    }

    var body: some View {
        EditorForm(
            title: document == nil ? "New document" : "Edit document",
            canSave: pdfData != nil && !isReading,
            saveTitle: willReview ? "Next" : "Save",
            dismissesOnSave: !willReview,
            onSave: saveAndReview
        ) {
            if let other = namedOwner {
                Section {
                    MisfiledNotice(filedUnder: person, owner: other, moveTitle: "Save to \(other.shortName) instead",
                                   onMove: { owner = other }, onKeep: { keptOwnerID = other.id })
                        .listRowInsets(EdgeInsets())
                }
            } else if let owner {
                Section {
                    HStack {
                        Label("Saving to \(owner.shortName)'s documents", systemImage: "person.crop.circle.badge.checkmark")
                        Spacer()
                        Button("Undo") {
                            keptOwnerID = owner.id
                            self.owner = nil
                        }
                    }
                }
            }
            Section {
                if let pdfData {
                    HStack(spacing: 12) {
                        DocumentThumbnail(data: pdfData)
                            .frame(width: 60, height: 78)
                        VStack(alignment: .leading, spacing: 4) {
                            let pages = DocumentPDF.pageCount(of: pdfData)
                            Text("\(pages) page\(pages == 1 ? "" : "s")")
                            if isReading {
                                Label("Reading the text…", systemImage: "text.viewfinder")
                                    .font(.footnote)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                }
                if VNDocumentCameraViewController.isSupported {
                    Button {
                        isScanning = true
                    } label: {
                        Label(pdfData == nil ? "Scan pages" : "Scan again", systemImage: "doc.viewfinder")
                    }
                }
                Button {
                    isImportingPDF = true
                } label: {
                    Label("Choose a PDF from Files", systemImage: "folder")
                }
                PhotosPicker(selection: $photoItems, maxSelectionCount: 30, matching: .images) {
                    Label("Choose photos", systemImage: "photo.on.rectangle")
                }
            } header: {
                Text("Pages")
            } footer: {
                if let error {
                    Text(error).foregroundStyle(.red)
                } else {
                    Text("To keep a PDF from an email, open it, tap Share, then Save to Files, and choose it here. The text is read on this iPhone so you can search it later.")
                }
            }
            Section {
                Picker("Type", selection: $kind) {
                    ForEach(DocumentKind.allCases) { Text($0.label).tag($0) }
                }
                TextField("Title (e.g. Blood work, Speech evaluation)", text: $title)
                DateField(label: "Date", date: $date)
                ProviderPicker(person: person, selection: $providerChoice, label: "From")
            }
            if let action = offeredImport {
                Section {
                    Toggle(isOn: $addContents) {
                        Label(action.buttonTitle, systemImage: action.systemImage)
                    }
                } footer: {
                    Text(addContents
                         ? "After you tap Next, check what was read before it's added to \(target.shortName)'s \(action.destination)."
                         : "You can add it later from the document.")
                }
            }
            Section { NotesField(text: $notes) }
        }
        .sheet(item: $review, onDismiss: {
            if let savedMessage { onFinished?(savedMessage) }
            dismiss()
        }) { review in
            DocumentImportSheet(person: review.person, document: review.document, action: review.action) { added in
                savedMessage = added
            }
        }
        .fullScreenCover(isPresented: $isScanning) {
            MultiPageScanner { images in
                isScanning = false
                if !images.isEmpty { setPages(DocumentPDF.pdf(from: images)) }
            }
            .ignoresSafeArea()
        }
        .fileImporter(isPresented: $isImportingPDF, allowedContentTypes: [.pdf]) { result in
            switch result {
            case .success(let url):
                let scoped = url.startAccessingSecurityScopedResource()
                defer { if scoped { url.stopAccessingSecurityScopedResource() } }
                if let data = try? Data(contentsOf: url), DocumentPDF.pageCount(of: data) > 0 {
                    setPages(data)
                    if title.isBlank { title = url.deletingPathExtension().lastPathComponent }
                } else {
                    error = "That file couldn't be opened as a PDF."
                }
            case .failure(let failure):
                error = failure.localizedDescription
            }
        }
        .onChange(of: photoItems) { _, items in
            guard !items.isEmpty else { return }
            Task {
                var images: [UIImage] = []
                for item in items {
                    if let raw = try? await item.loadTransferable(type: Data.self),
                       let jpeg = ImageDownscaler.jpeg(from: raw, maxDimension: 2000),
                       let image = UIImage(data: jpeg) {
                        images.append(image)
                    }
                }
                photoItems = []
                if !images.isEmpty { setPages(DocumentPDF.pdf(from: images)) }
            }
        }
        .onAppear {
            guard !didLoad else { return }
            didLoad = true
            guard let document else {
                if let initialKind {
                    kind = initialKind
                    title = Self.defaultTitle(for: initialKind)
                }
                if startsScanning, VNDocumentCameraViewController.isSupported { isScanning = true }
                return
            }
            title = document.title
            kind = document.kind
            date = document.date
            providerChoice = document.provider?.id.uuidString ?? ""
            notes = document.notes
            pdfData = document.pdfData
            recognizedText = document.recognizedText
        }
    }

    private func setPages(_ data: Data) {
        error = nil
        pdfData = data
        isReading = true
        Task {
            let text = await DocumentPDF.text(of: data)
            recognizedText = text
            isReading = false
            // A new document from the general Add button takes the type its pages read as.
            if document == nil, initialKind == nil, kind == .labResults || kind == .other,
               let action = DocumentImport.offered(kind: .other, text: text) {
                kind = action.documentKind(for: text)
            }
            // One scanned from the school details can turn out to be the other kind of plan.
            if document == nil, kind.isSchoolPlan,
               let read = SchoolPlanParser.planKind(of: text).documentKind, read != kind {
                if title == Self.defaultTitle(for: kind) { title = Self.defaultTitle(for: read) }
                kind = read
            }
        }
    }

    private func saveAndReview() {
        let saved = save()
        let movedMessage = owner.map { "Saved to \($0.shortName)'s documents" }
        if willReview, let action = offeredImport {
            savedMessage = movedMessage
            review = DocumentReview(person: target, document: saved, action: action)
        } else {
            onFinished?(movedMessage ?? "Saved to Documents")
        }
    }

    /// The title a new document of this type starts with.
    private static func defaultTitle(for kind: DocumentKind) -> String {
        kind == .iep ? "IEP" : kind.label
    }

    @discardableResult
    private func save() -> HealthDocument {
        let person = self.target
        let target = document ?? {
            let new = HealthDocument(title: title.trimmed, kind: kind)
            modelContext.insert(new)
            new.person = person
            return new
        }()
        target.title = title.trimmed
        target.kind = kind
        target.date = date
        target.notes = notes.trimmed
        target.provider = ProviderPicker.resolve(providerChoice, for: person, in: providers)
        if target.pdfData != pdfData {
            target.pdfData = pdfData
            target.pageCount = pdfData.map(DocumentPDF.pageCount(of:)) ?? 0
        }
        target.recognizedText = recognizedText
        // Adding a 504 plan or IEP marks it active in the school details.
        if person.schoolPlan == .noPlan {
            if kind == .plan504 { person.schoolPlan = .plan504 }
            if kind == .iep { person.schoolPlan = .iep }
        }
        return target
    }
}

/// Saving what a document says into the right part of the app, after the person checks it.
enum DocumentImport: String, Identifiable {
    case vaccines, prescription, visitSummary, schoolPlan

    var id: String { rawValue }

    var buttonTitle: String {
        switch self {
        case .vaccines: "Add these vaccines to Immunizations"
        case .prescription: "Add this medication"
        case .visitSummary: "Add a visit note from this summary"
        case .schoolPlan: "Add this plan to school details"
        }
    }

    var systemImage: String {
        switch self {
        case .vaccines: "syringe"
        case .prescription: "pills"
        case .visitSummary: "note.text.badge.plus"
        case .schoolPlan: "graduationcap"
        }
    }

    /// What to offer for this document: by its type first, then by what its text reads like.
    static func offered(for document: HealthDocument) -> DocumentImport? {
        offered(kind: document.kind, text: document.recognizedText)
    }

    static func offered(kind: DocumentKind, text: String) -> DocumentImport? {
        switch kind {
        case .vaccineRecord: return .vaccines
        case .prescription: return .prescription
        case .visitSummary: return .visitSummary
        case .plan504, .iep: return .schoolPlan
        default: break
        }
        if VaccineRecordParser.looksLikeVaccineRecord(text) { return .vaccines }
        if SchoolPlanParser.looksLikeSchoolPlan(text) { return .schoolPlan }
        // A visit summary often lists medications too, so it's checked before prescriptions.
        if VisitSummaryParser.looksLikeVisitSummary(text) { return .visitSummary }
        if PrescriptionParser.looksLikePrescription(text) { return .prescription }
        return nil
    }
}
