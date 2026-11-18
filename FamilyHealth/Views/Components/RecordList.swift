import SwiftData
import SwiftUI

struct RecordSection<Item: PersistentModel>: Identifiable {
    let id: String
    let title: String?
    let items: [Item]

    init(_ title: String? = nil, _ items: [Item]) {
        self.id = title ?? "all"
        self.title = title
        self.items = items
    }
}

/// Scanning a paper from a record list: the document is filed in the person's Documents,
/// and what it says is offered for this list, e.g. a medication label from Medications.
struct RecordScan {
    let person: Person
    let kind: DocumentKind
    /// The button's name, e.g. "Scan a label".
    let title: String
    /// Open this list's blank editor afterward, e.g. to add the surgery from its discharge papers.
    var thenAddRecord = false
}

/// Shared list screen for one kind of record: sections of rows, swipe to delete,
/// tap to edit, a + button that opens a blank editor, and optionally a Scan button.
struct RecordList<Item: PersistentModel, Row: View, Editor: View>: View {
    let title: String
    let emptyTitle: String
    let emptyMessage: String
    let systemImage: String
    let sections: [RecordSection<Item>]
    @ViewBuilder let row: (Item) -> Row
    @ViewBuilder let editor: (Item?) -> Editor
    /// Called instead of deleting the item, e.g. to unlink a shared provider.
    var onRemove: ((Item) -> Void)?
    var scan: RecordScan?

    @Environment(\.modelContext) private var modelContext
    @Environment(\.recordAccess) private var access
    @State private var isAdding = false
    @State private var editing: Item?
    @State private var isScanning = false
    @State private var didScan = false
    @State private var message: String?

    var body: some View {
        List {
            ForEach(sections.filter { !$0.items.isEmpty }) { section in
                Section {
                    ForEach(section.items) { item in
                        Button {
                            if access.canEdit { editing = item }
                        } label: {
                            row(item)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                    }
                    .onDelete { offsets in
                        for index in offsets {
                            let item = section.items[index]
                            if let onRemove {
                                onRemove(item)
                            } else {
                                modelContext.delete(item)
                            }
                        }
                    }
                    .deleteDisabled(!access.canEdit)
                } header: {
                    if let title = section.title { Text(title) }
                }
            }
        }
        .brandedBackground()
        .overlay {
            if sections.allSatisfy({ $0.items.isEmpty }) {
                ContentUnavailableView {
                    Label(emptyTitle, systemImage: systemImage)
                } description: {
                    Text(emptyMessage)
                } actions: {
                    if access.canEdit {
                        Button("Add") { isAdding = true }
                            .buttonStyle(.borderedProminent)
                        if let scan {
                            Button {
                                startScan()
                            } label: {
                                Label(scan.title, systemImage: "doc.viewfinder")
                            }
                            .buttonStyle(.bordered)
                        }
                    }
                }
            }
        }
        .navigationTitle(title)
        .toolbar {
            if access.canEdit, let scan {
                ToolbarItem(placement: .primaryAction) {
                    Button {
                        startScan()
                    } label: {
                        Label(scan.title, systemImage: "doc.viewfinder")
                    }
                }
            }
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
            NavigationStack { editor(nil) }
        }
        .sheet(item: $editing) { item in
            NavigationStack { editor(item) }
        }
        .sheet(isPresented: $isScanning, onDismiss: {
            if didScan, scan?.thenAddRecord == true { isAdding = true }
        }) {
            if let scan {
                NavigationStack {
                    DocumentEditView(person: scan.person, document: nil, initialKind: scan.kind, startsScanning: true) { saved in
                        didScan = true
                        message = saved
                    }
                }
            }
        }
        .successBanner($message)
    }

    private func startScan() {
        didScan = false
        isScanning = true
    }
}

/// Two-line row: a bold title and a muted detail line built from the non-empty parts.
struct RecordRow: View {
    let title: String
    let details: [String]
    var badge: String?
    var badgeColor: Color = .accentColor

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack(alignment: .firstTextBaseline) {
                Text(title)
                    .font(.body.weight(.medium))
                if let badge {
                    Text(badge)
                        .font(.caption.weight(.semibold))
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(badgeColor.opacity(0.15), in: Capsule())
                        .foregroundStyle(badgeColor)
                }
            }
            let line = details.filter { !$0.isBlank }.joined(separator: " · ")
            if !line.isEmpty {
                Text(line)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 2)
        .contextMenu {
            Button {
                UIPasteboard.general.string = ([title] + details.filter { !$0.isBlank }).joined(separator: ", ")
            } label: {
                Label("Copy", systemImage: "doc.on.doc")
            }
        }
    }
}

/// Form wrapper with Cancel and Save buttons.
struct EditorForm<Content: View>: View {
    let title: String
    let canSave: Bool
    /// The confirm button's title, e.g. "Next" when another step follows.
    var saveTitle = "Save"
    /// False when saving leads to another step that closes the sheet itself.
    var dismissesOnSave = true
    let onSave: () -> Void
    @ViewBuilder let content: Content

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        Form { content }
            .brandedBackground()
            // Medical words and names get "corrected" into the wrong thing.
            .autocorrectionDisabled()
            .navigationTitle(title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(saveTitle) {
                        onSave()
                        if dismissesOnSave { dismiss() }
                    }
                    .disabled(!canSave)
                }
            }
    }
}

struct NotesField: View {
    @Binding var text: String

    var body: some View {
        TextField("Notes", text: $text, axis: .vertical)
            .lineLimit(2...6)
    }
}
