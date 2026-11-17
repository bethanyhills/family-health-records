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
            NavigationStack { DocumentEditView(person: person, document: nil) }
        }
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
    @State private var isEditing = false

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

    @Environment(\.modelContext) private var modelContext
    @Query(sort: \Provider.name) private var providers: [Provider]
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

    var body: some View {
        EditorForm(
            title: document == nil ? "New document" : "Edit document",
            canSave: pdfData != nil && !isReading,
            onSave: save
        ) {
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
            Section { NotesField(text: $notes) }
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
                    title = initialKind == .iep ? "IEP" : initialKind.label
                }
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
            recognizedText = await DocumentPDF.text(of: data)
            isReading = false
        }
    }

    private func save() {
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
    }
}
