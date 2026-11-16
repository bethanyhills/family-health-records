import MapKit
import SwiftData
import SwiftUI

/// Pharmacies one family member uses. Pharmacies are shared, so swiping
/// removes one from this person only.
struct PharmaciesView: View {
    let person: Person

    @Environment(\.modelContext) private var modelContext
    @Environment(\.recordAccess) private var access
    @Query(sort: \Pharmacy.name) private var allPharmacies: [Pharmacy]

    var body: some View {
        let sorted = person.pharmacies.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
        let others = allPharmacies.filter { pharmacy in !person.pharmacies.contains { $0.id == pharmacy.id } }

        RecordList(
            title: "Pharmacies",
            emptyTitle: "No pharmacies",
            emptyMessage: "Find your pharmacy on Apple Maps. A pharmacy the whole family uses only needs to be added once.",
            systemImage: "cross.vial",
            sections: [RecordSection(nil, sorted)],
            row: { PharmacyRow(pharmacy: $0) },
            editor: { PharmacyEditView(pharmacy: $0, defaultPerson: person) },
            onRemove: { pharmacy in
                pharmacy.patients.removeAll { $0.id == person.id }
                ModelStore.removeUnusedSharedRecords(in: modelContext)
            }
        )
        .toolbar {
            if access.canEdit && !others.isEmpty {
                ToolbarItem(placement: .secondaryAction) {
                    Menu {
                        ForEach(others) { pharmacy in
                            Button(pharmacy.name) { pharmacy.patients.append(person) }
                        }
                    } label: {
                        Label("Add existing pharmacy", systemImage: "plus.rectangle.on.rectangle")
                    }
                }
            }
        }
    }
}

struct PharmacyRow: View {
    let pharmacy: Pharmacy

    var body: some View {
        RecordRow(title: pharmacy.name, details: [pharmacy.address, pharmacy.phone])
    }
}

struct PharmacyEditView: View {
    let pharmacy: Pharmacy?
    let defaultPerson: Person?
    var onSaved: ((Pharmacy) -> Void)?

    @Environment(\.modelContext) private var modelContext
    @Query(sort: [SortDescriptor(\Person.sortOrder), SortDescriptor(\Person.name)]) private var people: [Person]

    @State private var name = ""
    @State private var phone = ""
    @State private var address = ""
    @State private var latitude: Double?
    @State private var longitude: Double?
    @State private var notes = ""
    @State private var personIDs: Set<UUID> = []
    @State private var isSearching = false
    @State private var didLoad = false

    var body: some View {
        EditorForm(title: pharmacy == nil ? "New pharmacy" : "Edit pharmacy", canSave: !name.isBlank, onSave: save) {
            Section {
                Button {
                    isSearching = true
                } label: {
                    Label("Find on Apple Maps", systemImage: "magnifyingglass")
                }
            } footer: {
                Text("Search by name and town, then pick your store. Or type the details below.")
            }
            Section {
                TextField("Name (e.g. Walgreens #1234)", text: $name)
                TextField("Phone", text: $phone)
                    .keyboardType(.phonePad)
                TextField("Address", text: $address, axis: .vertical)
                    .textContentType(.fullStreetAddress)
            }
            Section("Used by") {
                PeopleToggles(people: people, selection: $personIDs)
            }
            Section { NotesField(text: $notes) }
        }
        .sheet(isPresented: $isSearching) {
            NavigationStack {
                PharmacySearchView { item in
                    name = item.name ?? name
                    phone = item.phoneNumber ?? phone
                    address = item.placemark.title ?? address
                    latitude = item.placemark.coordinate.latitude
                    longitude = item.placemark.coordinate.longitude
                }
            }
        }
        .onAppear {
            guard !didLoad else { return }
            didLoad = true
            if let pharmacy {
                name = pharmacy.name
                phone = pharmacy.phone
                address = pharmacy.address
                latitude = pharmacy.latitude
                longitude = pharmacy.longitude
                notes = pharmacy.notes
                personIDs = Set(pharmacy.patients.map(\.id))
            } else {
                if let defaultPerson { personIDs = [defaultPerson.id] }
                isSearching = true
            }
        }
    }

    private func save() {
        let target = pharmacy ?? {
            let new = Pharmacy(name: name.trimmed)
            modelContext.insert(new)
            return new
        }()
        target.name = name.trimmed
        target.phone = phone.trimmed
        target.address = address.trimmed
        target.latitude = latitude
        target.longitude = longitude
        target.notes = notes.trimmed
        target.patients = people.filter { personIDs.contains($0.id) }
        ModelStore.removeUnusedSharedRecords(in: modelContext)
        onSaved?(target)
    }
}

/// Searches Apple Maps for pharmacies. Only the typed search text is sent to Apple.
struct PharmacySearchView: View {
    let onPick: (MKMapItem) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var search = PharmacySearch()
    @State private var query = ""

    var body: some View {
        List {
            if let error = search.error {
                Text(error).foregroundStyle(.secondary)
            }
            ForEach(search.results, id: \.self) { completion in
                Button {
                    Task {
                        if let item = await search.mapItem(for: completion) {
                            onPick(item)
                            dismiss()
                        }
                    }
                } label: {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(completion.title).foregroundStyle(.primary)
                        Text(completion.subtitle)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }
        .overlay {
            if query.isBlank {
                ContentUnavailableView(
                    "Find your pharmacy",
                    systemImage: "cross.vial",
                    description: Text("Type the pharmacy and town, like \"CVS Naperville\".")
                )
            }
        }
        .searchable(text: $query, placement: .navigationBarDrawer(displayMode: .always), prompt: "Pharmacy name and town")
        .autocorrectionDisabled()
        .onChange(of: query) { _, newValue in search.update(newValue) }
        .navigationTitle("Find pharmacy")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("Cancel") { dismiss() }
            }
        }
    }
}

@MainActor
@Observable
final class PharmacySearch: NSObject, MKLocalSearchCompleterDelegate {
    private(set) var results: [MKLocalSearchCompletion] = []
    private(set) var error: String?
    @ObservationIgnored private let completer = MKLocalSearchCompleter()

    override init() {
        super.init()
        completer.delegate = self
        completer.resultTypes = .pointOfInterest
        completer.pointOfInterestFilter = MKPointOfInterestFilter(including: [.pharmacy])
    }

    func update(_ query: String) {
        error = nil
        if query.isBlank {
            results = []
        } else {
            completer.queryFragment = query
        }
    }

    func mapItem(for completion: MKLocalSearchCompletion) async -> MKMapItem? {
        do {
            return try await MKLocalSearch(request: MKLocalSearch.Request(completion: completion)).start().mapItems.first
        } catch {
            self.error = "Couldn't load that place. Check your connection and try again."
            return nil
        }
    }

    nonisolated func completerDidUpdateResults(_ completer: MKLocalSearchCompleter) {
        let latest = completer.results
        Task { @MainActor in self.results = latest }
    }

    nonisolated func completer(_ completer: MKLocalSearchCompleter, didFailWithError error: Error) {
        Task { @MainActor in self.error = "Search isn't available right now. Check your connection." }
    }
}
