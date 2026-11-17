import SwiftData
import SwiftUI

struct TherapiesView: View {
    let person: Person

    var body: some View {
        let sorted = person.therapies.sorted { $0.displayName.localizedCaseInsensitiveCompare($1.displayName) == .orderedAscending }
        RecordList(
            title: "Therapies",
            emptyTitle: "No therapies",
            emptyMessage: "Add therapies like OT, speech or ABA, and who provides them.",
            systemImage: "figure.play",
            sections: [
                RecordSection("Current", sorted.filter(\.isActive)),
                RecordSection("Past", sorted.filter { !$0.isActive }),
            ],
            row: { therapy in
                RecordRow(title: therapy.displayName, details: TherapyRowDetails.details(for: therapy))
            },
            editor: { TherapyEditView(person: person, therapy: $0) }
        )
    }
}

enum TherapyRowDetails {
    static func details(for therapy: Therapy) -> [String] {
        let provider = therapy.provider.map { p in
            p.practice.isBlank ? p.name : "\(p.name), \(p.practice)"
        } ?? ""
        let since = therapy.startDate.map { "since \(TypedDate.string(from: $0))" } ?? ""
        return [provider, therapy.frequency, therapy.isActive ? since : ""]
    }
}

struct TherapyEditView: View {
    let person: Person
    let therapy: Therapy?

    @Environment(\.modelContext) private var modelContext
    @Query(sort: \Provider.name) private var providers: [Provider]
    @State private var kind = TherapyKind.occupational
    @State private var customName = ""
    /// A provider's id as text, "" for none.
    @State private var providerChoice = ""
    @State private var isAddingProvider = false
    @State private var frequency = ""
    @State private var startDate: Date?
    @State private var endDate: Date?
    @State private var isActive = true
    @State private var goals = ""
    @State private var notes = ""
    @State private var didLoad = false

    private static let newProvider = "new"

    var body: some View {
        EditorForm(
            title: therapy == nil ? "New therapy" : "Edit therapy",
            canSave: kind != .other || !customName.isBlank,
            onSave: save
        ) {
            Section {
                Picker("Type", selection: $kind) {
                    ForEach(TherapyKind.allCases) { Text($0.label).tag($0) }
                }
                if kind == .other {
                    TextField("Name (e.g. Vision therapy)", text: $customName)
                }
                Toggle("Currently receiving", isOn: $isActive)
            }
            Section {
                Picker("Provider", selection: Binding(
                    get: { providerChoice },
                    set: { choice in
                        if choice == Self.newProvider {
                            isAddingProvider = true
                        } else {
                            providerChoice = choice
                        }
                    }
                )) {
                    Text("None").tag("")
                    ForEach(orderedProviders) { provider in
                        Text(providerLabel(provider)).tag(provider.id.uuidString)
                    }
                    Text("New provider…").tag(Self.newProvider)
                }
                TextField("How often (e.g. weekly, 45 min)", text: $frequency)
                DateField(label: "Start date", date: $startDate)
                if !isActive {
                    DateField(label: "End date", date: $endDate)
                }
            } footer: {
                Text("The provider is added to this person's care team.")
            }
            Section("Goals") {
                TextField("What they're working on", text: $goals, axis: .vertical)
                    .lineLimit(2...6)
            }
            Section { NotesField(text: $notes) }
        }
        .sheet(isPresented: $isAddingProvider) {
            NavigationStack {
                ProviderEditView(provider: nil, defaultPatient: person) { providerChoice = $0.id.uuidString }
            }
        }
        .onAppear {
            guard !didLoad else { return }
            didLoad = true
            guard let therapy else { return }
            kind = therapy.kind
            customName = therapy.customName
            providerChoice = therapy.provider?.id.uuidString ?? ""
            frequency = therapy.frequency
            startDate = therapy.startDate
            endDate = therapy.endDate
            isActive = therapy.isActive
            goals = therapy.goals
            notes = therapy.notes
        }
    }

    /// This person's providers first, then the rest of the family's.
    private var orderedProviders: [Provider] {
        let mine = Set(person.providers.map(\.id))
        return providers.filter { mine.contains($0.id) } + providers.filter { !mine.contains($0.id) }
    }

    private func providerLabel(_ provider: Provider) -> String {
        provider.specialty.isBlank ? provider.name : "\(provider.name) (\(provider.specialty))"
    }

    private func save() {
        let target = therapy ?? {
            let new = Therapy(kind: kind)
            modelContext.insert(new)
            new.person = person
            return new
        }()
        target.kind = kind
        target.customName = kind == .other ? customName.trimmed : ""
        target.frequency = frequency.trimmed
        target.startDate = startDate
        target.endDate = isActive ? nil : endDate
        target.isActive = isActive
        target.goals = goals.trimmed
        target.notes = notes.trimmed
        let provider = providers.first { $0.id.uuidString == providerChoice }
        target.provider = provider
        if let provider, !provider.patients.contains(where: { $0.id == person.id }) {
            provider.patients.append(person)
        }
    }
}
