import SwiftData
import SwiftUI

/// Reads a 504 plan or IEP kept in Documents, marks it as the person's active plan and
/// keeps its eligibility, services, accommodations and review date in the document's
/// notes, where the intake summary picks them up. Nothing is saved until they tap Save.
struct SchoolPlanImportView: View {
    let person: Person
    let document: HealthDocument
    /// Called with a short message after the plan is saved.
    var onFinished: ((String) -> Void)? = nil

    @Environment(\.dismiss) private var dismiss
    @State private var isReading = true
    @State private var plan: SchoolPlan = .iep
    @State private var planDate: Date?
    @State private var nextReview: Date?
    @State private var eligibility = ""
    @State private var services: [Choice] = []
    @State private var accommodations: [Choice] = []

    struct Choice: Identifiable {
        let id = UUID()
        var text: String
        var include = true
    }

    var body: some View {
        NavigationStack {
            Form {
                if isReading {
                    Section {
                        HStack(spacing: 12) {
                            ProgressView()
                            Text("Reading the plan…")
                        }
                    } footer: {
                        Text("The plan is read on this iPhone. Nothing is sent anywhere. Long plans take a little while.")
                    }
                } else {
                    Section {
                        Picker("Plan", selection: $plan) {
                            Text(SchoolPlan.iep.label).tag(SchoolPlan.iep)
                            Text(SchoolPlan.plan504.label).tag(SchoolPlan.plan504)
                        }
                        DateField(label: "Plan date", date: $planDate)
                        DateField(label: "Next review", date: $nextReview)
                        TextField("Eligibility (e.g. Autism)", text: $eligibility)
                    } footer: {
                        Text("Saving shows \"\(plan.activeLabel)\" in \(person.displayName)'s school details, linked to this document.")
                    }
                    choices("Services", $services, empty: "No services with minutes were found.")
                    choices("Accommodations", $accommodations, empty: "No accommodations list was found.")
                    Section {
                    } footer: {
                        Text("Check each item against the plan. The details are kept in the document's notes, where you can change them, and appear on the intake summary.")
                    }
                }
            }
            .brandedBackground()
            .autocorrectionDisabled()
            .navigationTitle("School plan")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        save()
                        dismiss()
                    }
                    .disabled(isReading)
                }
            }
            .task { await read() }
        }
    }

    @ViewBuilder
    private func choices(_ title: String, _ items: Binding<[Choice]>, empty: String) -> some View {
        Section(title) {
            if items.wrappedValue.isEmpty {
                Text(empty).foregroundStyle(.secondary)
            }
            ForEach(items) { $item in
                Toggle(isOn: $item.include) {
                    Text(item.text)
                }
            }
        }
    }

    private func read() async {
        guard isReading else { return }
        var rows: [String] = []
        if let data = document.pdfData { rows = await DocumentPDF.rows(of: data, maxScannedPages: 15) }
        let result = SchoolPlanParser.parse(rows: rows)
        let saved = SchoolPlanDetails(notes: document.notes)

        if document.kind == .iep { plan = .iep }
        else if document.kind == .plan504 { plan = .plan504 }
        else if result.plan != .noPlan { plan = result.plan }
        else if person.schoolPlan != .noPlan { plan = person.schoolPlan }

        planDate = document.date ?? result.planDate
        nextReview = result.details.nextReview ?? saved.nextReview
        eligibility = result.details.eligibility.isEmpty ? saved.eligibility : result.details.eligibility
        services = (result.details.services.isEmpty ? saved.services : result.details.services).map { Choice(text: $0) }
        accommodations = (result.details.accommodations.isEmpty ? saved.accommodations : result.details.accommodations)
            .map { Choice(text: $0) }
        isReading = false
    }

    private func save() {
        if let kind = plan.documentKind { document.kind = kind }
        if let planDate { document.date = planDate }
        let details = SchoolPlanDetails(
            eligibility: eligibility.trimmed,
            nextReview: nextReview,
            services: services.filter(\.include).map(\.text.trimmed).filter { !$0.isEmpty },
            accommodations: accommodations.filter(\.include).map(\.text.trimmed).filter { !$0.isEmpty }
        )
        document.notes = details.merged(into: document.notes)
        person.schoolPlan = plan
        document.importedAt = .now
        onFinished?("Added the \(plan == .iep ? "IEP" : "504 plan") to school details")
    }
}
