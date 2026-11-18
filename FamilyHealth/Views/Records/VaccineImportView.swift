import SwiftData
import SwiftUI

/// Reads a vaccine record kept in Documents and offers each vaccine and date it finds
/// for Immunizations. Nothing is saved until the person checks the list and taps Add.
struct VaccineImportView: View {
    let person: Person
    let document: HealthDocument
    /// Called with a short message after the vaccines are added.
    var onFinished: ((String) -> Void)? = nil

    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @State private var candidates: [Candidate] = []
    @State private var isReading = true

    struct Candidate: Identifiable {
        var found: VaccineRecordParser.Found
        var include: Bool
        let isAlreadyRecorded: Bool
        var id: UUID { found.id }
    }

    private var chosen: [Candidate] { candidates.filter(\.include) }

    var body: some View {
        NavigationStack {
            Form {
                if isReading {
                    Section {
                        HStack(spacing: 12) {
                            ProgressView()
                            Text("Reading the record…")
                        }
                    } footer: {
                        Text("The record is read on this iPhone. Nothing is sent anywhere.")
                    }
                } else if candidates.isEmpty {
                    Section {
                        Text("No vaccine names with dates could be read from this record. You can add them by hand in Immunizations.")
                            .foregroundStyle(.secondary)
                    }
                } else {
                    ForEach(groups, id: \.name) { group in
                        Section(group.name) {
                            ForEach(group.indices, id: \.self) { index in
                                row($candidates[index])
                            }
                        }
                    }
                    Section {
                    } footer: {
                        Text("Check each date against the record before adding. Handwriting and faint print can be misread. Tap a vaccine to fix its name or date.")
                    }
                }
            }
            .autocorrectionDisabled()
            .navigationTitle("Vaccines found")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(chosen.isEmpty ? "Add" : "Add \(chosen.count)") {
                        save()
                        dismiss()
                    }
                    .disabled(chosen.isEmpty)
                }
            }
            .task { await read() }
        }
    }

    /// The vaccines in the order the record lists them, each with its doses by date.
    private var groups: [(name: String, indices: [Int])] {
        var order: [String] = []
        var byName: [String: [Int]] = [:]
        for (index, candidate) in candidates.enumerated() {
            let name = candidate.found.vaccine
            if byName[name] == nil { order.append(name) }
            byName[name, default: []].append(index)
        }
        return order.map { name in
            (name, byName[name]!.sorted { candidates[$0].found.date < candidates[$1].found.date })
        }
    }

    private func row(_ candidate: Binding<Candidate>) -> some View {
        HStack(spacing: 12) {
            Button {
                candidate.wrappedValue.include.toggle()
            } label: {
                Image(systemName: candidate.wrappedValue.include ? "checkmark.circle.fill" : "circle")
                    .font(.title3)
                    .foregroundStyle(candidate.wrappedValue.include ? Color.accentColor : Color.secondary)
            }
            .buttonStyle(.plain)
            .accessibilityLabel(candidate.wrappedValue.include ? "Will be added" : "Won't be added")

            NavigationLink {
                CandidateEditView(found: candidate.found)
            } label: {
                VStack(alignment: .leading, spacing: 2) {
                    Text(candidate.wrappedValue.found.date.formDate)
                    if candidate.wrappedValue.isAlreadyRecorded {
                        Text("Already in Immunizations")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }
    }

    private func read() async {
        guard isReading else { return }
        var rows: [String] = []
        if let data = document.pdfData { rows = await DocumentPDF.rows(of: data) }
        let existing = person.immunizations.map { (vaccine: $0.vaccine, date: $0.date) }
        candidates = VaccineRecordParser.parse(rows: rows, dateOfBirth: person.dateOfBirth).map { found in
            let recorded = VaccineRecordParser.isAlreadyRecorded(found, in: existing)
            return Candidate(found: found, include: !recorded, isAlreadyRecorded: recorded)
        }
        isReading = false
    }

    private func save() {
        defer {
            document.importedAt = .now
            let count = chosen.count
            onFinished?("Added \(count) vaccine\(count == 1 ? "" : "s") to Immunizations")
        }
        for candidate in chosen {
            let shot = Immunization(vaccine: candidate.found.vaccine.trimmed, date: candidate.found.date)
            shot.notes = "From \(document.displayTitle)"
            modelContext.insert(shot)
            shot.person = person
        }
    }
}

/// Fixes the name or date of one vaccine found on a record.
private struct CandidateEditView: View {
    @Binding var found: VaccineRecordParser.Found

    var body: some View {
        Form {
            Section {
                Picker("Vaccine", selection: $found.vaccine) {
                    if !VaccineRecordParser.vaccines.contains(where: { $0.name == found.vaccine }) {
                        Text(found.vaccine).tag(found.vaccine)
                    }
                    ForEach(VaccineRecordParser.vaccines, id: \.name) { Text($0.name).tag($0.name) }
                }
                DateField(label: "Date given", date: Binding(
                    get: { found.date },
                    set: { if let date = $0 { found.date = date } }
                ), allowsFuture: false)
            }
        }
        .navigationTitle("Vaccine")
        .navigationBarTitleDisplayMode(.inline)
    }
}
