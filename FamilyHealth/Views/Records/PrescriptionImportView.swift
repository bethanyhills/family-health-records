import SwiftData
import SwiftUI

/// Reads a prescription label or printout kept in Documents and opens the medication
/// editor with what it found. If the person already has that medication, the editor
/// updates it instead of adding a second one. Nothing is saved until they tap Save.
struct PrescriptionImportView: View {
    let person: Person
    let document: HealthDocument

    @Environment(\.dismiss) private var dismiss
    @State private var result: PrescriptionParser.Result?

    var body: some View {
        NavigationStack {
            if let result, !result.isEmpty {
                MedicationEditView(
                    person: person,
                    medication: existingMedication(for: result),
                    draft: result,
                    draftSource: document.displayTitle
                )
            } else {
                Form {
                    if result == nil {
                        Section {
                            HStack(spacing: 12) {
                                ProgressView()
                                Text("Reading the label…")
                            }
                        } footer: {
                            Text("The label is read on this iPhone. Nothing is sent anywhere.")
                        }
                    } else {
                        Section {
                            Text("No medication name and strength could be read from this document. You can add it by hand in Medications.")
                                .foregroundStyle(.secondary)
                        }
                    }
                }
                .navigationTitle("Prescription")
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

    private func existingMedication(for result: PrescriptionParser.Result) -> Medication? {
        let medications = person.medications
        let index = PrescriptionParser.matchingMedication(
            named: result.name, in: medications.map { ($0.name, $0.isActive) })
        return index.map { medications[$0] }
    }

    private func read() async {
        guard result == nil else { return }
        var rows: [String] = []
        if let data = document.pdfData { rows = await DocumentPDF.rows(of: data, maxScannedPages: 3) }
        result = PrescriptionParser.parse(rows: rows)
    }
}
