import SwiftData
import SwiftUI

struct MedicationsView: View {
    let person: Person

    var body: some View {
        let sorted = person.medications.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
        RecordList(
            title: "Medications",
            emptyTitle: "No medications",
            emptyMessage: "Add prescriptions, over-the-counter medicines and supplements.",
            systemImage: "pills",
            sections: [
                RecordSection("Current", sorted.filter(\.isActive)),
                RecordSection("Past", sorted.filter { !$0.isActive }),
            ],
            row: { medication in
                RecordRow(
                    title: medication.name,
                    details: [medication.dose, medication.frequency, medication.reason.isBlank ? "" : "for \(medication.reason)"]
                )
            },
            editor: { MedicationEditView(person: person, medication: $0) }
        )
    }
}

struct MedicationEditView: View {
    let person: Person
    let medication: Medication?

    @Environment(\.modelContext) private var modelContext
    @Query(sort: \Provider.name) private var providers: [Provider]
    @Query(sort: \Pharmacy.name) private var pharmacies: [Pharmacy]
    @State private var isAddingProvider = false
    @State private var isAddingPharmacy = false
    @State private var name = ""
    @State private var dose = ""
    @State private var frequency = ""
    @State private var reason = ""
    @State private var prescriber = ""
    @State private var pharmacy = ""
    @State private var startDate: Date?
    @State private var endDate: Date?
    @State private var isActive = true
    @State private var notes = ""
    @State private var didLoad = false

    var body: some View {
        EditorForm(title: medication == nil ? "New medication" : "Edit medication", canSave: !name.isBlank, onSave: save) {
            Section {
                TextField("Name (e.g. Amoxicillin)", text: $name)
                TextField("Dose (e.g. 250 mg)", text: $dose)
                TextField("How often (e.g. twice a day)", text: $frequency)
                TextField("What it's for", text: $reason)
                Toggle("Currently taking", isOn: $isActive)
            }
            Section {
                ChoiceTextField(
                    placeholder: "Prescribed by",
                    text: $prescriber,
                    options: names(of: providers, linkedTo: person.providers),
                    addNewTitle: "New provider…",
                    onAddNew: { isAddingProvider = true }
                )
                ChoiceTextField(
                    placeholder: "Pharmacy",
                    text: $pharmacy,
                    options: names(of: pharmacies, linkedTo: person.pharmacies),
                    addNewTitle: "New pharmacy…",
                    onAddNew: { isAddingPharmacy = true }
                )
                DateField(label: "Start date", date: $startDate)
                if !isActive {
                    DateField(label: "Stop date", date: $endDate)
                }
            }
            Section { NotesField(text: $notes) }
        }
        .sheet(isPresented: $isAddingProvider) {
            NavigationStack {
                ProviderEditView(provider: nil, defaultPatient: person) { prescriber = $0.name }
            }
        }
        .sheet(isPresented: $isAddingPharmacy) {
            NavigationStack {
                PharmacyEditView(pharmacy: nil, defaultPerson: person) { pharmacy = $0.name }
            }
        }
        .onAppear {
            guard !didLoad else { return }
            didLoad = true
            if medication == nil {
                // Most people use one pharmacy; start with it filled in.
                if person.pharmacies.count == 1 { pharmacy = person.pharmacies[0].name }
                return
            }
            guard let medication else { return }
            name = medication.name
            dose = medication.dose
            frequency = medication.frequency
            reason = medication.reason
            prescriber = medication.prescriber
            pharmacy = medication.pharmacy
            startDate = medication.startDate
            endDate = medication.endDate
            isActive = medication.isActive
            notes = medication.notes
        }
    }

    /// This person's own providers or pharmacies first, then everyone else's.
    private func names<Item: PersistentModel>(of all: [Item], linkedTo mine: [Item]) -> [String] {
        let label: (Item) -> String = { item in
            (item as? Provider)?.name ?? (item as? Pharmacy)?.name ?? ""
        }
        let mineIDs = Set(mine.map(\.persistentModelID))
        let first = all.filter { mineIDs.contains($0.persistentModelID) }.map(label)
        let rest = all.filter { !mineIDs.contains($0.persistentModelID) }.map(label)
        var seen = Set<String>()
        return (first + rest).filter { !$0.isBlank && seen.insert($0).inserted }
    }

    private func save() {
        let target = medication ?? {
            let new = Medication(name: name.trimmed)
            modelContext.insert(new)
            new.person = person
            return new
        }()
        target.name = name.trimmed
        target.dose = dose.trimmed
        target.frequency = frequency.trimmed
        target.reason = reason.trimmed
        target.prescriber = prescriber.trimmed
        target.pharmacy = pharmacy.trimmed
        target.startDate = startDate
        target.endDate = isActive ? nil : endDate
        target.isActive = isActive
        target.notes = notes.trimmed
    }
}
