import SwiftUI

/// One screen with everything an intake form asks, in form order.
/// Tap any line to copy its value.
struct IntakeSummaryView: View {
    let person: Person

    @State private var copiedItem: SummaryItem?
    @State private var pdfURL: URL?
    @State private var exportError: String?

    var body: some View {
        let sections = IntakeSummary.sections(for: person)
        List {
            Section {
                Text("Tap any line to copy it, then paste it into the form.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
            ForEach(sections) { section in
                Section(section.title) {
                    if section.items.isEmpty {
                        Text(section.emptyText)
                            .foregroundStyle(.secondary)
                    }
                    ForEach(section.items) { item in
                        Button {
                            copy(item)
                        } label: {
                            HStack(alignment: .firstTextBaseline) {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(item.label)
                                        .font(item.value.isEmpty ? .body : .subheadline)
                                        .foregroundStyle(item.value.isEmpty ? .primary : .secondary)
                                    if !item.value.isEmpty {
                                        Text(item.value)
                                    }
                                }
                                Spacer()
                                Image(systemName: copiedItem?.id == item.id ? "checkmark.circle.fill" : "doc.on.doc")
                                    .foregroundStyle(copiedItem?.id == item.id ? Color.green : Color.secondary)
                                    .imageScale(.small)
                            }
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .accessibilityHint("Copies \(item.label)")
                    }
                }
            }
        }
        .brandedBackground()
        .navigationTitle("Intake summary")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Menu {
                    Button {
                        UIPasteboard.general.string = IntakeSummary.text(for: person)
                    } label: {
                        Label("Copy all as text", systemImage: "doc.on.doc")
                    }
                    if let pdfURL {
                        ShareLink(item: pdfURL) {
                            Label("Share PDF", systemImage: "doc.richtext")
                        }
                    }
                } label: {
                    Label("Share", systemImage: "square.and.arrow.up")
                }
            }
        }
        .task(id: IntakeSummary.text(for: person)) {
            do {
                pdfURL = try SummaryPDF.file(for: person)
            } catch {
                exportError = error.localizedDescription
            }
        }
        .onDisappear {
            if let pdfURL { try? FileManager.default.removeItem(at: pdfURL) }
        }
        .alert("Couldn't make the PDF", isPresented: Binding(
            get: { exportError != nil },
            set: { if !$0 { exportError = nil } }
        )) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(exportError ?? "")
        }
    }

    private func copy(_ item: SummaryItem) {
        UIPasteboard.general.string = item.copyValue ?? (item.value.isEmpty ? item.label : item.value)
        withAnimation { copiedItem = item }
        Task {
            try? await Task.sleep(for: .seconds(1.5))
            if copiedItem?.id == item.id {
                withAnimation { copiedItem = nil }
            }
        }
    }
}
