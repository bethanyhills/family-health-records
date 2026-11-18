import SwiftData
import SwiftUI

/// Reads an after-visit summary kept in Documents and opens a new visit note with what
/// it found. Nothing is saved until the person taps Save.
struct VisitSummaryImportView: View {
    let person: Person
    let document: HealthDocument
    /// Called with a short message after the visit note is saved.
    var onFinished: ((String) -> Void)? = nil

    @Environment(\.dismiss) private var dismiss
    @State private var result: VisitSummaryParser.Result?

    var body: some View {
        NavigationStack {
            if let result, !result.isEmpty {
                VisitEditView(person: person, visit: nil, draft: result, draftSource: document.displayTitle, onSaved: { updatedProfile in
                    document.importedAt = .now
                    onFinished?(updatedProfile
                                ? "Added a visit note and updated \(person.shortName)'s height and weight"
                                : "Added a visit note from this summary")
                })
            } else {
                Form {
                    if result == nil {
                        Section {
                            HStack(spacing: 12) {
                                ProgressView()
                                Text("Reading the summary…")
                            }
                        } footer: {
                            Text("The summary is read on this iPhone. Nothing is sent anywhere.")
                        }
                    } else {
                        Section {
                            Text("Nothing could be read from this document. You can write the visit note by hand in Visit notes.")
                                .foregroundStyle(.secondary)
                        }
                    }
                }
                .navigationTitle("Visit summary")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Cancel") { dismiss() }
                    }
                }
            }
        }
        .task { await read() }
    }

    private func read() async {
        guard result == nil else { return }
        var rows: [String] = []
        if let data = document.pdfData { rows = await DocumentPDF.rows(of: data, maxScannedPages: 6) }
        result = VisitSummaryParser.parse(rows: rows)
    }
}
