import SwiftData
import SwiftUI

/// Appointment notes: why they went, what the provider said, and what happens next.
struct VisitsView: View {
    let person: Person

    var body: some View {
        let sorted = person.visits.sorted { ($0.date ?? $0.createdAt) > ($1.date ?? $1.createdAt) }
        let now = Calendar.current.startOfDay(for: .now)
        RecordList(
            title: "Visit notes",
            emptyTitle: "No visit notes",
            emptyMessage: "After an appointment, jot down what the provider said and what happens next.",
            systemImage: "note.text",
            sections: [
                RecordSection("Follow-ups coming up", sorted.filter { ($0.followUpDate ?? .distantPast) >= now }),
                RecordSection("Visits", sorted.filter { ($0.followUpDate ?? .distantPast) < now }),
            ],
            row: { visit in
                RecordRow(title: VisitRow.title(for: visit), details: VisitRow.details(for: visit))
            },
            editor: { VisitEditView(person: person, visit: $0) }
        )
    }
}

enum VisitRow {
    static func title(for visit: Visit) -> String {
        [visit.date?.formDate ?? "", visit.provider?.name ?? ""].filter { !$0.isEmpty }.joined(separator: " · ")
            .nonEmpty ?? (visit.reason.isBlank ? "Visit" : visit.reason)
    }

    static func details(for visit: Visit) -> [String] {
        [
            visit.reason,
            visit.followUpDate.map { "follow up by \($0.formDate)" } ?? visit.followUp,
        ]
    }
}

private extension String {
    var nonEmpty: String? { isEmpty ? nil : self }
}

struct VisitEditView: View {
    let person: Person
    let visit: Visit?

    @Environment(\.modelContext) private var modelContext
    @Query(sort: \Provider.name) private var providers: [Provider]
    @State private var date: Date? = Calendar.current.startOfDay(for: .now).addingTimeInterval(12 * 3600)
    @State private var providerChoice = ""
    @State private var reason = ""
    @State private var notes = ""
    @State private var followUp = ""
    @State private var followUpDate: Date?
    @State private var didLoad = false

    var body: some View {
        EditorForm(title: visit == nil ? "New visit" : "Edit visit", canSave: true, onSave: save) {
            Section {
                DateField(label: "Date", date: $date)
                ProviderPicker(person: person, selection: $providerChoice, label: "Seen by")
                TextField("Reason (e.g. ear pain, 6-month checkup)", text: $reason)
            }
            Section("What they said") {
                TextField("Diagnosis, test results, advice, changes…", text: $notes, axis: .vertical)
                    .lineLimit(4...12)
            }
            Section {
                TextField("Next steps (e.g. come back in 6 weeks)", text: $followUp, axis: .vertical)
                    .lineLimit(1...4)
                DateField(label: "Follow up by", date: $followUpDate)
            } header: {
                Text("Follow-up")
            } footer: {
                Text("New medications or diagnoses still go in their own sections, so they appear on the intake summary.")
            }
        }
        .onAppear {
            guard !didLoad else { return }
            didLoad = true
            guard let visit else { return }
            date = visit.date
            providerChoice = visit.provider?.id.uuidString ?? ""
            reason = visit.reason
            notes = visit.notes
            followUp = visit.followUp
            followUpDate = visit.followUpDate
        }
    }

    private func save() {
        let target = visit ?? {
            let new = Visit()
            modelContext.insert(new)
            new.person = person
            return new
        }()
        target.date = date
        target.reason = reason.trimmed
        target.notes = notes.trimmed
        target.followUp = followUp.trimmed
        target.followUpDate = followUpDate
        target.provider = ProviderPicker.resolve(providerChoice, for: person, in: providers)
    }
}
