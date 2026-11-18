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
            editor: { VisitEditView(person: person, visit: $0) },
            scan: RecordScan(person: person, kind: .visitSummary, title: "Scan a visit summary")
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
    /// What was read from an after-visit summary, filled in for the person to check.
    var draft: VisitSummaryParser.Result? = nil
    /// The document the draft was read from.
    var draftSource: String? = nil
    /// Called after Save, e.g. to show what was added from a document. True when the
    /// person's height or weight was updated from it.
    var onSaved: ((_ updatedProfile: Bool) -> Void)? = nil

    @Environment(\.modelContext) private var modelContext
    @Query(sort: \Provider.name) private var providers: [Provider]
    @State private var date: Date? = Calendar.current.startOfDay(for: .now).addingTimeInterval(12 * 3600)
    @State private var providerChoice = ""
    @State private var reason = ""
    @State private var notes = ""
    @State private var followUp = ""
    @State private var followUpDate: Date?
    @State private var newConditions: Set<String> = []
    @State private var updatesHeight = false
    @State private var updatesWeight = false
    @State private var didLoad = false

    /// The height and weight the summary gives, written like the profile's, when they differ.
    private var newHeight: String { BodyMeasurement.update(height: draft?.height ?? "", current: person.height) }
    private var newWeight: String { BodyMeasurement.update(weight: draft?.weight ?? "", current: person.weight) }

    /// A summary older than another visit on file may not have the latest measurements.
    private var isOlderThanAnotherVisit: Bool {
        guard let summaryDate = draft?.date else { return false }
        return person.visits.contains { $0.id != visit?.id && ($0.date ?? .distantPast) > summaryDate }
    }

    var body: some View {
        EditorForm(title: visit == nil ? "New visit" : "Edit visit", canSave: true, onSave: save) {
            if let draftSource {
                Section {
                } footer: {
                    Text("Filled in from \(draftSource). Check each field against the summary before saving.")
                }
            }
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
                if draft?.diagnoses.isEmpty ?? true {
                    Text("New medications or diagnoses still go in their own sections, so they appear on the intake summary.")
                }
            }
            if let diagnoses = draft?.diagnoses, !diagnoses.isEmpty {
                Section {
                    ForEach(diagnoses, id: \.self) { diagnosis in
                        if isAlreadyACondition(diagnosis) {
                            LabeledContent(diagnosis) {
                                Text("Already listed").foregroundStyle(.secondary)
                            }
                        } else {
                            Toggle(diagnosis, isOn: Binding(
                                get: { newConditions.contains(diagnosis) },
                                set: { if $0 { newConditions.insert(diagnosis) } else { newConditions.remove(diagnosis) } }
                            ))
                        }
                    }
                } header: {
                    Text("Add to conditions")
                } footer: {
                    Text("Turn on the diagnoses that are ongoing, so they show on the intake summary. A one-time illness can stay in this note.")
                }
            }
            if !newHeight.isEmpty || !newWeight.isEmpty {
                Section {
                    if !newHeight.isEmpty {
                        Toggle(isOn: $updatesHeight) {
                            Text("Update height to \(newHeight)")
                            Text(person.height.isBlank ? "None on file" : "On file: \(person.height)")
                        }
                    }
                    if !newWeight.isEmpty {
                        Toggle(isOn: $updatesWeight) {
                            Text("Update weight to \(newWeight)")
                            Text(person.weight.isBlank ? "None on file" : "On file: \(person.weight)")
                        }
                    }
                } header: {
                    Text("\(person.shortName)'s profile")
                } footer: {
                    Text(isOlderThanAnotherVisit
                         ? "This summary is older than another visit on file, so these may not be the latest measurements."
                         : "Measured at this visit. Keeps the profile and intake summary current.")
                }
            }
        }
        .onAppear {
            guard !didLoad else { return }
            didLoad = true
            if let visit {
                date = visit.date
                providerChoice = visit.provider?.id.uuidString ?? ""
                reason = visit.reason
                notes = visit.notes
                followUp = visit.followUp
                followUpDate = visit.followUpDate
            }
            if let draft {
                apply(draft)
                updatesHeight = !isOlderThanAnotherVisit
                updatesWeight = !isOlderThanAnotherVisit
            }
        }
    }

    private func apply(_ draft: VisitSummaryParser.Result) {
        if let visitDate = draft.date { date = visitDate }
        if reason.isBlank { reason = draft.reason }
        if !draft.provider.isEmpty, providerChoice.isEmpty {
            let match = PrescriptionParser.matchProvider(
                draft.provider, existing: providers.map(\.name), preferred: person.providers.map(\.name))
            if let match, let provider = providers.first(where: { $0.name == match }) {
                providerChoice = provider.id.uuidString
            }
        }
        var lines: [String] = []
        if providerChoice.isEmpty, !draft.provider.isEmpty { lines.append("Seen by \(draft.provider)") }
        if !draft.notes.isEmpty { lines.append(draft.notes) }
        if let draftSource { lines.append("From \(draftSource)") }
        let added = lines.joined(separator: "\n\n")
        if !added.isEmpty { notes = notes.isBlank ? added : notes.trimmed + "\n\n" + added }
        if followUp.isBlank { followUp = draft.followUp }
        if followUpDate == nil { followUpDate = draft.followUpDate }
    }

    private func isAlreadyACondition(_ diagnosis: String) -> Bool {
        person.conditions.contains { $0.name.trimmed.localizedCaseInsensitiveCompare(diagnosis.trimmed) == .orderedSame }
    }

    private func save() {
        var updatedProfile = false
        defer { onSaved?(updatedProfile) }
        if updatesHeight, !newHeight.isEmpty {
            person.height = newHeight
            updatedProfile = true
        }
        if updatesWeight, !newWeight.isEmpty {
            person.weight = newWeight
            updatedProfile = true
        }
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

        for diagnosis in draft?.diagnoses ?? [] where newConditions.contains(diagnosis) && !isAlreadyACondition(diagnosis) {
            let condition = Condition(name: diagnosis.trimmed, diagnosedDate: date)
            condition.treatingProvider = target.provider?.name ?? ""
            if let draftSource { condition.notes = "From \(draftSource)" }
            modelContext.insert(condition)
            condition.person = person
        }
    }
}
