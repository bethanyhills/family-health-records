import SwiftData
import SwiftUI

struct PeopleListView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.recordAccess) private var access
    @Query(sort: [SortDescriptor(\Person.sortOrder), SortDescriptor(\Person.name)])
    private var people: [Person]

    @State private var isAddingPerson = false
    @State private var isShowingSettings = false
    @State private var personToDelete: Person?

    var body: some View {
        NavigationStack {
            Group {
                if people.isEmpty {
                    emptyState
                } else {
                    list
                }
            }
            .navigationTitle("Family")
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
        }
    }

    private var emptyState: some View {
        ContentUnavailableView {
            Label("Add your family", systemImage: "person.2.fill")
        } description: {
            Text("Start with one person. Their medications, allergies, doctors and insurance will all live on their page.")
        } actions: {
            if access.canEdit {
                Button("Add a family member") {
                    isAddingPerson = true
                }
                .buttonStyle(.borderedProminent)
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
                }
            }
        }
        .padding(.vertical, 2)
    }
}
