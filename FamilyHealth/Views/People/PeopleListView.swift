import SwiftData
import SwiftUI

struct PeopleListView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.recordAccess) private var access
    @Environment(Purchases.self) private var purchases
    @Query(sort: [SortDescriptor(\Person.sortOrder), SortDescriptor(\Person.name)])
    private var people: [Person]

    @State private var isAddingPerson = false
    @State private var isShowingSettings = false
    @State private var isShowingUnlock = false
    @State private var personToDelete: Person?
    @State private var searchText = ""
    @AppStorage(BackupStatus.lastBackupKey) private var lastBackupAt: Double = 0
    @AppStorage(FamilyTitle.key) private var familyTitle = ""

    var body: some View {
        NavigationStack {
            Group {
                if people.isEmpty {
                    emptyState
                } else if !searchText.isBlank {
                    SearchResultsList(hits: FamilySearch.hits(for: searchText, in: people))
                } else {
                    list
                }
            }
            .background(Theme.background.ignoresSafeArea())
            .searchable(text: $searchText, prompt: "Search all records")
            .navigationTitle(FamilyTitle.display(familyTitle))
            .navigationDestination(for: Person.self) { person in
                PersonDetailView(person: person)
            }
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button {
                        isShowingSettings = true
                    } label: {
                        Label("Settings", systemImage: "gearshape")
                    }
                }
                if access.canEdit {
                    ToolbarItem(placement: .primaryAction) {
                        Button {
                            isAddingPerson = true
                        } label: {
                            Label("Add family member", systemImage: "plus")
                        }
                    }
                }
            }
            .sheet(isPresented: $isAddingPerson) {
                NavigationStack {
                    PersonEditView(person: nil, nextSortOrder: (people.map(\.sortOrder).max() ?? -1) + 1)
                }
            }
            .sheet(isPresented: $isShowingSettings) {
                SettingsView()
            }
            .sheet(isPresented: $isShowingUnlock, onDismiss: {
                // Just started the free trial on a new install: go straight
                // on to adding the first person.
                if people.isEmpty, purchases.status.canEdit { isAddingPerson = true }
            }) {
                UnlockView()
            }
            .confirmationDialog(
                "Delete \(personToDelete?.displayName ?? "")?",
                isPresented: Binding(
                    get: { personToDelete != nil },
                    set: { if !$0 { personToDelete = nil } }
                ),
                titleVisibility: .visible
            ) {
                Button("Delete", role: .destructive) {
                    if let personToDelete {
                        modelContext.delete(personToDelete)
                        ModelStore.removeUnusedSharedRecords(in: modelContext)
                    }
                    personToDelete = nil
                }
            } message: {
                Text("This removes their medications, allergies, conditions and all other records. It can't be undone.")
            }
        }
    }

    private var list: some View {
        List {
            if PlanPolicy.showsBanner(purchases.status, now: purchases.now) {
                Section {
                    PlanBanner(status: purchases.status) { isShowingUnlock = true }
                }
            }

            if BackupStatus.isDue(lastBackupAt: lastBackupAt) {
                Section {
                    Button {
                        isShowingSettings = true
                    } label: {
                        Label {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(lastBackupAt == 0 ? "Make your first backup" : "Time for a fresh backup")
                                    .font(.subheadline.weight(.semibold))
                                Text("A password-protected backup keeps your records safe if this iPhone is lost.")
                                    .font(.footnote)
                                    .foregroundStyle(.secondary)
                            }
                        } icon: {
                            Image(systemName: "externaldrive.fill.badge.exclamationmark")
                                .foregroundStyle(Theme.warning)
                        }
                    }
                    .buttonStyle(.plain)
                }
            }

            ForEach(people) { person in
                NavigationLink(value: person) {
                    PersonRow(person: person)
                }
            }
            .onDelete { offsets in
                personToDelete = offsets.first.map { people[$0] }
            }
            .onMove { from, to in
                var reordered = people
                reordered.move(fromOffsets: from, toOffset: to)
                for (index, person) in reordered.enumerated() {
                    person.sortOrder = index
                }
            }
            .deleteDisabled(!access.canEdit)
            .moveDisabled(!access.canEdit)

            Section {
            } footer: {
                AppNameFooter()
                    .padding(.top, 24)
            }
        }
        .brandedBackground()
    }

    private var emptyState: some View {
        ContentUnavailableView {
            Label("Add your family", systemImage: "person.2.fill")
        } description: {
            Text("Welcome to Family Health Binder. Start with one person. Their medications, allergies, doctors and insurance will all live on their page.")
            if !access.canEdit {
                // A new install: the free trial starts here, through Apple.
                Text(purchases.freeTrialText.map { "Try everything free for \($0). Cancel before it ends and you won't be charged." }
                     ?? "Choose a plan to start adding your family.")
            }
        } actions: {
            if access.canEdit {
                Button("Add a family member") {
                    isAddingPerson = true
                }
                .primaryButton()
            } else {
                Button(purchases.startTitle) {
                    isShowingUnlock = true
                }
                .primaryButton()
            }
        }
    }
}

struct PersonRow: View {
    let person: Person

    var body: some View {
        HStack(spacing: 12) {
            AvatarView(photoData: person.photoData, initials: person.initials)
            VStack(alignment: .leading, spacing: 2) {
                Text(person.displayName)
                    .font(.headline)
                if let dob = person.dateOfBirth, let age = person.age {
                    Text("Age \(age) · Born \(dob.shortDate)")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .accessibilityLabel("Age \(age), born \(dob.formatted(date: .long, time: .omitted))")
                }
            }
        }
        .padding(.vertical, 2)
        .accessibilityElement(children: .combine)
    }
}
